return string.sub([========[x            add(true, string.format("velocity: recorded, %.0f u/s (%.0f, %.0f, %.0f)", math.sqrt(vx * vx + vy * vy), vx, vy, vz))
            local wearing = IsValid(ghost) and ghost:GetModel() or "?"
            local same = actor.m ~= nil and wearing == actor.m
            add(true, string.format("sequence: %s%s", seq and ("recorded " .. seq .. string.format(" at cycle %.2f", cyc or 0)) or "not recorded for this frame",
                same and " (applied: the ghost wears the recorded model)" or " (NOT applied: ghost is " .. tostring(wearing) .. ", clip says " .. tostring(actor.m) .. " - guessing from speed instead)"))
            local np = IsValid(ghost) and ghost.zcPoseN or 0
            local total = IsValid(ghost) and ghost:GetNumPoseParameters() or 0
            add(np > 0 or not same, string.format("pose parameters: %d of the model's %d driven from the recording%s", np, total,
                np == 0 and same and " - the clip carried none, so six of them are unset and the torso will not twist" or ""))
            -- The feet/aim split is the single most likely thing to be visibly wrong, and it is one number.
            local where = IsValid(ghost) and ghost.zcPoseWhere
            local ay = where and where.aim_yaw and IsValid(ghost) and ghost.zcPose and ghost.zcPose[where.aim_yaw]
            if ay then
                local mode = V.FeetCV and V.FeetCV:GetInt() or 1
                add(true, string.format("feet vs aim: aim_yaw %.1f deg, zc_killcam_feet %d -> legs drawn at aim %s %.1f. If the legs look BACKWARDS, set zc_killcam_feet %d",
                    ay, mode, mode == 0 and "+ 0 (split off)" or (mode < 0 and "+" or "-"), mode == 0 and 0 or math.abs(ay), mode == 1 and -1 or 1))
            elseif same then
                add(true, "feet vs aim: no aim_yaw on this model, so the body follows the aim exactly (as it did before)")
            end
        end
    end
    return out
end

concommand.Add("zc_killcam_selfcheck", function()
    local ok, res = pcall(checkLines)
    if not ok then return MsgN("[Killcam] self check failed: " .. tostring(res)) end
    MsgN("[Killcam] self check")
    for _, line in ipairs(res) do MsgN(line) end
end)

end

do -- ===== zc_killcam/cl_tape.lua =====
-- Z-City killcam, round tape step 2: the CLIENT decoder. Turns one chunk of tape.dat back into players, ragdolls,
-- events and tracks - the same numbers `work/killcam/tape_reader.py` reads offline, which is the reference this file
-- is tested against chunk by chunk on real pulled rounds.
--
-- A chunk is "ZCT1\n" <header json> "\n" <payload>. The header lists GROUPS (each one util.Compress stream, ~2.6 KB of
-- text) and PIECES (one slot's sample rows, or ragdoll frames, or events, or one tape-owned track) that say where they
-- sit inside their inflated group. Rows are delta-coded against the row before them by the piece's stride, so a piece
-- - and therefore a chunk - stands alone: seeking needs ONE chunk and nothing before it.
--
-- NOTHING HERE RUNS IN ONE FRAME. A chunk is 5-130 groups and tens of thousands of numbers; `job:Step()` does one unit
-- (inflate one group, or decode one piece) and the caller spends as many as its frame budget allows. Call it from a
-- Think/paint path, never in a loop that must finish.
--
-- The header is the authority on shape: `row` (numbers per sample row), `evrow`, `ang` (angle scale), `strides` per
-- track, `delta`. A tape recorded before a widening still reads, because every chunk declares its own.
if not CLIENT then return end
local V = ZCKillcamView or {}
ZCKillcamView = V
V.Tape = V.Tape or {}
local T = V.Tape
T.Version = "20260921.dec1"

local MARK = "ZCT1\n"

-- Pieces were named objects up to tape v3 and are arrays from v4 ({k, slot, uid, rows, g, a, n, bones, model}), which
-- is most of what the header weighs. A JSON null model simply leaves the last slot empty.
local function piece(p)
    if p[1] == nil then return p end -- v<=3: already the named form
    return {k = p[1], slot = p[2], uid = p[3], rows = p[4], frames = p[4], g = p[5], a = p[6], n = p[7], bones = p[8], m = p[9]}
end

-- Numbers per row for a piece, exactly as tape_reader picks it: samples and events from the header, tracks from the
-- stride table, ragdoll frames from their own bone count.
local function widthOf(head, strides, m)
    if m.k == "p" then return head.row end
    if m.k == "e" then return head.evrow end
    return strides[m.k] or (1 + (m.bones or 0) * 6)
end

-- "12,-3,0,..." -> a flat array. The one hot loop in the file: a chunk is tens of thousands of numbers.
local function numbers(raw)
    local out, n = {}, 0
    if raw == nil or raw == "" then return out, 0 end
    for s in string.gmatch(raw, "[^,]+") do
        n = n + 1
        out[n] = tonumber(s)
    end
    return out, n
end

-- Every row after the first holds the CHANGE from the row before it, by the piece's own stride.
local function undelta(nums, n, w)
    for i = w + 1, n do nums[i] = nums[i] + nums[i - w] end
end

local function rowsOf(nums, n, w)
    local rows, k = {}, 0
    for at = 1, n, w do
        local row = {}
        for i = 1, w do row[i] = nums[at + i - 1] end
        k = k + 1
        rows[k] = row
    end
    return rows, k
end

----------------------------------------------------------------- one chunk, one unit at a time
-- job.out is filled as it goes and is complete once Step() returns false. job.bad collects anything that did not add
-- up; a chunk with a bad piece still yields every other piece, because half a round is worth more than none.
local Job = {}
Job.__index = Job

function T.Chunk(blob)
    -- out exists from the start, even for a chunk that turns out to be rubbish: a caller never has to nil-check it
    local job = setmetatable({at = 0, bad = {}, out = {players = {}, rags = {}, events = {}, tracks = {}}}, Job)
    if type(blob) ~= "string" or string.sub(blob, 1, 5) ~= MARK then
        job.bad[1] = "not a tape chunk"
        job.done = true
        return job
    end
    local cut = string.find(blob, "\n", 6, true)
    local head = cut and util.JSONToTable(string.sub(blob, 6, cut - 1))
    if not head or not head.pieces then
        job.bad[1] = "unreadable chunk header"
        job.done = true
        return job
    end
    local strides = {}
    for k, v in pairs(head.strides or {}) do strides[k] = v end
    if head.segrow then strides.s = head.segrow end
    local pieces = {}
    for i = 1, #head.pieces do pieces[i] = piece(head.pieces[i]) end
    head.pieces = pieces

    job.head, job.strides, job.payload = head, strides, string.sub(blob, cut + 1)
    job.groups = head.groups or {}
    job.inflated = {}
    job.steps = #job.groups + #pieces -- one per group, then one per piece
    job.out.head = head
    return job
end

function Job:Progress()
    if self.done then return 1 end
    return self.steps > 0 and self.at / self.steps or 1
end

local function inflateGroup(job, i)
    local g = job.groups[i]
    local text = g and util.Decompress(string.sub(job.payload, g.off + 1, g.off + g.len))
    if not text then
        job.bad[#job.bad + 1] = "group " .. i .. " would not inflate"
    elseif g.raw and #text ~= g.raw then
        job.bad[#job.bad + 1] = "group " .. i .. " inflated to " .. #text .. ", not " .. g.raw
        job.inflated[i] = text
    else
        job.inflated[i] = text
    end
end

local function decodePiece(job, m)
    local head, out = job.head, job.out
    local raw
    if head.v and head.v >= 2 then
        local text = job.inflated[m.g]
        if not text then return end -- its group never inflated; already reported
        raw = string.sub(text, m.a + 1, m.a + m.n)
    else -- tape1: one stream per piece
        raw = util.Decompress(string.sub(job.payload, m.off + 1, m.off + m.len))
        if not raw then job.bad[#job.bad + 1] = "piece would not inflate" return end
    end
    local w = widthOf(head, job.strides, m)
    if not w or w < 1 then job.bad[#job.bad + 1] = "no width for track '" .. tostring(m.k) .. "'" return end
    local nums, n = numbers(raw)
    if head.delta then undelta(nums, n, w) end
    local want = (m.k == "r" and m.frames or m.rows) * w
    if n ~= want then
        job.bad[#job.bad + 1] = string.format("%s piece for slot %s is %d numbers, not %d", tostring(m.k), tostring(m.slot), n, want)
        return
    end
    local rows, count = rowsOf(nums, n, w)
    if m.k == "p" then
        local p = out.players[m.slot]
        if not p then p = {uid = m.uid, rows = {}} out.players[m.slot] = p end
        local into = p.rows
        local base = #into
        for i = 1, count do into[base + i] = rows[i] end
    elseif m.k == "r" then
        local list = out.rags[m.slot]
        if not list then list = {} out.rags[m.slot] = list end
        list[#list + 1] = {uid = m.uid, bones = m.bones, model = m.m, frames = rows}
    elseif m.k == "e" then
        local into = out.events
        local base = #into
        for i = 1, count do
            local row = rows[i]
            if row[2] == 4 and row[10] and row[10] > 0 and row[10] <= 10000 then
                row.swing = {v = 1, duration = row[10] / 1000}
            end
            into[base + i] = row
        end
    else
        local into = out.tracks[m.k]
        if not into then into = {} out.tracks[m.k] = into end
        local base = #into
        for i = 1, count do into[base + i] = rows[i] end
    end
end

-- One unit of work. Returns true while there is more to do.
function Job:Step()
    if self.done then return false end
    self.at = self.at + 1
    local groups = #self.groups
    if self.at <= groups then
        inflateGroup(self, self.at)
    else
        decodePiece(self, self.head.pieces[self.at - groups])
    end
    if self.at >= self.steps then
        self.out.segs = self.out.tracks.s
        self.done = true
        return false
    end
    return true
end

-- For tests and for anything that may block (never call it on a frame that must draw).
function Job:Finish()
    local more = true
    while more do more = self:Step() end
    return self.out, self.bad
end

function T.Decode(blob)
    return T.Chunk(blob):Finish()
end

----------------------------------------------------------------- reading the decoded chunk
-- The index's `t0` is centiseconds from the round start; a row's own first column is centiseconds from the chunk.
-- Everything a viewer asks for is "where was this player at time t", so that is the one accessor worth having here.
function T.RowAt(rows, cs)
    if not rows or #rows == 0 then return nil end
    local prev = rows[1]
    if cs <= prev[1] then return prev, prev, 0 end
    for i = 2, #rows do
        local row = rows[i]
        if row[1] >= cs then
            local span = row[1] - prev[1]
            return prev, row, span > 0 and (cs - prev[1]) / span or 0
        end
        prev = row
    end
    return rows[#rows], rows[#rows], 0
end

----------------------------------------------------------------- the round, as staff read it
-- The server serves "tape:<round>:index" as one JSON object per line, already filtered to what an operator is
-- allowed to see (sv_tapeserve K.TapeForOperator strips the SteamID off a who mark for non-admins). The whole
-- serving path - permission, paging, refusal - already existed and is tested; what was missing was anything on the
-- client that ASKED for it or could read the answer, so a round tape was write-only in practice.
--
-- This is the smallest thing that makes the round replay usable: not a scrub bar, but the question staff actually
-- have - "what happened in this round" - answered without watching it. Every death in order, names resolved from
-- the roster marks, with the classifier's own tag. From there the round id and the time point at the moment worth
-- opening properly.
function T.Lines(raw)
    local out = {}
    for line in string.gmatch(raw or "", "[^\r\n]+") do
        local t = util.JSONToTable(line)
        if istable(t) and t.k then out[#out + 1] = t end
    end
    return out
end

-- Tape times are centiseconds from the start of the round, so they read as round time, not wall clock.
function T.Clock(cs)
    local s = math.floor((tonumber(cs) or 0) / 100)
    return string.format("%d:%02d", math.floor(s / 60), s % 60)
end

-- Returns the printable lines, and the counts behind them so a caller can say "nothing happened" honestly rather
-- than showing an empty list that looks like a failure.
function T.Summary(raw)
    local rows, names, deaths = T.Lines(raw), {}, {}
    for _, t in ipairs(rows) do
        if t.k == "who" and t.uid then
            names[t.uid] = t.name or ("#" .. tostring(t.uid))
        elseif t.k == "death" then
            deaths[#deaths + 1] = t
        end
    end
    local function who(uid)
        if uid == nil then return "?" end
        return names[uid] or ("#" .. tostring(uid))
    end
    local out = {}
    for _, d in ipairs(deaths) do
        -- A death with no attacker is the world: a fall, a fire, bleeding out. Saying "? killed" of it would be a lie.
        out[#out + 1] = d.a and string.format("  %s  %s killed %s%s", T.Clock(d.t), who(d.a), who(d.v),
            (d.tag and d.tag ~= "") and ("   [" .. d.tag .. "]") or "")
            or string.format("  %s  %s died", T.Clock(d.t), who(d.v))
    end
    return out, #rows, #deaths
end

-- Who got hurt, and how badly. A dmg mark names the VICTIM by uid but the attacker only by entity CLASS
-- (sv_tape's mark carries `by` as a class string, not a uid), so "damage DEALT" cannot be attributed from the
-- index without inventing it - and this is a moderation tool, so it is not invented. What the index can answer
-- honestly is who took damage, how much, over how many hits, and how much of it they did to themselves; with the
-- death list that is usually enough to see the shape of a round before deciding to watch it.
function T.Hurt(raw)
    local rows, names, hurt, order = T.Lines(raw), {}, {}, {}
    for _, t in ipairs(rows) do
        if t.k == "who" and t.uid then
            names[t.uid] = t.name or ("#" .. tostring(t.uid))
        elseif t.k == "dmg" and t.uid then
            local h = hurt[t.uid]
            if not h then h = {dmg = 0, hits = 0, own = 0} hurt[t.uid] = h order[#order + 1] = t.uid end
            local amount = tonumber(t.dmg) or 0
            h.dmg = h.dmg + amount
            h.hits = h.hits + (tonumber(t.n) or 1)
            if t.self then h.own = h.own + amount end
        end
    end
    -- Worst hurt first: the question is "who was in the thick of it", not "who joined first".
    table.sort(order, function(a, b)
        if hurt[a].dmg == hurt[b].dmg then return a < b end -- stable enough to be worth pinning in a test
        return hurt[a].dmg > hurt[b].dmg
    end)
    local out = {}
    for _, uid in ipairs(order) do
        local h = hurt[uid]
        out[#out + 1] = string.format("  %-20s %5.0f damage over %d hit(s)%s", names[uid] or ("#" .. tostring(uid)),
            h.dmg, h.hits, h.own > 0 and string.format("   (%.0f self-inflicted)", h.own) or "")
    end
    return out
end

----------------------------------------------------------------- feeding the existing viewer
-- The top-down viewer, its timeline, its scrubbing and its seek already exist in cl_viewer.lua and are driven off
-- CLIP actors through V.StateAt. Tape rows carry the same columns in the same order - cs, x, y, z, yaw, pitch,
-- flags, wep, hp, eye height, then the first-person eye offset in tenths at [11..13] - with two differences:
--  * the tape keeps view angles in hundredths of a degree in [5] and [6] (the chunk head's `ang`), while a clip splits
--    each into WHOLE degrees in [5]/[6] and the hundredths remainder in [14]/[15], which is what V.StateAt adds back;
--  * the body-state block sits at [14..] on a tape (velocity, sequence, cycle, a pose COUNT, then the pose values)
--    because a tape row is a fixed stride and a clip row is not, so the clip can end early where the tape pads.
--    On a clip that block starts at [16], after the two remainders.
--
-- So a round tape can drive the existing viewer through an angle re-encode and a shuffle, and nothing else. Every
-- value is passed through untouched, deliberately: the moment this starts "helpfully" adjusting positions it stops
-- being a record of what happened. A row from an older, narrower tape simply has nil where the new columns would be,
-- and the viewer falls back to what it did before.
--
-- The split truncates TOWARD ZERO so whole and remainder always carry the same sign and
-- `whole + remainder / 100` reconstructs the original hundredths exactly, negatives included.
local function split(hundredths)
    local whole = hundredths / 100
    whole = whole >= 0 and math.floor(whole) or -math.floor(-whole)
    return whole, hundredths - whole * 100
end

function T.ToClipRows(rows)
    local out, anim, hands = {}, {}, {}
    for i = 1, #rows do
        local r = rows[i]
        local yaw, yawRem = split(r[5] or 0)
        local pitch, pitchRem = split(r[6] or 0)
        local row = {r[1], r[2], r[3], r[4], yaw, pitch, r[7], r[8], r[9], r[10], r[11], r[12], r[13], yawRem, pitchRem}
        if r[14] ~= nil then
            row[16], row[17], row[18], row[19], row[20] = r[14], r[15], r[16], r[17], r[18]
            -- [19] on the tape is how many pose values follow; a clip row just stops after the last real one, so a
            -- count of zero leaves the row 20 wide and V.PoseAt reads nothing rather than reading ten padded zeroes
            -- as a genuine pose.
            for k = 1, (r[19] or 0) do row[20 + k] = r[19 + k] or 0 end
        end
        out[i] = row
        if r[30] ~= nil and r[31] ~= nil then anim[#anim + 1] = {r[1], r[30], r[31]} end
        if r[38] ~= nil then hands[#hands + 1] = {r[1], r[32], r[33], r[34], r[35], r[36], r[37], r[38]} end
    end
    return out, #anim > 0 and anim or nil, #hands > 0 and hands or nil
end

-- Which chunk holds a moment. The index carries one `chunk` mark per chunk with `seq` and the `t0`/`t1` it spans,
-- in centiseconds from the start of the round (sv_tape.lua), and a chunk stands alone - seeking needs ONE chunk and
-- nothing before it - so picking is the whole of "seek" on the transport side.
--
-- Returns the seq, its t0 and its t1. A time before the first chunk or after the last clamps to the nearest rather
-- than answering nothing: a staff member typing a round time slightly past the end should get the end of the round,
-- not silence. Returns nil only when the index describes no chunks at all.
function T.PickChunk(raw, cs)
    local best, bestGap
    for _, t in ipairs(T.Lines(raw)) do
        if t.k == "chunk" and t.seq and t.t0 and t.t1 then
            local gap = 0
            if cs < t.t0 then gap = t.t0 - cs elseif cs > t.t1 then gap = cs - t.t1 end
            -- Ties go to the earlier chunk: on a boundary the moment belongs to the chunk it starts in.
            if bestGap == nil or gap < bestGap or (gap == bestGap and t.seq < best.seq) then
                best, bestGap = t, gap
            end
        end
    end
    if not best then return nil end
    return best.seq, best.t0, best.t1
end

-- What the round covers, for the staff view: how many chunks and the span they add up to.
function T.Span(raw)
    local n, first, last = 0, nil, nil
    for _, t in ipairs(T.Lines(raw)) do
        if t.k == "chunk" and t.t0 and t.t1 then
            n = n + 1
            if first == nil or t.t0 < first then first = t.t0 end
            if last == nil or t.t1 > last then last = t.t1 end
        end
    end
    return n, first, last
end

-- A round time as staff would type it: "2:14", or plain seconds. Centiseconds out, to match everything else.
-- Returns nil on anything it does not understand rather than guessing a moment.
function T.ParseTime(text)
    text = tostring(text or "")
    local m, s = string.match(text, "^(%d+):(%d+)$")
    if m then return (tonumber(m) * 60 + tonumber(s)) * 100 end
    local n = string.match(text, "^%d+%.?%d*$") and tonumber(text)
    return n and math.floor(n * 100 + 0.5) or nil
end

-- Where everybody was, at one moment inside a DECODED chunk. `cs` is relative to the chunk, not the round: the
-- index's t0 is from the round start but a row's own first column is from the chunk (see T.RowAt), so the caller
-- subtracts the chunk's t0. Interpolates between the two bracketing rows, exactly as the replay does.
function T.At(out, cs)
    local list = {}
    for slot, p in pairs((out and out.players) or {}) do
        local a, b, f = T.RowAt(p.rows, cs)
        if a then
            b, f = b or a, f or 0
            list[#list + 1] = {slot = slot, uid = p.uid, hp = a[9],
                x = a[2] + (b[2] - a[2]) * f, y = a[3] + (b[3] - a[3]) * f, z = a[4] + (b[4] - a[4]) * f}
        end
    end
    table.sort(list, function(m, n) return m.slot < n.slot end) -- stable output: a moving list is unreadable
    return list
end

-- The moment, as lines. Pure on purpose: the subtraction below is the one place a seek can silently land in the
-- wrong part of a round, and while it sat inline in a Think hook nothing could test it. Row times inside a chunk
-- are relative to the CHUNK; the index's times are relative to the ROUND; so the chunk's own start comes off first.
-- Getting this wrong does not error - it quietly reports the end of the chunk for every time you ask for.
function T.MomentLines(out, cs, chunkT0, names)
    local at = T.At(out, cs - (chunkT0 or 0))
    if #at == 0 then return {"  nobody was recorded at that moment"} end
    local lines = {}
    for i = 1, #at do
        local p = at[i]
        lines[i] = string.format("  %-20s %8.0f %8.0f %8.0f   %s hp",
            (names and names[p.uid]) or ("#" .. tostring(p.uid)), p.x, p.y, p.z, tostring(p.hp))
    end
    return lines
end

end
]========], 2)
