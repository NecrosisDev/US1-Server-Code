-- Z-City killcam, round tape step 3: the tape SERVER. Staff and (P2) ordinary players ask for the rounds list, one
-- round's index, or one chunk, and get it over the records channel that already exists (`zckc_clip`, K.SendBlob)
-- under a namespaced id:
--   tape:list              the newest rounds: id, wall time, bytes, map, mode, length, chunks, players
--   tape:list:<t>          the next page: rounds strictly older than catalog time <t> (D3 - page, never load all)
--   tape:<round>:index     index.txt of a CLOSED round, filtered for the viewer's class
--   tape:<round>:<seq>     one chunk, byte for byte as it lies in tape.dat (already compressed: never re-encoded)
-- Blobs for list and index are "ZCM1<len>,..;<streams>" as K.PackSequence writes them, so the client's V.Unpack reads
-- them; the text inside is JSON lines. A chunk blob is the chunk itself and starts "ZCT1\n".
--
-- THE TAPE'S RULE HOLDS HERE TOO: no unit of work above 2 ms. Every request is a K.Work job (sv_clips.lua); disk is read
-- through file.Open + Seek + Read in slices, never file.Read of a whole tape.dat; a compress call gets under 4 KB of
-- text. Stages: serve.open, serve.read and serve.index (index.txt), serve.chunk (tape.dat), serve.filter, serve.pack,
-- serve.list (see zc_killcam_work).
--
-- WHO SEES WHAT is decided here, at send time, never in the client:
--   admins     every closed round, every line.
--   operators  rounds they played in; SteamIDs cut from `who`; only the mark kinds in OPERATOR_KINDS, and of the voice
--              marks only the living speakers. A kind this file has never heard of is NOT sent to them.
--   players    (P2, zc_killcam_replay convar) EXACTLY the operator filtering above, but only for CLOSED rounds they
--              were actually in (D1/D2) - never an open round, never a round without their SteamID64 in `who`.
--              Rolled out via zc_killcam_replay: 0 off, 1 the trial audience (K.Trial), 2 everyone (D4).
--   the rest   nothing.
-- Chunks go to admin/operator/player unfiltered: what is staff-only (roles, traitors, chat, staff actions) lives in
-- index marks; chunk tracks are positions, ragdolls, events, bullets, organism, entities and wounds. RE-CHECK when a
-- track is added.
if not SERVER then return end
local K = assert(ZCKillcam, "recorder must load first")
K.TapeServeVersion = "20260926.serve2" -- P2: player class, tape:list:<t> paging, player wire/CPU priority cap

local ROOT = "zc_killcam/tapes"
-- PROVISIONAL(2026-09-21, sized from the tape's US1 write-side measurements before any read was timed; retune from zc_killcam_work, ratify-by: 2026-10-05)
local LIST_MAX   = 40      -- rounds in a list
local LIST_SCAN  = 60      -- rounds whose index this request may read for the FIRST time (US1 holds 411 of them, and an
                           -- operator matches few: without this, one list request walks every round on disk). Rounds
                           -- already known cost nothing, so the next request reaches further.
local READ       = 16384   -- bytes per index read: one unit
local READ_CHUNK = 32768   -- bytes per tape.dat read: one unit
local TEXT_MAX   = 3800    -- bytes of text per util.Compress call (0.17 ms/KB on US1)
local LINES_UNIT = 25      -- index lines parsed per unit when filtering for an operator
local CHUNK_MAX  = 2 * 1024 * 1024 -- K.SendBlob counts parts in 8 bits: 255 x 16 KB. A chunk is ~70 KB.
local QUEUE      = 2       -- chunk requests kept waiting per viewer; an older prefetch is dropped for a newer one
local ASK_GAP    = 0.1     -- seconds between requests from one viewer
-- PROVISIONAL(2026-09-26, not measured under real multi-player load; caps how many "player"-class viewers may have a
-- blob reserved on the shared wire lane at once, so N players streaming a round cannot push a death killcam's start
-- delay past a few tape transfers' worth. Relies on: K.SendBlob's shared lane K.WireAt (sv_net.lua:180,187-188) has
-- no priority concept - it is pure call-order FIFO across every K.SendBlob caller, including sv_life.lua:378's death
-- sequences - and K.Busy (sv_net.lua:167) only stops one PLAYER receiving two blobs at once; it never bounds how many
-- DIFFERENT players can each reserve lane time back to back. admin/operator stay uncapped (trusted, small
-- population). ratify-by: 2026-10-10)
local MAX_PLAYER_ACTIVE = 3

local OPERATOR_KINDS = {}
for kind in string.gmatch("head end chunk who name wep model ent entgone dmg door otrub wake veh drop equip join leave roundend death cleanup pill light reload reloaded getup knockdown amputate headexplode phrase search loot use break fire burning boom swing punch carry heal kick armor ammo interact disarm wire dryfire voice craft pull throw att lag rest zoom", "%S+") do
    OPERATOR_KINDS[kind] = true
end
K.TapeOperatorKinds = OPERATOR_KINDS

-- Survives a hot reload: closed rounds never change, so what was read about them stays true.
local S = K.TapeServe or {facts = {}, packed = {}, want = {}, told = {}}
K.TapeServe = S
S.playerActive = S.playerActive or {} -- "player" class viewers currently reserved on the wire; see MAX_PLAYER_ACTIVE
S.stats = S.stats or {asked = 0, sent = 0, refused = 0, dropped = 0, bytes = 0, readMax = 0}
local stats = S.stats
local STATUS = K.Status

local function refuse(p, id, status, why)
    stats.refused = stats.refused + 1
    if IsValid(p) and K.TapeClass(p) == "player" then stats.playerRefused = (stats.playerRefused or 0) + 1 end
    local key = IsValid(p) and (p:SteamID64() or tostring(p:UserID())) or "?"
    if not S.told[key] then -- once per viewer: a refusal is either a bug in the player or somebody poking
        S.told[key] = true
        print(string.format("[Killcam tape] refused %s to %s: %s", id, IsValid(p) and p:Nick() or "?", why))
    end
    if not IsValid(p) then return end
    net.Start("zckc_clip")
    net.WriteString(id)
    net.WriteUInt(status, 3)
    net.Send(p)
end

----------------------------------------------------------------- reading
-- Hands `fn` every whole line of a file, READ bytes of disk at a time. Runs inside a job.
local function eachLine(path, breathe, fn)
    local fd = file.Open(path, "rb", "DATA")
    breathe("serve.open")
    if not fd then return false end
    local size, at, tail = fd:Size(), 0, ""
    while at < size do
        local n = math.min(READ, size - at)
        local part = fd:Read(n) or ""
        at = at + n
        if n > stats.readMax then stats.readMax = n end
        breathe("serve.read")
        local text = tail .. part
        local from = 1
        while true do
            local stop = string.find(text, "\n", from, true)
            if not stop then break end
            if stop > from then fn(string.sub(text, from, stop - 1)) end
            from = stop + 1
        end
        tail = string.sub(text, from)
        breathe("serve.index")
    end
    fd:Close()
    if #tail > 0 and string.sub(tail, -1) == "}" then fn(tail) end -- a last line without its newline; a torn one is not a line
    return true
end

-- Is this index line of kind `k`? A cheap text test that keeps JSON parsing off every line of a 300-line index.
-- Tolerates the spaces a pretty-printer would add: util.TableToJSON writes none, but nothing here depends on that.
local function isKind(row, kind)
    return string.find(row, '"k"%s*:%s*"' .. kind .. '"') ~= nil
end

-- What the server needs to know about a closed round, read once: the head and end lines, where each chunk lies, and
-- who played (SteamID64 -> true; bots have none). Only `who`, `chunk`, head and end lines are ever JSON-parsed.
local function factsOf(id, breathe)
    local known = S.facts[id]
    if known and known.uidOf then return known end -- facts built before P2b have no uidOf: read them again once
    local facts = {chunks = {}, sids = {}, uidOf = {}, players = 0}
    local uids, first = {}, true
    local ok = eachLine(ROOT .. "/" .. id .. "/index.txt", breathe, function(row)
        if first then
            first = false
            local head = util.JSONToTable(row)
            if head and head.k == "head" then facts.head = head end
        elseif isKind(row, "chunk") then
            local c = util.JSONToTable(row)
            if c and c.seq and c.off and c.bytes then facts.chunks[c.seq] = {off = c.off, bytes = c.bytes} end
        elseif isKind(row, "who") then
            local w = util.JSONToTable(row)
            if w then
                if w.sid then
                    facts.sids[tostring(w.sid)] = true
                    if w.uid then facts.uidOf[tostring(w.sid)] = w.uid end -- the last `who` wins: a rejoin gets its newest uid
                end
                if w.uid and not uids[w.uid] then uids[w.uid] = true facts.players = facts.players + 1 end
            end
        elseif isKind(row, "end") then
            local e = util.JSONToTable(row)
            if e and e.k == "end" then facts["end"] = e end
        end
    end)
    if not ok or not facts.head then return nil end
    S.facts[id] = facts
    return facts
end

-- "closed" is the catalog's word, and the tape being written right now is never served whatever the catalog says.
local function closedEntry(id)
    local entry = K.TapeCatalog()[id]
    if not entry or entry.open or K.TapeOpenId() == id then return nil end
    return entry
end

----------------------------------------------------------------- who may see what
-- 0 = nobody, 1 = the trial audience (zc_killcam_trial_steamid via K.Trial, sv_life.lua), 2 = everyone (D4: owner
-- first, then everyone on his word) - the same rollout convention as zc_killcam_flash / zc_killcam_highlight_show
-- (AUDIT_DATA.md section 4, "existing player-facing precedent to reuse architecturally").
local replay = CreateConVar("zc_killcam_replay", "1", FCVAR_ARCHIVE, "Player-facing full round replay: 0 off, 1 the trial audience (zc_killcam_trial_steamid), 2 everyone")
function K.TapeClass(p)
    if K.IsStaff(p) then return "admin" end
    if K.IsOperator(p) then return "operator" end
    local mode = replay:GetInt()
    -- K.Trial is sv_life.lua's (SERVER loads it first, kc.py); the guard is the same "optional cross-file dependency"
    -- idiom this file already uses elsewhere (e.g. "if K.NoteAction and K.Kinds then", sv_tape.lua), not a real gap.
    if mode >= 2 or (mode == 1 and K.Trial and K.Trial(p)) then return "player" end
    return nil
end

-- The one gate; list, index and chunk all pass through it. `facts` is what factsOf read (operators need it).
function K.TapeMayView(p, id, facts)
    local class = K.TapeClass(p)
    if class == "admin" then return true end
    -- D1: a player gets EXACTLY the operator "was in this round" rule, never a looser one.
    if (class ~= "operator" and class ~= "player") or not facts then return false end
    local sid = p:SteamID64()
    return sid ~= nil and facts.sids[sid] == true
end

-- One index line as an operator may read it, or nil.
local function forOperator(row)
    local t = util.JSONToTable(row)
    if not t or not OPERATOR_KINDS[t.k] then return nil end
    if t.k == "voice" and t.alive ~= true then return nil end
    if t.k == "who" then
        if t.sid == nil then return row end
        t.sid = nil
        return util.TableToJSON(t)
    end
    return row
end
K.TapeForOperator = forOperator
K.TapeForPlayer = forOperator -- P2: players get exactly this filter (D1), never a looser one

----------------------------------------------------------------- packing
-- Lines go in one at a time and leave as compressed streams: the whole text is NEVER concatenated. Measured on US1,
-- a closed round's index is 155 KB over 2402 lines, and joining that in one unit is the 12 ms "concat" the tape's own
-- stats already show. Here the biggest string that exists at once is one TEXT_MAX stream.
local function packer(breathe)
    local buf, size, streams, sizes = {}, 0, {}, {}
    local function flush(force)
        while size >= TEXT_MAX or (force and size > 0) do
            local text = table.concat(buf) -- at most TEXT_MAX plus the line that crossed it
            local stream = util.Compress(string.sub(text, 1, TEXT_MAX)) or error("compress failed")
            streams[#streams + 1], sizes[#sizes + 1] = stream, #stream
            local rest = string.sub(text, TEXT_MAX + 1)
            buf, size = rest ~= "" and {rest} or {}, #rest
            breathe("serve.pack")
        end
    end
    local P = {}
    function P.add(line)
        buf[#buf + 1] = line
        buf[#buf + 1] = "\n"
        size = size + #line + 1
        if size >= TEXT_MAX then flush(false) end
    end
    function P.done()
        flush(true)
        return "ZCM1" .. table.concat(sizes, ",") .. ";" .. table.concat(streams)
    end
    return P
end

-- P2b: the viewer's own uid in this round, as a {"k":"me"} line appended to a packed ZCM1 blob as one more stream.
-- The packed text always ends in a newline (packer adds one per line), so the appended line starts a line of its own.
-- Rounds the viewer was not in (admins) or bots: the blob goes out unchanged.
function K.TapeWithMe(blob, facts, sid)
    local uid = tonumber(sid and facts and facts.uidOf and facts.uidOf[tostring(sid)])
    if not uid or uid ~= math.floor(uid) or string.sub(blob, 1, 4) ~= "ZCM1" then return blob end
    local stop = string.find(blob, ";", 5, true)
    if not stop then return blob end
    local extra = util.Compress('{"k":"me","uid":' .. string.format("%d", uid) .. '}\n')
    if not extra then return blob end
    local sizes = string.sub(blob, 5, stop - 1)
    return "ZCM1" .. (sizes ~= "" and (sizes .. ",") or "") .. #extra .. ";" .. string.sub(blob, stop + 1) .. extra
end

local function send(p, id, blob)
    if not IsValid(p) then return end
    stats.sent, stats.bytes = stats.sent + 1, stats.bytes + #blob
    if K.TapeClass(p) == "player" then
        stats.playerSent, stats.playerBytes = (stats.playerSent or 0) + 1, (stats.playerBytes or 0) + #blob
    end
    K.SendBlob(p, "zckc_clip", id, blob)
end

----------------------------------------------------------------- the three answers
-- Walks the catalog newest first and hands `emit` one JSON line per round the viewer may open, stopping at LIST_MAX
-- lines or LIST_SCAN rounds newly read. `mayView` is passed in so the measure command drives this same walk.
local function crawl(breathe, mayView, emit, before)
    local cat, order = K.TapeCatalog(), {}
    for rid, e in pairs(cat) do
        if not e.open and K.TapeOpenId() ~= rid then order[#order + 1] = {id = rid, t = e.t or 0, bytes = e.bytes or 0} end
    end
    table.sort(order, function(a, b) if a.t ~= b.t then return a.t > b.t end return a.id > b.id end)
    -- retention deletes rounds: forget what was kept about them (a packed index is ~10 KB)
    for rid in pairs(S.facts) do if not cat[rid] then S.facts[rid] = nil end end
    for key in pairs(S.packed) do if not cat[string.match(key, "^[^:]+")] then S.packed[key] = nil end end
    breathe("serve.list")
    local n, fresh = 0, 0
    for i = 1, #order do
        if n >= LIST_MAX or fresh >= LIST_SCAN then break end
        local o = order[i]
        -- D3 paging: strictly older than the caller's cursor. Skipped without touching factsOf, so a page full of
        -- rounds too new to qualify never eats into LIST_SCAN's bounded crawl of NEW reads.
        if not before or o.t < before then
            if S.facts[o.id] == nil then fresh = fresh + 1 end
            local facts = factsOf(o.id, breathe)
            if facts and mayView(o.id, facts) then
                local head, tail = facts.head, facts["end"] or {}
                emit(util.TableToJSON({id = o.id, t = o.t, bytes = o.bytes, map = head.map, mode = head.mode, base = head.base,
                    len = tail.len, chunks = tail.chunks, players = facts.players, partial = head.partial, tape = head.tape}))
                n = n + 1
                breathe("serve.list")
            end
        end
    end
    return n, fresh, #order
end

local function serveList(p, id, breathe, before)
    local pk = packer(breathe)
    crawl(breathe, function(rid, facts) return IsValid(p) and K.TapeMayView(p, rid, facts) end, pk.add, before)
    send(p, id, pk.done())
end

local function serveIndex(p, id, rid, breathe)
    if not closedEntry(rid) then return refuse(p, id, STATUS.expired, "not a closed round") end
    local facts = factsOf(rid, breathe)
    if not facts then return refuse(p, id, STATUS.expired, "no readable index") end
    if not IsValid(p) or not K.TapeMayView(p, rid, facts) then return refuse(p, id, STATUS.denied, "not their round") end
    local class = K.TapeClass(p)
    -- operator and player run the IDENTICAL filter (forOperator): share one cached blob, never pack it twice.
    local cacheClass = class == "admin" and "admin" or "restricted"
    local key = rid .. ":" .. cacheClass
    local blob = S.packed[key]
    if not blob then
        -- US1 measured JSONToTable at 3.8 us a line over a 2402-line index: nine milliseconds if it ran as one unit.
        local pk, since = packer(breathe), 0
        eachLine(ROOT .. "/" .. rid .. "/index.txt", breathe, function(row)
            if cacheClass == "admin" then
                pk.add(row)
            else
                local kept = forOperator(row)
                if kept then pk.add(kept) end
                since = since + 1
                if since >= LINES_UNIT then since = 0 breathe("serve.filter") end
            end
        end)
        blob = pk.done()
        S.packed[key] = blob
    end
    -- the job may have slept across ticks: the viewer can have left, or lost the rank that let them ask
    if not IsValid(p) or K.TapeClass(p) ~= class then return end
    send(p, id, K.TapeWithMe(blob, facts, p:SteamID64()))
end

local function serveChunk(p, id, rid, seq, breathe)
    if not closedEntry(rid) then return refuse(p, id, STATUS.expired, "not a closed round") end
    local facts = factsOf(rid, breathe)
    if not facts then return refuse(p, id, STATUS.expired, "no readable index") end
    if not IsValid(p) or not K.TapeMayView(p, rid, facts) then return refuse(p, id, STATUS.denied, "not their round") end
    local c = facts.chunks[seq]
    if not c or c.bytes <= 0 or c.bytes > CHUNK_MAX then return refuse(p, id, STATUS.expired, "no such chunk") end
    local fd = file.Open(ROOT .. "/" .. rid .. "/tape.dat", "rb", "DATA")
    breathe("serve.open")
    if not fd then return refuse(p, id, STATUS.expired, "no tape.dat") end
    if c.off + c.bytes > fd:Size() then fd:Close() return refuse(p, id, STATUS.expired, "chunk outside the file") end
    fd:Seek(c.off)
    local parts, left = {}, c.bytes
    while left > 0 do
        local n = math.min(READ_CHUNK, left)
        parts[#parts + 1] = fd:Read(n) or ""
        left = left - n
        if n > stats.readMax then stats.readMax = n end
        breathe("serve.chunk")
    end
    fd:Close()
    local blob = table.concat(parts)
    if #blob ~= c.bytes or string.sub(blob, 1, 5) ~= "ZCT1\n" then return refuse(p, id, STATUS.expired, "not a chunk") end
    send(p, id, blob)
end

----------------------------------------------------------------- requests and backpressure
-- One transfer per viewer at a time (K.Busy). What cannot go yet waits: one list-or-index request and QUEUE chunk
-- requests. Chunks are served NEWEST FIRST and the oldest is dropped once the queue is full: a viewer who asks again
-- has moved the playhead, and the chunk they want now is the one they asked for last.
local function begin(p, id)
    local slot = S.want[p]
    slot.running = true
    -- P2: a player-class job is queued LOW priority (K.Work's 4th arg, sv_clips.lua ~104) so it always runs behind
    -- life.cut/life.pack (sv_life.lua:204,314, normal tier) - CPU time for a death killcam never waits on a replay
    -- read.
    local isPlayer = K.TapeClass(p) == "player"
    if isPlayer then S.playerActive[p] = true end
    local function finish()
        slot.running = false
        if isPlayer then S.playerActive[p] = nil end
    end
    K.Work("tapeserve", function(breathe)
        local rid, tail = string.match(id, "^tape:(%d+_%d+):(%w+)$")
        if id == "tape:list" then
            serveList(p, id, breathe)
        elseif rid then
            if tail == "index" then serveIndex(p, id, rid, breathe) else serveChunk(p, id, rid, tonumber(tail), breathe) end
        else
            serveList(p, id, breathe, tonumber(string.match(id, "^tape:list:(%d+)$")))
        end
        finish()
    end, finish, isPlayer)
end

function K.TapeServePump()
    local playerActive = 0
    for _ in pairs(S.playerActive) do playerActive = playerActive + 1 end
    for p, slot in pairs(S.want) do
        if not IsValid(p) then
            S.want[p] = nil
        elseif not slot.running and not K.Busy(p) then
            local hasWork = slot.meta ~= nil or #slot.chunks > 0
            if not hasWork then
                S.want[p] = nil
            elseif K.TapeClass(p) == "player" and playerActive >= MAX_PLAYER_ACTIVE then
                -- at the cap: leave this player queued so admin/operator/death-killcam traffic keeps the shared lane
            else
                local id = slot.meta
                if id then slot.meta = nil else id = table.remove(slot.chunks) end
                begin(p, id)
                if K.TapeClass(p) == "player" then playerActive = playerActive + 1 end
            end
        end
    end
end
hook.Add("Think", "ZCKillcam.TapeServe", function() if next(S.want) ~= nil then K.TapeServePump() end end)
hook.Add("PlayerDisconnected", "ZCKillcam.TapeServe", function(p) S.want[p] = nil end)

-- Called by sv_net.lua's zckc_clip receiver for every id that starts "tape:".
function K.TapeRequest(p, id)
    if not IsValid(p) then return end
    stats.asked = stats.asked + 1
    local class = K.TapeClass(p)
    if not class then return refuse(p, id, STATUS.denied, "not staff") end
    if class == "player" then stats.playerAsked = (stats.playerAsked or 0) + 1 end
    local now = CurTime()
    if (p.zckcTapeNext or 0) > now then return end
    p.zckcTapeNext = now + ASK_GAP
    -- the round id's shape is validated by the pattern even though only the tail is read here; begin() re-parses it
    local tail = string.match(id, "^tape:%d+_%d+:(%w+)$")
    -- D3 paging: "tape:list:<t>" and nothing looser - t is digits only, no sign, no decimal point
    local listBefore = string.match(id, "^tape:list:(%d+)$")
    local meta = id == "tape:list" or listBefore ~= nil or tail == "index"
    if not meta and not (tail and #tail <= 5 and string.match(tail, "^%d+$")) then return end -- not a request this file knows
    if K.ViewLocked(p) then return refuse(p, id, STATUS.locked, "alive in a traitor round") end
    local slot = S.want[p]
    if not slot then slot = {chunks = {}} S.want[p] = slot end
    if meta then
        slot.meta = id
    else
        for i = 1, #slot.chunks do if slot.chunks[i] == id then return end end
        slot.chunks[#slot.chunks + 1] = id
        while #slot.chunks > QUEUE do table.remove(slot.chunks, 1) stats.dropped = stats.dropped + 1 end
    end
end

-- Acceptance instrument: run the real serve work for a round and send it to nobody, so the cost can be read from
-- zc_killcam_work before any client exists. Same precedent as zc_killcam_highlight_replay packing for nobody.
-- It answers no player and touches no cache but the facts every viewer would build anyway.
concommand.Add("zc_killcam_tape_measure", function(p, _, args)
    if IsValid(p) and not p:IsAdmin() then return end
    local rid = tostring(args[1] or "")
    local class = args[2] == "operator" and "operator" or "admin"
    if rid == "list" then -- the crawl an admin's rounds list does, priced with nothing sent
        K.Work("tapemeasure", function(breathe)
            local began, bytes = SysTime(), 0
            local pk = packer(breathe)
            local n, fresh, total = crawl(breathe, function() return true end, function(line) bytes = bytes + #line pk.add(line) end)
            print(string.format("[Killcam tape serve] measured the list: %d rounds on disk, %d read for the first time, %d listed, %d KB of text -> %d KB blob, %.2f s of wall clock",
                total, fresh, n, bytes / 1024, #pk.done() / 1024, SysTime() - began))
        end)
        return
    end
    if not closedEntry(rid) then
        local line = "[Killcam tape serve] " .. rid .. " is not a closed round"
        if IsValid(p) then p:PrintMessage(HUD_PRINTCONSOLE, line) else print(line) end
        return
    end
    K.Work("tapemeasure", function(breathe)
        local began = SysTime()
        local facts = factsOf(rid, breathe)
        if not facts then print("[Killcam tape serve] no readable index for " .. rid) return end
        local pk, lines, since = packer(breathe), 0, 0
        eachLine(ROOT .. "/" .. rid .. "/index.txt", breathe, function(row)
            local kept = class == "admin" and row or forOperator(row)
            if kept then pk.add(kept) end
            lines = lines + 1
            since = since + 1
            if since >= LINES_UNIT then since = 0 breathe("serve.filter") end
        end)
        local blob = pk.done()
        local seq, biggest = nil, 0
        for n, c in pairs(facts.chunks) do if c.bytes > biggest then seq, biggest = n, c.bytes end end
        local bytes = 0
        if seq then
            local c, fd = facts.chunks[seq], file.Open(ROOT .. "/" .. rid .. "/tape.dat", "rb", "DATA")
            breathe("serve.open")
            if fd and c.off + c.bytes <= fd:Size() then
                fd:Seek(c.off)
                local left = c.bytes
                while left > 0 do
                    local n = math.min(READ_CHUNK, left)
                    bytes = bytes + #(fd:Read(n) or "")
                    left = left - n
                    breathe("serve.chunk")
                end
            end
            if fd then fd:Close() end
        end
        print(string.format("[Killcam tape serve] measured %s as %s: %d index lines -> %d KB blob, biggest chunk #%s %d KB read in %.2f s of wall clock (see zc_killcam_work for the units)",
            rid, class, lines, #blob / 1024, tostring(seq), bytes / 1024, SysTime() - began))
    end)
end)

concommand.Add("zc_killcam_tapeserve", function(p)
    if IsValid(p) and not p:IsAdmin() then return end
    local rounds, packed, waiting = 0, 0, 0
    for _ in pairs(S.facts) do rounds = rounds + 1 end
    for _ in pairs(S.packed) do packed = packed + 1 end
    for _ in pairs(S.want) do waiting = waiting + 1 end
    local line = string.format("[Killcam tape serve %s] asked=%d sent=%d refused=%d dropped=%d MB=%.2f largestRead=%d | rounds known=%d indexes packed=%d viewers waiting=%d",
        K.TapeServeVersion, stats.asked, stats.sent, stats.refused, stats.dropped, stats.bytes / 1048576, stats.readMax, rounds, packed, waiting)
    local playerActive = 0
    for _ in pairs(S.playerActive) do playerActive = playerActive + 1 end
    local playerLine = string.format("[Killcam tape serve players] zc_killcam_replay=%d asked=%d sent=%d refused=%d MB=%.2f active=%d/%d",
        replay:GetInt(), stats.playerAsked or 0, stats.playerSent or 0, stats.playerRefused or 0, (stats.playerBytes or 0) / 1048576, playerActive, MAX_PLAYER_ACTIVE)
    if IsValid(p) then
        p:PrintMessage(HUD_PRINTCONSOLE, line)
        p:PrintMessage(HUD_PRINTCONSOLE, playerLine)
    else
        print(line)
        print(playerLine)
    end
end)
