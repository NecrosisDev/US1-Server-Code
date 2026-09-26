-- Z-City killcam, phase 3: the server side of the records menu.
-- Two requests, both answered from disk: a player's record list, and one clip by id.
-- The per-player index is the access list: a clip id that is not in your own index is
-- refused unless you are staff. Clips hold no SteamIDs, so the file is sent as stored.
if not SERVER then return end
local K = assert(ZCKillcam, "recorder must load first")
util.AddNetworkString("zckc_index")
util.AddNetworkString("zckc_clip")
util.AddNetworkString("zckc_notes")
util.AddNetworkString("zckc_zoom")

-- Scope zoom (owner, 2026-09-21: "record the scope zoom level too"). SWEP.ZoomFOV lives on the CLIENT only - the mouse
-- wheel changes it in cl_optics.lua and nothing ever tells the server - so each client reports its own (cl_life.lua,
-- at most 4 a second, only while holding a scoped weapon and only when it changed). It is what the player CLAIMS and is
-- only ever drawn in a replay: clamped, rate limited, the last ZOOM_KEEP changes per player kept, dropped each round.
local ZOOM_KEEP, ZOOM_GAP = 8, 0.2
local zoomLog = {} -- uid -> {at = {}, fov = {}, class = {}, n = count}
net.Receive("zckc_zoom", function(_, p)
    if not IsValid(p) then return end
    local now = CurTime()
    if (p.zckcZoomNext or 0) > now then return end
    p.zckcZoomNext = now + ZOOM_GAP
    local fov = math.Clamp(net.ReadUInt(10) / 10, 0.5, 100)
    local w = p:GetActiveWeapon()
    if not IsValid(w) then return end
    local uid = p:UserID()
    local log = zoomLog[uid]
    if not log then log = {at = {}, fov = {}, class = {}, n = 0} zoomLog[uid] = log end
    if log.n >= ZOOM_KEEP then
        table.remove(log.at, 1) table.remove(log.fov, 1) table.remove(log.class, 1)
        log.n = log.n - 1
    end
    log.n = log.n + 1
    log.at[log.n], log.fov[log.n], log.class[log.n] = now, fov, w:GetClass()
    local tape = K.Tape
    if tape and tape.note and tape.note.Zoom then tape.note.Zoom(uid, fov, w:GetClass()) end -- the round tape keeps it too
end)
function K.ZoomReset() zoomLog = {} end -- called from sv_clips.lua's round-start hook, next to the attachment cache
-- For the clip cutter: {centiseconds from `death`, fov in tenths, class}, oldest first, nothing after t1. Changes from
-- before the clip are kept - they are what the scope was set to when the clip begins.
function K.ZoomRows(uid, death, t1)
    local log = zoomLog[uid]
    if not log then return nil end
    local rows
    for i = 1, log.n do
        if log.at[i] <= t1 then rows = rows or {} rows[#rows + 1] = {math.floor((log.at[i] - death) * 100 + 0.5), math.floor(log.fov[i] * 10 + 0.5), log.class[i]} end
    end
    return rows
end

local CHUNK, MAX_FILE = 16384, 512 * 1024
K.Status = {ok = 0, denied = 1, expired = 2, locked = 3, busy = 4}
local STATUS = K.Status

-- Owner rule (2026-09-21): admins see ALL clips; operators see their own and those submitted for review.
-- "operator" is the ULib group; Community Manager inherits it, admin and superadmin sit above it.
-- PROVISIONAL(2026-09-21, ordinary players stay locked out until the owner opens it, ratify-by: 2026-10-21)
function K.IsStaff(p) return IsValid(p) and p:IsAdmin() end
function K.IsOperator(p) return IsValid(p) and (p:IsAdmin() or (p.CheckGroup ~= nil and p:CheckGroup("operator") == true)) end
-- Follows the death-sequence audience: once that is opened to everyone (zc_killcam_flash 2), players can
-- also open their OWN records, otherwise what they saved would be unreachable. K.MayView still limits them to those.
local flash
function K.CanUse(p)
    if K.IsOperator(p) then return true end
    flash = flash or GetConVar("zc_killcam_flash")
    return IsValid(p) and flash ~= nil and flash:GetInt() >= 2
end
-- A clip is "submitted for review" once a report pins it (phase 4 writes pinned.json).
function K.Submitted() return util.JSONToTable(file.Read(K.Root .. "/pinned.json", "DATA") or "") or {} end
-- No live-round intel: a living player in a traitor round cannot open clips. The dead can already spectate.
-- PROVISIONAL(2026-09-21, ZCityMetaSafety.Locked() semantics between rounds are unverified so it is not consulted, ratify-by: 2026-10-21)
function K.ViewLocked(p) return K.TraitorRound() and p:Alive() end

local nextAsk = {}
local function throttled(p, key, gap)
    local slot = nextAsk[p] or {}
    nextAsk[p] = slot
    local now = CurTime()
    if (slot[key] or 0) > now then return true end
    slot[key] = now + gap
end
hook.Add("PlayerDisconnected", "ZCKillcam.NetForget", function(p) nextAsk[p] = nil if K.Sending then K.Sending[p] = nil end end)

local function clipPath(id) return K.Root .. "/clips/" .. id .. ".dat" end

-- Drops entries whose clip has aged out, so the list never offers a dead link.
function K.LiveIndex(sid)
    local list, kept = K.Index(sid), {}
    for _, e in ipairs(list) do
        if isstring(e.clip) and file.Exists(clipPath(e.clip), "DATA") then kept[#kept + 1] = e end
    end
    if #kept ~= #list then file.Write(K.Root .. "/index/" .. sid .. ".json", util.TableToJSON(kept)) end
    return kept
end

----------------------------------------------------------------- sharing (UI cohesion U2, 2026-09-26)
-- Owner: "players must have access to the funny and embarrassing moments and be able to easily share them with
-- friends." A clip is SHARED when a party to it posts it to CityLeak (sv_feed.lua, the zc_feed_posts.clip column) or
-- copies its chat link ("!clip <id>", zckc_share below, kept in data/zc_killcam/shared.json as id -> until). A shared
-- clip may be fetched by ANY player; every other zckc_clip refusal (alive in a live round, expired, busy, the rate
-- limit) still applies. zc_goobos_share (feed_rules.lua, replicated, default 1) turns sharing off: nothing new is
-- shared and non-parties are refused again. What was shared stays protected from the age sweep either way (K.SharedSet).
K.StatusText = {[1] = "You are not a party to that clip.", [2] = "That clip has expired.", [3] = "Clips cannot be opened while you are alive in a live round.", [4] = "Still sending the previous clip."} -- the viewer's STATUS_TEXT (cl_part_02.lua), word for word
K.ShareLinkKeep = 14 * 86400 -- a chat link keeps its clip watchable (and out of the age sweep) this long after it was copied
K.SharePostKeep = 45 * 86400 -- a live CityLeak post keeps its clip out of the age sweep this long after it was posted (a report pin is 45 days too)
local SHARED_FILE = K.Root .. "/shared.json"
local function validId(id) return isstring(id) and #id <= 24 and string.match(id, "^%d+_%d+$") ~= nil end
function K.ShareOn()
    local cv = GetConVar("zc_goobos_share")
    return cv ~= nil and cv:GetBool()
end
local function clipLive(id)
    local size = file.Exists(clipPath(id), "DATA") and file.Size(clipPath(id), "DATA") or 0
    return size > 0 and size <= MAX_FILE
end
local function feed() local F = rawget(_G, "ZCGoobFeed") return istable(F) and F or nil end

-- A party to a clip: it is in your own record list (you were its victim, or its killer in an innocent-kills-innocent
-- clip), or you are the owner its sidecar names (a death sequence you saved, even after your 15-row list rotated it
-- out). This is the "You are not a party to that clip" rule of K.MayView without the staff, highlight and review
-- widening: those may WATCH a clip, they do not make it theirs to publish.
function K.IsClipParty(p, id)
    if not IsValid(p) or not validId(id) then return false end
    local sid = p:SteamID64()
    if not sid then return false end
    for _, e in ipairs(K.Index(sid)) do if e.clip == id then return true end end
    local meta = util.JSONToTable(file.Read(K.Root .. "/clips/" .. id .. ".meta.json", "DATA") or "")
    return istable(meta) and meta.owner == sid
end
local function inIndex(owner, id)
    for _, e in ipairs(K.Index(owner)) do if e.clip == id then return true end end
    return false
end
-- May `p` share (post or link) clip `id`? Returns ok, the refusal text. A saved round highlight was already shown to
-- the whole server, so anyone may pass it on; everything else needs a party.
function K.MayShare(p, id)
    if not K.ShareOn() then return false, "Sharing is turned off on this server." end
    if not validId(id) then return false, "Invalid clip reference." end
    if not clipLive(id) then return false, K.StatusText[2] end
    if K.IsClipParty(p, id) or inIndex(K.HIGHLIGHT_OWNER, id) then return true end
    return false, K.StatusText[1]
end

-- data/zc_killcam/shared.json: {[clip id] = unix time the chat link lapses}. Lapsed entries are dropped on write.
function K.SharedLinks()
    local t = util.JSONToTable(file.Read(SHARED_FILE, "DATA") or "")
    return istable(t) and t or {}
end
function K.ShareLink(id, now)
    now = now or os.time()
    local links, kept = K.SharedLinks(), {}
    for clip, till in pairs(links) do if validId(clip) and isnumber(till) and till >= now then kept[clip] = till end end
    kept[id] = math.max(tonumber(kept[id]) or 0, now + K.ShareLinkKeep)
    file.CreateDir(K.Root)
    file.Write(SHARED_FILE, util.TableToJSON(kept))
end
-- May anyone at all fetch clip `id`? A live chat link, or a live (not removed) CityLeak post that carries it.
function K.SharedClip(id, now)
    if not K.ShareOn() or not validId(id) then return false end
    local till = K.SharedLinks()[id]
    if isnumber(till) and till >= (now or os.time()) then return true end
    local F = feed()
    if not (F and isfunction(F.ClipPosted)) then return false end
    local ok, posted = pcall(F.ClipPosted, id)
    return ok and posted == true
end
-- For the age sweep (sv_clips.lua K.Sweep): every clip a share is still protecting, as a set. Independent of
-- zc_goobos_share on purpose - switching sharing off must not quietly delete what players already posted.
function K.SharedSet(now)
    now = now or os.time()
    local set = {}
    for id, till in pairs(K.SharedLinks()) do if validId(id) and isnumber(till) and till >= now then set[id] = true end end
    local F = feed()
    if F and isfunction(F.SharedClipIds) then
        local ok, ids = pcall(F.SharedClipIds, now - K.SharePostKeep)
        if ok and istable(ids) then for _, id in ipairs(ids) do if validId(id) then set[id] = true end end end
    end
    return set
end

-- Paging (U2): zckc_index answers at most 31 rows (the count is a UInt(5)), so a request may carry an optional
-- trailing UInt(16) offset and the reply ends with an optional trailer saying where to ask from next. The killcam
-- viewer (cl_part_03.lua) sends no offset and stops reading before the trailer, so it keeps working unchanged.
-- K.PageRows walks source positions offset+1..count, keeps up to `limit` rows `keep` accepts, and returns them, the
-- position to ask from next, and whether any source entries are left.
K.PAGE = 31
function K.PageRows(count, at, keep, offset, limit)
    local page, i = {}, math.max(0, math.floor(offset or 0))
    limit = limit or K.PAGE
    while i < count and #page < limit do
        i = i + 1
        local row = keep(at(i))
        if row then page[#page + 1] = row end
    end
    return page, i, i < count
end

-- The "shared" scope: clips on live CityLeak posts, newest post first, one row per clip. `other` is the poster and
-- the caption; the paging trailer adds the post id and whether the asker is a party (so the client can offer Post).
local function sharedRows(p, offset)
    local F = feed()
    if not (K.ShareOn() and F and isfunction(F.SharedClipPosts)) then return {}, offset, false end
    local ok, rows = pcall(F.SharedClipPosts, offset, 64)
    if not ok or not istable(rows) then return {}, offset, false end
    local maps, mine, sid = nil, {}, p:SteamID64()
    for _, e in ipairs(sid and K.Index(sid) or {}) do if isstring(e.clip) then mine[e.clip] = true end end
    local page, used, left = K.PageRows(#rows, function(i) return rows[i] end, function(r)
        if not validId(r.clip) or not file.Exists(clipPath(r.clip), "DATA") then return nil end
        if not maps then
            maps = {}
            for _, e in ipairs(K.AllIndex()) do if isstring(e.clip) and maps[e.clip] == nil then maps[e.clip] = e.map end end
        end
        local caption = string.Trim(string.gsub(tostring(r.body or ""), "[%c]", " "))
        if #caption > 120 then caption = string.sub(caption, 1, 117) .. "..." end
        return {clip = r.clip, t = tonumber(r.created) or 0, map = maps[r.clip] or "", tag = "shared", role = "",
            other = tostring(r.name or "?") .. (caption ~= "" and (": " .. caption) or ""), kind = "shared",
            post = tonumber(r.id) or 0, mine = r.author == sid or mine[r.clip] == true}
    end, 0)
    return page, offset + used, left or #rows == 64
end

net.Receive("zckc_index", function(_, p)
    local target = net.ReadString()
    local offset = (net.BytesLeft and (net.BytesLeft() or 0) or 0) >= 2 and net.ReadUInt(16) or 0
    -- The shared list is as public as CityLeak itself: it needs sharing on, not the killcam records.
    if not (K.CanUse(p) or (target == "shared" and IsValid(p) and K.ShareOn())) or throttled(p, "index", 1) then return end
    local sid, scope = p:SteamID64(), "mine"
    local list, nextAt, more
    local function fromAll(pinned)
        local all = K.AllIndex()
        return K.PageRows(#all, function(i) return all[i] end, function(e)
            if not isstring(e.clip) or (pinned and not pinned[e.clip]) or not file.Exists(clipPath(e.clip), "DATA") then return nil end
            return {clip = e.clip, t = e.t, map = e.map, tag = e.tag, role = "", other = tostring(e.killer) .. " killed " .. tostring(e.victim), reported = pinned ~= nil}
        end, offset)
    end
    if target == "all" and K.IsStaff(p) then
        scope = "all"
        list, nextAt, more = fromAll(nil)
    elseif target == "submitted" and K.IsOperator(p) then
        scope = "submitted"
        list, nextAt, more = fromAll(K.Submitted())
    elseif target == "shared" then
        scope = "shared"
        list, nextAt, more = sharedRows(p, offset)
    elseif target == "highlights" then
        -- P1 (killcam_revitalize, 2026-09-24): the round highlights saved by zc_killcam_persist_missed, newest first,
        -- for ANY player who may use the records at all (every one of them was shown to the whole server). Filed
        -- under the "_round" owner by sv_life.lua persist(); other players' death clips stay staff-only as before.
        sid, scope = K.HIGHLIGHT_OWNER, "highlights"
    elseif target ~= "" and K.IsStaff(p) and #target <= 20 and string.match(target, "^%d+$") then
        sid, scope = target, target
    end
    if not list then
        local live = sid and K.LiveIndex(sid) or {}
        list, nextAt, more = K.PageRows(#live, function(i) return live[i] end, function(e) return e end, offset)
    end
    local n = math.min(#list, 31)
    net.Start("zckc_index")
    net.WriteString(scope)
    net.WriteBool(K.ViewLocked(p))
    net.WriteUInt(n, 5)
    for i = 1, n do
        local e = list[i]
        net.WriteString(e.clip)
        net.WriteUInt(tonumber(e.t) or 0, 32)
        net.WriteString(tostring(e.map or ""))
        net.WriteString(tostring(e.tag or ""))
        net.WriteString(tostring(e.role or ""))
        net.WriteString(tostring(e.other or ""))
        net.WriteBool(e.reported == true)
    end
    -- P1: an additive TRAILER, one entry per row above, after all of them - a client that predates it stops reading
    -- at the last row and never sees it. Per row: missed (Bool), kind ("life" / "highlight" / "" for an older row),
    -- reason (why it was missed, "" if it was not). Only rows written by persist() since this landed carry them.
    for i = 1, n do
        local e = list[i]
        net.WriteBool(e.missed == true)
        net.WriteString(tostring(e.kind or ""))
        net.WriteString(tostring(e.reason or ""))
    end
    -- U2 paging TRAILER, after the P1 one (readers of either older shape stop before it): UInt(16) the offset to ask
    -- from for the next page, Bool whether there may be more, then per row UInt(32) the CityLeak post (0 = none) and
    -- Bool whether the asker is a party to it (shared rows only; every other scope is the asker's own or staff's).
    net.WriteUInt(math.min(nextAt or 0, 65535), 16)
    net.WriteBool(more == true)
    for i = 1, n do
        local e = list[i]
        net.WriteUInt(math.Clamp(tonumber(e.post) or 0, 0, 4294967295), 32)
        net.WriteBool(e.mine == true)
    end
    net.Send(p)
end)

local function refuse(p, id, status)
    net.Start("zckc_clip")
    net.WriteString(id)
    net.WriteUInt(status, 3)
    net.Send(p)
end

-- P1: the index owner the saved round highlights are filed under (sv_life.lua persist, sv_highlight.lua).
K.HIGHLIGHT_OWNER = "_round"
function K.MayView(p, id)
    if K.IsStaff(p) then return true end -- admins: every clip
    local sid = p:SteamID64()
    if sid then for _, e in ipairs(K.Index(sid)) do if e.clip == id then return true end end end -- anyone: their own
    for _, e in ipairs(K.Index(K.HIGHLIGHT_OWNER)) do if e.clip == id then return true end end -- anyone: a saved round highlight
    return K.IsOperator(p) and K.Submitted()[id] ~= nil -- operators: also what was submitted for review
end

-- Sends one compressed blob in 16 KB pieces on message `name`; the client reassembles by id.
K.Sending = K.Sending or {} -- kept on K so a hot reload of this file does not forget transfers in flight
local sending = K.Sending
function K.Busy(p) return (sending[p] or 0) > CurTime() end
-- Pacing (adversarial pass 2026-09-24, the map reel). A piece every 50 ms was 320 KB/s per client - over the Source
-- client's default `rate` (192 KB/s), so every transfer choked that client's whole channel for its duration - and
-- the round highlight goes to EVERY player at the same instant, so a full server took 30 x that at once. The map
-- reel is up to four cuts (compressed clips on this box: p50 54 KB, p90 195 KB, p99 695 KB), which made both worse.
-- Now: pieces are spaced so one client receives at most zc_killcam_blob_rate bytes/s (default 160 KB/s, under the
-- default rate with room for snapshots and voice), and recipients are queued on one shared lane so the server sends
-- at most zc_killcam_blob_total_rate bytes/s in aggregate (default 4 MB/s): each send reserves blob/total_rate
-- seconds of the lane and starts when the lane reaches it. The client reassembles by id with no deadline
-- (cl_life.lua / viewer_parts cl_part_02.lua), so a later start is never a lost clip. K.BlobSchedule is the pure
-- part, so the arithmetic can be tested without the engine; K.Stats.wireDelayMax is the longest start delay seen.
local cvRate = CreateConVar("zc_killcam_blob_rate", "160000", FCVAR_ARCHIVE, "Killcam clip delivery: bytes per second sent to any one client (pieces of 16 KB are spaced to this).", 16384, 2000000)
local cvTotalRate = CreateConVar("zc_killcam_blob_total_rate", "4000000", FCVAR_ARCHIVE, "Killcam clip delivery: bytes per second the server sends in aggregate across all recipients; 0 = no shared lane (everyone starts at once).", 0, 50000000)
K.WireAt = K.WireAt or 0 -- when the shared lane is next free (CurTime); survives a hot reload like K.Sending
function K.BlobSchedule(bytes, now)
    local total = math.ceil(bytes / CHUNK)
    local interval = CHUNK / math.max(cvRate:GetInt(), CHUNK)
    local totalRate = cvTotalRate:GetInt()
    local start = now
    if totalRate > 0 then
        start = math.max(now, K.WireAt)
        K.WireAt = start + bytes / totalRate
    end
    return start - now, interval, total
end
-- Returns true once the send is actually scheduled, false when refused (invalid player, or the
-- R5 overflow guard below) - callers that only want to count a REAL send (sv_highlight.lua's
-- audience, adversarial review 2026-09-24) must check this, not just call K.SendBlob and assume.
function K.SendBlob(p, name, id, blob)
    if not IsValid(p) then return false end
    local total = math.ceil(#blob / CHUNK)
    -- R5: WriteUInt(total, 8) and WriteUInt(seq, 8) below can only carry 0-255. A blob over 255 chunks (~4 MB)
    -- would corrupt seq/total on the wire instead of just failing loudly. Refuse it instead.
    if total > 255 then
        K.Drops = K.Drops or {}
        K.Drops.overflow = (K.Drops.overflow or 0) + 1
        ErrorNoHalt(string.format("[Killcam] blob for %s dropped: %d bytes needs %d chunks, over the 255-chunk wire limit\n", p:Nick(), #blob, total))
        return false
    end
    local delay, interval = K.BlobSchedule(#blob, CurTime())
    K.Stats = K.Stats or {}
    K.Stats.wireDelayMax = math.max(K.Stats.wireDelayMax or 0, delay)
    sending[p] = CurTime() + delay + total * interval + 0.1
    for seq = 1, total do
        timer.Simple(delay + (seq - 1) * interval, function()
            if not IsValid(p) then return end
            local part = string.sub(blob, (seq - 1) * CHUNK + 1, seq * CHUNK)
            net.Start(name)
            net.WriteString(id)
            net.WriteUInt(STATUS.ok, 3)
            net.WriteUInt(seq, 8)
            net.WriteUInt(total, 8)
            net.WriteUInt(#part, 16)
            net.WriteData(part, #part)
            net.Send(p)
        end)
    end
    -- M1 (killcam_polish, 2026-09-24): also hands back the lane delay, the span of the chunk timers and the chunk
    -- count, for sv_life.lua's latency rows. Every caller so far tests the first value only.
    return true, delay, (total - 1) * interval, total
end

net.Receive("zckc_clip", function(_, p)
    local id = net.ReadString()
    -- round tape requests ride this channel under "tape:" ids; sv_tapeserve.lua has its own gate, throttle and queue
    if string.sub(id, 1, 5) == "tape:" then
        if K.TapeRequest then K.TapeRequest(p, id) end
        return
    end
    -- U2: a SHARED clip (K.SharedClip) may be fetched by anyone, records access or not; nothing else changes. A
    -- player without records access now spends the same 2 s throttle slot before the shared check, so a stream of
    -- requests cannot turn into a stream of lookups.
    local canUse = K.CanUse(p)
    if not IsValid(p) or throttled(p, "clip", 2) then return end
    if #id > 24 or not string.match(id, "^%d+_%d+$") then return end -- the id becomes a file name: digits only
    local mayView = canUse and K.MayView(p, id)
    if not mayView and not K.SharedClip(id) then
        if not canUse then return end -- as before: no records access and nothing shared is silence
        return refuse(p, id, STATUS.denied)
    end
    if K.ViewLocked(p) then return refuse(p, id, STATUS.locked) end
    if K.Busy(p) then return refuse(p, id, STATUS.busy) end
    local blob = file.Read(clipPath(id), "DATA")
    if not blob or #blob == 0 or #blob > MAX_FILE then return refuse(p, id, STATUS.expired) end
    K.SendBlob(p, "zckc_clip", id, blob)
    -- Operators and up also get the reports filed on it; only admins get the attacker's SteamID.
    if not K.IsOperator(p) then return end
    local report = util.JSONToTable(file.Read(K.Root .. "/reports/" .. id .. ".json", "DATA") or "")
    if not report or not report.items then return end
    local n = math.min(#report.items, 31)
    net.Start("zckc_notes")
    net.WriteString(id)
    net.WriteString(tostring(report.name or ""))
    net.WriteUInt(n, 5)
    for i = 1, n do
        local item = report.items[i]
        net.WriteUInt(math.Clamp(tonumber(item.instance) or 0, 0, 31), 5)
        net.WriteString(string.sub(tostring(item.text or ""), 1, 240))
        net.WriteString(tostring(item.attacker or ""))
        net.WriteString(K.IsStaff(p) and tostring(item.attackerId or "") or "")
    end
    net.Send(p)
end)

-- U2 share requests (share.lua, ZCGoobApps.Share): make a clip ready to share and say which id it goes out under.
--   client -> server: String kind ("life" = the death sequence the server holds for you, by its id; "clip" = a stored
--                     clip), String id, Bool link (true = the player is copying a chat link: record it as shared).
--   server -> client: String the id asked about, String the clip id to share ("" when refused), UInt(3) code, String
--                     the refusal in words. Codes: 0 ok, 1 not a party, 2 gone / expired, 3 sharing off, 4 slow down.
-- "life" SAVES the held sequence first (the zckc_save path: sv_life.lua persist, exported as K.Persist) - a saved
-- sequence is stored under its own id, so the reply names the same id. Posting to CityLeak is not done here: the
-- client publishes through CityLeak's own request, which runs K.MayShare again (sv_feed.lua).
util.AddNetworkString("zckc_share")
K.ShareCode = {ok = 0, denied = 1, gone = 2, off = 3, slow = 4}
local SHARE = K.ShareCode
net.Receive("zckc_share", function(_, p)
    if not IsValid(p) then return end
    local kind, id, link = net.ReadString(), net.ReadString(), net.ReadBool()
    if not validId(id) or (kind ~= "life" and kind ~= "clip") then return end
    local function reply(clip, code, text)
        net.Start("zckc_share")
        net.WriteString(id)
        net.WriteString(clip or "")
        net.WriteUInt(code, 3)
        net.WriteString(text or "")
        net.Send(p)
    end
    if throttled(p, "share", 1) then return reply("", SHARE.slow, "Slow down a moment, then try again.") end
    if not K.ShareOn() then return reply("", SHARE.off, "Sharing is turned off on this server.") end
    if kind == "life" then
        if not (K.LifeAllowed and K.LifeAllowed(p)) then return reply("", SHARE.denied, "Death replays are not open to you yet.") end
        local sid = p:SteamID64()
        local h = sid and K.Held and K.Held[sid]
        if h and h.id ~= id then h = h.prev end -- the one it replaced on screen, when zc_killcam_persist_missed keeps it
        if h and h.id == id and not h.saved and K.Persist then K.Persist(sid, h) end
        if h and h.id == id and not h.saved then return reply("", SHARE.gone, "The replay is still saving. Try again in a moment.") end
        -- not held any more (a newer death replaced it): it can still be shared if it was saved before
        if not (h and h.id == id) and not clipLive(id) then return reply("", SHARE.gone, "That replay is gone: a newer death replaced it before it was saved.") end
    end
    local ok, why = K.MayShare(p, id)
    if not ok then return reply("", why == K.StatusText[2] and SHARE.gone or SHARE.denied, why) end
    if link then K.ShareLink(id) end
    reply(id, SHARE.ok, "")
end)
