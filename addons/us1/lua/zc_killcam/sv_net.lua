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

net.Receive("zckc_index", function(_, p)
    if not K.CanUse(p) or throttled(p, "index", 1) then return end
    local target = net.ReadString()
    local sid, scope = p:SteamID64(), "mine"
    local list
    if target == "all" and K.IsStaff(p) then
        scope, list = "all", {}
        for _, e in ipairs(K.AllIndex()) do
            if #list < 31 and file.Exists(clipPath(e.clip), "DATA") then list[#list + 1] = {clip = e.clip, t = e.t, map = e.map, tag = e.tag, role = "", other = tostring(e.killer) .. " killed " .. tostring(e.victim)} end
        end
    elseif target == "submitted" and K.IsOperator(p) then
        scope, list = "submitted", {}
        local pinned = K.Submitted()
        for _, e in ipairs(K.AllIndex()) do
            if pinned[e.clip] and #list < 31 and file.Exists(clipPath(e.clip), "DATA") then list[#list + 1] = {clip = e.clip, t = e.t, map = e.map, tag = e.tag, role = "", other = tostring(e.killer) .. " killed " .. tostring(e.victim), reported = true} end
        end
    elseif target == "highlights" then
        -- P1 (killcam_revitalize, 2026-09-24): the round highlights saved by zc_killcam_persist_missed, newest first,
        -- for ANY player who may use the records at all (every one of them was shown to the whole server). Filed
        -- under the "_round" owner by sv_life.lua persist(); other players' death clips stay staff-only as before.
        sid, scope = K.HIGHLIGHT_OWNER, "highlights"
    elseif target ~= "" and K.IsStaff(p) and #target <= 20 and string.match(target, "^%d+$") then
        sid, scope = target, target
    end
    list = list or (sid and K.LiveIndex(sid) or {})
    net.Start("zckc_index")
    net.WriteString(scope)
    net.WriteBool(K.ViewLocked(p))
    net.WriteUInt(math.min(#list, 31), 5)
    for i = 1, math.min(#list, 31) do
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
    for i = 1, math.min(#list, 31) do
        local e = list[i]
        net.WriteBool(e.missed == true)
        net.WriteString(tostring(e.kind or ""))
        net.WriteString(tostring(e.reason or ""))
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
    if not K.CanUse(p) or throttled(p, "clip", 2) then return end
    if #id > 24 or not string.match(id, "^%d+_%d+$") then return end -- the id becomes a file name: digits only
    if not K.MayView(p, id) then return refuse(p, id, STATUS.denied) end
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
