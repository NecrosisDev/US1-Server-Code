-- Z-City killcam, phase 2: cut the clip, anonymise it, file it on the right records.
-- A clip is cut POST seconds after a qualifying death, so the recorder's ring
-- already holds the aftermath. Everything identifying is captured AT the death.
if not SERVER then return end
local K = assert(ZCKillcam, "recorder must load first")
K.ClipVersion = 2
local ROOT, RADIUS, KEEP, MAX_AGE, MAX_BYTES = "zc_killcam", 1500, 15, 14 * 86400, 300 * 1024 * 1024
K.Root, K.Keep = ROOT, KEEP
local stats = K.Stats
stats.clips, stats.cutMax, stats.bytes = stats.clips or 0, 0, stats.bytes or 0
stats.gather, stats.json, stats.pack = 0, 0, 0 -- worst single stage in seconds; cutMax is the worst of the three
file.CreateDir(ROOT) file.CreateDir(ROOT .. "/clips") file.CreateDir(ROOT .. "/index")

-- R7: one per-map table of WHY a replay was not shown, so "not shown" becomes a number the owner can read
-- instead of a guess. Printed by zc_killcam_life (sv_life.lua) and zc_killcam_highlight_stats (sv_highlight.lua).
-- `respawned` is bumped by the client (zckc_life_drop) when a held-while-alive blob's 90s window lapses unclaimed.
K.Drops = K.Drops or {roundEnding = 0, backlog = 0, expired = 0, busy = 0, generation = 0, floor = 0, respawned = 0, overflow = 0, unsent = 0, earlyDone = 0}
-- P1 (killcam_revitalize, 2026-09-24): the reasons that were never counted. Client-reported (zckc_life_drop):
-- respawnedWait / respawnedPlay / map / replaced; server side: respawnedPack (the victim respawned before the
-- sequence was packed) and empty (every cut of the life failed). Filled in here AND bumped with `or 0`, so a
-- K.Drops that survived a hot reload without them still works.
for _, key in ipairs({"respawnedWait", "respawnedPlay", "map", "replaced", "respawnedPack", "empty"}) do K.Drops[key] = K.Drops[key] or 0 end
-- Shared with sv_life.lua's age-check (R2) and sv_highlight.lua's funny-moment window (R4): how far back the
-- sample/event rings actually reach (sv_recorder K.Depth/K.HZ). One place to derive it instead of two.
K.RingReach = (K.Depth and K.HZ) and (K.Depth / K.HZ) or 20

----------------------------------------------------------------- the worker
-- Cutting and packing clips is the expensive part of the killcam, and it used to run as whole units: on US1 one cut
-- measured up to 8.6 ms, one util.TableToJSON of a sequence 14.4 ms, one util.Compress 13.2 ms. Those now run as jobs:
-- coroutines resumed from Think for SLICE seconds a tick, one job at a time, first in first out. Work inside a job
-- is split into units; breathe(stage) closes one (timed, counted when over LIMIT) and hands the tick back when the
-- slice is spent. Nothing inside a job may pcall around a breathe (plain Lua cannot yield across it): a job that
-- throws is dropped and its onFail is told.
-- PROVISIONAL(2026-09-21, slice and batch sizes come from the round tape's US1 measurements, ratify-by: 2026-10-05)
local SLICE, LIMIT, RAG_SPAN, RAG_BATCH, TEXT_MAX, BACKLOG = 0.001, 0.002, 1, 12, 3800, 6
-- P1 (2026-09-26, killcam_polish): two scratch tables reused across every K.Cut call for the two hottest
-- per-sample allocations (a sample row, a ragdoll frame) - see K.Cut below. Never shrunk, only grown as needed;
-- an index past the current row/frame's tracked width holds a stale value from a wider previous one and is never
-- read past that width, so reuse is safe. This does not change what gets stored: a row/frame that is actually KEPT
-- (differs from the last one, or ends a held run) still gets its own fresh table, exactly as before - only the
-- per-tick THROWAWAY copy that used to be built just to test "did anything change" is gone.
-- ROWSBUF is a third scratch table, unrelated to the two above: rowsJSON (near K.PackSequence, below) flattens a
-- row array straight into it instead of building one throwaway string PER ROW plus a `parts` table sized to the
-- row count, then joining those; same table.concat number formatting, byte-identical text, one join instead of N+1.
local ROWBUF, RAGBUF, ROWSBUF = {}, {}, {}
K.WorkQ = K.WorkQ or {}
-- R2/P5 (owner correction, 2026-09-24): a second, LOW-priority queue. An opted-out victim's cut still runs
-- (it must, so zckc_save/zckc_report keep working - see sv_life.lua queueCut), but it must never make a cut
-- that WILL be watched wait behind it. Drained only once the normal queue is empty, so a low job queued first
-- still yields to a normal job queued after it - true priority, not just FIFO order.
K.WorkQLow = K.WorkQLow or {}
K.Backlog = BACKLOG -- R2: exposed so a caller (sv_life.lua's age-check drop) can tell an expiry apart from a queue backlog
local queue, queueLow = K.WorkQ, K.WorkQLow
stats.work = stats.work or {over = 0, errors = 0, jobs = 0, ticksMax = 0, expired = 0, stage = {}}
local work = stats.work
local sliceBegan, draining = 0, false

-- P1 (killcam_revitalize, 2026-09-24): which scheduler runs the queue.
--   0 = as shipped: one job a tick, each tier strictly first in first out (the normal tier before the low one).
--   1 = ring-bound jobs first: a job that reads the recorder's rings (a life or highlight CUT - it carries `due`, the
--       moment its window leaves the ring) runs before any job that does not (packing, persisting, the tape server),
--       earliest due first, normal tier before low; everything else keeps its arrival order. When a job finishes
--       with slice to spare, the next one starts in the same tick. The per-tick cap is unchanged: SLICE, halved
--       while the round tape is busy, doubled while behind - over BACKLOG jobs as before, or (sched 1 only) once the
--       oldest queued job has waited more than LATE seconds. Never more than 2 x SLICE a tick, as before.
-- Why (live US1, 2026-09-24, 26 players): cuts average ~10.6 ms of work in ~117 tiny units; packs ~194 ms in ~250
-- units (pack.compress alone ~173 units of 0.61 ms). In arrival order a cut queued behind k packs waits k x ~3 s, so
-- a fight that ends six or seven lives at once pushes the last cuts past the 20 s ring (longestWait 19.8 s /
-- expired 10 on the first probe, 16.6 s on the second). A pack reads copies and can wait; a cut cannot.
-- Default 0 until the owner flips it; zc_killcam_work prints the wait histogram for either setting.
local LATE = 1 -- seconds; see K.WorkPump
local sched = CreateConVar("zc_killcam_work_sched", "0", FCVAR_ARCHIVE, "Killcam work scheduler: 0 one job a tick in arrival order (as shipped), 1 cuts before packing by ring deadline, several short jobs per tick (same per-tick budget)")

local function book(stage, began)
    local cost = SysTime() - began
    local s = work.stage[stage]
    if not s then s = {n = 0, sum = 0, max = 0} work.stage[stage] = s end
    s.n, s.sum = s.n + 1, s.sum + cost
    if cost > s.max then s.max = cost end
    if cost > LIMIT then work.over = work.over + 1 end
end

-- P1 instrumentation (always on, either scheduler): per job kind, how long jobs WAITED from being queued to their
-- first slice (histogram), how long they then took to finish (wall seconds and ticks), and how many never ran.
-- Keyed "kind" or "kind(low)" for the low tier. Printed by zc_killcam_work; `zc_killcam_work reset` zeroes it.
local WAIT_EDGES = {0.1, 0.5, 1, 2, 5, 10, 20} -- seconds; bucket i counts waits under WAIT_EDGES[i], the last one >= 20
work.wait = work.wait or {}
local function waitRow(job)
    local key = job.low and (job.kind .. "(low)") or job.kind
    local h = work.wait[key]
    if not h then h = {n = 0, sum = 0, max = 0, runMax = 0, ticksMax = 0, dropped = 0, b = {0, 0, 0, 0, 0, 0, 0, 0}} work.wait[key] = h end
    return h
end
local function bookWait(job, now)
    local h, w = waitRow(job), now - job.born
    h.n, h.sum = h.n + 1, h.sum + w
    if w > h.max then h.max = w end
    local i = 1
    while WAIT_EDGES[i] and w >= WAIT_EDGES[i] do i = i + 1 end
    h.b[i] = h.b[i] + 1
end
local function bookDone(job, now)
    local h = waitRow(job)
    local run = now - (job.started or now)
    if run > h.runMax then h.runMax = run end
    if job.ticks > h.ticksMax then h.ticksMax = job.ticks end
end

-- fn(breathe) runs inside the job. breathe(stage) returns nothing; call it after every unit of work.
-- lowPriority: queued behind everything in the normal queue, drained only once it is empty.
-- due (optional): the CurTime() by which the job must have run, because it reads the recorder's rings and they only
-- reach back so far (K.RingReach). Only the ring-bound scheduler (zc_killcam_work_sched 1) orders by it.
-- noExpire (optional): the legacy low-tier age sweep below leaves this job alone (it reads no ring: a persist).
function K.Work(kind, fn, onFail, lowPriority, due, noExpire)
    local job = {kind = kind, ticks = 0, onFail = onFail, born = CurTime(), low = lowPriority == true or nil, due = due, noExpire = noExpire}
    job.co = coroutine.create(function()
        local began = SysTime()
        fn(function(stage)
            book(stage, began)
            if not draining and SysTime() - sliceBegan > job.slice then coroutine.yield() end
            began = SysTime()
        end)
    end)
    if lowPriority then queueLow[#queueLow + 1] = job else queue[#queue + 1] = job end
    return job
end

-- Adversarial review 2026-09-24: the low-priority tier could sit forever under constant deaths (it
-- only drains once the normal queue is empty). Sweeps it for jobs older than the ring actually
-- reaches back (K.RingReach) - they would cut garbage anyway (same test `cut()`, sv_life.lua,
-- applies to a job that DOES get to run) - dropping them with the same K.Drops.expired counter.
-- Run at the top of every WorkPump call and on ZB_StartRound (a round starting makes every queued
-- low job's window stale relative to the new round regardless of age).
-- P1: a job marked noExpire (a persist: it reads no ring) is left alone. Under the ring-bound scheduler the sweep
-- is not needed at all - a low cut runs before any packing and applies the same age test itself - so it is skipped.
local function sweepLow()
    if sched:GetInt() == 1 then return end
    local reach, now = K.RingReach or 20, CurTime()
    for i = #queueLow, 1, -1 do
        local job = queueLow[i]
        if not job.noExpire and now - job.born > reach then
            table.remove(queueLow, i)
            K.Drops.expired = K.Drops.expired + 1
            work.expired = (work.expired or 0) + 1
            local row = waitRow(job)
            row.dropped = row.dropped + 1
            if job.onFail then pcall(job.onFail, "expired in the low-priority queue") end
        end
    end
end
hook.Add("ZB_StartRound", "ZCKillcam.WorkSweepLow", sweepLow)

-- Resumes `job` (which sits at index `at` of `list`) for one slice. Returns true when the job is finished.
local function resume(job, list, at, slice, now)
    job.slice = slice
    if job.ticks == 0 then
        work.waitMax = math.max(work.waitMax or 0, now - job.born)
        bookWait(job, now)
        job.started = now
    end
    job.ticks = job.ticks + 1
    local ok, err = coroutine.resume(job.co)
    local finished = not ok or coroutine.status(job.co) == "dead"
    if finished then
        table.remove(list, at)
        work.jobs = work.jobs + 1
        if job.ticks > work.ticksMax then work.ticksMax = job.ticks end
        bookDone(job, now)
    end
    if not ok then
        work.errors = work.errors + 1
        ErrorNoHalt("[Killcam] " .. job.kind .. " job failed: " .. tostring(err) .. "\n")
        if job.onFail then pcall(job.onFail, err) end
    end
    return finished
end

-- The ring-bound scheduler's choice: the earliest-due ring job (normal tier, then low), else the head of the normal
-- tier, else the head of the low tier. A job that has already started keeps its place in its tier, so a pack that
-- was interrupted by a cut resumes where it stopped as soon as no cut is waiting.
local tiers = {queue, queueLow}
local function pick()
    for _, list in ipairs(tiers) do
        local best, at
        for i, job in ipairs(list) do
            if job.due and (not best or job.due < best.due) then best, at = job, i end
        end
        if best then return best, list, at end
    end
    if queue[1] then return queue[1], queue, 1 end
    if queueLow[1] then return queueLow[1], queueLow, 1 end
end

-- Pack boost (killcam_polish, 2026-09-25). Measured on US1 (21 deaths): the life pack is 2.13 s of the 4.99 s average
-- death->screen, and that is wall time, not CPU - about 1 ms of work per KB spread one SLICE a tick. A life.pack gets
-- zc_killcam_pack_boost x the slice while at most one other job is queued (both tiers), the round tape is idle and
-- TickGov (sv_tick_governor.lua) reads NORMAL; never over 4 ms a tick. Any other state, or boost 1: as before.
-- PROVISIONAL(2026-09-25, boost 3 = 3 ms a tick chosen from the measured pack share, not measured under load, ratify-by: 2026-10-09)
K.PackBoost = CreateConVar("zc_killcam_pack_boost", "3", FCVAR_ARCHIVE, "Killcam: a death's pack job may take this many times the work slice per tick while the queue is short and the server tick is NORMAL (1 = off)", 1, 4)
function K.PackSlice(slice)
    local boost = K.PackBoost:GetInt()
    if boost <= 1 or #queue + #queueLow > 2 or (K.Tape and K.Tape.queue and K.Tape.queue[1]) then return slice end
    local gov = rawget(_G, "TickGov")
    if not (istable(gov) and isfunction(gov.State)) then
        if not K.PackSaidGov then K.PackSaidGov = true print("[Killcam] pack boost idle: TickGov.State is missing (sv_tick_governor.lua)") end
        return slice
    end
    if gov.State() ~= "NORMAL" then return slice end
    return math.min(slice * boost, 0.004)
end
-- Runs queued work for one tick's slice. Returns true while there is work left (either tier).
function K.WorkPump()
    sweepLow()
    local low = queue[1] == nil
    local active = low and queueLow or queue
    if not active[1] then return false end
    local now = CurTime()
    sliceBegan = SysTime()
    -- the round tape has a slice of its own: when it is busy in the same tick, this one takes half
    local slice = (K.Tape and K.Tape.queue and K.Tape.queue[1]) and SLICE / 2 or SLICE
    -- The sample rings reach back 20 s: a long queue (a big fight ends many lives at once) is worked off at double pace.
    local behind = #active > BACKLOG
    -- P1, ring-bound scheduler only: counting JOBS stops meaning "behind" once the cheap cuts are taken first - the
    -- queue is then a few long packs, never over BACKLOG, and they would crawl at the single slice (simulated from the
    -- live counters: average pack delivery 7.5 s -> 12.6 s for 6 deaths in 3 s). So under sched 1 the double slice
    -- also applies while the oldest queued job has waited over LATE. Same cap as ever (2 x SLICE); same total work.
    if not behind and sched:GetInt() == 1 then
        local oldest = now
        for _, job in ipairs(queue) do if job.born < oldest then oldest = job.born end end
        for _, job in ipairs(queueLow) do if job.born < oldest then oldest = job.born end end
        behind = now - oldest > LATE
    end
    if behind then slice = slice * 2 end
    local boosted = K.PackSlice(slice)
    if sched:GetInt() ~= 1 then
        resume(active[1], active, 1, active[1].kind == "life.pack" and boosted or slice, now)
        return queue[1] ~= nil or queueLow[1] ~= nil
    end
    -- Several jobs a tick, inside the one budget: another starts only while the slice has time left, and a job that
    -- yields has spent it. While draining (K.WorkDrain) each call runs one job; the drain loop does the rest.
    repeat
        local job, list, at = pick()
        if not job then break end
        local own = job.kind == "life.pack" and boosted or slice -- pack boost: the pack's own slice ends the tick
        if not resume(job, list, at, own, now) then break end
    until draining or SysTime() - sliceBegan > own
    return queue[1] ~= nil or queueLow[1] ~= nil
end
function K.WorkDrain()
    draining = true
    local guard = 0
    while K.WorkPump() and guard < 100000 do guard = guard + 1 end
    draining = false
end
hook.Add("Think", "ZCKillcam.Work", function() if queue[1] or queueLow[1] then K.WorkPump() end end)

local function workLines()
    local parts = {}
    for name, s in pairs(work.stage) do parts[#parts + 1] = string.format("%s n=%d avg=%.2f max=%.2f", name, s.n, s.sum / math.max(s.n, 1) * 1000, s.max * 1000) end
    table.sort(parts)
    local out = {string.format("[Killcam] work sched=%d jobs=%d queue=%d queueLow=%d over2ms=%d errors=%d expired=%d worstJob=%d ticks longestWait=%.1fs | ms: %s", sched:GetInt(), work.jobs, #queue, #queueLow, work.over, work.errors, work.expired or 0, work.ticksMax, work.waitMax or 0, table.concat(parts, " | "))}
    local kinds = {}
    for kind in pairs(work.wait) do kinds[#kinds + 1] = kind end
    table.sort(kinds)
    for _, kind in ipairs(kinds) do
        local h = work.wait[kind]
        local b = h.b
        out[#out + 1] = string.format("[Killcam] wait %s n=%d avg=%.2fs max=%.1fs | <0.1:%d <0.5:%d <1:%d <2:%d <5:%d <10:%d <20:%d >=20:%d | run max=%.1fs ticks=%d | never ran=%d",
            kind, h.n, h.sum / math.max(h.n, 1), h.max, b[1], b[2], b[3], b[4], b[5], b[6], b[7], b[8], h.runMax, h.ticksMax, h.dropped)
    end
    return out
end
K.WorkLines = workLines
concommand.Add("zc_killcam_work", function(p, _, args)
    if IsValid(p) and not p:IsAdmin() then return end
    if args and args[1] == "reset" then
        -- Zero the counters, keep the queues: for a clean before/after of zc_killcam_work_sched on one map.
        work.over, work.errors, work.jobs, work.ticksMax, work.expired, work.waitMax, work.stage, work.wait = 0, 0, 0, 0, 0, 0, {}, {}
    end
    for _, line in ipairs(workLines()) do
        if IsValid(p) then p:PrintMessage(HUD_PRINTCONSOLE, line) else print(line) end
    end
end)

-- Only modes with traitors have "innocent" and "traitor"; elsewhere every frag would look innocent-on-innocent.
function K.TraitorRound()
    local mode = CurrentRound and CurrentRound()
    return mode ~= nil and (mode.name == "hmcd" or mode.base == "hmcd")
end

local function identity(p, role)
    return {slot = p:EntIndex(), uid = p:UserID(), id = not p:IsBot() and p:SteamID64() or nil, name = K.DisplayName(p), steam = K.SteamName(p), role = role, traitor = p.isTraitor == true}
end

local round = math.Round
-- Builds the clip table. `parties` maps slot -> identity for everyone allowed to keep a name.
-- `from`/`to`/`radius` are optional: the life sequence cuts short windows around each hit with a tighter radius.
-- `breathe` is optional: inside a K.Work job it ends a unit after every player slot and every RAG_SPAN seconds of
-- ragdoll frames. It is never called from inside a ring walk - the rings keep turning while a job sleeps, and
-- K.EachRagFrame reads its head live.
-- What is fitted to an actor's weapons (owner, 2026-09-21: "draw the optics and attachments"). homigrad_base keeps it
-- in wep.attachments, placement -> {name, ...} (sh_attachment.lua); the clip carries only the names, class ->
-- {placement = name} - the client has the rest in hg.attachments and the weapon's availableAttachments.
-- Read when the clip is cut, NOT sampled: the 20 Hz path pays nothing. The dead hold nothing, so both parties of a
-- death are remembered at DoPlayerDeath (the weapons are still held there) and the cut falls back on that.
-- PROVISIONAL(2026-09-21, a set swapped between the clip's start and the cut is drawn as the newer set, ratify-by: 2026-10-21)
local attCache = {} -- uid -> {class = {placement = name}}
function K.AttachmentsOf(p)
    local out
    for _, w in ipairs(p:GetWeapons()) do
        if istable(w.attachments) then
            local set
            for place, att in pairs(w.attachments) do
                local name = istable(att) and att[1]
                if isstring(name) and name ~= "" and name ~= "empty" then set = set or {} set[tostring(place)] = name end
            end
            if set then out = out or {} out[w:GetClass()] = set end
        end
    end
    return out
end
local function remember(p)
    if not IsValid(p) or not p:IsPlayer() then return end
    local ok, set = pcall(K.AttachmentsOf, p)
    if ok then attCache[p:UserID()] = set end
end
hook.Add("DoPlayerDeath", "ZCKillcam.ClipAttachments", function(victim, attacker) remember(victim) remember(attacker) end) -- returns nothing
hook.Add("ZB_PreRoundStart", "ZCKillcam.ClipAttachments", function() attCache = {} if K.ZoomReset then K.ZoomReset() end end)
local function attachmentsOf(slot)
    local who = K.Identity(slot)
    if not who then return nil end
    local p = Entity(slot)
    if IsValid(p) and p:IsPlayer() and p:UserID() == who.uid and p:Alive() then remember(p) end
    return attCache[who.uid]
end

-- How far behind the server this player's screen runs, in centiseconds: round trip + interpolation - exactly what the engine's
-- lag compensation rewinds by, and homigrad_base fires inside LagCompensation (sh_bullet.lua:690). Read at cut time.
function K.LagOf(ident)
    return K.LagOfPlayer(ident and ident.uid and Player and Player(ident.uid))
end
function K.LagOfPlayer(p)
    if not IsValid(p) or p:IsBot() then return end
    local lerp = math.max(p:GetInfoNum("cl_interp", 0.1), p:GetInfoNum("cl_interp_ratio", 2) / math.max(p:GetInfoNum("cl_updaterate", 30), 1))
    return math.Clamp(math.floor((p:Ping() / 1000 + lerp) * 100 + 0.5), 0, 50)
end

function K.Cut(death, origin, parties, mode, tag, from, to, radius, breathe)
    breathe = breathe or function() end
    local t0, t1 = from or death - K.Pre, to or death + K.Post
    local clip = {v = K.ClipVersion, map = game.GetMap(), mode = mode, tag = tag, t = os.time(), pre = death - t0, len = t1 - t0, hz = K.HZ,
        origin = {round(origin.x), round(origin.y), round(origin.z)}, actors = {}, events = {}}
    local index = {} -- slot -> actor number inside the clip
    local near = (radius or RADIUS) ^ 2
    for slot = 1, game.MaxPlayers() do
        local captured = K.Identity(slot)
        local capturedUID = captured and captured.uid
        local rows, close = {}, parties[slot] ~= nil
        local anim, animLast, animHeld = {}, nil, nil
        local hands, lastHands, heldHandsTime = {}, nil, nil
        local last, heldTime, rowLen -- a player standing still (or dead) collapses to the first and last row of the run
        -- Most of the server is far away: find that out without building a row table per sample
        -- (one instance cut measured 13.6 ms on US1 when every slot built rows first).
        if not close then
            K.EachSample(slot, t0, t1, function(_, x, y)
                if close then return end
                local dx, dy = x - origin.x, y - origin.y
                if dx * dx + dy * dy <= near then close = true end
            end)
        end
        local named = parties[slot] ~= nil -- only a named party can be looked through: bystanders keep the short row
        if close then K.EachSample(slot, t0, t1, function(t, x, y, z, yaw, pitch, flags, wep, hp, eye, ex, ey, ez, vx, vy, vz, seq, cyc, pose, pb, pn, bodyYaw, animMode, grip, carry, cx, cy, cz, cp, cyaw)
            local dx, dy = x - origin.x, y - origin.y
            -- Relative, rounded integers compress several times better than raw floats.
            local r1, r2, r3, r4 = round((t - death) * 100), round(dx), round(dy), round(z - origin.z)
            local r5, r6, r7, r8, r9, r10 = round(yaw), round(pitch), flags, wep, hp, round(eye or 64)
            ROWBUF[1], ROWBUF[2], ROWBUF[3], ROWBUF[4], ROWBUF[5] = r1, r2, r3, r4, r5
            ROWBUF[6], ROWBUF[7], ROWBUF[8], ROWBUF[9], ROWBUF[10] = r6, r7, r8, r9, r10
            -- The first-person eye in tenths of a unit, measured from the ROUNDED position so the camera does not inherit
            -- the rounding: [11] [12] [13], all 0 when the recorder did not know it (ragdoll, no neck bone).
            -- [14] [15]: what whole degrees throw away of yaw and pitch, in hundredths - seen through someone's eyes, aim in
            -- one-degree steps is a visible judder (owner, 2026-09-21: "aim is very steppy").
            -- Only a named party can be looked THROUGH, so only they get a real eye - but the fields are still written as
            -- zeroes for everyone else, because [16] onwards follow them and a Lua array with a hole in it is not an array
            -- any more: util.TableToJSON would hand the client an object, or a row cut off at ten.
            if named and ez and ez ~= 0 then
                ROWBUF[11], ROWBUF[12], ROWBUF[13] = round((dx + ex - r2) * 10), round((dy + ey - r3) * 10), round((z - origin.z + ez - r4) * 10)
            else
                ROWBUF[11], ROWBUF[12], ROWBUF[13] = 0, 0, 0
            end
            if named then
                ROWBUF[14], ROWBUF[15] = round((yaw - r5) * 100), round((pitch - r6) * 100)
            else
                ROWBUF[14], ROWBUF[15] = 0, 0
            end
            -- What the body was doing, for EVERY actor and not just the named ones: a bystander walking through the
            -- background is exactly where a replay gives itself away. [16..18] velocity in whole units/s, [19] the
            -- sequence the server was playing, [20] its cycle in thousandths, [21..] the pose parameters in hundredths,
            -- as many as the recorder had (none at all when zc_killcam_pose is off, and then the row simply ends at 20).
            ROWBUF[16], ROWBUF[17], ROWBUF[18] = round(vx or 0), round(vy or 0), round(vz or 0)
            ROWBUF[19], ROWBUF[20] = seq or -1, round((cyc or 0) * 1000)
            local pcount = pn or 0
            for k = 1, pcount do ROWBUF[20 + k] = round(pose[pb + k] * 100) end
            rowLen = 20 + pcount
            -- Separate from pose values, so old clients can ignore this metadata.
            -- P1 (2026-09-26): the {row[1], grip, ...} comparison table used to be built every single sample a hand
            -- item was held, only to be thrown away when nothing changed. The values are now compared as scalars
            -- against lastHands' own fields; a table is only allocated when the state actually changes (new
            -- lastHands, exactly as before) or when a held run ends (the flush, built once from lastHands + the
            -- last-seen held time instead of once per held tick).
            if grip ~= nil then
                local g, c = grip, carry or 0
                local h4 = c > 0 and round((cx - origin.x) * 10) or 0
                local h5 = c > 0 and round((cy - origin.y) * 10) or 0
                local h6 = c > 0 and round((cz - origin.z) * 10) or 0
                local h7, h8 = round((cp or 0) * 100), round((cyaw or 0) * 100)
                local same = lastHands ~= nil and lastHands[2] == g and lastHands[3] == c and lastHands[4] == h4 and lastHands[5] == h5 and lastHands[6] == h6 and lastHands[7] == h7 and lastHands[8] == h8
                if same then heldHandsTime = r1 else
                    if heldHandsTime then hands[#hands + 1] = {heldHandsTime, lastHands[2], lastHands[3], lastHands[4], lastHands[5], lastHands[6], lastHands[7], lastHands[8]} heldHandsTime = nil end
                    local hand = {r1, g, c, h4, h5, h6, h7, h8}
                    hands[#hands + 1], lastHands = hand, hand
                end
            end
            local ay, mode = round((bodyYaw or 0) * 100), animMode or 0
            if animLast and animLast[2] == ay and animLast[3] == mode then
                animHeld = r1
            else
                if animHeld then anim[#anim + 1] = {animHeld, animLast[2], animLast[3]} animHeld = nil end
                animLast = {r1, ay, mode}
                anim[#anim + 1] = animLast
            end
            -- P1 (2026-09-26): the row itself is the biggest win here - it used to be a brand-new table every
            -- sample, kept or not, just to run this comparison. ROWBUF is scratch; a real table (`newRow`, or `h`
            -- for a held-run flush) is only built for a row that is actually kept, exactly as many as before.
            local same = last ~= nil and rowLen == #last
            if same then for f = 2, rowLen do if ROWBUF[f] ~= last[f] then same = false break end end end
            if same then heldTime = r1 return end
            if heldTime then
                local h = {}
                for f = 1, #last do h[f] = last[f] end
                h[1] = heldTime
                rows[#rows + 1] = h
                heldTime = nil
            end
            local newRow = {}
            for f = 1, rowLen do newRow[f] = ROWBUF[f] end
            rows[#rows + 1] = newRow
            last = newRow
        end) end
        if heldTime then
            local h = {}
            for f = 1, #last do h[f] = last[f] end
            h[1] = heldTime
            rows[#rows + 1] = h
        end
        if heldHandsTime then hands[#hands + 1] = {heldHandsTime, lastHands[2], lastHands[3], lastHands[4], lastHands[5], lastHands[6], lastHands[7], lastHands[8]} end
        if animHeld then anim[#anim + 1] = {animHeld, animLast[2], animLast[3]} end
        -- Ragdoll poses for this actor, relative to the clip origin: {cs, x, y, z, pitch, yaw, roll, ... per bone}.
        local frames, bones
        if close and #rows > 0 and K.EachRagFrame then
            local prev, heldFrameTime
            -- P1 (2026-09-26): same scratch-then-materialize trick as the row buffer above, on RAGBUF (file scope) -
            -- a still ragdoll used to allocate one full multi-bone table (up to 1 + 24*6 = 145 fields, RAG_BONES=24
            -- per sv_recorder.lua) every single frame it stayed still, just to compare it and throw it away.
            local function frame(t, d, base, n)
                if n == 0 or (frames and #frames >= 360) then return end -- 12 s of fall at 30 Hz, as 240 was at 20
                local flen = 1 + n * 6
                RAGBUF[1] = round((t - death) * 100)
                for b = 0, n - 1 do
                    local i, o = base + b * 6, 1 + b * 6
                    RAGBUF[o + 1], RAGBUF[o + 2], RAGBUF[o + 3] = round(d[i + 1] - origin.x), round(d[i + 2] - origin.y), round(d[i + 3] - origin.z)
                    RAGBUF[o + 4], RAGBUF[o + 5], RAGBUF[o + 6] = round(d[i + 4]), round(d[i + 5]), round(d[i + 6])
                end
                if prev and #prev ~= flen then frames, prev, heldFrameTime = nil, nil, nil end -- the body changed shape: keep the newest body only, one skeleton per actor
                local same = prev ~= nil
                if same then for k = 2, flen do if RAGBUF[k] ~= prev[k] then same = false break end end end
                if same then heldFrameTime = RAGBUF[1] return end
                if heldFrameTime and heldFrameTime > prev[1] and #frames < 359 then
                    local h = {}
                    for k = 1, #prev do h[k] = prev[k] end
                    h[1] = heldFrameTime
                    frames[#frames + 1] = h
                end
                heldFrameTime = nil
                frames = frames or {}
                local f = {}
                for k = 1, flen do f[k] = RAGBUF[k] end
                frames[#frames + 1] = f
                prev, bones = f, n
            end
            for a = t0, t1, RAG_SPAN do
                K.EachRagFrame(slot, a, math.min(a + RAG_SPAN, t1), frame)
                breathe("cut.ragdoll")
            end
        end
        if close and #rows > 0 and (K.Identity(slot) and K.Identity(slot).uid) == capturedUID then
            local who = parties[slot]
            -- What they wore, recorded off the live player (sv_recorder's look()): the model file alone is the default
            -- variant in the default colour, which is somebody else.
            --
            -- Appearance rides on BYSTANDERS TOO; the owner now also requests their Steam names. This is a real trade, not a free
            -- one: appearance here is player-authored and persistent, so a regular's colour and outfit are recognised
            -- on sight by other regulars. The clip already carried the bystander's MODEL, so this sharpens an existing
            -- edge rather than opening a new one, and a replay in which the uninvolved are all the same grey stranger
            -- is hard to read. If the owner would rather bystanders stay unrecognisable, drop sk/bg/col (and m) for
            -- actors with no name - that is the whole change, right here.
            -- how they looked AT THE DEATH, not at cut time ~1.3 s later (sv_recorder K.LookAt)
            local me = (K.LookAt and K.LookAt(slot, death)) or K.Identity(slot)
            local ragSkin, ragGroups
            if K.RagLook then ragSkin, ragGroups = K.RagLook(slot) end -- `x and f()` would keep only the first return
            -- Owner 2026-09-22: Steam names above all recorded bodies, including nearby actors.
            -- Character names/roles retain their existing scope; no SteamID is placed in the clip.
            clip.actors[#clip.actors + 1] = {name = who and who.name or nil, steam = (who and who.steam) or (me and me.steam), uid = capturedUID, role = who and who.role or "bystander", s = rows, anim = anim, hands = #hands > 0 and hands or nil, -- no SteamID: the index grants access
                m = me and me.model or nil, sk = me and me.skin or nil, bg = me and me.groups or nil, col = me and me.colour or nil,
                sm = me and me.subs or nil, ac = me and me.acc or nil,
                gore = K.GoreRows and K.GoreRows(slot, capturedUID, t0, t1, death, origin) or nil,
                att = attachmentsOf(slot), lag = named and K.LagOf(K.Identity(slot)) or nil, rest = K.RestRows and K.RestRows(slot, t0, t1, death, origin.x, origin.y, origin.z) or nil, zoom = named and K.ZoomRows and K.Identity(slot) and K.ZoomRows(K.Identity(slot).uid, death, t1) or nil, rag = frames and {m = K.RagModel(slot), n = bones, f = frames, sk = ragSkin, bg = ragGroups} or nil}
            index[slot] = #clip.actors
        end
        breathe("cut.slot")
    end
    local soundUID = {}
    for slot, i in pairs(index) do
        soundUID[slot] = clip.actors[i].uid
        clip.actors[i].uid = nil
    end
    if K.EachSound then
        local sounds = {}
        K.EachSound(t0, t1, function(row)
            local actor = index[row[2]]
            local dx, dy, dz = row[4] - origin.x, row[5] - origin.y, row[6] - origin.z
            if ((actor and soundUID[row[2]] == row[3]) or row[2] == 0)
                and dx * dx + dy * dy + dz * dz <= ((radius or RADIUS) + 300) ^ 2 then
                sounds[#sounds + 1] = {round((row[1] - death) * 100), actor or 0, row[7],
                    round(dx * 10), round(dy * 10), round(dz * 10), row[8], row[9], row[10], row[11]}
            end
        end)
        clip.sounds = {}
        for i = math.max(#sounds - 383, 1), #sounds do clip.sounds[#clip.sounds + 1] = sounds[i] end
    end
    local weapons = {}
    K.EachEvent(t0, t1, function(t, kind, a, b, dmg, hitgroup, wep, los, _, px, py, pz, eyaw, epitch, body, ballistic, facts, penetration, swing, anchor, organs)
        if index[a] or index[b] then
            local e = {round((t - death) * 100), kind, index[a] or 0, index[b] or 0, round(dmg * 10) / 10, hitgroup, wep, los and 1 or 0}
            -- [9..11] the bullet's source (shot) or landing point (hit) in tenths from the origin, [12] [13] its yaw and pitch in hundredths
            if px and (px ~= 0 or py ~= 0 or pz ~= 0) then
                e[9], e[10], e[11] = round((px - origin.x) * 10), round((py - origin.y) * 10), round((pz - origin.z) * 10)
                e[12], e[13] = round((eyaw or 0) * 100), round((epitch or 0) * 100)
            end
            if swing then e.swing = {v = 1, duration = swing.duration} end
            if facts then
                e.ballistics = {v = 1, range = facts.range, angle = facts.angle, muzzle = facts.muzzle, caliber = facts.caliber, diameter = facts.diameter}
            end
            if penetration then
                e.penetration = {v = 1, reason = penetration.reason, points = {}}
                for _, point in ipairs(penetration.points) do
                    e.penetration.points[#e.penetration.points + 1] = {
                        round((point[1] - origin.x) * 10),
                        round((point[2] - origin.y) * 10),
                        round((point[3] - origin.z) * 10),
                    }
                end
                local detail = penetration.v2
                if istable(detail) and detail.v == 2 then
                    local v2 = {
                        v = 2,
                        mode = detail.mode,
                        reason = detail.reason,
                        energy = detail.energy,
                        deflections = detail.deflections,
                        armored = detail.armored,
                        expanded = detail.expanded,
                        fragments = detail.fragments,
                        events = {},
                    }
                    for _, mark in ipairs(detail.events or {}) do
                        local row = {
                            k = mark[1],
                            p = {
                                round((mark[2] - origin.x) * 10),
                                round((mark[3] - origin.y) * 10),
                                round((mark[4] - origin.z) * 10),
                            },
                            f = mark[5],
                        }
                        v2.events[#v2.events + 1] = row
                    end
                    e.penetration.v2 = v2
                end
            end
            if istable(organs) then -- UI cohesion U1: the organ rows the round crossed (sv_recorder.lua organList)
                e.organs = {}
                for k = 1, math.min(#organs, 12) do
                    local o = organs[k]
                    e.organs[k] = {bone = o.bone, key = o.key, name = o.name, label = string.sub(tostring(o.label or o.name), 1, 40), class = o.class, dep = o.dep}
                end
            end
            e.ballistic = ballistic -- nil in older recordings; 0 explicitly excludes melee/merged/shotgun hits
            e.anchor = anchor -- A1: the landing point on the body (sv_recorder.lua eanchor); nil when the hit had no point
            if body then
                e.body = {}
                for k = 1, 6 do
                    local axis = (k - 1) % 3
                    local offset = axis == 0 and origin.x or (axis == 1 and origin.y or origin.z)
                    e.body[k] = round((body[k] - offset) * 10)
                end
            end
            clip.events[#clip.events + 1] = e
            weapons[wep] = true
        end
    end)
    for _, actor in ipairs(clip.actors) do for _, row in ipairs(actor.s) do weapons[row[8]] = true end end
    clip.weapons = {} -- {id, class} pairs: JSON turns numeric-string keys back into numbers
    for id in pairs(weapons) do if id > 0 then clip.weapons[#clip.weapons + 1] = {id, K.WeaponName(id)} end end
    clip.gibs = K.GibRows and K.GibRows(t0, t1, death, origin, radius or RADIUS) or nil
    -- P8: thrown props and projectiles ride in the same list, tagged k = kind (the client draws their real model)
    local objects = K.ObjectRows and K.ObjectRows(t0, t1, death, origin, radius or RADIUS) or nil
    if objects then
        clip.gibs = clip.gibs or {}
        for _, row in ipairs(objects) do clip.gibs[#clip.gibs + 1] = row end
    end
    breathe("cut.events")
    return clip
end

-- Packs a sequence ({..., instances = {{..., clip = clip}, ...}}) into the wire blob, a unit at a time:
--     "ZCM1" <len>,<len>,...;" <stream> <stream> ...
-- The JSON text is built actor by actor and ragdoll frames RAG_BATCH at a time, then compressed as independent streams
-- of at most TEXT_MAX bytes (util.Compress costs ~0.17 ms per KB on US1). The client unpacks each stream and joins
-- the text (V.Unpack, cl_viewer.lua); a blob without the "ZCM1" mark is a single stream, as clips stored before this were.
local function splice(text, mark, with, field)
    -- Match the owned field, not a user's Steam name that happens to equal a marker.
    local first = assert(string.find(text, '"' .. field .. '"%s*:%s*"' .. mark .. '"'), "missing packed field")
    local from, to = string.find(text, '"' .. mark .. '"', first, true)
    return string.sub(text, 1, from - 1) .. with .. string.sub(text, to + 1)
end
-- P7 (killcam_revitalize, 2026-09-24): every splice of one text in ONE pass. splice() rebuilds the whole text per
-- marker, so joining N clips into the skeleton copied the growing text N times over: pack.join measured 149 ms max and
-- 4.2 ms average on US1. Each marker is found in the ORIGINAL text with splice()'s own two searches, then the pieces
-- are concatenated once. Byte-identical to calling splice() for each in turn: the inserted texts cannot contain an
-- unescaped '"field":"@MARK@"' (rows are numbers; names are JSON-escaped, so their quotes are \"), so every search
-- lands where the sequential one did. test_pack_parity.py compares the two on real sequences.
-- `list` is flat: mark, with, field, mark, with, field, ...
local function spliceAll(text, list)
    local cuts = {}
    for i = 1, #list, 3 do
        local mark = list[i]
        local first = assert(string.find(text, '"' .. list[i + 2] .. '"%s*:%s*"' .. mark .. '"'), "missing packed field")
        local from, to = string.find(text, '"' .. mark .. '"', first, true)
        cuts[#cuts + 1] = {from, to, list[i + 1]}
    end
    table.sort(cuts, function(a, b) return a[1] < b[1] end)
    local out, at = {}, 1
    for _, c in ipairs(cuts) do
        assert(c[1] >= at, "overlapping packed fields")
        out[#out + 1] = string.sub(text, at, c[1] - 1)
        out[#out + 1] = c[3]
        at = c[2] + 1
    end
    out[#out + 1] = string.sub(text, at)
    return table.concat(out)
end
local function packGoreRows(rows, size, breathe, label)
    local parts = {}
    for first = 1, #rows, size do
        local batch = {}
        for i = first, math.min(first + size - 1, #rows) do batch[#batch + 1] = rows[i] end
        parts[#parts + 1] = string.sub(util.TableToJSON(batch), 2, -2)
        breathe(label)
    end
    return "[" .. table.concat(parts, ",") .. "]"
end
-- P1: `s`/`anim`/`hands` are plain arrays of plain arrays of already-rounded Lua numbers (K.Cut's `round()`) - no
-- strings, no nested objects, no holes. util.TableToJSON on the WHOLE actor (rows and all) was 25-40% of a cut's
-- cost, measured on US1. table.concat's default number->string ("%.14g", the same rule util.TableToJSON's own
-- codec uses for a whole-valued float - see work/killcam/lua_json_stub.lua) renders an integer identically to
-- what the general encoder would, so building the JSON text by hand and splicing it in (the same trick already
-- used for ragdoll frames just below) is wire-identical but skips the general encoder's per-value walk entirely.
-- test_clips_pack_parity.py compares this against the old whole-table encode on real clip shapes.
local function rowsJSON(rows)
    local n = #rows
    if n == 0 then return "[]" end
    -- P1 (2026-09-26): was one throwaway string per row (`"[" .. table.concat(rows[i], ",") .. "]"`) plus a
    -- `parts` table sized to the row count, joined again at the end - N+1 allocations of the two. Now the whole
    -- row array is flattened straight into ROWSBUF (file scope, reused) and joined ONCE. table.concat's own
    -- number->string rule stringifies a value in ROWSBUF exactly as it would inside a row's own table, so the
    -- text is unchanged - test_pack_parity.py/test_clips.py prove it byte for byte.
    local bi = 1
    ROWSBUF[1] = "["
    for i = 1, n do
        local row = rows[i]
        if i > 1 then bi = bi + 1 ROWSBUF[bi] = "," end
        bi = bi + 1 ROWSBUF[bi] = "["
        local rn = #row
        for f = 1, rn do
            if f > 1 then bi = bi + 1 ROWSBUF[bi] = "," end
            bi = bi + 1 ROWSBUF[bi] = row[f]
        end
        bi = bi + 1 ROWSBUF[bi] = "]"
    end
    bi = bi + 1 ROWSBUF[bi] = "]"
    return table.concat(ROWSBUF, "", 1, bi)
end
function K.PackSequence(seq, breathe)
    breathe = breathe or function() end
    local skeleton, clips, soundText, gibText = {}, {}, {}, {}
    for k, v in pairs(seq) do skeleton[k] = v end
    skeleton.instances = {}
    for n, inst in ipairs(seq.instances) do
        local list = {}
        for i, actor in ipairs(inst.clip.actors) do
            local frames = actor.rag and actor.rag.f
            local text = util.TableToJSON({name = actor.name, steam = actor.steam, role = actor.role, m = actor.m, sk = actor.sk, bg = actor.bg, col = actor.col,
                sm = actor.sm, ac = actor.ac, gore = actor.gore and "@G@" or nil,
                att = actor.att, lag = actor.lag, rest = actor.rest, zoom = actor.zoom, s = "@S@", anim = "@AN@", hands = actor.hands and "@H@" or nil,
                rag = frames and {m = actor.rag.m, n = actor.rag.n, f = "@F@", sk = actor.rag.sk, bg = actor.rag.bg} or nil})
            -- P7: one pass for the three row arrays (was three splice() rebuilds of the actor's text)
            local rowsList = {"@S@", rowsJSON(actor.s), "s", "@AN@", rowsJSON(actor.anim), "anim"}
            if actor.hands then rowsList[7], rowsList[8], rowsList[9] = "@H@", rowsJSON(actor.hands), "hands" end
            text = spliceAll(text, rowsList)
            breathe("pack.actor")
            if frames then
                local parts = {}
                for first = 1, #frames, RAG_BATCH do
                    local batch = {}
                    for k = first, math.min(first + RAG_BATCH - 1, #frames) do batch[#batch + 1] = frames[k] end
                    parts[#parts + 1] = string.sub(util.TableToJSON(batch), 2, -2) -- the frames, without the batch's own brackets
                    breathe("pack.frames")
                end
                text = splice(text, "@F@", "[" .. table.concat(parts, ",") .. "]", "f")
            end
            if actor.gore then
                local gore = util.TableToJSON({v = actor.gore.v, f = "@GF@"})
                gore = splice(gore, "@GF@", packGoreRows(actor.gore.f, 8, breathe, "pack.gore"), "f")
                text = splice(text, "@G@", gore, "gore")
            end
            list[i] = text
        end
        clips[n] = "[" .. table.concat(list, ",") .. "]"
        local shell, copy = {}, {}
        for k, v in pairs(inst.clip) do shell[k] = v end
        shell.actors = "@A" .. n .. "@"
        if inst.clip.gibs then
            local parts = {}
            for i, track in ipairs(inst.clip.gibs) do
                local text = util.TableToJSON({m = track.m, k = track.k, by = track.by, c = track.c, f = "@GF@"}) -- k: P8 object kind (nil for gibs); by/c: O1 thrower uid and class
                parts[i] = splice(text, "@GF@", packGoreRows(track.f, 32, breathe, "pack.gibs"), "f")
            end
            gibText[n] = "[" .. table.concat(parts, ",") .. "]"
            shell.gibs = "@GIB" .. n .. "@"
        end
        if inst.clip.sounds then
            local parts = {}
            for first = 1, #inst.clip.sounds, 32 do
                local batch = {}
                for i = first, math.min(first + 31, #inst.clip.sounds) do batch[#batch + 1] = inst.clip.sounds[i] end
                parts[#parts + 1] = string.sub(util.TableToJSON(batch), 2, -2)
                breathe("pack.sounds")
            end
            soundText[n] = "[" .. table.concat(parts, ",") .. "]"
            shell.sounds = "@S" .. n .. "@"
        end
        for k, v in pairs(inst) do copy[k] = v end
        copy.clip = shell
        skeleton.instances[n] = copy
        breathe("pack.join")
    end
    local text = util.TableToJSON(skeleton)
    breathe("pack.skeleton")
    -- P7: every clip's actors, sounds and gibs spliced into the skeleton in one pass (was one rebuild per marker)
    local joinList = {}
    for n, actors in ipairs(clips) do
        joinList[#joinList + 1], joinList[#joinList + 2], joinList[#joinList + 3] = "@A" .. n .. "@", actors, "actors"
        if soundText[n] then joinList[#joinList + 1], joinList[#joinList + 2], joinList[#joinList + 3] = "@S" .. n .. "@", soundText[n], "sounds" end
        if gibText[n] then joinList[#joinList + 1], joinList[#joinList + 2], joinList[#joinList + 3] = "@GIB" .. n .. "@", gibText[n], "gibs" end
    end
    text = spliceAll(text, joinList)
    breathe("pack.join")
    local streams, sizes = {}, {}
    for at = 1, #text, TEXT_MAX do
        local stream = util.Compress(string.sub(text, at, at + TEXT_MAX - 1)) or error("compress failed")
        streams[#streams + 1], sizes[#sizes + 1] = stream, #stream
        breathe("pack.compress")
    end
    return "ZCM1" .. table.concat(sizes, ",") .. ";" .. table.concat(streams)
end

local function readIndex(id)
    return util.JSONToTable(file.Read(ROOT .. "/index/" .. id .. ".json", "DATA") or "") or {}
end
function K.Index(id) return readIndex(id) end
local function addRecord(id, entry)
    local list = readIndex(id)
    table.insert(list, 1, entry)
    while #list > KEEP do table.remove(list) end
    file.Write(ROOT .. "/index/" .. id .. ".json", util.TableToJSON(list))
end

-- The global list behind the admin "All" tab and the operator "Submitted" tab: newest first, names only.
local ALL, ALL_KEEP = ROOT .. "/index/_all.json", 300
function K.AllIndex()
    local list = util.JSONToTable(file.Read(ALL, "DATA") or "")
    if list then return list end
    -- First use: rebuild from the per-player records so clips cut before this list existed still show.
    list = {}
    local seen = {}
    for _, name in ipairs(file.Find(ROOT .. "/index/*.json", "DATA")) do
        if name ~= "_all.json" then
            for _, e in ipairs(util.JSONToTable(file.Read(ROOT .. "/index/" .. name, "DATA") or "") or {}) do
                if e.clip and not seen[e.clip] then
                    seen[e.clip] = true
                    list[#list + 1] = {clip = e.clip, t = e.t, map = e.map, tag = e.tag,
                        killer = e.role == "killer" and "?" or e.other, victim = e.role == "killer" and e.other or "?"}
                end
            end
        end
    end
    table.sort(list, function(a, b) return (a.t or 0) > (b.t or 0) end)
    file.Write(ALL, util.TableToJSON(list))
    return list
end

local serial = 0
function K.Store(clip, tag, victim, killer, packed)
    -- `serial` restarts when this file is hot-reloaded, so an id is only used once it is known to be free.
    local id
    repeat
        serial = serial + 1
        id = os.time() .. "_" .. serial
    until not file.Exists(ROOT .. "/clips/" .. id .. ".dat", "DATA")
    packed = packed or util.Compress(util.TableToJSON(clip))
    if not packed then return end
    file.Write(ROOT .. "/clips/" .. id .. ".dat", packed)
    stats.clips, stats.bytes = stats.clips + 1, stats.bytes + #packed
    local function entry(me, other) return {clip = id, t = clip.t, map = clip.map, tag = tag, role = me.role, other = other.name, reported = false} end
    -- Owner rule: innocent kills traitor -> the traitor's record only. Innocent kills innocent -> both.
    local all = K.AllIndex()
    table.insert(all, 1, {clip = id, t = clip.t, map = clip.map, tag = tag, killer = killer.name, victim = victim.name})
    while #all > ALL_KEEP do table.remove(all) end
    file.Write(ALL, util.TableToJSON(all))
    if victim.id then addRecord(victim.id, entry(victim, killer)) end
    if tag == "ivi" and killer.id then addRecord(killer.id, entry(killer, victim)) end
    return id, #packed
end

local function stage(name, began)
    local cost = SysTime() - began
    if cost > stats[name] then stats[name] = cost end
    if cost > stats.cutMax then stats.cutMax = cost end
end
local function guarded(what, fn)
    local ok, result = pcall(fn)
    if not ok then ErrorNoHalt("[Killcam] clip " .. what .. " failed: " .. tostring(result) .. "\n") return end
    return result
end

-- `killer` is the recorder's cached identity table, so a killer who already left still counts.
-- Superseded 2026-09-21 by the life sequence (sv_life.lua): per-kill clips are off unless this is set to 1.
local autoclips = CreateConVar("zc_killcam_autoclips", "0", FCVAR_ARCHIVE, "Also save the older one-clip-per-qualifying-kill records")
hook.Add("ZCKillcam_Death", "ZCKillcam.Cut", function(victim, killer, tag)
    if not autoclips:GetBool() or not tag or not killer or not K.TraitorRound() then return end
    local death, origin = CurTime(), victim:GetPos()
    local mode = CurrentRound().name
    local v = identity(victim, "victim")
    local k = {slot = killer.slot, uid = killer.uid, id = killer.id, name = killer.name, steam = killer.steam, role = "killer", traitor = killer.traitor}
    local parties = {[v.slot] = v, [k.slot] = k}
    -- The ring keeps moving, so rows are gathered once the aftermath is in it; encoding and
    -- compression then get a tick each (one combined cut measured 34.8 ms on US1).
    timer.Simple(K.Post + 0.2, function()
        local began = SysTime()
        local clip = guarded("gather", function()
            -- Everyone who damaged the victim inside the window is a named party, not a bystander.
            K.EachEvent(death - K.Pre, death + K.Post, function(_, kind, a, b, _, _, _, _, uid)
                local who = K.Identity(a)
                if kind == K.Kinds.hit and b == v.slot and not parties[a] and who and who.uid == uid then
                    parties[a] = {slot = a, uid = uid, name = who.name, steam = who.steam, role = "attacker"}
                end
            end)
            return K.Cut(death, origin, parties, mode, tag)
        end)
        stage("gather", began)
        if not clip then return end
        timer.Simple(0, function()
            local t = SysTime()
            local json = guarded("encode", function() return util.TableToJSON(clip) end)
            stage("json", t)
            if not json then return end
            timer.Simple(0, function()
                local t2 = SysTime()
                local packed = guarded("pack", function() return util.Compress(json) end)
                stage("pack", t2)
                if packed then guarded("store", function() K.Store(clip, tag, v, k, packed) return true end) end
            end)
        end)
    end)
end)

-- Age sweep, once per map load: clips older than 14 days go unless a report pinned them.
function K.Sweep(now)
    local pinned = util.JSONToTable(file.Read(ROOT .. "/pinned.json", "DATA") or "") or {}
    local removed, lapsed = 0, false
    for id, till in pairs(pinned) do -- a report pins for 45 days, then the clip ages out like any other
        if isnumber(till) and till < now then pinned[id] = nil lapsed = true end
    end
    if lapsed then file.Write(ROOT .. "/pinned.json", util.TableToJSON(pinned)) end
    -- UI cohesion U2 (sharing): a clip on a live CityLeak post (up to K.SharePostKeep after posting) or behind a live chat
    -- link (K.ShareLinkKeep after copying) is kept like a pinned one (sv_net.lua K.SharedSet; never raises).
    local shared = isfunction(K.SharedSet) and K.SharedSet(now) or {}
    for _, name in ipairs(file.Find(ROOT .. "/clips/*.dat", "DATA")) do
        local id = string.sub(name, 1, -5)
        local born = tonumber(string.match(id, "^(%d+)_")) or now
        if now - born > MAX_AGE and not pinned[id] and not shared[id] then file.Delete(ROOT .. "/clips/" .. name) file.Delete(ROOT .. "/clips/" .. id .. ".meta.json") removed = removed + 1 end
    end
    -- Global cap: oldest unpinned clips go first. Map load only, never mid-round.
    local files, total = {}, 0
    for _, name in ipairs(file.Find(ROOT .. "/clips/*.dat", "DATA")) do
        local size = file.Size(ROOT .. "/clips/" .. name, "DATA") or 0
        total = total + size
        files[#files + 1] = {name = name, size = size, born = tonumber(string.match(name, "^(%d+)_")) or now}
    end
    table.sort(files, function(a, b) return a.born < b.born end)
    for _, f in ipairs(files) do
        if total <= (K.MaxBytes or MAX_BYTES) then break end
        if not pinned[string.sub(f.name, 1, -5)] and not shared[string.sub(f.name, 1, -5)] then file.Delete(ROOT .. "/clips/" .. f.name) file.Delete(ROOT .. "/clips/" .. string.sub(f.name, 1, -5) .. ".meta.json") total = total - f.size removed = removed + 1 end
    end
    return removed
end
hook.Add("InitPostEntity", "ZCKillcam.Sweep", function() K.Sweep(os.time()) end)

concommand.Add("zc_killcam_clips", function(p)
    if IsValid(p) and not p:IsAdmin() then return end
    local line = string.format("[Killcam] clips=%d bytes=%d avgKB=%.1f cutMax=%.2fms gather=%.2f json=%.2f pack=%.2f onDisk=%d traitorRound=%s",
        stats.clips, stats.bytes, stats.clips > 0 and stats.bytes / stats.clips / 1024 or 0, stats.cutMax * 1000, stats.gather * 1000, stats.json * 1000, stats.pack * 1000,
        #file.Find(ROOT .. "/clips/*.dat", "DATA"), tostring(K.TraitorRound()))
    if IsValid(p) then p:PrintMessage(HUD_PRINTCONSOLE, line) else print(line) end
end)
