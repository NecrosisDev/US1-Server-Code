-- ZC Killcam round tape (server only) 20260921.tape10
--
-- Every round, written to disk as it happens, in ten-second chunks that each stand alone as a seek point.
-- Existing owner: zc_killcam. Extension seam: the recorder's READ api (K.EachSample / K.EachEvent / K.EachRagFrame /
-- K.Identity / K.WeaponName) - the 20 Hz sampling path is not touched and pays nothing for this file.
-- Current consumer: work/killcam/tape_reader.py (offline). The staff player and the bookmark cutter come later.
--
-- THE ONE RULE: no unit of work above 2 ms, ever, and about 1 ms of work per tick. A round is never encoded at once,
-- and neither is a chunk: a chunk is a coroutine that gathers one slot, packs one piece, writes one file, and hands
-- the tick back whenever its slice is spent. Every unit is timed; the counters are the acceptance test.
--
-- ON DISK  data/zc_killcam/tapes/<roundId>/
--   index.txt   append-only, one JSON object per line. The FIRST line is the head (map, mode, clocks, versions), the
--               LAST is the end (reason, length, totals); between them chunks (with their offset into tape.dat),
--               roster changes, weapon ids, deaths, hard cuts. Append-only on purpose: O(1) per chunk, and a crash can cost the last
--               line, never the file. A chunk counts only once its index line exists, so a torn tail is ignored.
--   tape.dat    every chunk of the round, back to back, through ONE file handle held open for the round. Measured on
--               US1 (tape2, a new file per chunk): file.Write averaged 0.67 ms and spiked to 7.9 ms - creating a file
--               is a metadata operation on a shared disk. Appending to an open handle is not.
--   a chunk     "ZCT1\n" <header json> "\n" <payload>. A piece is one slot's rows (or ragdoll frames, or events) as
--               comma-separated integers, DELTA-coded against the previous row of the same piece (first row absolute,
--               so a piece - and therefore a chunk - still stands alone). Compress cost on US1 is linear in the text
--               it is given (~0.17 ms/KB), and deltas are a third of the text. Pieces are batched into GROUPS of a few KB and each group is one
--               util.Compress stream: the header lists groups {off, len} and pieces {k, slot, g, a, n, ...} where
--               g/a/n locate the piece inside its inflated group. Groups bound the one unit that cannot be sliced
--               (a compress call) and still let a reader inflate only the part of a chunk it needs.
--   ../catalog.txt   a log of {id, t, bytes, open | gone}, last line per round wins. Retention reads this and nothing else.
--
-- LIFECYCLE (verified in zcity/gamemode/libraries/sv_roundsystem.lua): ZB_StartRound :606 opens a tape, ZB_PreRoundStart
-- :156 closes it, so the end-of-round aftermath (ROUND_STATE 3) is on the tape. zb.ROUND_STATE is also polled once a
-- second, so a hot load in the middle of a round starts a tape marked partial instead of waiting for the next hook.
if not SERVER then return end
local K = assert(ZCKillcam, "recorder must load first")
K.TapeVersion = "20260922.tape24"

local ROOT = "zc_killcam/tapes"
local tapeOn = CreateConVar("zc_killcam_tape", "0", FCVAR_ARCHIVE, "Write every round to disk as a chunked tape (server only, invisible to players)")
local capMb = CreateConVar("zc_killcam_tape_mb", "2000", FCVAR_ARCHIVE, "Disk budget for round tapes; the oldest unpinned rounds are deleted first", 50, 50000)
-- P7 (killcam_revitalize, 2026-09-24): A/B of the batch sizes below, for zc_killcam_tape_stats. 0 = as shipped
-- (RAG_BATCH 10, GROUP_RAW 4096); 1 = 16 / 5120 - fewer, larger ragdoll pieces and pack groups (fewer units, each a
-- little heavier: the <8 KB pack curve is 1.19 ms average, 1.93 ms worst on US1). The FORMAT does not change: every
-- piece carries its own frame count and every group its own offset/length, so a reader never assumes a batch size.
-- Read once per chunk. On K so it is not a new file-scope local.
K.TapeBatch = K.TapeBatch or CreateConVar("zc_killcam_tape_batch", "0", FCVAR_ARCHIVE, "Round tape batch sizes: 0 as shipped (10 ragdoll frames / 4 KB groups), 1 larger (16 / 5 KB) - an A/B for zc_killcam_tape_stats", 0, 1)

-- PROVISIONAL(2026-09-21, sized from the blueprint before any live measurement; retune from zc_killcam_tape_stats, ratify-by: 2026-10-05)
local CHUNK      = 10     -- seconds per chunk = seek granularity. The sample ring holds 16-20 s, so a chunk must be cut within ~6 s of closing
local SETTLE     = 0.15   -- let the sample that lands exactly on the boundary arrive first
local SLICE      = 0.001  -- seconds of tape work per tick
local LIMIT      = 0.002  -- the acceptance line: a single unit above this is counted in stats.over
local ROWS_PIECE          -- sample rows per piece; bounds the cost of one concat and one compress. Set below, from ROW,
                          -- because the thing being bounded is NUMBERS, not rows. Held at 96 while the row grew from 13
                          -- to 29 it would have tripled the text in one piece and pushed a single piece past GROUP_RAW,
                          -- at which point every piece is its own group and grouping stops meaning anything.
local RAG_BATCH  = 10     -- ragdoll frames per piece (a frame is up to 145 numbers, so ~7 KB of text)
local GROUP_RAW  = 4096   -- (US1: <4 KB packs average 0.66 ms, <8 KB 1.19 ms with a 1.93 ms worst case - too close to the line)
--  bytes of text per compressed group; stats.stage "pack<N" is the cost curve this is tuned from
local PACK_ROOM  = 0.0002 -- a pack is the one heavy unit, so it never starts late in a slice: it gets a tick of its own
local BATCH_NUMS = 900    -- numbers per event / track piece (~3 KB of delta text). US1, tape8: 400-row pieces of the wide
                          -- tracks made 8-16 KB groups that packed in 2.1-2.5 ms - over the line
local POSE_W = K.PoseN or 10 -- pose parameter slots kept per row; fixed, because a tape row is a fixed stride
local ROW, EVROW = 28 + POSE_W, 10 -- yaw/mode, grip/carry masks, carry target/aim
-- Event column 10: melee animation duration in milliseconds, 0 for legacy/other events.
-- A positive duration identifies an animation-start timestamp. Existing columns keep their meanings.
                          -- numbers per sample row / per event row. Rows 11-13: the first-person eye (hg.eye) in tenths of a
                          -- unit from the row's own rounded position, 0 0 0 when the recorder did not know it. 14-16 the
                          -- recorded velocity in whole units/s, 17 the sequence the server was playing (-1 unknown), 18 its
                          -- cycle in thousandths, 19 how many pose parameters follow, 20.. those parameters in hundredths
                          -- (a COUNT rather than a sentinel, because "every parameter is zero" is a real pose). Readers take
                          -- the width from the chunk head (`row`), so older 10- and 13-wide tapes still read.
local ANG        = 100    -- view angles in hundredths of a degree (the head's `ang`): what the killcam clips keep for named parties
ROWS_PIECE = math.max(math.floor(1250 / ROW), 8) -- 1250 numbers is the tuned budget: it reproduces the old 96 at the old width of 13

local round = math.Round

-- Survives a hot reload of this file: an open tape carries on, and jobs already queued finish on the code they started with.
local T = K.Tape or {queue = {}, ragStride = 1, clean = 0}
K.Tape = T
T.stats = T.stats or {chunks = 0, bytes = 0, over = 0, errors = 0, degraded = 0, late = 0, ticksMax = 0, pumpMax = 0, pumpSum = 0, pumps = 0, swept = 0, stage = {}}
local stats = T.stats

----------------------------------------------------------------- the worker
-- book() closes one timed unit of work under a stage name. pause() is book() for code running inside a job: it also
-- hands the tick back when the slice is spent. Timers and hooks use book(): they have nothing to yield to.
local function book(stage, began)
    local cost = SysTime() - began
    local s = stats.stage[stage]
    if not s then s = {n = 0, sum = 0, max = 0} stats.stage[stage] = s end
    s.n, s.sum = s.n + 1, s.sum + cost
    if cost > s.max then s.max = cost end
    -- A slow unit during which the Lua heap SHRANK was interrupted by a collector sweep: the whole server's garbage
    -- debt, billed to whoever allocates next. Slicing cannot bound that, so it is counted apart and never degrades
    -- the tape. (US1, tape5: every disk and pack unit under 1.3 ms; the only units over the line were two 8 ms
    -- "concat"s - the one unit that allocates a thousand short strings.)
    local heap = collectgarbage("count")
    if cost > LIMIT then
        if heap < (T.heap or heap) then
            stats.overGc = (stats.overGc or 0) + 1
        else
            stats.over = stats.over + 1
            if T.job then T.job.over = T.job.over + 1 end
        end
    end
    T.heap = heap
end

local function pause(stage, began)
    book(stage, began)
    if T.job and not T.drain and SysTime() - T.sliceBegan > T.slice then coroutine.yield() end -- T.job is nil when staff call a job body directly
end

local function enqueue(kind, fn)
    local job = {kind = kind, over = 0, ticks = 0}
    job.co = coroutine.create(function() fn(job) end)
    T.queue[#T.queue + 1] = job
    return job
end

-- Runs the job at the head of the queue for one slice. Returns true while there is work left.
function K.TapePump()
    local job = T.queue[1]
    if not job then return false end
    local began = SysTime()
    T.job, T.sliceBegan = job, began
    T.slice = #T.queue > 2 and SLICE * 2 or SLICE -- behind: the ring will not wait, so spend more rather than lose a chunk
    job.ticks = job.ticks + 1
    local ok, err = coroutine.resume(job.co)
    if not ok then
        stats.errors = stats.errors + 1
        if not T.errOnce then T.errOnce = true print("[Killcam tape] " .. job.kind .. " job failed: " .. tostring(err)) end
    end
    if not ok or coroutine.status(job.co) == "dead" then
        table.remove(T.queue, 1)
        if job.ticks > stats.ticksMax then stats.ticksMax = job.ticks end
    end
    T.job = nil
    local cost = SysTime() - began
    stats.pumps, stats.pumpSum = stats.pumps + 1, stats.pumpSum + cost
    if cost > stats.pumpMax then stats.pumpMax = cost end
    return T.queue[1] ~= nil
end

-- Map shutdown: nothing is waiting on the frame any more, so finish everything that is queued.
function K.TapeDrain()
    T.drain = true
    local guard = 0
    while K.TapePump() and guard < 100000 do guard = guard + 1 end
    T.drain = false
end

----------------------------------------------------------------- index lines
-- Buffered per tape: when one round supersedes another, the old tape's last chunk is still being cut while the new
-- tape is already collecting lines.
-- A line is kept as a TABLE by whoever raises it (often a game hook, where microseconds matter) and turned into JSON
-- later by the worker, twenty-five at a time.
local function line(tape, tbl) tape.lines[#tape.lines + 1] = tbl end

local function encodeLines(tape)
    local raw = tape.lines
    if #raw == 0 then return end
    tape.lines = {}
    tape.ready = tape.ready or {}
    for first = 1, #raw, 25 do
        local began = SysTime()
        for i = first, math.min(first + 24, #raw) do tape.ready[#tape.ready + 1] = util.TableToJSON(raw[i]) end
        pause("marks", began)
    end
end

local function flushLines(tape)
    local ready = tape.ready or {}
    for i = 1, #tape.lines do ready[#ready + 1] = util.TableToJSON(tape.lines[i]) end -- the few raised since encodeLines
    tape.lines, tape.ready = {}, {}
    if #ready == 0 then return end
    local body = table.concat(ready, "\n") .. "\n"
    if tape.fi then
        tape.fi:Write(body)
        tape.fi:Flush()
    else
        file.Append(ROOT .. "/" .. tape.id .. "/index.txt", body)
    end
end

----------------------------------------------------------------- gathering
-- One slot's samples inside (t0, t1] as a flat run of integers, ROW per row. A player who is not changing collapses
-- to the first and last row of the run, exactly as clips do - so every chunk still opens with a row for everyone
-- present, which is what makes it a seek point.
-- perf 2026-09-21: cutChunk used to allocate a fresh integer array per slot, per piece copy, per ragdoll walk and per
-- ragdoll batch - the bulk of the 186 KB/s of Lua garbage measured in Think/ZCKillcam.Tape at 23-31 players. None of
-- them outlives the chunk (only the text addPiece builds is kept), so they are scratch arrays now: reused, never shrunk.
-- Exactly one tape job runs at a time - K.TapePump resumes only T.queue[1] and drops it only when it is dead, and
-- cutChunk runs only inside an enqueue'd job body - so no two users of a buffer are ever live together, not even across
-- the coroutine yields inside addPiece/pause. Every consumer is bounded by an explicit count, so numbers left behind by
-- a longer slot are never read and the bytes written are identical.
local sampleBuf, pieceBuf, refBuf, ragBuf, trackBuf = {}, {}, {}, {}, {}
-- A row and the previous one, reused for the life of the server: the row is wide enough now that naming every field
-- twice over was the thing most likely to go quietly out of step with the recorder.
local curRow, prevRow = {}, {}
local function gatherSamples(tape, slot, t0, t1)
    local out, n, rows = sampleBuf, 0, 0
    local heldAt, have
    local lastCs = 0
    K.EachSample(slot, t0, t1, function(t, x, y, z, yaw, pitch, flags, wep, hp, eye, ex, ey, ez, vx, vy, vz, seq, cyc, pose, pb, pn, bodyYaw, animMode, grip, carry, cx, cy, cz, cp, cyaw)
        if t <= t0 then return end
        -- Shot and hit stamps are timed on the shooter's command clock, which runs a few centiseconds off the server's,
        -- so ring order is the truth and the timestamp is nudged to agree with it: time never runs backwards on a tape.
        local cs = round((t - t0) * 100)
        if cs < lastCs then cs = lastCs end
        lastCs = cs
        local rx, ry, rz = round(x), round(y), round(z)
        if ez and ez ~= 0 then ex, ey, ez = round((x + ex - rx) * 10), round((y + ey - ry) * 10), round((z + ez - rz) * 10) else ex, ey, ez = 0, 0, 0 end
        local c = curRow
        c[1], c[2], c[3], c[4], c[5] = cs, rx, ry, rz, round(yaw * ANG)
        c[6], c[7], c[8], c[9], c[10] = round(pitch * ANG), flags, wep, hp, round(eye or 64)
        c[11], c[12], c[13] = ex, ey, ez
        c[14], c[15], c[16] = round(vx or 0), round(vy or 0), round(vz or 0)
        c[17], c[18], c[19] = seq or -1, round((cyc or 0) * 1000), pn or 0
        for k = 1, POSE_W do c[19 + k] = (pn and k <= pn) and round(pose[pb + k] * 100) or 0 end
        c[20 + POSE_W], c[21 + POSE_W] = round((bodyYaw or 0) * 100), animMode or 0
        c[22 + POSE_W], c[23 + POSE_W] = grip or 0, carry or 0
        c[24 + POSE_W], c[25 + POSE_W], c[26 + POSE_W] = round((cx or 0) * 10), round((cy or 0) * 10), round((cz or 0) * 10)
        c[27 + POSE_W], c[28 + POSE_W] = round((cp or 0) * 100), round((cyaw or 0) * 100)
        local same = have
        if same then for f = 2, ROW do if c[f] ~= prevRow[f] then same = false break end end end
        if same then
            heldAt = cs
            return
        end
        if heldAt then
            out[n + 1] = heldAt
            for f = 2, ROW do out[n + f] = prevRow[f] end
            n, rows, heldAt = n + ROW, rows + 1, nil
        end
        if wep ~= (have and prevRow[8] or -1) and wep > 0 and not tape.weps[wep] then
            tape.weps[wep] = true
            line(tape, {k = "wep", id = wep, class = K.WeaponName(wep)})
        end
        for f = 1, ROW do out[n + f] = c[f] prevRow[f] = c[f] end
        n, rows, have = n + ROW, rows + 1, true
    end)
    if heldAt then
        out[n + 1] = heldAt
        for f = 2, ROW do out[n + f] = prevRow[f] end
        rows = rows + 1
    end
    return out, rows
end

-- Who is in a slot, as of this chunk. The recorder caches identity when a slot changes hands, but Z-City dresses the
-- player after that, so the model is read from the live entity and a change of model is a new roster line.
local function roster(tape, slot, t0)
    local who = K.Identity(slot)
    if not who then return 0 end
    local ent = Player and Player(who.uid) or nil
    local live = IsValid(ent)
    local model = live and ent:GetModel() or who.model or ""
    local key = who.uid .. "|" .. model
    if tape.roster[slot] ~= key then
        tape.roster[slot] = key
        local entry = {k = "who", t = round((t0 - tape.t0) * 100), slot = slot, uid = who.uid, sid = who.id, name = who.name, model = model}
        if live then
            entry.skin = ent:GetSkin()
            -- The ARRAY, not a flattened string. `table.concat(groups, "")` was unreadable the moment any bodygroup
            -- had ten or more submodels - and the rebel models on this server go to 15, so {0,12,3} came out "0123"
            -- and reads back as four groups of 0,1,2,3. Nothing consumes this field TODAY (sv_tapeserve reads only
            -- `sid` and `uid` off a who mark), but a tape is durable: every round recorded with the flattened form
            -- is permanently wrong for the replay viewer that will read it, so this is fixed at the writer now.
            -- All-zero is dropped entirely, exactly as the recorder does it (sv_recorder.lua look()): most players
            -- wear nothing, and a row of zeroes is not worth the bytes - so this is also SMALLER than what it replaces.
            local groups, worn = {}, false
            for g = 1, ent:GetNumBodyGroups() do
                local v = ent:GetBodygroup(g - 1)
                groups[g] = v
                if v ~= 0 then worn = true end
            end
            entry.groups = worn and groups or nil
            local c = ent:GetPlayerColor()
            entry.colour = {round(c.x * 255), round(c.y * 255), round(c.z * 255)}
        end
        line(tape, entry)
    end
    -- Staff-only: who the traitor is, whenever that changes (ply.isTraitor is the gamemode's own field).
    local traitor = live and ent.isTraitor == true or false
    if (tape.traitor[who.uid] or false) ~= traitor then
        tape.traitor[who.uid] = traitor
        line(tape, {k = "traitor", t = round((t0 - tape.t0) * 100), uid = who.uid, v = traitor})
    end
    return who.uid
end

-- Ragdoll frames are collected as references first (one cheap walk of the ring), then rounded and packed a batch at
-- a time with a pause between batches: the ring holds 15 s, so the cells cannot be overwritten under us.
--
-- EachRagFrame emits both clipped boundaries of a coalesced resting pose.
local function ragRefs(slot, t0, t1)
    local refs, data = refBuf, nil
    local stride, k, rn = T.ragStride, 0, 0
    K.EachRagFrame(slot, t0, t1, function(t, d, base, n)
        if n > 0 then
            k = k + 1
            if k == 1 or t == t1 or k % stride == 0 or stride == 1 then
                refs[rn + 1], refs[rn + 2], refs[rn + 3], data = t, base, n, d
                rn = rn + 3
            end
        end
    end)
    return refs, data, rn
end

----------------------------------------------------------------- tape-owned tracks
-- Everything below is recorded by the tape itself, without touching the recorder. Two shapes:
--
--   ROW TRACKS  dense numbers, buffered live and drained into each chunk as a piece of their own:
--       s  bullet segments   cs, shooter slot, start xyz, end xyz, surface, hit slot (-1 world, 0 other)
--       o  organism, 2 Hz    cs, slot, blood, bleed x10, pain, shock, consciousness %, unconscious, brain %, adrenaline %
--       x  entity poses      cs, tape entity id, pos xyz, ang pyr   (throwables, moving props, vehicles; 10 Hz, on change)
--       w  wound channel     cs, victim slot, shooter slot, organ name id, bone name id, entry xyz (bone-local, x10),
--                            direction xyz (bone-local, x100), damage x100, ricochet, entry xyz (world)   - one row per organ a bullet crossed
--      Rows are written on change, so every chunk is opened with a KEYFRAME of each track: whatever a reader seeks
--      to, the state of every body and every known entity is inside that one chunk.
--   MARKS       sparse facts, one index line each: ent / entgone, dmg (non-player damage), door, chat, role, traitor,
--      otrub / wake, veh, drop / equip, join / leave, roundend. The index is small and read whole, so marks need no
--      keyframes: a reader folds them from the start of the round.
--
-- STAFF-ONLY DATA: chat, role and traitor marks must never reach a player whose round is still running. Nothing
-- sends index.txt anywhere today; the window cutter (step 4) has to filter by mark kind, not pass lines through.
local TRACKS = {s = {stride = 10, max = 1500}, o = {stride = 10, max = 800}, x = {stride = 8, max = 4000}, w = {stride = 16, max = 1200}}
local TRACK_ORDER = {"s", "o", "x", "w"}
local MARK_MAX = 800     -- index lines buffered per chunk; a flood of anything is counted, not written
local HOT_MAX, KNOWN_MAX = 48, 256
T.buf = T.buf or {}
stats.dropped = stats.dropped or {}

local function room(k)
    local b = T.buf[k]
    if not b then b = {d = {}, n = 0} T.buf[k] = b end
    if b.n >= TRACKS[k].max * TRACKS[k].stride then stats.dropped[k] = (stats.dropped[k] or 0) + 1 return nil end
    return b
end

local function mark(tbl)
    local tape = T.cur
    if not tape then return end
    if #tape.lines >= MARK_MAX then stats.dropped.marks = (stats.dropped.marks or 0) + 1 return end
    tbl.t = tbl.t or round((CurTime() - tape.t0) * 100)
    tape.lines[#tape.lines + 1] = tbl
end

-- Moves the rows that belong to (.., t1] out of a live buffer. Column 1 is a CurTime; hooks that run inside a player's
-- command see that player's clock, so it is clamped into the chunk rather than trusted. Producers round the rest.
local function takeRows(k, t0, t1)
    local b, stride = T.buf[k], TRACKS[k].stride
    if not b or b.n == 0 then return nil, 0 end
    local d, out, on, keep, kn = b.d, trackBuf, 0, {}, 0
    local len = round((t1 - t0) * 100)
    for i = 1, b.n, stride do
        if d[i] <= t1 then
            out[on + 1] = math.Clamp(round((d[i] - t0) * 100), 0, len)
            for c = 1, stride - 1 do out[on + 1 + c] = d[i + c] end
            on = on + stride
        else
            for c = 0, stride - 1 do keep[kn + 1 + c] = d[i + c] end
            kn = kn + stride
        end
    end
    b.d, b.n = keep, kn
    return out, on / stride
end

local function slotOfEnt(e)
    if not IsValid(e) then return 0 end
    if e:IsPlayer() then return e:EntIndex() end
    local owner = e.ply or (e.GetOwner and e:GetOwner()) -- a fake ragdoll (hg.RagdollOwner: ragdoll.ply) or a weapon stands for its player
    if IsValid(owner) and owner:IsPlayer() then return owner:EntIndex() end
    return 0
end

---- s: bullet segments
-- Source: PostEntityFireBullets, which Z-City's Lua bullets run once per traced segment - first flight, every
-- penetration, every ricochet - with the finished trace (homigrad/sh_luabullets.lua:835; sv_util's suppression and
-- three weapons already listen). Observed only, nothing returned: a bullet is never altered. GAP: the phys-bullet
-- plugin does not run this hook (phys_bullets/sh_plugin.lua:1023 is commented out): those weapons leave shots only.
hook.Add("PostEntityFireBullets", "ZCKillcam.Tape", function(ent, data)
    if not T.cur then return end
    local tr = data and data.Trace
    if not tr or not tr.HitPos or not tr.StartPos then return end
    local b = room("s")
    if not b then return end
    local d, n, a, h = b.d, b.n, tr.StartPos, tr.HitPos
    local shooter = slotOfEnt(data.Attacker)
    if shooter == 0 then shooter = slotOfEnt(ent) end
    d[n + 1], d[n + 2], d[n + 3], d[n + 4], d[n + 5] = CurTime(), shooter, round(a.x), round(a.y), round(a.z)
    d[n + 6], d[n + 7], d[n + 8], d[n + 9], d[n + 10] = round(h.x), round(h.y), round(h.z), tr.MatType or 0, tr.HitWorld and -1 or slotOfEnt(tr.Entity)
    b.n = n + 10
    -- No return value: this hook must never alter the bullet.
end)

-- Contact discharges bypass both bullet engines. Record the owner-provided segment without
-- running a new trace or applying damage. Material 0 means unknown; this is not a bullet trace.
hook.Add("ZCityHostageContactShot", "ZCKillcam.ContactSegment", function(owner, weapon, source, direction, targetPosition, target)
    if not T.cur or not IsValid(owner) or not IsValid(weapon) or not IsValid(target)
        or not isvector(source) or not isvector(targetPosition) then return end
    local shooter = slotOfEnt(owner)
    if shooter == 0 then return end
    local b = room("s")
    if not b then return end
    local d, n = b.d, b.n
    d[n + 1], d[n + 2], d[n + 3], d[n + 4], d[n + 5] = CurTime(), shooter, round(source.x), round(source.y), round(source.z)
    d[n + 6], d[n + 7], d[n + 8], d[n + 9], d[n + 10] = round(targetPosition.x), round(targetPosition.y), round(targetPosition.z), 0, slotOfEnt(target)
    b.n = n + 10
end)

---- o: organism - WHY someone dropped. Fields verified in homigrad/organism/tier_1 (blood 0-5000, consciousness 0-1,
-- otrub = unconscious). Anything missing or not a finite number is written as 0 rather than trusted.
local function num(v, mul)
    if type(v) ~= "number" or v ~= v or v > 1e7 or v < -1e7 then return 0 end
    return round(v * mul)
end
---- w: the wound channel - which organs a bullet crossed, in order, and where.
-- Z-City already traces every bullet through the victim's organ boxes (organism/tier_0/sh_hitboxorgans.lua builds them
-- per bone; tier_1/sv_input.lua Trace_Bullet walks them) and announces each crossing BEFORE applying it:
--     PreTraceOrganBulletDamage(org, bone, dmg, dmgInfo, box, dir, hit, ricochet, organ, hook_info)
-- box = {pos, ang, mins, maxs, center, boneName, organKey}, organ[1] = its name ("heart", "lungsR", "liver", "spine1",
-- "vest", "helmet" ...), hit = where the bullet met it, in the world. The entry point and direction are stored
-- relative to the organ's BONE, so a replay can draw the channel on the body in whatever pose it is in, and the
-- client can rebuild the organ boxes from the same shared tables.
-- hook_info is the gamemode's way to veto or rescale the damage: it is never written here. Nothing is returned.
local function nameId(tape, text)
    local id = tape.names[text]
    if not id then
        tape.nameN = tape.nameN + 1
        id = tape.nameN
        tape.names[text] = id
        mark({k = "name", id = id, s = text})
    end
    return id
end

local function wound(tape, org, dmgInfo, box, dir, hit, ricochet, organ, info)
    if not isvector(hit) or not isvector(dir) or not istable(box) or not istable(organ) then return end
    local b = room("w")
    if not b then return end
    local victim = slotOfEnt(org and org.owner)
    local shooter = slotOfEnt(dmgInfo and dmgInfo:GetAttacker())
    local at = WorldToLocal(hit, angle_zero, box[1], box[2])
    local ahead = WorldToLocal(hit + dir:GetNormalized(), angle_zero, box[1], box[2])
    local d, n = b.d, b.n
    d[n + 1], d[n + 2], d[n + 3] = CurTime(), victim, shooter
    d[n + 4], d[n + 5] = nameId(tape, tostring(organ[1])), nameId(tape, tostring(box[6]))
    d[n + 6], d[n + 7], d[n + 8] = round(at.x * 10), round(at.y * 10), round(at.z * 10)
    d[n + 9], d[n + 10], d[n + 11] = round((ahead.x - at.x) * 100), round((ahead.y - at.y) * 100), round((ahead.z - at.z) * 100)
    d[n + 12], d[n + 13] = num(istable(info) and info.dmg, 100), ricochet and 1 or 0
    -- ...and in the world too: on US1 some boxes sit far from their bone (a pelvis entry read 60 units out), so the
    -- player can fall back to placing the channel where it really was.
    d[n + 14], d[n + 15], d[n + 16] = round(hit.x), round(hit.y), round(hit.z)
    b.n = n + 16
end

T.orgLast = T.orgLast or {}
local function sampleOrganism(now)
    for _, p in ipairs(player.GetAll()) do
        local org, s = p.organism, p:EntIndex()
        if istable(org) then
            local a1, a2, a3, a4 = num(org.blood, 1), num(org.bleed, 10), num(org.pain, 1), num(org.shock, 1)
            local a5, a6, a7, a8 = num(org.consciousness, 100), org.otrub and 1 or 0, num(org.brain, 100), num(org.adrenaline, 100)
            local last = T.orgLast[s]
            if not last then last = {} T.orgLast[s] = last end
            if last[1] ~= a1 or last[2] ~= a2 or last[3] ~= a3 or last[4] ~= a4 or last[5] ~= a5 or last[6] ~= a6 or last[7] ~= a7 or last[8] ~= a8 then
                local b = room("o")
                if not b then return end
                local d, n = b.d, b.n
                d[n + 1], d[n + 2], d[n + 3], d[n + 4], d[n + 5], d[n + 6], d[n + 7], d[n + 8], d[n + 9], d[n + 10] = now, s, a1, a2, a3, a4, a5, a6, a7, a8
                b.n = n + 10
                last[1], last[2], last[3], last[4], last[5], last[6], last[7], last[8] = a1, a2, a3, a4, a5, a6, a7, a8
            end
        end
    end
end
-- This runs inside the gamemode's damage path, once per organ per bullet: fenced, so a surprise in its arguments
-- costs a counter and can never interrupt a hit being applied.
hook.Add("PreTraceOrganBulletDamage", "ZCKillcam.Tape", function(org, _, _, dmgInfo, box, dir, hit, ricochet, organ, info)
    local tape = T.cur
    if not tape then return end
    if not pcall(wound, tape, org, dmgInfo, box, dir, hit, ricochet, organ, info) then
        stats.dropped.woundErrors = (stats.dropped.woundErrors or 0) + 1
    end
end)

hook.Add("HG_OnOtrub", "ZCKillcam.Tape", function(p) if IsValid(p) then mark({k = "otrub", uid = p:UserID()}) end end)
hook.Add("HG_OnWakeOtrub", "ZCKillcam.Tape", function(p) if IsValid(p) then mark({k = "wake", uid = p:UserID()}) end end)

---- x: entities. A registry kept by OnEntityCreated / EntityRemoved - never a scan of ents.GetAll() per tick.
--   throw  ent_hg_* (grenades, molotov, pipebomb, slam, smoke ...): hot from creation to removal
--   veh    vehicles: hot while occupied, and for a moment after
--   prop   prop_physics*, loose prop_ragdoll (not a player's body): hot only while moving; a few are tested per tick, round-robin
--   item   a weapon lying in the world: as a prop; ignored while somebody carries it
--   pill   pill-pack morph entities (pill_ent_costume, pill_ent_phys): hot for life
--   npc    NPCs and nextbots: hot for life, while there is room
--   spawn  anything staff spawned or picked up with the physgun that fits none of the above
T.ents  = T.ents  or {} -- ent -> {kind, id, x, y, z, p, yw, r, hotUntil, hot}
T.hot   = T.hot   or {} -- array of ents sampled at 10 Hz
T.props = T.props or {} -- array of prop ents, for the round-robin motion test
T.known = T.known or {} -- array of ents that have a tape id this round (they get keyframes)
T.doors = T.doors or {} -- array of door ents
T.doorLast = T.doorLast or {}
T.plyLast = T.plyLast or {} -- uid -> last polled state (pill form, model, noclip, flashlight)
T.seldom = T.seldom or {}   -- rate-limit keys -> next allowed CurTime
T.carry = T.carry or {}     -- uid -> the entity that player's hands are carrying
T.voice = T.voice or {}     -- uid -> {on, quietSince}: who is holding the microphone open
local DOOR = {prop_door_rotating = "m_eDoorState", func_door = "m_toggle_state", func_door_rotating = "m_toggle_state"}
local DOOR_SHUT = {prop_door_rotating = 0, func_door = 1, func_door_rotating = 1}

local function classify(ent)
    if not IsValid(ent) or T.ents[ent] then return end
    local class = ent:GetClass()
    if DOOR[class] then T.doors[#T.doors + 1] = ent return end
    local kind
    if string.sub(class, 1, 7) == "ent_hg_" then kind = "throw"
    elseif class == "prop_physics" or class == "prop_physics_multiplayer" then kind = "prop"
    elseif class == "pill_ent_costume" or class == "pill_ent_phys" then kind = "pill"
    elseif class == "prop_ragdoll" and not IsValid(ent.ply) then kind = "prop"
    elseif ent:IsVehicle() and not IsValid(ent:GetParent()) then kind = "veh"
    elseif ent:IsNPC() or ent:IsNextBot() then kind = "npc"
    elseif ent:IsWeapon() then kind = "item" end
    if not kind then return end
    local e = {kind = kind, hotUntil = 0}
    T.ents[ent] = e
    if kind == "prop" or kind == "item" then T.props[#T.props + 1] = ent end
    if kind == "throw" or kind == "pill" or (kind == "npc" and #T.hot < HOT_MAX) then e.hot = true e.hotUntil = math.huge T.hot[#T.hot + 1] = ent end
end

local function heat(ent, seconds)
    local e = T.ents[ent]
    if not e then return end
    e.hotUntil = math.max(e.hotUntil, CurTime() + seconds)
    if not e.hot then
        if #T.hot >= HOT_MAX then stats.dropped.hot = (stats.dropped.hot or 0) + 1 return end
        e.hot = true
        T.hot[#T.hot + 1] = ent
    end
end

-- Gives an entity its id on this tape the first time it has something to say, so props that never move cost nothing.
local function announce(ent, e)
    local tape = T.cur
    if e.tape == tape then return true end
    if #T.known >= KNOWN_MAX then stats.dropped.known = (stats.dropped.known or 0) + 1 return false end
    tape.entSeq = (tape.entSeq or 0) + 1
    e.tape, e.id, e.x = tape, tape.entSeq, nil
    T.known[#T.known + 1] = ent
    local owner = ent.GetOwner and ent:GetOwner() or nil
    mark({k = "ent", id = e.id, kind = e.kind, class = ent:GetClass(), model = ent:GetModel(), skin = ent:GetSkin(), owner = IsValid(owner) and owner:IsPlayer() and owner:UserID() or nil})
    return true
end

local function pose(ent, e, now, force)
    local pos, ang = ent:GetPos(), ent:GetAngles()
    local x, y, z, p, yw, r = round(pos.x), round(pos.y), round(pos.z), round(ang.p), round(ang.y), round(ang.r)
    if not force and e.x == x and e.y == y and e.z == z and e.p == p and e.yw == yw and e.r == r then return false end
    if not announce(ent, e) then return false end
    local b = room("x")
    if not b then return false end
    local d, n = b.d, b.n
    d[n + 1], d[n + 2], d[n + 3], d[n + 4], d[n + 5], d[n + 6], d[n + 7], d[n + 8] = now, e.id, x, y, z, p, yw, r
    b.n = n + 8
    e.x, e.y, e.z, e.p, e.yw, e.r = x, y, z, p, yw, r
    return true
end

local propCursor, doorCursor, orgAt = 0, 0, 0
local pendingDmg = {}

---- actions: everything else a replay wants to show, as index marks (owner, 2026-09-21: "EVERY single action that would
-- be relevant to a round replay, including pill-pack characters, items, props, vehicles" and staff context-menu actions).
-- watch() is the only way these hooks are added: the body runs fenced and NOTHING is ever returned, because several of
-- these are question hooks (ULibCommandCalled, CanTool, PlayerUse, HG_ReplacePhrase, PlayerGiveSWEP) where a return
-- value would change the game. The identifier differs from "ZCKillcam.Tape" so a watched event can also have a plain hook.
-- STAFF-ONLY kinds (same rule as chat/role/traitor): staff, spawn, physgun, tool, give.
local function watch(event, fn)
    hook.Add(event, "ZCKillcam.TapeWatch", function(...)
        if not T.cur then return end
        if not pcall(fn, ...) then stats.dropped.watchErrors = (stats.dropped.watchErrors or 0) + 1 end
    end)
end
local function uidOf(e)
    if not IsValid(e) then return nil end
    if e:IsPlayer() then return e:UserID() end
    local owner = e.ply or (e.GetOwner and e:GetOwner())
    return IsValid(owner) and owner:IsPlayer() and owner:UserID() or nil
end
-- Who or what an action was done to: a player (uid), a tracked entity (its tape id) and always the class.
local function target(tbl, ent)
    if not IsValid(ent) then return tbl end
    tbl.to, tbl.class = uidOf(ent), ent:GetClass()
    local e = T.ents[ent]
    if e and e.tape == T.cur then tbl.id = e.id end
    return tbl
end
local function at(tbl, pos)
    if pos then tbl.pos = {round(pos.x), round(pos.y), round(pos.z)} end
    return tbl
end
-- one mark per key per `gap` seconds: hooks that fire every tick while a key is held, or once per flame
local function seldom(key, gap)
    local now = CurTime()
    if (T.seldom[key] or 0) > now then return false end
    T.seldom[key] = now + gap
    return true
end

-- Staff. ULib runs this for every ulx command however it was issued - chat, console, the XGUI menu, a bind.
watch("ULibCommandCalled", function(p, cmd, args)
    mark({k = "staff", how = "ulx", uid = IsValid(p) and p:UserID() or 0, cmd = tostring(cmd), args = string.sub(table.concat(istable(args) and args or {}, " "), 1, 160)})
end)
-- Context-menu ("C" menu) actions are properties: the client sends net message "properties" and the library calls
-- prop:Receive(len, ply). Z-City's player properties (admintools/sh_player_properties.lua: strip, freeze, ragdollize,
-- lobotomize, killsilent, amputate_limb, setplayerclass ...) and extra_context's do not run CanProperty, so there is
-- no hook to listen to. Each property's Receive is wrapped once: the wrapper notes who and which, then calls the
-- original with the same arguments. It cannot read the message (that would consume it), so the target is the entity
-- under the staff member's cursor - the context menu aims GetAimVector at the mouse - and is marked aim = true.
-- PROVISIONAL(2026-09-21, the only seam in this file that is not a hook; replace if the gamemode grows a property hook, ratify-by: 2026-10-21)
function T.noteProperty(name, p)
    if not T.cur or not IsValid(p) then return end
    local tr = util.TraceLine({start = p:EyePos(), endpos = p:EyePos() + p:GetAimVector() * 8192, filter = p})
    mark(target({k = "staff", how = "menu", uid = p:UserID(), cmd = tostring(name), aim = true}, tr and tr.Entity))
end
local function wrapProperties()
    if not properties or not istable(properties.List) then return end
    for name, prop in pairs(properties.List) do
        if istable(prop) and isfunction(prop.Receive) and not prop.zcTapeReceive then
            local original = prop.Receive
            prop.zcTapeReceive = original
            prop.Receive = function(self, len, p, ...)
                pcall(T.noteProperty, name, p)
                return original(self, len, p, ...)
            end
        end
    end
end
wrapProperties()
hook.Add("InitPostEntity", "ZCKillcam.TapeProperties", wrapProperties)

-- Sandbox: what staff spawn, carry and shoot tools at. A spawned entity is tracked from its first moment.
local adopt
local function spawned(p, ent, model)
    if not IsValid(ent) then return end
    adopt(ent)
    mark(target({k = "spawn", uid = uidOf(p), model = model or ent:GetModel()}, ent))
end
watch("PlayerSpawnedProp", function(p, model, ent) spawned(p, ent, model) end)
watch("PlayerSpawnedRagdoll", function(p, model, ent) spawned(p, ent, model) end)
watch("PlayerSpawnedEffect", function(p, model, ent) spawned(p, ent, model) end)
watch("PlayerSpawnedSENT", function(p, ent) spawned(p, ent) end)
watch("PlayerSpawnedNPC", function(p, ent) spawned(p, ent) end)
watch("PlayerSpawnedVehicle", function(p, ent) spawned(p, ent) end)
watch("PlayerSpawnedSWEP", function(p, ent) spawned(p, ent) end)
watch("PlayerGiveSWEP", function(p, class) mark({k = "give", uid = uidOf(p), class = tostring(class)}) end)
watch("OnPhysgunPickup", function(p, ent)
    if not IsValid(ent) then return end
    if not ent:IsPlayer() then adopt(ent, 3600) end -- carried things are posed for as long as they are held
    mark(target({k = "physgun", uid = uidOf(p), on = true}, ent))
end)
watch("PhysgunDrop", function(p, ent)
    if not IsValid(ent) then return end
    local e = T.ents[ent]
    if e then e.hotUntil = CurTime() + 5 end
    mark(target({k = "physgun", uid = uidOf(p), on = false}, ent))
end)
watch("CanTool", function(p, tr, tool)
    if seldom("tool" .. tostring(uidOf(p)) .. tostring(tool), 0.5) then mark(target({k = "tool", uid = uidOf(p), tool = tostring(tool)}, istable(tr) and tr.Entity or nil)) end
end)

-- Weapons and bodies
watch("HGReloading", function(wep) if IsValid(wep) then mark({k = "reload", uid = uidOf(wep), wep = wep:GetClass()}) end end) -- homigrad_base + crossbow, rpg
watch("OnReloadedWep", function(wep) if IsValid(wep) then mark({k = "reloaded", uid = uidOf(wep), wep = wep:GetClass()}) end end) -- homigrad_base/shared.lua:97
watch("Player Getup", function(p) mark({k = "getup", uid = uidOf(p)}) end) -- sh_utility.lua:482; lying down is the sample flag "ragdoll"
watch("ZC_SomeoneGetFallBy", function(attacker, p) mark({k = "knockdown", uid = uidOf(attacker), to = uidOf(p)}) end) -- organism/tier_1/sv_input.lua:1670
watch("OnAmputateLimb", function(org, _, limb) mark({k = "amputate", uid = uidOf(istable(org) and org.owner or nil), limb = tostring(limb)}) end)
watch("OnHeadExplode", function(p) mark({k = "headexplode", uid = uidOf(p)}) end)
watch("HG_ReplacePhrase", function(p, phrase) -- sv_phrases.lua:340: every spoken line passes here before it plays
    local uid = uidOf(p)
    if uid and seldom("phrase" .. uid, 0.5) then mark({k = "phrase", uid = uid, p = string.sub(tostring(istable(phrase) and phrase[1] or phrase), 1, 80)}) end
end)

-- Kicks. PLAYER:LegAttack (dynamic_anims_util/animations/legkick/sv_legkick.lua:5) asks PlayerCanLegAttack only after its
-- own gates have passed (alive, standing, on the ground, off cooldown), so the question IS the start of a kick - unless
-- another listener says no (the headcrab-zombie class does): that case is recorded as a kick that never landed.
-- LegAttack itself is NOT wrapped: pat's_jump_kick already wraps it and re-installs its wrapper from Think.
-- The style is worked out the way LegAttack does it. Shoves are not a separate thing in Z-City: the crowbar, shovel,
-- axe and ram "shove" is their alternate melee attack, which is a swing with alt = true.
watch("PlayerCanLegAttack", function(p)
    local uid = uidOf(p)
    if not uid or not seldom("kick" .. uid, 0.3) then return end
    local style = (p:Crouching() and "crouch") or (p:EyeAngles().p > 60 and "stomp") or "kick"
    mark({k = "kick", uid = uid, style = style})
end)

-- Looting and searching (homigrad/sv_inventory.lua :237 :291 :352)
watch("ZB_InventoryOpened", function(p, ent) mark(target({k = "search", uid = uidOf(p)}, ent)) end)
watch("ItemTransfer", function(p, ent, placement, armor) mark(target({k = "loot", uid = uidOf(p), item = tostring(placement), armor = armor and tostring(armor) or nil}, ent)) end)
watch("ItemsTransfered", function(p, body) mark(target({k = "loot", uid = uidOf(p), all = true}, body)) end)

-- The world: buttons, breakage, fire, blasts
local USABLE = {func_button = true, func_rot_button = true, momentary_rot_button = true, func_door = true, func_door_rotating = true, prop_door_rotating = true}
watch("PlayerUse", function(p, ent) -- runs every tick while +use is held
    if not IsValid(ent) or not USABLE[ent:GetClass()] then return end
    local uid = uidOf(p)
    if uid and seldom("use" .. uid .. ":" .. ent:EntIndex(), 1) then mark(at({k = "use", uid = uid, class = ent:GetClass(), map = ent:MapCreationID()}, ent:GetPos())) end
end)
watch("PropBreak", function(p, prop)
    if IsValid(prop) then mark(at({k = "break", uid = uidOf(p), class = prop:GetClass(), model = prop:GetModel()}, prop:GetPos())) end
end)
local FIRE_MAX = 150 -- flames spread one entity at a time: enough to draw where it burned, never a flood
watch("vFireCreated", function(fire, parent)
    local tape = T.cur
    tape.fires = (tape.fires or 0) + 1
    if tape.fires > FIRE_MAX or not IsValid(fire) then return end
    mark(at(target({k = "fire", n = tape.fires}, parent), fire:GetPos()))
end)
watch("vFireEntityStartedBurning", function(ent) if IsValid(ent) then mark(target({k = "burning", on = true}, ent)) end end)
watch("vFireEntityStoppedBurning", function(ent) if IsValid(ent) then mark(target({k = "burning", on = false}, ent)) end end)
watch("EntityTakeDamage", function(ent, info) -- one mark per blast, not one per thing it touched
    if not info:IsExplosionDamage() then return end
    local inflictor, attacker = info:GetInflictor(), info:GetAttacker()
    if not seldom("boom" .. (IsValid(inflictor) and inflictor:EntIndex() or 0), 1) then return end
    local pos = info:GetDamagePosition()
    if IsValid(inflictor) and (not pos or (pos.x == 0 and pos.y == 0 and pos.z == 0)) then pos = inflictor:GetPos() end
    mark(at({k = "boom", uid = uidOf(attacker), with = IsValid(inflictor) and inflictor:GetClass() or nil}, pos))
end)

---- player state that is not in the 20 Hz sample, polled at 2 Hz and written on change: the pill-pack form (US1's
-- compat layer keeps the morph entity in NWEntity "zc_pill_morph"; pill_ent_costume / pill_ent_phys), the model
-- (playerclass changes swap it), noclip and the flashlight. The first sight in a round is always written, so a reader
-- never has to guess what a player looked like.
local NOCLIP = MOVETYPE_NOCLIP or 8
local FIT_PLACES = {"barrel", "sight", "mount", "grip", "underbarrel", "magwell"}
local function sampleState()
    for _, p in ipairs(player.GetAll()) do
        local uid = p:UserID()
        local last = T.plyLast[uid]
        if not last then last = {} T.plyLast[uid] = last end
        local morph = p:GetNWEntity("zc_pill_morph")
        morph = IsValid(morph) and morph or false
        if last.morph ~= morph and (morph or last.morph ~= nil) then
            local puppet = morph and isfunction(morph.GetPuppet) and morph:GetPuppet() or nil
            local row = {k = "pill", uid = uid, on = morph and true or false, form = morph and isfunction(morph.GetPillForm) and tostring(morph:GetPillForm()) or nil,
                model = IsValid(puppet) and puppet:GetModel() or (morph and morph:GetModel()) or nil}
            if morph then adopt(morph, math.huge) target(row, morph) row.to = nil end
            mark(row)
        end
        last.morph = morph
        local model = p:GetModel()
        if last.model ~= model then mark({k = "model", uid = uid, model = model, skin = p:GetSkin()}) last.model = model end
        -- Z-City parks a player in MOVETYPE_NOCLIP while they lie in their fake ragdoll (US1, tape12: 66 "noclip" marks in
        -- one round, all of them knockdowns), and spectators fly the same way: only a living, standing player counts.
        local noclip = p:GetMoveType() == NOCLIP and p:Alive() and not IsValid(p.FakeRagdoll)
        if last.noclip ~= noclip and (noclip or last.noclip ~= nil) then mark({k = "noclip", uid = uid, on = noclip}) end
        last.noclip = noclip
        -- Armour worn: hg.AddArmor keeps it in ply.armors, placement -> name (sv_equipment.lua; read by the abnormalty plugins).
        local worn = ""
        if istable(p.armors) then
            local list = {}
            for place, name in pairs(p.armors) do list[#list + 1] = tostring(place) .. "=" .. tostring(name) end
            table.sort(list)
            worn = table.concat(list, ";")
        end
        if last.worn ~= worn and (worn ~= "" or last.worn ~= nil) then mark({k = "armor", uid = uid, worn = worn}) end
        last.worn = worn
        -- Ammunition in the held weapon: magazine and reserve, on change. Shots are events already, so twice a second is
        -- enough to pin the count; a reader interpolates with the shots in between.
        local wep = p:GetActiveWeapon()
        local clip, reserve, class = -1, 0, ""
        if IsValid(wep) and p:Alive() then
            class, clip = wep:GetClass(), wep:Clip1()
            local kind = wep:GetPrimaryAmmoType()
            reserve = kind and kind >= 0 and p:GetAmmoCount(kind) or 0
        end
        if last.clip ~= clip or last.reserve ~= reserve or last.ammoWep ~= class then
            if clip >= 0 then mark({k = "ammo", uid = uid, wep = class, clip = clip, res = reserve}) end
            last.clip, last.reserve, last.ammoWep = clip, reserve, class
        end
        -- What the killcam clips carry and a whole-round replay needs too (owner, 2026-09-21: parity): the fittings on the gun
        -- in hand, how far this player's screen runs behind the server, and where a rested gun's bipod stands.
        local gun = p:GetActiveWeapon()
        local fit = ""
        if IsValid(gun) and istable(gun.attachments) then
            for _, place in ipairs(FIT_PLACES) do
                local a = gun.attachments[place]
                if istable(a) and isstring(a[1]) and a[1] ~= "" then fit = fit .. place .. "=" .. a[1] .. ";" end
            end
            if fit ~= "" then fit = gun:GetClass() .. "|" .. fit end
        end
        if fit ~= "" and last.fit ~= fit then mark({k = "att", uid = uid, fit = fit}) end
        if fit ~= "" then last.fit = fit end
        local lag = K.LagOfPlayer and K.LagOfPlayer(p)
        if lag and math.abs(lag - (last.lag or -99)) >= 2 then mark({k = "lag", uid = uid, cs = lag}) last.lag = lag end
        local rest = K.RestNow and IsValid(gun) and gun.RestPosition ~= nil and gun:GetNWBool("IsResting", false) and K.RestNow(p:EntIndex()) -- only while rested: the log outlives a round
        if rest and last.rest ~= rest then mark({k = "rest", uid = uid, pos = {round(rest[2] * 10) / 10, round(rest[3] * 10) / 10, round(rest[4] * 10) / 10}}) end
        last.rest = rest or nil -- forgotten when the gun comes up: resting on the same spot again is marked again
        local light = p:FlashlightIsOn() == true
        if last.light ~= light and (light or last.light ~= nil) then mark({k = "light", uid = uid, on = light}) end
        last.light = light
    end
end


-- Melee, fists, carrying and medicine have no hook either (owner, 2026-09-21: "wrap the melee and medical weapon
-- functions too"). The same treatment as the properties: the STORED weapon table's method is wrapped once, the wrapper
-- calls the original with the same arguments and hands back exactly what it returned, and the note is written inside a
-- pcall. Weapons that already exist keep their old methods until they are re-created; new ones get the wrapped ones.
--   weapon_melee and everything based on it   SWEP:PlayAnim(anim, duration, ...) - the accepted animation start,
--                                             before delayed hit testing, including stamina-adjusted duration
--   weapon_hands_sh and everything based on it SWEP:AttackFront(special) - a punch;  SWEP:SetCarrying(ent, ...) - pick
--                                             up / let go of a prop or a body (it returns false when refused)
--   every weapon that defines it               SWEP:Heal(ent, mode, bone) - bandage, tourniquet, medkit, morphine,
--                                             needles, pills ...; true when the item did something
-- PROVISIONAL(2026-09-21, method wraps stand in for hooks the gamemode does not fire, ratify-by: 2026-10-21)
T.wrapped = T.wrapped or setmetatable({}, {__mode = "k"}) -- wrapper function -> true
T.note = T.note or {}
-- The scope zoom a client reports (sv_net.lua zckc_zoom): the dialled field of view, as the clips keep it.
function T.note.Zoom(uid, fov, class)
    if T.cur then pcall(mark, {k = "zoom", uid = uid, fov = fov, wep = class}) end
end
-- The native animation call is emitted only after attack rejection gates. Observing
-- hit tests instead loses interrupted wind-ups and guesses stamina-adjusted timing.
function T.note.PlayAnim(self, anim, duration)
    if anim ~= "attack" and anim ~= "attack2" then return end
    if not isnumber(duration) or not (duration > 0 and duration <= 10) then return end
    local owner = self:GetOwner()
    local uid = uidOf(owner)
    if not uid then return end
    local alt = anim == "attack2"
    -- Each native call is a distinct accepted start; never suppress a fast follow-up by wall-clock cooldown.
    if K.NoteAction and K.Kinds then K.NoteAction(owner, K.Kinds.swing, alt and 2 or 1, self, duration) end
    if T.cur then mark({k = "swing", uid = uid, wep = self:GetClass(), alt = alt and true or nil, start = true, duration = duration}) end
end
-- A pull-back put away again: SWEP:ResetThrow (weapon_hg_grenade_tpik.lua:718, reached from Reload). It does nothing once
-- the spoon has gone (SpoonTime), and it clears IsLowThrow, so both are read BEFORE the original runs.
function T.note.ResetThrow(self)
    if self.SpoonTime then return end
    local owner = self:GetOwner()
    local uid = uidOf(owner)
    if not uid or not seldom("unpull" .. uid, 0.3) then return end
    mark({k = "pull", uid = uid, wep = self:GetClass(), off = true, low = self.IsLowThrow and true or nil})
    if K.NoteAction and K.Kinds then K.NoteAction(owner, K.Kinds.unpull, self.IsLowThrow and 2 or 1) end
end
function T.note.Throw(self) -- weapon_hg_grenade_tpik SWEP:Throw: the grenade leaves the hand, at the END of the throw animation
    local owner = self:GetOwner()
    local uid = uidOf(owner)
    if not uid or not seldom("throw" .. uid, 0.3) then return end
    mark({k = "throw", uid = uid, wep = self:GetClass(), low = self.IsLowThrow and true or nil})
    if K.NoteAction and K.Kinds then K.NoteAction(owner, K.Kinds.throw, self.IsLowThrow and 2 or 1) end
end
function T.note.AttackFront(self, special, right)
    local owner = self:GetOwner()
    local uid = uidOf(owner)
    if uid and seldom("punch" .. uid, 0.15) then
        mark({k = "punch", uid = uid, alt = special and true or nil})
        -- weapon_hands_sh.lua:1441 plays range_fists_r when (special_attack or rand), else range_fists_l
        if K.NoteAction and K.Kinds then K.NoteAction(owner, K.Kinds.punch, (special or right) and 2 or 1) end
    end
end
function T.note.PrimaryShootEmpty(self) -- the trigger pulled on an empty gun (homigrad_base/shared.lua PrimaryAttack)
    local uid = uidOf(self:GetOwner())
    if uid and seldom("dry" .. uid, 0.5) then mark({k = "dryfire", uid = uid, wep = self:GetClass()}) end
end
function T.noteAfter(name, self, a, b, c, d, ...)
    -- P8 (killcam, independent of whether a tape is open): the hands let a prop go -> the recorder tracks its flight
    -- and knows who threw it. self.zcLastCarry is the recorder's own memory of what these hands held last.
    if SERVER and name == "SetCarrying" and K.TrackObject then
        local carried = IsValid(self.CarryEnt) and self.CarryEnt or nil
        local before = self.zcLastCarry
        if not carried and IsValid(before) and before ~= self then pcall(K.TrackObject, before, "prop", self:GetOwner()) end
        self.zcLastCarry = carried
    end
    if T.cur and SERVER then
        if name == "SetCarrying" then
            local carried = IsValid(self.CarryEnt) and self.CarryEnt or nil
            pcall(function()
                local uid = uidOf(self:GetOwner())
                if not uid or T.carry[uid] == carried then return end
                T.carry[uid] = carried
                if carried then adopt(carried, 3600) end
                mark(target({k = "carry", uid = uid, on = carried ~= nil}, carried))
            end)
        elseif name == "Heal" then
            local done = ...
            pcall(function()
                local uid = uidOf(self:GetOwner())
                if not uid then return end
                if done or seldom("heal" .. uid .. self:GetClass(), 1) then
                    mark(target({k = "heal", uid = uid, wep = self:GetClass(), mode = tonumber(b), done = done and true or nil}, a))
                end
            end)
        end
    end
    return ...
end
local function basedOn(stored, class)
    for _ = 1, 8 do
        if not istable(stored) then return false end
        if stored.ClassName == class then return true end
        stored = stored.Base and stored.Base ~= stored.ClassName and weapons.GetStored(stored.Base) or nil
    end
    return false
end
-- pat's_jump_kick: PAT_JumpKick:StartJumpKick(ply) is where an airborne kick begins (sv_pat_jumpkick.lua:781).
local function wrapJumpKick()
    local addon = rawget(_G, "PAT_JumpKick")
    local original = istable(addon) and addon.StartJumpKick
    if not isfunction(original) or T.wrapped[original] then return end
    local wrapper = function(self, p, ...)
        if T.cur then pcall(function() local uid = uidOf(p) if uid and seldom("kick" .. uid, 0.3) then mark({k = "kick", uid = uid, style = "jump"}) end end) end
        return original(self, p, ...)
    end
    T.wrapped[wrapper] = true
    addon.StartJumpKick = wrapper
end

-- Traitor abilities, shop purchases, bomb keypads (owner, 2026-09-21). What US1 actually has:
--   * Neck breaks, disarms, the fiberwire and hostage-taking all run through US1's own interaction layer
--     (addons/zcity_hostage, global ZCityInteractions). Every one of them takes a session with I.Reserve(s, actors) and
--     gives it back with I.Release(s): those two are the choke point. Homicide's legacy MODE.BreakOtherNeck returns false
--     on the server while that layer is loaded, so it is not wrapped. I.CommitDisarm(a, v) is the moment a disarm
--     succeeds; I.StartWire(a, target) the moment a garrote goes on.
--   * Shops and keypads are net receivers with no hook: tdm_buyitem, defense_commander_purchase, bomb_enter,
--     ZB_RequestAirStrike. The receiver is wrapped to note WHO and WHICH; the message itself cannot be read twice, so
--     what was bought shows up as the equip / ent marks that follow.
--   * US1's homigrad_base has NO fire-mode selector and NO jam system (searched 2026-09-21: nothing under
--     weapons/homigrad_base matches firemode / jam / malfunction). The nearest real action is pulling the trigger on
--     an empty gun, SWEP:PrimaryShootEmpty, recorded as "dryfire".
-- All of it is pass-through and fenced, like the weapon wraps. PROVISIONAL(2026-09-21, wraps stand in for hooks, ratify-by: 2026-10-21)
T.sessions = T.sessions or setmetatable({}, {__mode = "k"}) -- interaction session -> true while it is on the tape
local function after(note, a, b, c, d, ...)
    if T.cur then pcall(note, (...), a, b, c, d) end
    return ...
end
local function wrapIn(tbl, name, note)
    local original = istable(tbl) and tbl[name]
    if not isfunction(original) or T.wrapped[original] then return end
    local wrapper = function(a, b, c, d, ...) return after(note, a, b, c, d, original(a, b, c, d, ...)) end
    T.wrapped[wrapper] = true
    tbl[name] = wrapper
end
-- A session says what it is in `kind` (hostage moves), else `policyIntent` ("disarm", ...), else `system` (sv_roles.lua:31,
-- zcity_hostage/sv_gameplay.lua newSession). US1, tape17: the first guess fell through to `phase` and wrote "commit".
local function sessionKind(s) return tostring(s.kind or s.policyIntent or s.system or "interaction") end
local RECEIVERS = {tdm_buyitem = {"buy", "tdm"}, defense_commander_purchase = {"buy", "defense"}, bomb_enter = {"keypad", "bomb"}, zb_requestairstrike = {"airstrike", "hl2dm"}}
local function wrapInteractions()
    local I = rawget(_G, "ZCityInteractions")
    wrapIn(I, "Reserve", function(ok, s, actors)
        if not ok or not istable(s) or T.sessions[s] then return end
        T.sessions[s] = true
        mark({k = "interact", on = true, kind = sessionKind(s), sys = s.system and tostring(s.system) or nil, uid = uidOf(s.a), to = uidOf(s.v), n = istable(actors) and #actors or nil})
    end)
    wrapIn(I, "Release", function(_, s)
        if not istable(s) or not T.sessions[s] then return end
        T.sessions[s] = nil
        mark({k = "interact", on = false, kind = sessionKind(s), uid = uidOf(s.a), to = uidOf(s.v), done = s.done and true or nil, phase = s.phase and tostring(s.phase) or nil})
    end)
    wrapIn(I, "CommitDisarm", function(ok, a, v) if ok then mark({k = "disarm", uid = uidOf(a), to = uidOf(v)}) end end)
    wrapIn(I, "StartWire", function(ok, a, v) if ok ~= false then mark({k = "wire", uid = uidOf(a), to = uidOf(v)}) end end)
    -- The engineer's pipebomb is a console command (modes/homicide/sv_professions_abilities.lua:73) that either hands over
    -- weapon_hg_pipebomb_tpik or does nothing: crafted = the weapon is there afterwards and was not before.
    local commands = concommand and concommand.GetTable and concommand.GetTable()
    local craft = istable(commands) and commands["hg_create_pipebomb"]
    if isfunction(craft) and not T.wrapped[craft] then
        local wrapper = function(p, ...)
            local had = IsValid(p) and p:HasWeapon("weapon_hg_pipebomb_tpik")
            local function done(...)
                if T.cur then pcall(function() if not had and IsValid(p) and p:HasWeapon("weapon_hg_pipebomb_tpik") then mark({k = "craft", uid = uidOf(p), item = "pipebomb"}) end end) end
                return ...
            end
            return done(craft(p, ...))
        end
        T.wrapped[wrapper] = true
        commands["hg_create_pipebomb"] = wrapper
    end
    if not net or not istable(net.Receivers) then return end
    for name, what in pairs(RECEIVERS) do
        local original = net.Receivers[name]
        if isfunction(original) and not T.wrapped[original] then
            local wrapper = function(len, p, ...)
                if T.cur then pcall(function() mark({k = what[1], uid = uidOf(p), shop = what[2]}) end) end
                return original(len, p, ...)
            end
            T.wrapped[wrapper] = true
            net.Receivers[name] = wrapper
        end
    end
end
-- The grenade's pull-back (pin out, arm cocked). SWEP:PrimaryAttack / SecondaryAttack run for as long as the button is
-- held and return early unless a pull-back really starts; when one does they set self.CoolDown (weapon_hg_grenade_tpik.lua
-- :545 / :367) - that change is the signal. Pass-through like every other wrap here.
local function wrapPull(stored, name, how)
    local original = rawget(stored, name)
    if not isfunction(original) or T.wrapped[original] then return end
    local wrapper = function(self, ...)
        local was = self.CoolDown
        local function done(...)
            if SERVER and self.CoolDown ~= was then
                pcall(function()
                    local owner = self:GetOwner()
                    local uid = uidOf(owner)
                    if not uid then return end
                    if T.cur then mark({k = "pull", uid = uid, wep = self:GetClass(), low = how == 2 and true or nil}) end
                    if K.NoteAction and K.Kinds then K.NoteAction(owner, K.Kinds.pull, how) end
                end)
            end
            return ...
        end
        return done(original(self, ...))
    end
    T.wrapped[wrapper] = true
    stored[name] = wrapper
end
local WRAPS = {{"ResetThrow", "weapon_hg_grenade_tpik", "before"}, {"Throw", "weapon_hg_grenade_tpik", "before"}, {"PrimaryShootEmpty", "homigrad_base", "before"}, {"PlayAnim", "weapon_melee", "before"}, {"AttackFront", "weapon_hands_sh", "before"}, {"SetCarrying", "weapon_hands_sh", "after"}, {"Heal", nil, "after"}}
local function wrapWeapons()
    wrapJumpKick()
    wrapInteractions()
    if not weapons or not weapons.GetList then return end
    for _, listed in ipairs(weapons.GetList()) do
        local stored = listed.ClassName and weapons.GetStored(listed.ClassName)
        if istable(stored) then
            if basedOn(stored, "weapon_hg_grenade_tpik") then
                wrapPull(stored, "PrimaryAttack", 1)
                wrapPull(stored, "SecondaryAttack", 2)
            end
            for _, w in ipairs(WRAPS) do
                local name, base, when = w[1], w[2], w[3]
                local original = rawget(stored, name)
                if isfunction(original) and not T.wrapped[original] and (not base or basedOn(stored, base)) then
                    local wrapper
                    if when == "before" then
                        wrapper = function(self, ...)
                            -- Killcam capture is independent of whether a round tape is open.
                            if SERVER and (T.cur or name == "PlayAnim" or name == "AttackFront") then pcall(T.note[name], self, ...) end
                            return original(self, ...)
                        end
                    else
                        wrapper = function(self, a, b, c, d, ...) return T.noteAfter(name, self, a, b, c, d, original(self, a, b, c, d, ...)) end
                    end
                    T.wrapped[wrapper] = true
                    stored[name] = wrapper
                    stats.wraps = (stats.wraps or 0) + 1
                end
            end
        end
    end
end
wrapWeapons()
hook.Add("InitPostEntity", "ZCKillcam.TapeWeapons", wrapWeapons)

-- Tracks an entity that classify() has no kind for (or heats one it has): staff spawns, physgun cargo, pill morphs.
function adopt(ent, seconds)
    classify(ent)
    local e = T.ents[ent]
    if not e then
        e = {kind = "spawn", hotUntil = 0}
        T.ents[ent] = e
        T.props[#T.props + 1] = ent
    end
    if not T.cur then return end
    e.hotUntil = math.max(e.hotUntil, CurTime() + (seconds or 2))
    heat(ent, 0)
    pose(ent, e, CurTime(), true)
end
-- Voice chat ACTIVITY - who had the microphone open, and when. Never the audio: the server does not have it to give.
-- Player:IsSpeaking() works on the server (Z-City's own sv_comunication.lua and sv_bone.lua rely on it; checked live on
-- US1). Polled at 10 Hz; "off" is only written after VOICE_GAP seconds of silence, so breaths between words do not
-- flood the index. `alive` rides along as it does for chat: what the dead say is STAFF-ONLY while the round runs.
local VOICE_GAP = 0.4
local function sampleVoice(now)
    for _, p in ipairs(player.GetAll()) do
        local talking = p:IsSpeaking() == true
        local uid = p:UserID()
        local v = T.voice[uid]
        if talking then
            if not v then v = {} T.voice[uid] = v end
            if not v.on then v.on = true mark({k = "voice", uid = uid, on = true, alive = p:Alive() or nil}) end
            v.quiet = nil
        elseif v and v.on then
            v.quiet = v.quiet or now
            if now - v.quiet >= VOICE_GAP then
                v.on = false
                mark({k = "voice", uid = uid, on = false, t = round((v.quiet - T.cur.t0) * 100)}) -- stamped where the talking stopped
            end
        end
    end
end

local function tracksTick()
    if not T.cur then return end
    local began, now = SysTime(), CurTime()
    sampleVoice(now)
    local hot = T.hot
    for i = #hot, 1, -1 do
        local ent = hot[i]
        local e = IsValid(ent) and T.ents[ent]
        if not e then
            table.remove(hot, i)
        else
            local moved = pose(ent, e, now)
            if moved and (e.kind == "prop" or e.kind == "item" or e.kind == "spawn") then e.hotUntil = math.max(e.hotUntil, now + 2) end
            if now > e.hotUntil then e.hot = false table.remove(hot, i) end
        end
    end
    local props = T.props
    for _ = 1, math.min(40, #props) do
        propCursor = propCursor % #props + 1
        local ent = props[propCursor]
        if not IsValid(ent) then
            props[propCursor] = props[#props]
            props[#props] = nil
            if #props == 0 then break end
        elseif T.ents[ent] and not T.ents[ent].hot and ent:GetVelocity():LengthSqr() > 100 and not (T.ents[ent].kind == "item" and IsValid(ent:GetOwner())) then
            heat(ent, 2)
        end
    end
    local doors = T.doors
    for _ = 1, math.min(20, #doors) do
        doorCursor = doorCursor % #doors + 1
        local ent = doors[doorCursor]
        if not IsValid(ent) then
            doors[doorCursor] = doors[#doors]
            doors[#doors] = nil
            if #doors == 0 then break end
        else
            local class = ent:GetClass()
            local st = (tonumber(ent:GetInternalVariable(DOOR[class])) or 0) + (ent:GetInternalVariable("m_bLocked") and 100 or 0)
            local last = T.doorLast[ent]
            if last ~= st and (last ~= nil or st ~= DOOR_SHUT[class]) then -- first sight of a shut, unlocked door is not news
                local pos = ent:GetPos()
                mark({k = "door", id = ent:MapCreationID(), class = class, st = st % 100, locked = st >= 100 or nil, pos = {round(pos.x), round(pos.y), round(pos.z)}})
            end
            T.doorLast[ent] = st
        end
    end
    if now >= orgAt then
        orgAt = now + 0.5
        sampleOrganism(now)
        sampleState()
        if now >= (T.wrapAt or 0) then T.wrapAt = now + 30 wrapProperties() wrapWeapons() end -- an autorefreshed addon re-adds its properties unwrapped
        for key, d in pairs(pendingDmg) do
            if now - d.at > 0.5 then pendingDmg[key] = nil d.at = nil mark(d) end
        end
    end
    book("tracks", began)
end
-- The gamemode's entities are read here ten times a second; one that misbehaves must cost a counter, not the timer.
timer.Create("ZCKillcam.TapeTracks", 0.1, 0, function()
    local ok, err = pcall(tracksTick)
    if not ok then
        stats.errors = stats.errors + 1
        if not T.trackErrOnce then T.trackErrOnce = true print("[Killcam tape] tracks tick failed: " .. tostring(err)) end
    end
end)

local function flushDamage()
    for key, d in pairs(pendingDmg) do pendingDmg[key] = nil d.at = nil mark(d) end
end

-- Called when a chunk is scheduled: the rows land just past the boundary, so they open the NEXT chunk.
local function keyframes(now)
    local began = SysTime()
    T.orgLast = {}
    sampleOrganism(now)
    orgAt = now + 0.5
    local known = T.known
    for i = #known, 1, -1 do
        local ent = known[i]
        local e = IsValid(ent) and T.ents[ent]
        if e and e.tape == T.cur then pose(ent, e, now, true) else table.remove(known, i) end
    end
    book("keyframes", began)
end

local function resetTracks()
    T.buf, T.orgLast, T.doorLast, T.known, T.plyLast, T.seldom, T.carry, T.voice = {}, {}, {}, {}, {}, {}, {}, {}
    pendingDmg = {}
end

hook.Add("OnEntityCreated", "ZCKillcam.Tape", function(ent)
    timer.Simple(0, function() classify(ent) end) -- class and model are not settled until the entity has spawned
end)
hook.Add("EntityRemoved", "ZCKillcam.Tape", function(ent)
    local e = T.ents[ent]
    if not e then return end
    T.ents[ent] = nil
    if e.tape and e.tape == T.cur then
        local pos = ent:GetPos()
        mark({k = "entgone", id = e.id, pos = {round(pos.x), round(pos.y), round(pos.z)}}) -- for a grenade this is where it went off
    end
end)
hook.Add("PlayerEnteredVehicle", "ZCKillcam.Tape", function(p, veh)
    local body = IsValid(veh:GetParent()) and veh:GetParent() or veh -- Glide and simfphys seat the player in a child pod
    classify(body)
    local e = T.ents[body]
    if e and T.cur then
        e.hotUntil = math.huge
        heat(body, 0)
        if announce(body, e) then mark({k = "veh", uid = p:UserID(), id = e.id, on = true}) end
    end
end)
hook.Add("PlayerLeaveVehicle", "ZCKillcam.Tape", function(p, veh)
    local body = IsValid(veh:GetParent()) and veh:GetParent() or veh
    local e = T.ents[body]
    if e then
        e.hotUntil = CurTime() + 5 -- it is still rolling
        if e.tape == T.cur then mark({k = "veh", uid = p:UserID(), id = e.id, on = false}) end
    end
end)

---- marks
-- Damage that no player dealt: falls, fire, bleeding out, blasts with no owner, vehicles, the world. The recorder's hit
-- events only cover player-on-player. Fire ticks many times a second, so one victim + one damage type is summed into
-- one mark per half second. Returns nothing: this hook must never alter damage.
hook.Add("EntityTakeDamage", "ZCKillcam.Tape", function(ent, info)
    if not T.cur then return end
    local victim = ent:IsPlayer() and ent or ent.ply
    if not IsValid(victim) or not victim:IsPlayer() then return end
    local attacker = info:GetAttacker()
    if IsValid(attacker) and attacker:IsPlayer() and attacker ~= victim then return end
    local dmg = info:GetDamage()
    if dmg <= 0 then return end
    local kind = info:GetDamageType()
    local key = victim:UserID() .. ":" .. kind
    local d = pendingDmg[key]
    if d then d.dmg, d.n = d.dmg + dmg, d.n + 1 return end
    local inflictor = info:GetInflictor()
    pendingDmg[key] = {k = "dmg", t = round((CurTime() - T.cur.t0) * 100), at = CurTime(), uid = victim:UserID(), type = kind, dmg = dmg, n = 1,
        self = attacker == victim or nil, by = attacker ~= victim and IsValid(attacker) and attacker:GetClass() or nil, with = IsValid(inflictor) and inflictor:GetClass() or nil}
end)

-- ZChat runs HG_PlayerSay after mutes and ChatGuard have had their say (sh_chat.lua:229), so this is what was actually
-- delivered. The third argument is the text before furrify and the brain-damage garble rewrite it.
hook.Add("HG_PlayerSay", "ZCKillcam.Tape", function(p, _, text)
    if not T.cur or not IsValid(p) or not isstring(text) then return end
    mark({k = "chat", uid = p:UserID(), alive = p:Alive() or nil, text = string.sub(text, 1, 240)})
end)
hook.Add("ZB_GettingRole", "ZCKillcam.Tape", function(p, name) -- zb.GiveRole, libraries/sh_giverole.lua:5
    if IsValid(p) then mark({k = "role", uid = p:UserID(), name = tostring(name)}) end
end)
hook.Add("PlayerDropWeapon", "ZCKillcam.Tape", function(p, wep)
    if IsValid(p) and p:IsPlayer() then mark({k = "drop", uid = p:UserID(), wep = IsValid(wep) and wep:GetClass() or nil}) end
end)
hook.Add("WeaponEquip", "ZCKillcam.Tape", function(wep, p)
    if IsValid(p) and IsValid(wep) then mark({k = "equip", uid = p:UserID(), wep = wep:GetClass()}) end
end)
hook.Add("PlayerInitialSpawn", "ZCKillcam.Tape", function(p) mark({k = "join", uid = p:UserID(), name = p:Nick()}) end)
hook.Add("PlayerDisconnected", "ZCKillcam.Tape", function(p) mark({k = "leave", uid = p:UserID()}) end)
hook.Add("ZB_EndRound", "ZCKillcam.Tape", function() mark({k = "roundend"}) end)

----------------------------------------------------------------- one chunk
local function flushGroup(chunk)
    local group = chunk.group
    if not group or group.size == 0 then return end
    chunk.group = nil
    if T.job and not T.drain and SysTime() - T.sliceBegan > PACK_ROOM then coroutine.yield() end
    local began = SysTime()
    local packed = util.Compress(table.concat(group.texts)) or ""
    chunk.groups[#chunk.groups + 1] = {off = chunk.size, len = #packed, raw = group.size}
    chunk.blobs[#chunk.blobs + 1] = packed
    chunk.size = chunk.size + #packed
    local kb = group.size / 1024
    pause(kb < 2 and "pack<2k" or kb < 4 and "pack<4k" or kb < 8 and "pack<8k" or kb < 16 and "pack<16k" or "pack16k+", began)
end

-- Never called inside a timed unit: it may yield. `flat` is consumed: it is delta-coded in place, back to front.
local function addPiece(chunk, meta, flat, count, stride)
    local began = SysTime()
    for i = count, stride + 1, -1 do flat[i] = flat[i] - flat[i - stride] end
    local text = table.concat(flat, ",", 1, count)
    pause("concat", began)
    if chunk.group and chunk.group.size + #text > (chunk.groupRaw or GROUP_RAW) then flushGroup(chunk) end
    local group = chunk.group
    if not group then group = {texts = {}, size = 0} chunk.group = group end
    -- The piece table is written as JSON arrays, formatted here a piece at a time: [k, slot, uid, rows, group, offset,
    -- length, bones, model]. A busy chunk has ~250 pieces, and handing that many objects to util.TableToJSON in one
    -- unit cost 1.4 ms on average and 2.0 ms at worst on US1.
    chunk.metas[#chunk.metas + 1] = string.format('["%s",%d,%d,%d,%d,%d,%d,%d,"%s"]', meta.k, meta.slot or 0, meta.uid or 0, meta.rows or meta.frames,
        #chunk.groups + 1, group.size, #text, meta.bones or 0, string.gsub(meta.m or "", '[%c"\\]', ""))
    group.texts[#group.texts + 1] = text
    group.size = group.size + #text
end

local function cutChunk(tape, seq, t0, t1, job)
    if tape.dead then return end -- its files could not be opened
    local chunk = {metas = {}, groups = {}, blobs = {}, size = 0}
    local wide = K.TapeBatch:GetInt() == 1 -- P7: the A/B, fixed for the whole chunk
    chunk.groupRaw = wide and 5120 or GROUP_RAW
    local ragBatch = wide and 16 or RAG_BATCH
    local slots = game.MaxPlayers()

    for slot = 1, slots do
        local began = SysTime()
        local flat, rows = gatherSamples(tape, slot, t0, t1)
        local uid = rows > 0 and roster(tape, slot, t0) or 0
        pause("gather", began)
        if rows > 0 then
            for first = 1, rows, ROWS_PIECE do
                local n = math.min(ROWS_PIECE, rows - first + 1)
                local part = flat
                if rows > ROWS_PIECE then
                    part = pieceBuf
                    local from = (first - 1) * ROW
                    for i = 1, n * ROW do part[i] = flat[from + i] end
                end
                addPiece(chunk, {k = "p", slot = slot, uid = uid, rows = n}, part, n * ROW, ROW)
            end

            began = SysTime()
            local refs, d, refn = ragRefs(slot, t0, t1)
            pause("ragwalk", began)
            local batch, bn, frames, bones = ragBuf, 0, 0, 0
            local cur = {} -- one scratch frame reused: no table per frame
            local function flushRag()
                if frames > 0 then addPiece(chunk, {k = "r", slot = slot, uid = uid, bones = bones, frames = frames, m = K.RagModel(slot)}, batch, bn, 1 + bones * 6) end
                bn, frames = 0, 0
            end
            began = SysTime()
            for r = 1, refn, 3 do
                local t, base, n = refs[r], refs[r + 1], refs[r + 2]
                if n ~= bones then -- the body changed shape: a new piece, one skeleton per piece
                    pause("rag", began) -- closed first: a unit must never be timed across a yield
                    flushRag()
                    bones, began = n, SysTime()
                end
                for i = 1, n * 6 do
                    local v = round(d[base + i])
                    cur[i] = v
                end
                do -- retain the final stationary frame before an arm starts moving
                    batch[bn + 1] = round((t - t0) * 100)
                    for i = 1, n * 6 do batch[bn + 1 + i] = cur[i] end
                    bn, frames = bn + 1 + n * 6, frames + 1
                    if frames >= ragBatch then
                        pause("rag", began)
                        flushRag()
                        began = SysTime()
                    end
                end
            end
            pause("rag", began)
            flushRag()
        end
    end

    local began = SysTime()
    local ev, en, count = {}, 0, 0
    K.EachEvent(t0, t1, function(t, kind, a, b, dmg, hitgroup, wep, los, uid, px, py, pz, yaw, pitch, body, ballistic, facts, penetration, swing)
        if t <= t0 then return end
        ev[en + 1], ev[en + 2], ev[en + 3], ev[en + 4], ev[en + 5] = round((t - t0) * 100), kind, a, b, round(dmg * 10)
        ev[en + 6], ev[en + 7], ev[en + 8], ev[en + 9] = hitgroup, wep, los and 1 or 0, uid
        ev[en + 10] = swing and math.max(1, round(swing.duration * 1000)) or 0
        en, count = en + EVROW, count + 1
        if wep > 0 and not tape.weps[wep] then
            tape.weps[wep] = true
            line(tape, {k = "wep", id = wep, class = K.WeaponName(wep)})
        end
    end)
    pause("events", began)
    local evBatch = math.floor(BATCH_NUMS / EVROW)
    for first = 1, count, evBatch do
        local n = math.min(evBatch, count - first + 1)
        local part = ev
        if count > evBatch then
            part = pieceBuf
            local from = (first - 1) * EVROW
            for i = 1, n * EVROW do part[i] = ev[from + i] end
        end
        addPiece(chunk, {k = "e", rows = n}, part, n * EVROW, EVROW)
    end

    for _, k in ipairs(TRACK_ORDER) do
        began = SysTime()
        local rows, total = takeRows(k, t0, t1)
        pause("take." .. k, began)
        local stride = TRACKS[k].stride
        local batch = math.floor(BATCH_NUMS / stride)
        for first = 1, total, batch do
            local n = math.min(batch, total - first + 1)
            local part = rows
            if total > batch then
                part = pieceBuf
                local from = (first - 1) * stride
                for i = 1, n * stride do part[i] = rows[from + i] end
            end
            addPiece(chunk, {k = k, rows = n}, part, n * stride, stride)
        end
    end
    encodeLines(tape)

    flushGroup(chunk)

    began = SysTime()
    local header = util.TableToJSON({v = 4, delta = 1, round = tape.id, seq = seq, t0 = round((t0 - tape.t0) * 100), t1 = round((t1 - tape.t0) * 100),
        wall = os.time(), row = ROW, evrow = EVROW, strides = {s = 10, o = 10, x = 8, w = 16}, ang = ANG, ragStride = T.ragStride, groups = chunk.groups})
    header = string.sub(header, 1, -2) .. ',"pieces":[' .. table.concat(chunk.metas, ",") .. "]}"
    local body = "ZCT1\n" .. header .. "\n" .. table.concat(chunk.blobs)
    pause("frame", began)

    began = SysTime()
    local off = tape.bytes
    tape.fd:Write(body)
    tape.fd:Flush() -- to the OS, so a crash costs at most the chunk being cut
    pause("write", began)

    began = SysTime()
    tape.chunks, tape.bytes = tape.chunks + 1, tape.bytes + #body
    stats.chunks, stats.bytes = stats.chunks + 1, stats.bytes + #body
    line(tape, {k = "chunk", seq = seq, t0 = round((t0 - tape.t0) * 100), t1 = round((t1 - tape.t0) * 100), off = off, bytes = #body, pieces = #chunk.metas, groups = #chunk.groups, ticks = job.ticks, over = job.over})
    flushLines(tape)
    pause("index", began)

    -- Degrade before dropping: two slow units in one chunk halve the ragdoll rate (the only heavy track so far),
    -- and a long clean run earns it back. The tape says which rate each chunk used.
    if job.over >= 2 and T.ragStride < 4 then
        T.ragStride, T.clean = T.ragStride * 2, 0
        stats.degraded = stats.degraded + 1
    elseif job.over == 0 then
        T.clean = T.clean + 1
        if T.clean >= 12 and T.ragStride > 1 then T.ragStride, T.clean = T.ragStride / 2, 0 end
    else
        T.clean = 0
    end
end

----------------------------------------------------------------- catalog and retention
-- Measured on US1: creating or rewriting a file costs 2-23 ms on this host (head.json rewrite: 9.5 ms average), while
-- writing through a handle that is already open costs ~30 us. So nothing here rewrites a file on a running server.
-- The catalog is a LOG (catalog.txt, one JSON line per change, last line per round wins) appended through one handle
-- kept open for the life of the map; it is compacted once, at boot, by the repair job.
local function readJson(path)
    local raw = file.Read(path, "DATA")
    return raw and util.JSONToTable(raw) or nil
end

local function catalog()
    if T.catalog then return T.catalog end
    local cat = readJson(ROOT .. "/catalog.json") or {} -- tape1-4 kept a rewritten JSON file; read once as the base
    for row in string.gmatch(file.Read(ROOT .. "/catalog.txt", "DATA") or "", "[^\r\n]+") do
        local e = util.JSONToTable(row)
        if e and e.id then
            if e.gone then cat[e.id] = nil else cat[e.id] = {t = e.t, bytes = e.bytes, open = e.open} end
        end
    end
    T.catalog = cat
    return cat
end

-- For readers (sv_tapeserve.lua): the catalog is read-only to them, and the round being written is not theirs to open.
function K.TapeCatalog() return catalog() end
function K.TapeOpenId() return T.cur and T.cur.id or nil end

-- Records a change in memory and on the log. Call from a job: it is a timed unit.
local function note(id, entry)
    local began = SysTime()
    catalog()[id] = entry
    if not T.catfd then T.catfd = file.Open(ROOT .. "/catalog.txt", "ab", "DATA") end
    if T.catfd then
        T.catfd:Write(util.TableToJSON(entry and {id = id, t = entry.t, bytes = entry.bytes, open = entry.open} or {id = id, gone = true}) .. "\n")
        T.catfd:Flush()
    end
    pause("catalog", began)
end

local function deleteRound(id)
    local dir = ROOT .. "/" .. id
    local names = file.Find(dir .. "/*", "DATA") or {}
    for i = 1, #names do
        local began = SysTime()
        file.Delete(dir .. "/" .. names[i])
        pause("delete", began)
    end
    file.Delete(dir)
    note(id, nil)
    stats.swept = stats.swept + 1
end

-- Oldest unpinned rounds go first, by the open time kept in the catalog (never by sorting the id text: ids of
-- different lengths sort wrongly). The newest round is never deleted, so a cap set too low cannot eat the round
-- that was just written.
-- pinned.json (roundId -> os.time it is pinned until) is honoured here; nothing writes it until reports and saves land.
function K.TapeSweep()
    local cat = catalog()
    local ids, total = {}, 0
    for id, e in pairs(cat) do
        ids[#ids + 1] = id
        total = total + (e.bytes or 0)
    end
    local cap = capMb:GetInt() * 1024 * 1024
    if total <= cap then return end -- the usual case costs one pass over the catalog and no disk at all
    local pinned, now = readJson(ROOT .. "/pinned.json") or {}, os.time()
    table.sort(ids, function(a, b)
        local ta, tb = cat[a].t or 0, cat[b].t or 0
        if ta ~= tb then return ta < tb end
        return a < b
    end)
    local newest = ids[#ids]
    for _, id in ipairs(ids) do
        if total <= cap then break end
        local keep = id == newest or (T.cur and T.cur.id == id) or (pinned[id] and pinned[id] > now)
        if not keep then
            total = total - (cat[id].bytes or 0)
            deleteRound(id)
        end
    end
end

-- Boot only. After a crash the catalog can hold rounds still marked open, and after a lost catalog it holds nothing
-- at all: both are repaired from the directory listing, a few files per unit. Then the log is compacted - the one
-- place a catalog file is rewritten, at a moment when nobody is playing yet.
function K.TapeRepair()
    local cat = catalog()
    local _, dirs = file.Find(ROOT .. "/*", "DATA")
    local seen = {}
    for _, id in ipairs(dirs or {}) do
        seen[id] = true
        local e = cat[id]
        if (not e or e.open) and not (T.cur and T.cur.id == id) then
            local names = file.Find(ROOT .. "/" .. id .. "/*", "DATA") or {}
            local bytes, began = 0, SysTime()
            for i = 1, #names do
                bytes = bytes + (file.Size(ROOT .. "/" .. id .. "/" .. names[i], "DATA") or 0)
                if i % 16 == 0 then pause("repair", began) began = SysTime() end
            end
            pause("repair", began)
            cat[id] = {t = tonumber(string.match(id, "^(%d+)")) or os.time(), bytes = bytes}
        end
    end
    for id in pairs(cat) do if not seen[id] then cat[id] = nil end end -- a directory someone deleted by hand
    local began = SysTime()
    if T.catfd then T.catfd:Close() T.catfd = nil end
    local rows = {}
    for id, e in pairs(cat) do rows[#rows + 1] = util.TableToJSON({id = id, t = e.t, bytes = e.bytes, open = e.open}) end
    file.Write(ROOT .. "/catalog.txt", #rows > 0 and (table.concat(rows, "\n") .. "\n") or "")
    file.Delete(ROOT .. "/catalog.json")
    pause("compact", began)
end

----------------------------------------------------------------- opening and closing a tape
local serial = 0
local function roundFacts()
    local mode = CurrentRound and CurrentRound() or nil
    return mode and mode.name or nil, mode and mode.base or nil
end

-- Runs inside ZB_StartRound, the busiest tick of a round, so it touches no disk at all: it takes the clock, queues
-- the head as the first index line, and leaves the directory and the two handles to the worker, a unit each.
function K.TapeOpen(reason, partial)
    if T.cur then K.TapeClose("superseded") end
    serial = serial % 99 + 1
    local now = CurTime()
    local id = string.format("%d_%02d", os.time(), serial)
    resetTracks() -- whatever happened between rounds belongs to no tape
    local tape = {id = id, t0 = now, next = now + CHUNK, seq = 0, chunks = 0, bytes = 0, roster = {}, weps = {}, lines = {}, ready = {}, traitor = {}, names = {}, nameN = 0, wall = os.time()}
    T.cur = tape
    local name, base = roundFacts()
    line(tape, {k = "head", v = 2, id = id, map = game.GetMap(), mode = name, base = base, wall0 = tape.wall, cur0 = round(now * 100) / 100,
        hz = K.HZ, chunk = CHUNK, slots = game.MaxPlayers(), recorder = K.Version, tape = K.TapeVersion, partial = partial or nil, opened = reason})
    enqueue("open", function()
        local dir = ROOT .. "/" .. id
        local began = SysTime()
        if file.Exists(dir, "DATA") then tape.dead = true else file.CreateDir(dir) end -- two opens in one second with one serial: never share a directory
        pause("open.dir", began)
        if not tape.dead then
            began = SysTime()
            tape.fd = file.Open(dir .. "/tape.dat", "wb", "DATA")
            pause("open.tape", began)
            began = SysTime()
            tape.fi = file.Open(dir .. "/index.txt", "wb", "DATA")
            pause("open.index", began)
        end
        if not tape.fd or not tape.fi then -- no handle, no tape: better one missing round than a job failing every ten seconds
            if tape.fd then tape.fd:Close() end
            if tape.fi then tape.fi:Close() end
            tape.fd, tape.fi, tape.dead = nil, nil, true
            stats.errors = stats.errors + 1
            if T.cur == tape then T.cur, T.blocked = nil, true end -- the once-a-second poll must not retry this; the next round hook clears it
            return
        end
        note(id, {t = tape.wall, bytes = 0, open = true})
    end)
    return tape
end

function K.TapeClose(reason)
    local tape = T.cur
    if not tape then return end
    flushDamage()
    T.cur = nil
    local now = CurTime()
    local t0 = tape.next - CHUNK
    tape.seq = tape.seq + 1
    local seq = tape.seq
    enqueue("chunk", function(job) if now > t0 and not tape.dead then cutChunk(tape, seq, t0, now, job) end end)
    enqueue("close", function()
        if tape.dead then return end
        local began = SysTime()
        -- The closing facts are the LAST index line, through the open handle. Rewriting a head file cost 9.5 ms here.
        line(tape, {k = "end", reason = reason, wall1 = os.time(), len = round((now - tape.t0) * 100) / 100, chunks = tape.chunks, bytes = tape.bytes})
        flushLines(tape)
        tape.fi:Close()
        tape.fi = nil
        pause("close.index", began)
        began = SysTime()
        tape.fd:Close()
        tape.fd = nil
        pause("close.tape", began)
        note(tape.id, {t = tape.wall, bytes = tape.bytes})
        K.TapeSweep()
    end)
end

-- Everything that decides whether a tape should exist, in one idempotent place: the hooks call it for precision and
-- the poll calls it for safety.
local function want() return tapeOn:GetBool() and GetConVar("zc_killcam_enabled"):GetBool() end

function K.TapeRound(event)
    if not want() then
        if T.cur then K.TapeClose("disabled") end
        return
    end
    if event == "start" then
        T.blocked = nil
        K.TapeOpen("round start")
    elseif event == "pre" then
        T.blocked = nil
        K.TapeClose("round over")
    elseif event == "poll" and not T.cur and not T.blocked and zb and zb.ROUND_STATE == 1 then
        K.TapeOpen("found a round already running", true)
    end
end

hook.Add("ZB_StartRound", "ZCKillcam.Tape", function() K.TapeRound("start") end)
hook.Add("ZB_PreRoundStart", "ZCKillcam.Tape", function() K.TapeRound("pre") end)
hook.Add("PostCleanupMap", "ZCKillcam.Tape", function()
    if T.cur then line(T.cur, {k = "cleanup", t = round((CurTime() - T.cur.t0) * 100)}) end
end)
hook.Add("ZCKillcam_Death", "ZCKillcam.Tape", function(victim, killer, tag)
    local tape = T.cur
    if not tape or not IsValid(victim) then return end
    line(tape, {k = "death", t = round((CurTime() - tape.t0) * 100), v = victim:UserID(), a = killer and killer.uid or nil, tag = tag})
end)
hook.Add("ShutDown", "ZCKillcam.Tape", function()
    K.TapeClose("map shutdown")
    K.TapeDrain()
    if T.catfd then T.catfd:Close() T.catfd = nil end
end)

local nextPoll = 0
hook.Add("Think", "ZCKillcam.Tape", function()
    local now = CurTime()
    if now >= nextPoll then
        nextPoll = now + 1
        K.TapeRound("poll")
    end
    local tape = T.cur
    if tape and now >= tape.next + SETTLE then
        local t0, t1 = tape.next - CHUNK, tape.next
        tape.next, tape.seq = tape.next + CHUNK, tape.seq + 1
        local seq = tape.seq
        if now - t1 > 4 then stats.late = stats.late + 1 end -- the ring is about to let go of the front of this chunk
        local ok, err = pcall(keyframes, now) -- reads the gamemode's entities from inside Think: fenced like the tracks tick
        if not ok then
            stats.errors = stats.errors + 1
            if not T.trackErrOnce then T.trackErrOnce = true print("[Killcam tape] keyframes failed: " .. tostring(err)) end
        end
        enqueue("chunk", function(job) cutChunk(tape, seq, t0, t1, job) end)
    end
    if T.queue[1] then K.TapePump() end
end)

----------------------------------------------------------------- staff
concommand.Add("zc_killcam_tape_stats", function(p)
    if IsValid(p) and not p:IsAdmin() then return end
    local out = {}
    local tape = T.cur
    out[#out + 1] = string.format("[Killcam tape %s] on=%s round=%s chunks=%d roundKB=%d | total chunks=%d MB=%.1f avgKB=%.1f", K.TapeVersion, tostring(want()),
        tape and tape.id or "none", tape and tape.chunks or 0, tape and tape.bytes / 1024 or 0, stats.chunks, stats.bytes / 1048576, stats.bytes / 1024 / math.max(stats.chunks, 1))
    out[#out + 1] = string.format("over2ms=%d (+%d during a collector sweep) errors=%d late=%d degraded=%d ragStride=%d queue=%d | pump avg=%.0fus max=%.0fus | worst chunk=%d ticks | swept=%d",
        stats.over, stats.overGc or 0, stats.errors, stats.late, stats.degraded, T.ragStride, #T.queue, stats.pumpSum / math.max(stats.pumps, 1) * 1e6, stats.pumpMax * 1e6, stats.ticksMax, stats.swept)
    local names = {}
    for name in pairs(stats.stage) do names[#names + 1] = name end
    table.sort(names)
    local parts = {}
    for _, name in ipairs(names) do
        local s = stats.stage[name]
        parts[#parts + 1] = string.format("%s %d x %.0f/%.0fus", name, s.n, s.sum / math.max(s.n, 1) * 1e6, s.max * 1e6)
    end
    out[#out + 1] = "stages (n x avg/max): " .. table.concat(parts, " | ")
    local dropped = {}
    for name, n in pairs(stats.dropped or {}) do dropped[#dropped + 1] = name .. "=" .. n end
    table.sort(dropped)
    out[#out + 1] = string.format("tracks: hot=%d known=%d props=%d doors=%d | dropped: %s", #T.hot, #T.known, #T.props, #T.doors, #dropped > 0 and table.concat(dropped, " ") or "none")
    local rounds, bytes = 0, 0
    for _, e in pairs(catalog()) do rounds, bytes = rounds + 1, bytes + (e.bytes or 0) end
    out[#out + 1] = string.format("on disk: %d rounds, %.1f MB of %d MB", rounds, bytes / 1048576, capMb:GetInt())
    for _, l in ipairs(out) do if IsValid(p) then p:PrintMessage(HUD_PRINTCONSOLE, l) else print(l) end end
end)

file.CreateDir(ROOT)
if not T.registered then -- entities that existed before this file loaded, a couple of hundred per unit
    T.registered = true
    enqueue("registry", function()
        local all = ents.GetAll()
        for first = 1, #all, 200 do
            local began = SysTime()
            for i = first, math.min(first + 199, #all) do classify(all[i]) end
            pause("registry", began)
        end
    end)
end
if not T.repaired then
    T.repaired = true
    enqueue("repair", function() K.TapeRepair() end)
end
