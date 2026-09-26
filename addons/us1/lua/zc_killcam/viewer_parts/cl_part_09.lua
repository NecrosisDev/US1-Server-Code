return string.sub([========[x
do -- ===== zc_killcam round replay viewer (replay_v1 P3) =====
-- The whole round in 3D, built from the round tape. NOT a second renderer: a ROUND MODE of the death-killcam life
-- player (cl_part_03..07). This file owns what the life player does not have: the tape transport (index, chunk
-- prefetch, budgeted decode, splice / evict), the round clip it hands the life player, the cameras, the input, the
-- HUD (mockup 17) and the entry points. The life player sees one synthetic sequence whose single clip holds every
-- participant of the round; `L.round` switches its round branches on (see DESIGN.md in replay_v1/p3_viewer).
--
-- LOCALS: the shipped bundle is one Lua chunk with 2 spare main-chunk local slots (kc.py gate measures it by
-- compiling). Everything here lives on `V.Round` (R); this block declares three locals (V, R, one sort comparator) and
-- every function hangs off R. V.Tape is created by cl_tape (earlier in the bundle) and is still looked up at call time, never hoisted.
-- PROVISIONAL(2026-09-26, the whole viewer is unseen in-engine by its author: every visual needs the owner's eyes, ratify-by: 2026-10-10)
if not CLIENT then return end
local V = ZCKillcamView
if V.Round and V.Round.Close then pcall(V.Round.Close, "reload") end -- a hot reload: the copy being replaced lets go first
local R = {}
V.Round = R
-- When this client joined, as best it can tell: the first time the bundle ran. A round whose head is later than this
-- began on the server run we are connected to, which is the only place a UserID means us (see R.ResolveMe).
V.RoundJoinedAt = V.RoundJoinedAt or os.time()

R.KEEP, R.AHEAD, R.INFLIGHT, R.ASK_AGAIN, R.ASK_GAP = 4, 2, 2, 10, 0.15
R.BUDGET, R.LINES, R.LEAD = 0.002, 40, 400
R.INDEX_WAIT = 20 -- seconds for the index before the viewer says nothing came back
-- the index kinds the viewer reads; every other line is skipped before JSON (a cheap text test, as tapeserve does)
R.KINDS = {head = true, ["end"] = true, chunk = true, who = true, wep = true, death = true, model = true, me = true}
-- the server's status codes (sv_net.lua K.Status) as the player reads them; the server sends only the number
R.REFUSED = {[1] = "You can't watch that round: only rounds you played, and only once they are over.",
    [2] = "That round is no longer on the server.", [3] = "Replays can't be opened while you are alive in a live round.",
    [4] = "The server is still sending something else; try again in a moment."}
R.Actors = CreateClientConVar("zc_replay_actors", "16", true, false, "Round replay: how many players nearest the camera are drawn (the followed one always is)", 2, 64)
R.stats = {think = {n = 0, sum = 0, max = 0}, hud = {n = 0, sum = 0, max = 0}}
R.keys, R.hits, R.hitN = {}, {}, 0

----------------------------------------------------------------- pure: the index
function R.NewIndex()
    return {chunks = {}, weapons = {}, wepSeen = {}, actors = {}, byUid = {}, deaths = {}}
end
-- One decoded index line folded into the model. Pure and order-tolerant: FinishIndex sorts what needs sorting.
function R.FoldLine(idx, t)
    local k = t.k
    if k == "head" then idx.head = t
    elseif k == "end" then
        local len = tonumber(t.len) -- SECONDS on the tape (sv_tape.lua `len = round(... * 100) / 100`)
        if len then idx.len = math.floor(len * 100 + 0.5) end
        idx.ended = tonumber(t.wall1)
    elseif k == "chunk" then
        local seq, t0, t1 = tonumber(t.seq), tonumber(t.t0), tonumber(t.t1)
        if seq and t0 and t1 then idx.chunks[#idx.chunks + 1] = {seq = seq, t0 = t0, t1 = t1} end
    elseif k == "wep" then
        local id = tonumber(t.id)
        if id and isstring(t.class) and not idx.wepSeen[id] then idx.wepSeen[id] = true idx.weapons[#idx.weapons + 1] = {id, t.class} end
    elseif k == "who" or k == "model" then
        local uid = tonumber(t.uid)
        if not uid or uid <= 0 then return end
        local a = idx.byUid[uid]
        if not a then
            a = {uid = uid, role = "player", s = {}, looks = {}, kills = {}, dies = {}}
            idx.byUid[uid] = a
            idx.actors[#idx.actors + 1] = a
        end
        if k == "who" then
            if isstring(t.name) and t.name ~= "" and not a.name then a.name = t.name end
            if isstring(t.sid) and t.sid ~= "" then a.sid = t.sid end
        end
        local prev = a.looks[#a.looks]
        local look = {t = tonumber(t.t) or 0, m = isstring(t.model) and t.model ~= "" and t.model or nil, sk = tonumber(t.skin),
            bg = istable(t.groups) and t.groups or nil, col = istable(t.colour) and t.colour or nil, n = #a.looks + 1}
        if k == "model" and prev then look.col = look.col or prev.col end -- a model mark carries model and skin only
        a.looks[#a.looks + 1] = look
    elseif k == "death" then
        local v, at = tonumber(t.v), tonumber(t.t)
        if v and at then idx.deaths[#idx.deaths + 1] = {t = at, v = v, a = tonumber(t.a), n = #idx.deaths + 1} end
    elseif k == "me" then
        idx.me = tonumber(t.uid)
    end
end
-- The line at `pos` in `raw`, and where the next one starts.
function R.NextLine(raw, pos)
    if pos > #raw then return nil, pos end
    local nl = string.find(raw, "\n", pos, true)
    local stop = nl or (#raw + 1)
    return string.sub(raw, pos, stop - 1), stop + 1
end
-- One budget unit of index parsing: up to R.LINES lines. Returns true while there is more.
function R.IndexStep(job)
    for _ = 1, R.LINES do
        local line
        line, job.pos = R.NextLine(job.raw, job.pos)
        if not line then return false end
        local kind = string.match(line, '"k"%s*:%s*"(%w+)"')
        if kind and R.KINDS[kind] then
            local t = util.JSONToTable(line)
            if istable(t) and t.k then R.FoldLine(job.idx, t) end
        end
    end
    return job.pos <= #job.raw
end
local function byT(a, b) if a.t ~= b.t then return a.t < b.t end return a.n < b.n end
-- Who "me" is. Never by name or model (a moderation tool must not guess). The UserID fallback is taken only for a round
-- that began after this client joined: a UserID is unique within one server run, and a round that started after we
-- connected cannot predate a restart. PROVISIONAL(2026-09-26, the index has no `me` line until tapeserve adds one, ratify-by: 2026-10-10)
function R.ResolveMe(idx, uid, sid, joinedAt)
    if idx.me and idx.byUid[idx.me] then return idx.me, "server" end
    if isstring(sid) and sid ~= "" and sid ~= "0" then
        for _, a in ipairs(idx.actors) do if a.sid == sid then return a.uid, "steamid" end end
    end
    local wall = idx.head and tonumber(idx.head.wall0)
    if uid and idx.byUid[uid] and wall and joinedAt and wall >= joinedAt then return uid, "session" end
    return nil, "unknown"
end
function R.Clock(cs)
    local s = math.floor((tonumber(cs) or 0) / 100)
    return string.format("%d:%02d", math.floor(s / 60), s % 60)
end
function R.NameOf(idx, uid, me)
    if uid and uid == me then return "You" end
    local a = uid and idx.byUid[uid]
    return a and a.name or (uid and ("#" .. uid) or "the world")
end
-- Everything the viewer needs once the lines are in: sorted chunks and deaths, the actors' looks and fixed indices,
-- me, bookmarks, the feed's text (built ONCE here, never per frame), the round length.
function R.FinishIndex(idx, uid, sid, joinedAt)
    table.sort(idx.chunks, function(a, b) if a.t0 ~= b.t0 then return a.t0 < b.t0 end return a.seq < b.seq end)
    table.sort(idx.deaths, byT)
    idx.seqAt = {}
    for k, c in ipairs(idx.chunks) do idx.seqAt[c.seq] = k end
    local last = idx.chunks[#idx.chunks]
    if not idx.len or idx.len <= 0 then idx.len = last and last.t1 or 0 end
    idx.index = {}
    for i, a in ipairs(idx.actors) do
        idx.index[a.uid] = i
        table.sort(a.looks, byT)
        local look = a.looks[1] or {}
        a.m, a.sk, a.bg, a.col = look.m, look.sk, look.bg, look.col
        a.name = a.name or ("#" .. a.uid)
        a.steam = a.name -- the nametag (V.ReplayNameAnchor reads .steam): the name the tape recorded
        -- PROVISIONAL(2026-09-26, nametags show who.name as tapeserve serves it to this viewer, ratify-by: 2026-10-10)
    end
    idx.me, idx.meHow = R.ResolveMe(idx, uid, sid, joinedAt)
    idx.marks = {}
    for _, d in ipairs(idx.deaths) do
        d.clock = R.Clock(d.t)
        d.text = d.a and d.a ~= d.v and (R.NameOf(idx, d.a, idx.me) .. " killed " .. R.NameOf(idx, d.v, idx.me))
            or (R.NameOf(idx, d.v, idx.me) .. " died")
        d.tip = d.clock .. "  ·  " .. d.text
        local victim, killer = idx.byUid[d.v], d.a and idx.byUid[d.a]
        if victim then victim.dies[#victim.dies + 1] = d.t end
        if killer and d.a ~= d.v then killer.kills[#killer.kills + 1] = d.t end
        local kind = (idx.me and d.v == idx.me) and "death" or ((idx.me and d.a == idx.me) and "kill" or "other")
        idx.marks[#idx.marks + 1] = {t = d.t, at = math.max(0, d.t - R.LEAD), kind = kind, d = d}
    end
    return idx
end
-- first MY death - 4 s, else first MY kill - 4 s, else the start
function R.OpensAt(marks)
    for _, b in ipairs(marks) do if b.kind == "death" then return b.at end end
    for _, b in ipairs(marks) do if b.kind == "kill" then return b.at end end
    return 0
end
-- The next (dir > 0) or previous bookmark jump from `cs`, half a second of slack either way so a press right after a
-- jump moves on. Mine only when "me" is known; every death otherwise. PROVISIONAL(2026-09-26, all deaths when me is unknown, ratify-by: 2026-10-10)
function R.StepMark(marks, cs, dir, mineOnly)
    local best
    for _, b in ipairs(marks) do
        if not mineOnly or b.kind ~= "other" then
            if dir > 0 and b.at > cs + 50 then return b.at end
            if dir < 0 and b.at < cs - 50 then best = b.at end
        end
    end
    return best
end

----------------------------------------------------------------- pure: chunks, window, prefetch, evict
-- The chunk holding `cs` (the last one starting at or before it), clamped to the ends. nil when there are none.
function R.ChunkAt(chunks, cs)
    local n = #chunks
    if n == 0 then return nil end
    if cs <= chunks[1].t0 then return 1 end
    local lo, hi = 1, n
    while lo < hi do
        local mid = math.floor((lo + hi + 1) / 2)
        if chunks[mid].t0 <= cs then lo = mid else hi = mid - 1 end
    end
    return lo
end
-- The contiguous run of READY chunks around p. A hole is never bridged: V.StateAt would glide an actor across it.
function R.Window(chunks, p)
    local c = p and chunks[p]
    if not c or c.state ~= "ready" then return nil end
    local lo, hi = p, p
    while chunks[lo - 1] and chunks[lo - 1].state == "ready" do lo = lo - 1 end
    while chunks[hi + 1] and chunks[hi + 1].state == "ready" do hi = hi + 1 end
    return lo, hi
end
-- Which chunks to ask for now: the playhead's first, then ahead, then behind; never more than R.INFLIGHT unanswered
-- (the server keeps two per viewer and drops the older), and never more than R.AHEAD ahead. A request unanswered for
-- R.ASK_AGAIN seconds was dropped by the server and may go again.
R.ORDER = {0, 1, 2, -1}
function R.Want(chunks, p, now, out)
    out = out or {}
    for i = #out, 1, -1 do out[i] = nil end
    if not p then return out end
    local inflight = 0
    for _, c in ipairs(chunks) do
        if c.state == "asked" and now - (c.askedAt or 0) < R.ASK_AGAIN then inflight = inflight + 1 end
    end
    for _, d in ipairs(R.ORDER) do
        if inflight >= R.INFLIGHT then break end
        local c = chunks[p + d]
        if c and (c.state == nil or (c.state == "asked" and now - (c.askedAt or 0) >= R.ASK_AGAIN)) then
            out[#out + 1] = p + d
            inflight = inflight + 1
        end
    end
    return out
end
-- Drops everything held for chunks more than R.KEEP from the playhead. Returns how many were dropped.
function R.Evict(chunks, p)
    local n = 0
    if not p then return 0 end
    for k, c in ipairs(chunks) do
        if c.state ~= nil and math.abs(k - p) > R.KEEP then
            c.state, c.data, c.raw, c.askedAt = nil, nil, nil, nil
            n = n + 1
        end
    end
    return n
end

----------------------------------------------------------------- pure: one decoded chunk -> round-time, clip-shaped
-- Tape events are {cs, kind, slotA, slotB, dmg x10, hitgroup, wep, los, uid, swingMs} (sv_tape.lua cutChunk); the life
-- player reads clip events {cs, kind, actorA, actorB, dmg, hitgroup, wep, los, [9..13] shot/hit point} (sv_clips.lua).
-- Slots become actors through this chunk's own sample pieces (a slot can change hands between chunks); the uid in [9]
-- names the acting player when set. [9..13] are NOT carried: a uid there would be read as a shot origin, so the
-- adapted event ends at [8] and the tracer / bullet-cam code, which needs the point, correctly draws nothing.
function R.AdaptEvents(rows, t0, slotUid, index)
    local out = {}
    for i = 1, #rows do
        local r = rows[i]
        local ua = (r[9] and r[9] > 0) and r[9] or slotUid[r[3]]
        local ub = slotUid[r[4]]
        local e = {r[1] + t0, r[2], ua and index[ua] or 0, ub and index[ub] or 0, (r[5] or 0) / 10, r[6], r[7], r[8]}
        if r.swing then e.swing = r.swing end
        e.n = i
        out[#out + 1] = e
    end
    -- shot stamps run a few cs off the server's clock and are not clamped on the tape: every reader below breaks on
    -- time, so the chunk's events are put in time order here, once
    table.sort(out, function(a, b) if a[1] ~= b[1] then return a[1] < b[1] end return a.n < b.n end)
    return out
end
-- Bullet segments {cs, shooter slot, start xyz, end xyz, surface, hit slot} -> {round cs, actor, from, to}.
function R.AdaptSegments(rows, t0, slotUid, index)
    local out = {}
    for i = 1, #(rows or {}) do
        local r = rows[i]
        local uid = slotUid[r[2]]
        out[#out + 1] = {r[1] + t0, uid and index[uid] or 0, Vector(r[3], r[4], r[5]), Vector(r[6], r[7], r[8]), n = i}
    end
    table.sort(out, function(a, b) if a[1] ~= b[1] then return a[1] < b[1] end return a.n < b.n end)
    return out
end
-- One player's sample rows -> clip rows in ROUND time (T.ToClipRows keeps the chunk's own clock; t0 is added here).
function R.AdaptRows(rows, t0)
    local s, anim, hands = V.Tape.ToClipRows(rows)
    for i = 1, #s do s[i][1] = s[i][1] + t0 end
    if anim then for i = 1, #anim do anim[i][1] = anim[i][1] + t0 end end
    if hands then for i = 1, #hands do hands[i][1] = hands[i][1] + t0 end end
    return {s = s, anim = anim, hands = hands}
end
-- A slot's ragdoll pieces -> {m, n, f} with ONE skeleton (the newest bone count; poseRagdoll places bones by index).
function R.AdaptRag(list, t0)
    local n = list[#list].bones
    local f, m = {}, nil
    for _, piece in ipairs(list) do
        if piece.bones == n then
            m = piece.model or m
            for _, fr in ipairs(piece.frames) do fr[1] = fr[1] + t0 f[#f + 1] = fr end
        end
    end
    return {m = m, n = n, f = f}
end

----------------------------------------------------------------- pure: splice (always NEW tables)
-- One uid's rows across the window, oldest first. A new table every time: cl_analysis caches weapon runs on the
-- identity of actor.s, so mutating the old array in place would serve the previous window's runs.
function R.SpliceRows(chunks, lo, hi, uid)
    local s, anim, hands = {}, nil, nil
    for k = lo, hi do
        local d = chunks[k] and chunks[k].data
        local r = d and d.rows[uid]
        if r then
            for i = 1, #r.s do s[#s + 1] = r.s[i] end
            if r.anim then anim = anim or {} for i = 1, #r.anim do anim[#anim + 1] = r.anim[i] end end
            if r.hands then hands = hands or {} for i = 1, #r.hands do hands[#hands + 1] = r.hands[i] end end
        end
    end
    return s, anim, hands
end
function R.SpliceRag(chunks, lo, hi, uid)
    local n
    for k = hi, lo, -1 do
        local d = chunks[k] and chunks[k].data
        local r = d and d.rags[uid]
        if r then n = r.n break end
    end
    if not n then return nil end
    local out = {n = n, f = {}}
    for k = lo, hi do
        local d = chunks[k] and chunks[k].data
        local r = d and d.rags[uid]
        if r and r.n == n then
            out.m = r.m or out.m
            for i = 1, #r.f do out.f[#out.f + 1] = r.f[i] end
        end
    end
    return out
end
function R.SpliceList(chunks, lo, hi, field)
    local out = {}
    for k = lo, hi do
        local d = chunks[k] and chunks[k].data
        local list = d and d[field]
        if list then for i = 1, #list do out[#out + 1] = list[i] end end
    end
    return out
end

----------------------------------------------------------------- pure: the alive rule
-- Fullscreen only while the local player is not alive in a live round (dead, spectating, or between rounds).
-- PROVISIONAL(2026-09-26, owner has not ruled on it; blueprint "Alive rule", ratify-by: 2026-10-10)
function R.AliveStep(open, alive, live)
    local blocked = alive and live
    if open then return blocked and "close" or "stay" end
    return blocked and "refuse" or "open"
end
function R.Blocked(me)
    if not IsValid(me) then return false end
    local zbT = rawget(_G, "zb")
    local live = not istable(zbT) or zbT.ROUND_STATE == nil or zbT.ROUND_STATE == 1
    return R.AliveStep(false, me:Alive(), live) == "refuse"
end

----------------------------------------------------------------- transport
function R.Ask(id)
    net.Start("zckc_clip")
    net.WriteString(id)
    net.SendToServer()
    R.lastAsk = RealTime()
end
-- Is this answer ours? Only what the open viewer (or the list) is waiting for: anything else - a staff member's own
-- zc_killcam_round, say - goes on to the original V.TapeBlob exactly as before.
function R.Claims(id)
    if string.sub(id, 1, 9) == "tape:list" then return R.listWanted == true end
    local rs = R.open
    if not rs or string.sub(id, 1, #rs.prefix) ~= rs.prefix then return false end
    local tail = string.sub(id, #rs.prefix + 1)
    if tail == "index" then return rs.idx == nil end
    local k = rs.idx and rs.idx.seqAt[tonumber(tail) or -1]
    return k ~= nil
end
function R.OnBlob(id, raw)
    if string.sub(id, 1, 9) == "tape:list" then return R.OnList(id, raw) end
    local rs = R.open
    local tail = string.sub(id, #rs.prefix + 1)
    if tail == "index" then
        rs.indexJob = {raw = raw or "", pos = 1, idx = R.NewIndex()}
        rs.status = "Reading the round…" -- the loading card's line (a state); passing notes are V.Say
        return
    end
    local c = rs.chunks[rs.idx.seqAt[tonumber(tail)]]
    if not c or c.state ~= "asked" then return end -- evicted while it travelled (the playhead moved on), or not asked yet
    c.raw, c.state = raw, "raw"
end
function V.TapeRefused(id, status)
    if not R.Claims(id) then return false end
    local text = R.REFUSED[status] or ("The server refused (" .. tostring(status) .. ").")
    if string.sub(id, 1, 9) == "tape:list" then
        R.listNote = text
        MsgN("[Replay] " .. text)
        return true
    end
    local rs = R.open
    if string.sub(id, #rs.prefix + 1) == "index" then
        R.Fail(rs, "Couldn't open this round", text, status == 4) -- 4: the server was busy; worth another try
        return true
    end
    local c = rs.chunks[rs.idx.seqAt[tonumber(string.sub(id, #rs.prefix + 1))]]
    if c and c.state == "asked" then c.state = nil end
    V.Say(text, "error") -- U4: the viewer's one note
    return true
end
-- Wrapped at call time: cl_part_03 defines V.TapeBlob and this runs after it. Hot reload rebuilds both.
R.TapeBlob0 = V.TapeBlob
function V.TapeBlob(id, raw)
    if R.Claims(id) then return R.OnBlob(id, raw) end
    if R.TapeBlob0 then return R.TapeBlob0(id, raw) end
end
-- A chunk is served byte for byte as it lies in tape.dat, "ZCT1\n..." (sv_tapeserve.lua serveChunk -> K.SendBlob), and
-- the zckc_clip receiver unpacks every blob: V.Unpack sent anything without the "ZCM1" mark to util.Decompress, which
-- answers nil for it (wiki: "nil on failure or invalid input"). Every chunk was lost before it reached V.TapeBlob -
-- the staff zc_killcam_round lookup included; its test stubs Decompress as identity, which hid it. Pass it through.
R.Unpack0 = V.Unpack
if R.Unpack0 then
    function V.Unpack(data)
        if isstring(data) and string.sub(data, 1, 5) == "ZCT1\n" then return data end
        return R.Unpack0(data)
    end
end

----------------------------------------------------------------- the work pump (2 ms a frame, one unit a step)
function R.NearestRaw(rs)
    local best, gap
    for k, c in ipairs(rs.chunks) do
        if c.state == "raw" then
            local g = math.abs(k - (rs.p or k))
            if not gap or g < gap then best, gap = k, g end
        end
    end
    return best
end
function R.ConvStep(rs)
    local cv = rs.conv
    local c = rs.chunks[cv.k]
    if c.state ~= "converting" then rs.conv = nil return end -- evicted meanwhile
    local out, idx = cv.out, rs.idx
    if not cv.slots then
        cv.slots, cv.slotUid, cv.i = {}, {}, 0
        for slot, p in pairs(out.players or {}) do
            if p.uid and p.uid > 0 then cv.slotUid[slot] = p.uid cv.slots[#cv.slots + 1] = slot end
        end
        table.sort(cv.slots)
        cv.data = {rows = {}, rags = {}}
        return
    end
    cv.i = cv.i + 1
    local slot = cv.slots[cv.i]
    if slot then
        local p = out.players[slot]
        if idx.index[p.uid] then
            local r = R.AdaptRows(p.rows, c.t0)
            cv.data.rows[p.uid] = r
            local b = rs.bounds
            for i = 1, #r.s, 8 do -- the minimap's extent, sampled
                local row = r.s[i]
                if row[2] < b[1] then b[1] = row[2] end
                if row[2] > b[3] then b[3] = row[2] end
                if row[3] < b[2] then b[2] = row[3] end
                if row[3] > b[4] then b[4] = row[3] end
            end
            local rag = out.rags and out.rags[slot]
            if rag and #rag > 0 then cv.data.rags[p.uid] = R.AdaptRag(rag, c.t0) end
        end
        return
    end
    cv.data.events = R.AdaptEvents(out.events or {}, c.t0, cv.slotUid, idx.index)
    cv.data.segs = R.AdaptSegments(out.tracks and out.tracks.s, c.t0, cv.slotUid, idx.index)
    c.data, c.state = cv.data, "ready"
    rs.conv = nil
end
function R.RebuildStep(rs)
    local rb = rs.rebuild
    local clip = rs.clip
    if not rb.i then
        rb.i = 0
        if rb.lo then
            clip.events = R.SpliceList(rs.chunks, rb.lo, rb.hi, "events")
            rs.segs = R.SpliceList(rs.chunks, rb.lo, rb.hi, "segs")
        else
            clip.events, rs.segs = {}, {}
        end
        return
    end
    rb.i = rb.i + 1
    local a = clip.actors[rb.i]
    if not a then rs.rebuild = nil return end
    if rb.lo then
        a.s, a.anim, a.hands = R.SpliceRows(rs.chunks, rb.lo, rb.hi, a.uid)
        a.rag = R.SpliceRag(rs.chunks, rb.lo, rb.hi, a.uid)
    else
        a.s, a.anim, a.hands, a.rag = {}, nil, nil, nil
    end
    a._weaponRows, a._weaponRuns, a._reloadRuns = nil, nil, nil
end
-- One unit of work. Returns false when there is nothing to do.
function R.Step(rs)
    local ij = rs.indexJob
    if ij then
        if not R.IndexStep(ij) then
            rs.indexJob = nil
            local me = LocalPlayer()
            rs.idx = R.FinishIndex(ij.idx, IsValid(me) and me:UserID() or nil, IsValid(me) and me:SteamID64() or nil, V.RoundJoinedAt)
        end
        return true
    end
    if rs.conv then R.ConvStep(rs) return true end
    local job = rs.job
    if job then
        if job.job:Step() then return true end
        rs.job = nil
        local c = rs.chunks[job.k]
        if c.state ~= "decoding" then return true end
        if not job.job.head then
            -- not a chunk at all: an EMPTY ready chunk, so playback carries on through it (actors hidden for its
            -- ten seconds) instead of stalling on it or asking for it again forever
            c.state, c.data = "ready", {rows = {}, rags = {}, events = {}, segs = {}}
            V.Say("Part of this round could not be read.", "warn")
            MsgN("[Replay] chunk " .. tostring(c.seq) .. ": " .. tostring(job.job.bad[1]))
            return true
        end
        c.state = "converting"
        rs.conv = {k = job.k, out = job.job.out}
        if job.job.bad and job.job.bad[1] and not rs.badSaid then
            rs.badSaid = true
            MsgN("[Replay] chunk " .. tostring(c.seq) .. ": " .. tostring(job.job.bad[1]))
        end
        return true
    end
    if rs.rebuild then R.RebuildStep(rs) return true end
    local k = R.NearestRaw(rs)
    if k then
        local c = rs.chunks[k]
        c.state = "decoding"
        rs.job = {k = k, job = V.Tape.Chunk(c.raw)} -- the header's JSON is this step's one unit
        c.raw = nil
        return true
    end
    return false
end
function R.Pump(rs, budget)
    local began = SysTime()
    while SysTime() - began < budget do
        if not R.Step(rs) then return end
    end
end

----------------------------------------------------------------- opening, closing
function R.Remember(rs, L)
    if not rs or not rs.idx then return end
    local a = rs.clip and rs.clip.actors[rs.follow or 0]
    R.resume = {rid = rs.rid, cs = L and L.cs or rs.startCs or 0, mode = rs.mode, uid = a and a.uid}
end
function R.Close(reason)
    local rs = R.open
    if not rs then return end
    R.open = nil
    if IsValid(rs.panel) then rs.panel:Remove() end
    local L = V.Life and V.Life.State and V.Life.State()
    if rs.L and L == rs.L then
        R.Remember(rs, L)
        if V.Life.stop then V.Life.stop() end
    end
    if reason == "alive" then
        local at = R.Clock(R.resume and R.resume.cs or 0)
        MsgN("[Replay] you are alive in a live round, so the replay closed. `zc_replay resume` picks it up again at "
            .. at .. " once you are dead or the round is over.")
        -- replay_ui_20260926: say it where the player looks, not only in the console
        local N = istable(ZCGoobApps) and ZCGoobApps.Notify
        if istable(N) and isfunction(N.Push) then
            pcall(N.Push, {key = "replay:paused", app = "Replays", glyph = "play", title = "Replay paused at " .. at,
                body = "You're alive in a live round. Resume it from Replays once you're dead or the round ends."})
        end
    end
    rs.chunks, rs.clip, rs.L = nil, nil, nil
end
-- The life player let go of our replay without us asking (a death replay or the round highlight took the screen, or
-- its fence stopped it): remember where we were and get out of the way.
function R.Lost(rs)
    R.Remember(rs, rs.L)
    R.open = nil
    if IsValid(rs.panel) then rs.panel:Remove() end
    MsgN("[Replay] the replay left the screen (another killcam took it, or an error above). `zc_replay resume` returns to round " .. rs.rid .. " at " .. R.Clock(R.resume and R.resume.cs or 0) .. ".")
end
function V.OpenRound(rid, cs, resume)
    rid = tostring(rid or "")
    if not string.match(rid, "^%d+_%d+$") then MsgN("[Replay] not a round id: " .. rid) return false end
    local me = LocalPlayer()
    if R.Blocked(me) then MsgN("[Replay] " .. R.REFUSED[3]) return false end
    local L = V.Life and V.Life.State and V.Life.State()
    if L and not L.round then MsgN("[Replay] a killcam is on screen; open the replay once it ends.") return false end
    local rs = R.open
    if rs and rs.rid == rid then
        if cs and rs.L then R.Seek(rs, rs.L, cs) end
        return true
    end
    R.Close("replaced")
    rs = {rid = rid, prefix = "tape:" .. rid .. ":", askedAt = RealTime(), startCs = cs, resume = resume, chunks = {},
        mode = resume and resume.mode or "follow", speed = 1, playing = true, dist = 110, orbitYaw = 0, orbitPitch = 14,
        show = {}, dist2 = {}, order = {}, want = {}, bounds = {math.huge, math.huge, -math.huge, -math.huge},
        map = true, rosterTop = 0, status = "Asking the server for round " .. rid .. "…",
        menuUp = gui.IsGameUIVisible and gui.IsGameUIVisible() or false}
    R.open = rs
    R.Ask(rs.prefix .. "index")
    R.MakePanel(rs)
    return true
end
-- The index is in: build the round clip and hand it to the life player as a one-instance sequence.
function R.Start(rs)
    local idx = rs.idx
    if #idx.chunks == 0 or #idx.actors == 0 then
        return R.Fail(rs, "Nothing to replay", "This round's recording has no players or no footage in it.", false)
    end
    -- Owner 2026-09-26 (choice A): the round is drawn inside the LIVE world, so a tape from another map would put its
    -- players inside the wrong level. Block it with the reason; a head without a map (older tapes) plays as before.
    if idx.head and isstring(idx.head.map) and idx.head.map ~= "" and idx.head.map ~= game.GetMap() then
        return R.Fail(rs, "Recorded on " .. idx.head.map, "Round replays play inside the map they were recorded on. Watch it when " .. idx.head.map .. " is on.", false)
    end
    local L0 = V.Life.State()
    if L0 then MsgN("[Replay] a killcam took the screen while the round loaded.") return R.Close("busy") end
    for k, c in ipairs(idx.chunks) do rs.chunks[k] = {seq = c.seq, t0 = c.t0, t1 = c.t1} end
    local clip = {round = true, origin = {0, 0, 0}, pre = 0, len = idx.len / 100, weapons = idx.weapons, actors = idx.actors, events = {}}
    clip.target = idx.me and idx.index[idx.me] or nil -- the "this is you" halo
    rs.clip = clip
    local L = {id = "round:" .. rs.rid, seq = {instances = {{clip = clip}}}, reported = {}, round = rs,
        startAt = RealTime(), wall = RealTime() + idx.len / 100 + 600} -- the wall-clock failsafe: the round's length + 10 min
    rs.L = L
    V.Life.Set(L)
    V.Life.load(1)
    local want = rs.startCs
    if rs.resume and rs.resume.cs then want = rs.resume.cs end
    L.cs = math.Clamp(want or R.OpensAt(idx.marks), 0, L.clip.last)
    local follow = rs.resume and rs.resume.uid and idx.index[rs.resume.uid]
    rs.follow = follow or (idx.me and idx.index[idx.me]) or 1
    rs.status = nil
    if idx.me == nil then V.Say("You are not identified in this round: no bookmarks of your own.", "info") end
    R.SetMode(rs, L, rs.mode)
end
function R.Seek(rs, L, cs)
    L.cs = math.Clamp(cs, 0, L.clip.last)
    rs.jumped = true -- no burst of every shot in between
end
function R.SetMode(rs, L, mode)
    rs.mode = mode
    if V.Life.SetPov then V.Life.SetPov(mode == "fp" and rs.follow or nil) end
    local a = L.clip.actors[rs.follow or 0]
    if mode == "follow" and a then
        local _, _, _, yaw = V.StateAt(a, L.cs)
        if yaw then rs.orbitYaw = yaw else rs.aimYaw = true end
    end
    if mode == "free" then
        rs.freePos = rs.freePos or Vector(0, 0, 0)
        rs.freeAng = rs.freeAng or Angle(0, 0, 0)
        rs.freePos:Set(R.camPos) rs.freeAng:Set(R.camAng)
    end
end
function R.Follow(rs, L, i)
    if not L.clip.actors[i] then return end
    rs.follow = i
    if rs.mode == "free" then rs.mode = "follow" end
    R.SetMode(rs, L, rs.mode)
end

----------------------------------------------------------------- cameras
-- PROVISIONAL(2026-09-26, camera numbers by reasoning, not tuned in game: follow 110 u at 14 deg (40-600 on the wheel), target 56 u up
-- (20 lying), RMB 0.3 deg/px orbit and 0.2 free look, free fly 320 u/s x3 Shift x0.3 Ctrl, trace hull 8 u, ratify-by: 2026-10-10)
R.camPos, R.camAng = Vector(0, 0, 0), Angle(0, 0, 0) -- handed out every frame: reused, never a new pair per frame
R.tr = {start = Vector(0, 0, 0), endpos = Vector(0, 0, 0), mins = Vector(-4, -4, -4), maxs = Vector(4, 4, 4), mask = MASK_SOLID_BRUSHONLY, output = {}}
-- The round's camera, reached from eyeOf (cl_part_06) whenever L.round is set.
function R.Camera(clip, cs)
    local rs = R.open
    if not rs then return R.camPos, R.camAng end
    local actor = clip.actors[rs.follow or 0]
    local x, y, z, yaw, pitch, flags
    if actor then x, y, z, yaw, pitch, flags = V.StateAt(actor, cs) end
    if rs.mode == "fp" and x then
        local pos, ang = V.Life.eyeView(clip, cs)
        if pos then R.camPos:Set(pos) R.camAng:Set(ang) return pos, ang end
    end
    if rs.mode == "free" and rs.freePos then
        R.camPos:Set(rs.freePos) R.camAng:Set(rs.freeAng)
        return R.camPos, R.camAng
    end
    if x then -- follow; first person with no eye to look through falls back to it
        local lying = V.HasFlag(flags, 4) or not V.HasFlag(flags, 1)
        rs.fx, rs.fy, rs.fz = x, y, z + (lying and 20 or 56)
        if rs.aimYaw then rs.aimYaw, rs.orbitYaw = nil, yaw end -- start behind them once their rows have arrived
    end
    if not rs.fx then return R.camPos, R.camAng end -- nothing recorded yet: hold wherever the view was
    local p, yw = math.rad(rs.orbitPitch), math.rad(rs.orbitYaw)
    local cp = math.cos(p)
    local tr = R.tr
    tr.start.x, tr.start.y, tr.start.z = rs.fx, rs.fy, rs.fz
    tr.endpos.x, tr.endpos.y, tr.endpos.z = rs.fx - cp * math.cos(yw) * rs.dist, rs.fy - cp * math.sin(yw) * rs.dist, rs.fz + math.sin(p) * rs.dist
    util.TraceHull(tr)
    local o = tr.output
    if o.Hit and not o.StartSolid then R.camPos:Set(o.HitPos) else R.camPos:Set(tr.endpos) end
    R.camAng.p, R.camAng.y, R.camAng.r = rs.orbitPitch, rs.orbitYaw, 0
    return R.camPos, R.camAng
end
-- Free camera: WASD along the view, Shift fast, Ctrl slow. Real time, so it flies while paused.
function R.Fly(rs, dt)
    local pos, ang = rs.freePos, rs.freeAng
    if not pos then return end
    local speed = 320 * (input.IsKeyDown(KEY_LSHIFT) and 3 or 1) * (input.IsKeyDown(KEY_LCONTROL) and 0.3 or 1) * dt
    local f = (input.IsKeyDown(KEY_W) and 1 or 0) - (input.IsKeyDown(KEY_S) and 1 or 0)
    local s = (input.IsKeyDown(KEY_D) and 1 or 0) - (input.IsKeyDown(KEY_A) and 1 or 0)
    if f == 0 and s == 0 then return end
    local p, y = math.rad(ang.p), math.rad(ang.y)
    local cp = math.cos(p)
    pos.x = pos.x + (math.cos(y) * cp * f + math.sin(y) * s) * speed
    pos.y = pos.y + (math.sin(y) * cp * f - math.cos(y) * s) * speed
    pos.z = pos.z - math.sin(p) * f * speed
end
-- The actors drawn this frame: the `n` nearest the camera plus the followed one. `show` is reused; nothing allocated.
function R.Cull(clip, cs, ex, ey, ez, n, follow, show, dist, order)
    local m = 0
    for i, actor in ipairs(clip.actors) do
        show[i] = false
        local x, y, z = V.StateAt(actor, cs)
        if x then
            m = m + 1
            order[m] = i
            local dx, dy, dz = x - ex, y - ey, z - ez
            dist[i] = dx * dx + dy * dy + dz * dz
        end
    end
    for a = 1, math.min(n, m) do
        local best = a
        for b = a + 1, m do if dist[order[b]] < dist[order[best]] then best = b end end
        order[a], order[best] = order[best], order[a]
        show[order[a]] = true
    end
    if follow and clip.actors[follow] then show[follow] = true end
    return m
end

----------------------------------------------------------------- the frame (called from cl_part_06 V.Life.RoundThink)
function R.Pressed(code)
    if code == nil then return false end
    if V.VoiceKey and code == V.VoiceKey() then return false end -- push-to-talk is never a replay key
    local down = input.IsKeyDown(code)
    local edge = down and not R.keys[code]
    R.keys[code] = down
    return edge
end
function R.Toggle(rs, L)
    if not rs.playing and L.cs >= L.clip.last then R.Seek(rs, L, 0) end
    rs.playing = not rs.playing
end
function R.Mark(rs, L, dir)
    local at = R.StepMark(rs.idx.marks, L.cs, dir, rs.idx.me ~= nil)
    if at then R.Seek(rs, L, at) end
end
function R.Cycle(rs, L, dir)
    local n = #L.clip.actors
    local i = rs.follow or 1
    for _ = 1, n do
        i = (i - 1 + dir) % n + 1
        if V.StateAt(L.clip.actors[i], L.cs) then return R.Follow(rs, L, i) end
    end
end
-- The keys are V.Shortcuts (cl_part_01), the list the tactical viewer's hint row shares: one key, one meaning.
function R.Keys(rs, L)
    local P = R.Pressed
    if P(KEY_SPACE) then R.Toggle(rs, L) end
    if P(KEY_LBRACKET) then R.Mark(rs, L, -1) end
    if P(KEY_RBRACKET) then R.Mark(rs, L, 1) end
    if P(KEY_LEFT) then R.Seek(rs, L, L.cs - 500) end
    if P(KEY_RIGHT) then R.Seek(rs, L, L.cs + 500) end
    -- U4: comma / period step one frame (0.1 s) and hold there, as in the tactical viewer
    if P(KEY_COMMA) then rs.playing = false R.Seek(rs, L, L.cs - 10) end
    if P(KEY_PERIOD) then rs.playing = false R.Seek(rs, L, L.cs + 10) end
    if P(KEY_1) then R.SetMode(rs, L, "free") end
    if P(KEY_2) then R.SetMode(rs, L, "follow") end
    if P(KEY_3) then R.SetMode(rs, L, "fp") end
    if P(KEY_M) then rs.map = not rs.map end
    if P(KEY_Q) then R.Cycle(rs, L, -1) end
    if P(KEY_E) then R.Cycle(rs, L, 1) end
    -- U4: S shares this moment. The free camera flies on WASD, so there S is "back" and the Share button shares.
    if P(KEY_S) and rs.mode ~= "free" then R.Share(rs, L) end
end
-- Share the moment on screen: ZCGoobApps.Share.Open({kind = "round", round, at = seconds into the round, title}).
function R.Share(rs, L)
    if not rs or not rs.idx or not L or not L.clip then return end
    R.Titles(rs)
    local at = math.floor(math.max(0, L.cs or 0) / 100)
    if V.Share({kind = "round", round = rs.rid, at = at, title = rs.cardTitle .. " · " .. R.Clock(L.cs)}) then
        rs.playing = false -- the moment holds still under the sheet
    end
end
-- replay_close_20260926 (owner: "the full round replay does NOT let you close it"): Z-City replaces the game menu -
-- its OnPauseMenuShow opens ZMainMenu and returns false - so gui.IsGameUIVisible() never turns true on Esc and the
-- check in R.Advance below never fired: Esc was the viewer's only way out. Z-City asks OnShowZCityPause first; while
-- a round replay is open, Esc closes it and the menu stays shut.
hook.Add("OnShowZCityPause", "ZCKillcam.RoundEsc", function()
    -- hook order is pairs order: when chat is open, leave Esc to ZChat (it closes chat) - final review 2026-09-26
    if IsValid(hg and hg.chat) and hg.chat:GetActive() then return end
    if R.open then
        if V.ShareUp() then V.ShareClose() return false end -- U4: a share sheet over the replay closes first
        R.Close("esc")
        return false
    end
end)
-- Returns false when the viewer closed. Runs inside the life player's fenced Think.
function R.Advance(L, me)
    local rs = L.round
    if R.open ~= rs then V.Life.stop() return false end -- a stale round clip: never keep drawing it
    if R.Blocked(me) then R.Close("alive") return false end
    -- Esc: the game menu opening after the viewer did is the way out (the console is not)
    local menu = gui.IsGameUIVisible()
    if menu and not rs.menuUp and not gui.IsConsoleVisible() then
        gui.HideGameUI()
        R.Close("esc")
        return false
    end
    rs.menuUp = menu
    local dt = RealFrameTime()
    if not (menu or gui.IsConsoleVisible() or vgui.GetKeyboardFocus() ~= nil) then R.Keys(rs, L) end
    if rs.looking then R.Look(rs) end
    if rs.dragging then R.DragSeek(rs, L) end
    -- the playhead: the transport's, not a slow-motion rate. It waits for its chunk rather than play into nothing.
    -- PROVISIONAL(2026-09-26, buffering holds the clock; the mockup's "never blocks play" could also mean play on with hidden actors, ratify-by: 2026-10-10)
    local p = R.ChunkAt(rs.chunks, L.cs)
    local c = p and rs.chunks[p]
    rs.buffering = c ~= nil and c.state ~= "ready"
    if rs.playing and not rs.buffering and not rs.dragging then
        L.cs = math.min(L.cs + dt * 100 * rs.speed, L.clip.last)
        if L.cs >= L.clip.last then rs.playing = false end
        p = R.ChunkAt(rs.chunks, L.cs)
    end
    rs.p = p
    -- streaming
    R.Evict(rs.chunks, p)
    local lo, hi = R.Window(rs.chunks, p) -- after the evict: an evicted chunk inside the old window shrinks it
    if lo ~= rs.lo or hi ~= rs.hi then
        rs.lo, rs.hi = lo, hi
        rs.rebuild = {lo = lo, hi = hi}
    end
    if RealTime() - (R.lastAsk or 0) >= R.ASK_GAP then -- tapeserve ignores a viewer's requests closer than 0.1 s
        local want = R.Want(rs.chunks, p, RealTime(), rs.want)
        local k = want[1]
        if k then
            local ck = rs.chunks[k]
            ck.state, ck.askedAt = "asked", RealTime()
            R.Ask(rs.prefix .. ck.seq)
        end
    end
    R.Pump(rs, R.BUDGET)
    if rs.mode == "free" then R.Fly(rs, dt) end
    local e = R.camPos
    R.Cull(L.clip, L.cs, e.x, e.y, e.z, R.Actors:GetInt(), rs.follow, rs.show, rs.dist2, rs.order)
    return true
end
function R.BookThink(began)
    local s, ms = R.stats.think, (SysTime() - began) * 1000
    s.n, s.sum = s.n + 1, s.sum + ms
    if ms > s.max then s.max = ms end
end
-- Mid-round appearance: the look recorded at the playhead. Changed only when the look does.
-- PROVISIONAL(2026-09-26, SetModel on a live ghost is unseen in-engine: its per-model bone caches are dropped here, ratify-by: 2026-10-10)
function R.Dress(g, actor, cs)
    local looks = actor.looks
    if not looks or #looks < 2 then return end
    local k = 1
    for i = 2, #looks do if looks[i].t <= cs then k = i else break end end
    if g.zcLook == k or (g.zcLook == nil and k == 1) then g.zcLook = k return end
    g.zcLook = k
    local look = looks[k]
    local model, guessed = V.Life.modelFor({m = look.m})
    if g:GetModel() ~= model then
        g:SetModel(model)
        g.zcLegBones, g.zcFingers, g.zcSwingSeq, g.zcNoFingers = nil, nil, nil, nil
        if g.zcPov then
            local head = g:LookupBone("ValveBiped.Bip01_Head1")
            if head then g:ManipulateBoneScale(head, Vector(0.01, 0.01, 0.01)) end
        end
    end
    V.Life.wear(g, not guessed and look.sk or nil, not guessed and look.bg or nil, look.col or actor.col, nil)
end

----------------------------------------------------------------- input surface
-- A full-screen transparent popup with the KEYBOARD OFF: the mouse is ours (HUD clicks, wheel, RMB look), keys are read
-- raw with input.IsKeyDown and every bind but push-to-talk and the scoreboard is swallowed by the life player's own
-- PlayerBindPress / CreateMove lock (cl_part_06). PROVISIONAL(2026-09-26, key reading under a mouse-only popup is not documented; unseen in-engine, ratify-by: 2026-10-10)
function R.MakePanel(rs)
    if not vgui or not vgui.Create then return end
    local pnl = vgui.Create("EditablePanel")
    if not IsValid(pnl) then return end
    pnl:SetPos(0, 0)
    pnl:SetSize(ScrW(), ScrH())
    pnl:MakePopup()
    pnl:SetKeyboardInputEnabled(false)
    pnl.Paint = function(self, w, h)
        local ok, err = pcall(R.Paint, w, h)
        if not ok and not R.paintErr then R.paintErr = true print("[Replay] HUD: " .. tostring(err)) end
    end
    pnl.OnMousePressed = function(self, code) local ok, err = pcall(R.Press, code) if not ok then R.Fault("input", err) end return true end
    pnl.OnMouseReleased = function(self, code) local ok, err = pcall(R.Release, code) if not ok then R.Fault("input", err) end return true end
    pnl.OnMouseWheeled = function(self, d) local ok, err = pcall(R.Wheel, d) if not ok then R.Fault("input", err) end return true end
    rs.panel = pnl
end
function R.Fault(what, err)
    if not R.faultSaid then R.faultSaid = true print("[Replay] " .. what .. ": " .. tostring(err)) end
end
function R.Press(code)
    local rs = R.open
    if not rs then return end
    if code == MOUSE_LEFT then -- replay_ui_20260926: the ways out work while loading and on the failure card too
        local mx0, my0 = input.GetCursorPos()
        local t0 = R.HitAt(mx0, my0)
        if t0 and t0[5] == "close" then return R.Close("button") end
        if t0 and t0[5] == "retry" then
            local rid = rs.rid
            R.Close("retry")
            return V.OpenRound(rid)
        end
        if t0 and t0[5] == "keys" then rs.keysOpen = not rs.keysOpen return end
        if t0 and t0[5] == "feed" then rs.feed = rs.feed == false return end
    end
    if not rs.L then return end
    local L = rs.L
    if code == MOUSE_RIGHT then
        rs.looking = true
        rs.lookX, rs.lookY = input.GetCursorPos()
        if IsValid(rs.panel) then rs.panel:SetCursor("blank") rs.panel:MouseCapture(true) end
        return
    end
    if code ~= MOUSE_LEFT then return end
    local mx, my = input.GetCursorPos()
    local t = R.HitAt(mx, my)
    if not t then return end
    local act, arg = t[5], t[6]
    if act == "timeline" then rs.dragging = true R.DragSeek(rs, L)
    elseif act == "seek" then R.Seek(rs, L, arg)
    elseif act == "mode" then R.SetMode(rs, L, arg)
    elseif act == "follow" then R.Follow(rs, L, arg)
    elseif act == "play" then R.Toggle(rs, L)
    elseif act == "jump" then R.Seek(rs, L, L.cs + arg)
    elseif act == "mark" then R.Mark(rs, L, arg)
    elseif act == "speed" then rs.speed = arg
    elseif act == "share" then R.Share(rs, L)
    elseif act == "map" then rs.map = not rs.map
    elseif act == "cycle" then R.Cycle(rs, L, arg) end
end
function R.Release(code)
    local rs = R.open
    if not rs then return end
    if code == MOUSE_LEFT then rs.dragging = false end
    if code == MOUSE_RIGHT and rs.looking then
        rs.looking = false
        if IsValid(rs.panel) then rs.panel:SetCursor("arrow") rs.panel:MouseCapture(false) end
        if rs.lookX then input.SetCursorPos(rs.lookX, rs.lookY) end
    end
end
function R.Wheel(d)
    local rs = R.open
    if not rs then return end
    local mx, my = input.GetCursorPos()
    local r = rs.rosterBox
    if r and mx >= r[1] and my >= r[2] and mx < r[1] + r[3] and my < r[2] + r[4] then
        rs.rosterTop = math.max(0, rs.rosterTop - d)
    elseif rs.mode == "follow" or rs.mode == "fp" then
        rs.dist = math.Clamp(rs.dist - d * 18, 40, 600)
    end
end
-- RMB held: the cursor is hidden and kept where it was pressed; the distance it tries to travel turns the view.
function R.Look(rs)
    if not input.IsMouseDown(MOUSE_RIGHT) then return R.Release(MOUSE_RIGHT) end
    local mx, my = input.GetCursorPos()
    local dx, dy = mx - rs.lookX, my - rs.lookY
    if dx == 0 and dy == 0 then return end
    input.SetCursorPos(rs.lookX, rs.lookY)
    if rs.mode == "free" and rs.freeAng then
        rs.freeAng.y = rs.freeAng.y - dx * 0.2
        rs.freeAng.p = math.Clamp(rs.freeAng.p + dy * 0.2, -89, 89)
    else
        rs.orbitYaw = rs.orbitYaw - dx * 0.3
        rs.orbitPitch = math.Clamp(rs.orbitPitch + dy * 0.3, -60, 85)
    end
end
function R.DragSeek(rs, L)
    if not input.IsMouseDown(MOUSE_LEFT) then rs.dragging = false return end
    local tl = rs.tlBox
    if not tl then return end
    local mx = input.GetCursorPos()
    R.Seek(rs, L, math.Clamp((mx - tl[1]) / tl[3], 0, 1) * L.clip.last)
end

----------------------------------------------------------------- the HUD (mockup 17; ZCity tokens)
R.SEG = {}
for age = 0, 12 do R.SEG[age] = Color(255, 225, 140, 255 - age * 18) end
R.KT = {}
function R.KillText(n) local t = R.KT[n] if not t then t = n .. " K" R.KT[n] = t end return t end
function R.Hit(x, y, w, h, act, arg)
    local n = R.hitN + 1
    R.hitN = n
    local t = R.hits[n]
    if not t then t = {} R.hits[n] = t end
    t[1], t[2], t[3], t[4], t[5], t[6] = x, y, w, h, act, arg
end
function R.HitAt(mx, my)
    for i = R.hitN, 1, -1 do
        local t = R.hits[i]
        if mx >= t[1] and my >= t[2] and mx < t[1] + t[3] and my < t[2] + t[4] then return t end
    end
end
-- replay_ui_20260926 (owner-approved canvas "Round Replay Redesign", Main + Loading boards): a top bar with the round,
-- the camera switch, Share, Shortcuts and a real Close button; the followed player's chip; the map and the player
-- list on the right; the kill feed bottom-left; one transport bar with the timeline, play, skip, bookmarks, speed and
-- toggles; and loading / failure cards that always have a way out. Laid out at 1440x810 and scaled by the screen
-- height. Every helper is a field on R: the assembled viewer chunk is at LuaJIT's 200-local limit.
-- U4 (2026-09-26): the colours are the one theme's (V.Theme: the GoobOS kit's tokens, or the viewer's copy), with the
-- few alpha variants this HUD needs made once per theme table here rather than every frame in the painters.
function R.Palette()
    local T = V.Theme()
    if R.uiFor == T and R.UI then return R.UI end
    R.uiFor = T
    local function a(c, alpha) return Color(c.r, c.g, c.b, alpha) end
    R.UI = {panel = T.glassHi, edge = a(T.edge, 204), red = T.main, redEdge = T.accent, accent = T.accent, text = T.text,
        muted = T.muted, caps = T.muted, gold = T.gold, ink = T.ink, me = T.death, alive = T.healthy, down = T.amber,
        dead = a(T.muted, 90), deadText = a(T.muted, 170), track = a(T.white, 23), buf = a(T.white, 51), sel = a(T.main, 97),
        segBg = a(T.ink, 150), line = a(T.white, 36), hover = a(T.white, 14), kill = T.kill, death = T.death,
        other = a(T.white, 140), white = T.white, ghostHover = a(T.hover, 240), mapBg = a(T.ink, 245), ring = T.ink,
        feedEdge = a(T.edge, 190), goldEdge = a(T.gold, 115), pill = a(T.ink, 230), tip = a(T.ink, 245),
        head = a(T.accent, 140), playHover = Color(math.min(255, T.accent.r + 22), T.accent.g, T.accent.b), warnEdge = a(T.amber, 140)}
    return R.UI
end
R.Palette()
-- The rate chip format every viewer uses (%.2gx): 0.25x, 0.5x, 1x, 2x, 4x.
R.SPEEDS = {{0.25}, {0.5}, {1}, {2}, {4}}
for _, sp in ipairs(R.SPEEDS) do sp[2] = string.format("%.2gx", sp[1]) end
R.MODES = {{"free", "1", "Free"}, {"follow", "2", "Follow"}, {"fp", "3", "First person"}}
-- The Shortcuts card lists V.Shortcuts (cl_part_01): the one list, shared with the tactical viewer's hint row.
R.HINTS = {free = "WASD move · right-drag look · Shift fast", follow = "Scroll to zoom · right-drag to orbit", fp = "Their eyes"}

-- U4: V.Font (hg_font, cached, rebuilt when it changes); R.F holds this scale's names and R.T takes the short one.
function R.Fonts(h)
    local u = math.Clamp(h / 810, 0.7, 2.2)
    R.u = u
    if R.fontU == u and R.fontGen == V.FontGen and R.F then return u end
    R.fontU, R.fontGen, R.w2, R.F = u, V.FontGen, {}, {}
    for name, spec in pairs({Title = {20, 700}, Body = {14, 500}, Strong = {15, 600}, Small = {12, 500}, Caps = {11, 600},
        Key = {11, 500}, Time = {22, 700}, Big = {20, 700}}) do
        R.F[name] = V.Font(math.max(10, math.floor(spec[1] * u + 0.5)), spec[2])
    end
    return u
end
function R.TW(font, text)
    local byFont = R.w2[font]
    if not byFont then byFont = {} R.w2[font] = byFont end
    local w = byFont[text]
    if not w then surface.SetFont(font) w = surface.GetTextSize(text) byFont[text] = w end
    return w
end
function R.T(text, font, x, y, col, ax, ay) draw.SimpleText(text, R.F[font], x, y, col, ax or TEXT_ALIGN_LEFT, ay or TEXT_ALIGN_TOP) end
function R.Card(x, y, w, h, edge)
    local r = math.floor(8 * R.u)
    draw.RoundedBox(r, x, y, w, h, edge or R.UI.edge)
    draw.RoundedBox(r, x + 1, y + 1, w - 2, h - 2, R.UI.panel)
end
function R.Over(x, y, w, h)
    local mx, my = input.GetCursorPos()
    return mx >= x and my >= y and mx < x + w and my < y + h
end
-- A clickable box: style "red" (filled), "on" (selected in a group), "ghost" (outlined), "flat" (group member).
function R.Btn(x, y, w, h, style, act, arg)
    local U, r = R.UI, math.floor(6 * R.u)
    local over = R.Over(x, y, w, h)
    if style == "red" or style == "on" then
        draw.RoundedBox(r, x, y, w, h, style == "red" and U.redEdge or U.red)
        draw.RoundedBox(r, x + 1, y + 1, w - 2, h - 2, over and U.accent or U.red)
    elseif style == "ghost" then
        draw.RoundedBox(r, x, y, w, h, U.line)
        draw.RoundedBox(r, x + 1, y + 1, w - 2, h - 2, over and U.ghostHover or U.panel)
    elseif over then
        draw.RoundedBox(r, x, y, w, h, U.hover)
    end
    R.Hit(x, y, w, h, act, arg)
end
-- Code-drawn icons (the HUD font has no media glyphs). s = icon size in pixels, centred on (cx, cy).
function R.Bar(x1, y1, x2, y2, t, col)
    local dx, dy = x2 - x1, y2 - y1
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.5 then return end
    surface.SetDrawColor(col)
    surface.DrawTexturedRectRotated((x1 + x2) / 2, (y1 + y2) / 2, len, t, -math.deg(math.atan2(dy, dx)))
end
function R.Icon(name, cx, cy, s, col)
    draw.NoTexture()
    local t = math.max(1.5, s * 0.12)
    local h = s / 2
    surface.SetDrawColor(col)
    if name == "x" then
        R.Bar(cx - h * 0.7, cy - h * 0.7, cx + h * 0.7, cy + h * 0.7, t * 1.2, col)
        R.Bar(cx + h * 0.7, cy - h * 0.7, cx - h * 0.7, cy + h * 0.7, t * 1.2, col)
    elseif name == "play" then
        surface.DrawPoly({{x = cx - h * 0.45, y = cy - h * 0.7}, {x = cx + h * 0.75, y = cy}, {x = cx - h * 0.45, y = cy + h * 0.7}})
    elseif name == "pause" then
        surface.DrawRect(cx - h * 0.55, cy - h * 0.65, h * 0.38, h * 1.3)
        surface.DrawRect(cx + h * 0.17, cy - h * 0.65, h * 0.38, h * 1.3)
    elseif name == "prev" or name == "next" then
        local d = name == "next" and 1 or -1
        surface.DrawRect(cx + d * h * 0.55 - t / 2, cy - h * 0.6, t, h * 1.2)
        local tip, base = cx + d * h * 0.35, cx - d * h * 0.55
        if d == 1 then surface.DrawPoly({{x = base, y = cy - h * 0.6}, {x = tip, y = cy}, {x = base, y = cy + h * 0.6}})
        else surface.DrawPoly({{x = tip, y = cy}, {x = base, y = cy - h * 0.6}, {x = base, y = cy + h * 0.6}}) end
    elseif name == "chevL" or name == "chevR" then
        local d = name == "chevR" and 1 or -1
        R.Bar(cx - d * h * 0.3, cy - h * 0.55, cx + d * h * 0.3, cy, t * 1.3, col)
        R.Bar(cx + d * h * 0.3, cy, cx - d * h * 0.3, cy + h * 0.55, t * 1.3, col)
    elseif name == "back" or name == "fwd" then
        local d = name == "fwd" and 1 or -1
        for i = 0, 5 do -- an open arc with an arrowhead
            local a1, a2 = math.rad(-120 + i * 45), math.rad(-120 + (i + 1) * 45)
            R.Bar(cx + d * math.cos(a1) * h * 0.6, cy + math.sin(a1) * h * 0.6, cx + d * math.cos(a2) * h * 0.6, cy + math.sin(a2) * h * 0.6, t, col)
        end
        local ax, ay = cx + d * math.cos(math.rad(-120)) * h * 0.6, cy + math.sin(math.rad(-120)) * h * 0.6
        R.Bar(ax, ay, ax - d * h * 0.35, ay + h * 0.05, t, col)
        R.Bar(ax, ay, ax - d * h * 0.05, ay + h * 0.35, t, col)
    elseif name == "keys" then
        surface.DrawOutlinedRect(cx - h * 0.9, cy - h * 0.5, h * 1.8, h, math.max(1, math.floor(t)))
        for i = 0, 3 do surface.DrawRect(cx - h * 0.6 + i * h * 0.38, cy - h * 0.2, t, t) end
        surface.DrawRect(cx - h * 0.45, cy + h * 0.15, h * 0.9, t)
    elseif name == "map" then
        R.Bar(cx - h * 0.8, cy - h * 0.55, cx - h * 0.27, cy - h * 0.75, t, col) R.Bar(cx - h * 0.27, cy - h * 0.75, cx + h * 0.27, cy - h * 0.55, t, col)
        R.Bar(cx + h * 0.27, cy - h * 0.55, cx + h * 0.8, cy - h * 0.75, t, col) R.Bar(cx - h * 0.8, cy + h * 0.75, cx - h * 0.27, cy + h * 0.55, t, col)
        R.Bar(cx - h * 0.27, cy + h * 0.55, cx + h * 0.27, cy + h * 0.75, t, col) R.Bar(cx + h * 0.27, cy + h * 0.75, cx + h * 0.8, cy + h * 0.55, t, col)
        for _, x in ipairs({-0.8, -0.27, 0.27, 0.8}) do R.Bar(cx + h * x, cy - h * 0.65, cx + h * x, cy + h * 0.65, t, col) end
    elseif name == "list" then
        for i = -1, 1 do
            surface.DrawRect(cx - h * 0.8, cy + i * h * 0.5 - t / 2, t * 1.2, t)
            surface.DrawRect(cx - h * 0.45, cy + i * h * 0.5 - t / 2, h * 1.25, t)
        end
    end
end
function R.Circle(cx, cy, r, col) draw.RoundedBox(math.floor(r), cx - r, cy - r, r * 2, r * 2, col) end
function R.Chip(text, x, cy, col, font)
    font = font or "Key"
    local u = R.u
    local w = R.TW(R.F[font], text) + 10 * u
    local h = 16 * u
    draw.RoundedBox(math.floor(3 * u), x, cy - h / 2, w, h, V.Alpha(col, 110))
    draw.RoundedBox(math.floor(3 * u), x + 1, cy - h / 2 + 1, w - 2, h - 2, R.UI.panel)
    R.T(text, font, x + w / 2, cy, col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    return w
end

function R.Status(a, cs)
    local x, _, _, _, _, flags = V.StateAt(a, cs)
    if x then
        if not V.HasFlag(flags, 1) then return "dead" end
        return V.HasFlag(flags, 4) and "down" or "alive"
    end
    for _, t in ipairs(a.dies) do if t <= cs then return "dead" end end -- not loaded here: the index still knows
    return "alive"
end
function R.Kills(a, cs)
    local n = 0
    for _, t in ipairs(a.kills) do if t <= cs then n = n + 1 else break end end
    return n
end
function R.StatusColor(st) local U = R.UI return st == "alive" and U.alive or (st == "down" and U.down or U.dead) end

function R.Paint(w, h)
    local rs = R.open
    if not rs or (V.ScoreboardUp and V.ScoreboardUp()) then R.hitN = 0 return end
    local began = SysTime()
    R.hitN = 0
    R.Fonts(h)
    R.Palette()
    local L = rs.L
    if rs.failed or not L or not L.clip then
        R.PaintLoading(rs, w, h)
    else
        local cs = L.cs
        local u = R.u
        local barTop = h - 16 * u - 122 * u
        R.PaintTop(rs, L, w, h)
        R.PaintSubject(rs, L, cs, w, h)
        local colX = w - 16 * u - 300 * u
        local y = 88 * u
        if rs.map then y = R.PaintMap(rs, L, cs, colX, y, 300 * u, 210 * u) + 10 * u end
        R.PaintRoster(rs, L, cs, colX, y, 300 * u, barTop - 10 * u - y)
        if rs.feed ~= false then R.PaintFeed(rs, cs, 16 * u, barTop - 12 * u, 330 * u) end
        R.PaintBar(rs, L, cs, 16 * u, barTop, w - 32 * u, 122 * u)
        if rs.keysOpen then R.PaintKeys(colX - 16 * u - 300 * u, 88 * u, 300 * u) end
        if rs.buffering then R.PaintBuffering(rs, cs, w, h) end
        V.DrawNote(w / 2, 88 * u, TEXT_ALIGN_CENTER, 32 * u) -- U4: the viewer's one note, as on the other replay screens
    end
    local s, ms = R.stats.hud, (SysTime() - began) * 1000
    s.n, s.sum = s.n + 1, s.sum + ms
    if ms > s.max then s.max = ms end
end

function R.Titles(rs)
    if rs.cardTitle then return end
    local idx = rs.idx or {}
    local head = idx.head or {}
    rs.cardTitle = tostring(head.mode or "Round replay")
    rs.cardSub = string.format("%s · %d players%s", tostring(head.map or "?"), #(idx.actors or {}),
        idx.ended and (" · ended " .. os.date("%H:%M", idx.ended)) or "")
end
function R.PaintTop(rs, L, w, h)
    local U, u = R.UI, R.u
    local x, y, bw, bh = 16 * u, 16 * u, w - 32 * u, 60 * u
    R.Card(x, y, bw, bh)
    R.Titles(rs)
    R.T("ROUND REPLAY", "Caps", x + 18 * u, y + 10 * u, U.caps)
    local cw = R.TW(R.F.Caps, "ROUND REPLAY")
    draw.RoundedBox(math.floor(3 * u), x + 26 * u + cw, y + 9 * u, 38 * u, 15 * u, U.gold)
    R.T("BETA", "Caps", x + 45 * u + cw, y + 16.5 * u, U.ink, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    R.T(rs.cardTitle, "Title", x + 18 * u, y + 27 * u, U.text)
    R.T(rs.cardSub, "Small", x + 30 * u + R.TW(R.F.Title, rs.cardTitle), y + 33 * u, U.muted)
    -- the camera switch, centred
    local segH, pad = 36 * u, 3 * u
    local widths, total = {}, 0
    for i, m in ipairs(R.MODES) do
        widths[i] = R.TW(R.F.Strong, m[3]) + R.TW(R.F.Key, m[2]) + 44 * u
        total = total + widths[i] + 2 * u
    end
    local gx = x + bw / 2 - total / 2
    draw.RoundedBox(math.floor(7 * u), gx - pad, y + bh / 2 - segH / 2 - pad, total + pad * 2, segH + pad * 2, U.segBg)
    for i, m in ipairs(R.MODES) do
        local on = rs.mode == m[1]
        R.Btn(gx, y + bh / 2 - segH / 2, widths[i], segH, on and "on" or "flat", "mode", m[1])
        R.T(m[3], "Strong", gx + 12 * u, y + bh / 2, on and U.white or U.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        R.Chip(m[2], gx + 20 * u + R.TW(R.F.Strong, m[3]), y + bh / 2, on and U.white or U.muted)
        gx = gx + widths[i] + 2 * u
    end
    -- Close (a real way out: Esc is Z-City's menu key), then Shortcuts to its left
    local closeW = 58 * u + R.TW(R.F.Strong, "Close") + R.TW(R.F.Key, "Esc")
    local cx = x + bw - 10 * u - closeW
    R.Btn(cx, y + 10 * u, closeW, 40 * u, "red", "close")
    R.Icon("x", cx + 18 * u, y + 30 * u, 16 * u, U.white)
    R.T("Close", "Strong", cx + 32 * u, y + 30 * u, U.white, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    R.Chip("Esc", cx + 40 * u + R.TW(R.F.Strong, "Close"), y + 30 * u, U.white)
    local kw = 44 * u + R.TW(R.F.Body, "Shortcuts")
    local kx = cx - 8 * u - kw
    R.Btn(kx, y + 10 * u, kw, 40 * u, rs.keysOpen and "on" or "ghost", "keys")
    R.Icon("keys", kx + 18 * u, y + 30 * u, 18 * u, U.text)
    R.T("Shortcuts", "Body", kx + 32 * u, y + 30 * u, U.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    -- U4: Share this moment (S), left of Shortcuts
    local shareW = 40 * u + R.TW(R.F.Body, "Share") + R.TW(R.F.Key, "S")
    local sx = kx - 8 * u - shareW
    R.Btn(sx, y + 10 * u, shareW, 40 * u, "ghost", "share")
    R.T("Share", "Body", sx + 14 * u, y + 30 * u, U.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    R.Chip("S", sx + 22 * u + R.TW(R.F.Body, "Share"), y + 30 * u, U.muted)
end
function R.PaintSubject(rs, L, cs, w, h)
    local U, u = R.UI, R.u
    local a = L.clip.actors[rs.follow or 0]
    local name = a and (a.uid == rs.idx.me and (a.name .. " (you)") or a.name) or "?"
    local label = rs.mode == "free" and "FREE CAMERA" or (rs.mode == "fp" and "FIRST PERSON" or "FOLLOWING")
    local hint = R.HINTS[rs.mode] or ""
    local nameW = math.max(200 * u, R.TW(R.F.Strong, name) + 70 * u)
    local bw = 6 * u + 40 * u + 8 * u + nameW + 40 * u + 20 * u + R.TW(R.F.Small, hint) + 16 * u
    local x, y, bh = 16 * u, 88 * u, 52 * u
    R.Card(x, y, bw, bh)
    R.Btn(x + 6 * u, y + 6 * u, 40 * u, 40 * u, "flat", "cycle", -1)
    R.Icon("chevL", x + 26 * u, y + 26 * u, 18 * u, U.text)
    local nx = x + 54 * u
    R.T(label, "Caps", nx, y + 9 * u, U.muted)
    if a then R.Circle(nx + 4.5 * u, y + 34 * u, 4.5 * u, R.StatusColor(R.Status(a, cs))) end
    R.T(name, "Strong", nx + 16 * u, y + 34 * u, a and a.uid == rs.idx.me and U.me or U.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    if a then R.T(R.KillText(R.Kills(a, cs)), "Small", nx + 24 * u + R.TW(R.F.Strong, name), y + 34 * u, U.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
    local ex = nx + nameW
    R.Btn(ex, y + 6 * u, 40 * u, 40 * u, "flat", "cycle", 1)
    R.Icon("chevR", ex + 20 * u, y + 26 * u, 18 * u, U.text)
    surface.SetDrawColor(255, 255, 255, 30)
    surface.DrawRect(ex + 48 * u, y + 12 * u, 1, 28 * u)
    R.T(hint, "Small", ex + 60 * u, y + 26 * u, U.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
end
function R.PaintMap(rs, L, cs, x, y, mw, mh)
    local U, u = R.UI, R.u
    R.Card(x, y, mw, mh)
    R.T("MAP", "Caps", x + 10 * u, y + 9 * u, U.caps)
    R.T("M to hide", "Small", x + mw - 10 * u, y + 9 * u, U.muted, TEXT_ALIGN_RIGHT)
    R.Hit(x, y, mw, 26 * u, "map")
    local ix, iy, iw, ih = x + 10 * u, y + 30 * u, mw - 20 * u, mh - 40 * u
    draw.RoundedBox(math.floor(4 * u), ix, iy, iw, ih, U.mapBg)
    local b = rs.bounds
    if b[1] > b[3] then return y + mh end
    local spanX, spanY = math.max(b[3] - b[1], 256), math.max(b[4] - b[2], 256)
    local scale = math.min(iw / spanX, ih / spanY) * 0.92
    local cx, cy = (b[1] + b[3]) / 2, (b[2] + b[4]) / 2
    local mx, my = ix + iw / 2, iy + ih / 2
    for i, a in ipairs(L.clip.actors) do
        local ax, ay, _, _, _, flags = V.StateAt(a, cs)
        if ax then
            local px, py = mx + (ax - cx) * scale, my - (ay - cy) * scale -- world +y is up the map
            local col = (a.uid == rs.idx.me) and U.death or (V.HasFlag(flags, 1) and (V.HasFlag(flags, 4) and U.down or U.text) or U.dead)
            if i == rs.follow then R.Circle(px, py, 7 * u, U.white) R.Circle(px, py, 5.5 * u, U.ring) end
            R.Circle(px, py, 4 * u, col)
        end
    end
    if rs.mode == "free" and R.camPos then R.Circle(mx + (R.camPos.x - cx) * scale, my - (R.camPos.y - cy) * scale, 3 * u, U.gold) end
    return y + mh
end
function R.PaintRoster(rs, L, cs, x, y, rw, maxH)
    local U, u = R.UI, R.u
    local actors = L.clip.actors
    local rowH = 34 * u
    local headH = 30 * u
    local fit = math.max(1, math.floor((maxH - headH - 10 * u) / (rowH + 2 * u)))
    local shown = math.min(#actors, fit)
    rs.rosterTop = math.Clamp(rs.rosterTop, 0, math.max(0, #actors - fit))
    local rh = headH + shown * (rowH + 2 * u) + 8 * u
    R.Card(x, y, rw, rh)
    rs.rosterBox = rs.rosterBox or {}
    rs.rosterBox[1], rs.rosterBox[2], rs.rosterBox[3], rs.rosterBox[4] = x, y, rw, rh
    if rs.clockSec ~= math.floor(cs / 100) then
        rs.clockSec = math.floor(cs / 100)
        rs.clockNow = R.Clock(cs)
        rs.clockEnd = R.Clock(L.clip.last)
        rs.rosterHead = "PLAYERS · AT " .. rs.clockNow
        local alive = 0
        for _, a in ipairs(actors) do if R.Status(a, cs) ~= "dead" then alive = alive + 1 end end
        rs.aliveText = alive .. " alive"
    end
    R.T(rs.rosterHead, "Caps", x + 14 * u, y + 11 * u, U.caps)
    R.T(rs.aliveText or "", "Small", x + rw - 14 * u, y + 10 * u, U.muted, TEXT_ALIGN_RIGHT)
    local me = rs.idx.me
    local ry = y + headH
    for n = 1, shown do
        local i = n + rs.rosterTop
        local a = actors[i]
        if not a.hudName then
            a.hudName = a.uid == me and (a.name .. " (you)") or a.name
            a.hudCol = a.col and Color(a.col[1] or 200, a.col[2] or 200, a.col[3] or 200) or U.text -- once per actor
        end
        local sel = i == rs.follow
        if sel then draw.RoundedBox(math.floor(5 * u), x + 6 * u, ry, rw - 12 * u, rowH, U.sel)
        elseif R.Over(x + 6 * u, ry, rw - 12 * u, rowH) then draw.RoundedBox(math.floor(5 * u), x + 6 * u, ry, rw - 12 * u, rowH, U.hover) end
        local st = R.Status(a, cs)
        R.Circle(x + 20 * u, ry + rowH / 2, 4.5 * u, R.StatusColor(st))
        local nameCol = a.uid == me and U.me or (st == "dead" and U.deadText or U.text)
        R.T(a.hudName, a.uid == me and "Strong" or "Body", x + 34 * u, ry + rowH / 2, nameCol, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        if st == "dead" then
            surface.SetDrawColor(255, 255, 255, 64)
            surface.DrawRect(x + 34 * u, ry + rowH / 2, math.min(R.TW(R.F.Body, a.hudName), rw - 110 * u), 1)
        end
        if st ~= "alive" then R.T(st, "Small", x + rw - 52 * u, ry + rowH / 2, U.muted, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER) end
        R.T(R.KillText(R.Kills(a, cs)), "Small", x + rw - 16 * u, ry + rowH / 2, U.text, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        R.Hit(x + 6 * u, ry, rw - 12 * u, rowH, "follow", i)
        ry = ry + rowH + 2 * u
    end
end
function R.PaintFeed(rs, cs, x, bottom, fw)
    local U, u = R.UI, R.u
    local deaths = rs.idx.deaths
    local last = 0
    for i = #deaths, 1, -1 do if deaths[i].t <= cs then last = i break end end
    local first = math.max(1, last - 4)
    local n = last > 0 and (last - first + 1) or 0
    local rowH = 26 * u
    local fh = 36 * u + math.max(n, 1) * rowH + 6 * u
    local y = bottom - fh
    R.Card(x, y, fw, fh, U.feedEdge)
    R.T("KILL FEED", "Caps", x + 14 * u, y + 12 * u, U.caps)
    local ry = y + 34 * u
    if n == 0 then R.T("Nothing yet", "Small", x + 14 * u, ry + rowH / 2, U.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) return end
    local me = rs.idx.me
    for i = first, last do
        local d = deaths[i]
        if R.Over(x + 8 * u, ry, fw - 16 * u, rowH) then draw.RoundedBox(math.floor(4 * u), x + 8 * u, ry, fw - 16 * u, rowH, U.hover) end
        R.T(d.clock, "Small", x + 14 * u, ry + rowH / 2, U.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        local mine = me and (d.a == me or d.v == me)
        R.T(d.text, mine and "Strong" or "Body", x + 60 * u, ry + rowH / 2, mine and U.me or U.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        R.Hit(x + 8 * u, ry, fw - 16 * u, rowH, "seek", math.max(0, d.t - 300)) -- three seconds before, to see it happen
        ry = ry + rowH
    end
end
function R.PaintKeys(x, y, kw)
    local U, u = R.UI, R.u
    local rowH = 22 * u
    local list = R.shortcutList -- V.Shortcuts' round entries, picked once
    if not list or R.shortcutFor ~= V.Shortcuts then
        list = {}
        for _, s in ipairs(V.Shortcuts) do if s.round then list[#list + 1] = s end end
        R.shortcutList, R.shortcutFor = list, V.Shortcuts
    end
    local kh = 40 * u + #list * rowH
    R.Card(x, y, kw, kh, U.goldEdge)
    R.T("SHORTCUTS", "Caps", x + 16 * u, y + 14 * u, U.gold)
    local ry = y + 36 * u
    for _, k in ipairs(list) do
        R.T(k.text, "Body", x + 16 * u, ry + rowH / 2, U.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        R.T(k.keys, "Strong", x + kw - 16 * u, ry + rowH / 2, U.white, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        ry = ry + rowH
    end
end
function R.PaintBuffering(rs, cs, w, h)
    local U, u = R.UI, R.u
    local c = rs.p and rs.chunks[rs.p]
    local text = c and ("Loading " .. R.Clock(c.t0) .. " – " .. R.Clock(c.t1) .. "…") or "Loading this part of the round…"
    local tw = R.TW(R.F.Body, text) + 54 * u
    local th = 40 * u
    draw.RoundedBox(math.floor(th / 2), w / 2 - tw / 2, h * 0.45 - th / 2, tw, th, U.pill)
    local a = RealTime() * 5 -- a turning arc
    local sx, sy, sr = w / 2 - tw / 2 + 22 * u, h * 0.45, 7 * u
    for i = 0, 5 do
        local a1, a2 = a + i * 0.7, a + (i + 1) * 0.7
        R.Bar(sx + math.cos(a1) * sr, sy + math.sin(a1) * sr, sx + math.cos(a2) * sr, sy + math.sin(a2) * sr, 2.2 * u, U.gold)
    end
    R.T(text, "Body", w / 2 + 12 * u, h * 0.45, U.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end
function R.PaintBar(rs, L, cs, x, y, bw, bh)
    local U, u = R.UI, R.u
    R.Card(x, y, bw, bh)
    local len = math.max(L.clip.last, 1)
    -- timeline
    local tx, tw, ty, th = x + 16 * u, bw - 32 * u, y + 12 * u, 40 * u
    rs.tlBox = rs.tlBox or {}
    rs.tlBox[1], rs.tlBox[2], rs.tlBox[3], rs.tlBox[4] = tx, ty, tw, th
    R.Hit(tx, ty, tw, th, "timeline")
    local railY, railH = ty + 20 * u, 6 * u
    local rr = math.floor(3 * u)
    draw.RoundedBox(rr, tx, railY, tw, railH, U.track)
    for _, c in ipairs(rs.chunks) do
        if c.state == "ready" then draw.RoundedBox(rr, tx + tw * c.t0 / len, railY, math.max(1, tw * (c.t1 - c.t0) / len), railH, U.buf) end
    end
    local head = math.Clamp(cs / len, 0, 1)
    draw.RoundedBox(rr, tx, railY, tw * head, railH, U.accent)
    local mx, my = input.GetCursorPos()
    local tip
    draw.NoTexture()
    for _, m in ipairs(rs.idx.marks) do
        local px = tx + tw * m.t / len
        if m.kind == "kill" then
            surface.SetDrawColor(U.kill)
            surface.DrawTexturedRectRotated(px, ty + 7 * u, 10 * u, 10 * u, 45)
            R.Hit(px - 8 * u, ty, 16 * u, 16 * u, "seek", m.at)
        elseif m.kind == "death" then
            R.Circle(px, ty + 7 * u, 7 * u, U.ring)
            R.Circle(px, ty + 7 * u, 5 * u, U.death)
            R.Hit(px - 8 * u, ty, 16 * u, 16 * u, "seek", m.at)
        else
            surface.SetDrawColor(U.other)
            surface.DrawRect(px - 1, railY + railH + 4 * u, 2, 10 * u)
            R.Hit(px - 4 * u, railY + railH, 8 * u, 16 * u, "seek", m.at)
        end
        if mx >= px - 8 * u and mx <= px + 8 * u and my >= ty - 2 * u and my <= ty + th then tip = m end
    end
    local hx = tx + tw * head
    R.Circle(hx, railY + railH / 2, 11 * u, U.head)
    R.Circle(hx, railY + railH / 2, 8 * u, U.white)
    if tip and tip.d and tip.d.tip then
        local text = tip.d.tip
        local ww = R.TW(R.F.Small, text) + 16 * u
        local px = math.Clamp(tx + tw * tip.t / len - ww / 2, x, x + bw - ww)
        draw.RoundedBox(math.floor(4 * u), px, ty - 30 * u, ww, 24 * u, U.tip)
        R.T(text, "Small", px + 8 * u, ty - 18 * u, U.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    -- controls
    local cy = ty + th + 8 * u + 24 * u
    local bx = tx
    local sq = 40 * u
    R.Btn(bx, cy - sq / 2, sq, sq, "ghost", "mark", -1) R.Icon("prev", bx + sq / 2, cy, 18 * u, U.text) bx = bx + sq + 6 * u
    local fiveW = 16 * u + 8 * u + R.TW(R.F.Body, "5 s") + 12 * u
    R.Btn(bx, cy - sq / 2, fiveW, sq, "ghost", "jump", -500) R.Icon("back", bx + 16 * u, cy, 16 * u, U.text)
    R.T("5 s", "Body", bx + 28 * u, cy, U.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) bx = bx + fiveW + 6 * u
    local pr = 24 * u
    R.Circle(bx + pr, cy, pr, R.Over(bx, cy - pr, pr * 2, pr * 2) and U.playHover or U.accent)
    R.Hit(bx, cy - pr, pr * 2, pr * 2, "play")
    R.Icon(rs.playing and "pause" or "play", bx + pr, cy, 20 * u, U.white) bx = bx + pr * 2 + 6 * u
    R.Btn(bx, cy - sq / 2, fiveW, sq, "ghost", "jump", 500)
    R.T("5 s", "Body", bx + 12 * u, cy, U.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    R.Icon("fwd", bx + fiveW - 16 * u, cy, 16 * u, U.text) bx = bx + fiveW + 6 * u
    R.Btn(bx, cy - sq / 2, sq, sq, "ghost", "mark", 1) R.Icon("next", bx + sq / 2, cy, 18 * u, U.text) bx = bx + sq + 18 * u
    R.T(rs.clockNow or "0:00", "Time", bx, cy, U.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    bx = bx + R.TW(R.F.Time, rs.clockNow or "0:00") + 6 * u
    R.T("/ " .. (rs.clockEnd or ""), "Body", bx, cy + 2 * u, U.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    bx = bx + R.TW(R.F.Body, "/ " .. (rs.clockEnd or "")) + 24 * u
    -- legend
    surface.SetDrawColor(U.kill) surface.DrawTexturedRectRotated(bx + 4 * u, cy, 8 * u, 8 * u, 45)
    R.T("Your kills", "Small", bx + 14 * u, cy, U.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) bx = bx + 24 * u + R.TW(R.F.Small, "Your kills")
    R.Circle(bx + 4 * u, cy, 4.5 * u, U.death)
    R.T("Your death", "Small", bx + 14 * u, cy, U.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) bx = bx + 24 * u + R.TW(R.F.Small, "Your death")
    surface.SetDrawColor(U.other) surface.DrawRect(bx + 3 * u, cy - 5 * u, 2, 10 * u)
    R.T("Other kills", "Small", bx + 12 * u, cy, U.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    -- right: speed, feed, map
    local rx = x + bw - 16 * u
    R.Btn(rx - sq, cy - sq / 2, sq, sq, rs.map and "on" or "ghost", "map") R.Icon("map", rx - sq / 2, cy, 18 * u, rs.map and U.white or U.muted)
    rx = rx - sq - 6 * u
    local feedOn = rs.feed ~= false
    R.Btn(rx - sq, cy - sq / 2, sq, sq, feedOn and "on" or "ghost", "feed") R.Icon("list", rx - sq / 2, cy, 18 * u, feedOn and U.white or U.muted)
    rx = rx - sq - 12 * u
    local segH, pad = 34 * u, 3 * u
    local sw = math.max(42 * u, R.TW(R.F.Strong, R.SPEEDS[1][2]) + 12 * u) -- wide enough for "0.25x"
    local gx = rx - #R.SPEEDS * (sw + 2 * u)
    draw.RoundedBox(math.floor(7 * u), gx - pad, cy - segH / 2 - pad, #R.SPEEDS * (sw + 2 * u) + pad * 2, segH + pad * 2, U.segBg)
    for _, sp in ipairs(R.SPEEDS) do
        local on = rs.speed == sp[1]
        R.Btn(gx, cy - segH / 2, sw, segH, on and "on" or "flat", "speed", sp[1])
        R.T(sp[2], "Strong", gx + sw / 2, cy, on and U.white or U.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        gx = gx + sw + 2 * u
    end
end
-- Loading, and a round that could not be opened: always a card with a way out (Cancel / Back), never a bare line.
function R.PaintLoading(rs, w, h)
    local U, u = R.UI, R.u
    local cw = math.min(640 * u, w - 32 * u)
    local f = rs.failed
    local ch = f and 170 * u or 160 * u
    local x, y = w / 2 - cw / 2, h * 0.42 - ch / 2
    R.Card(x, y, cw, ch, f and U.warnEdge or nil)
    if f then
        R.T(f.title, "Big", x + 28 * u, y + 26 * u, U.text)
        R.T(f.text, "Body", x + 28 * u, y + 62 * u, U.text)
        local bx = x + 28 * u
        if f.retry then
            local tw = R.TW(R.F.Strong, "Try again") + 32 * u
            R.Btn(bx, y + ch - 64 * u, tw, 40 * u, "red", "retry")
            R.T("Try again", "Strong", bx + tw / 2, y + ch - 44 * u, U.white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            bx = bx + tw + 10 * u
        end
        local bw2 = R.TW(R.F.Strong, "Back to Replays") + 32 * u
        R.Btn(bx, y + ch - 64 * u, bw2, 40 * u, "ghost", "close")
        R.T("Back to Replays", "Strong", bx + bw2 / 2, y + ch - 44 * u, U.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        return
    end
    R.T("ROUND REPLAY", "Caps", x + 28 * u, y + 24 * u, U.caps)
    R.T("Round " .. tostring(rs.rid), "Big", x + 28 * u, y + 42 * u, U.text)
    local cancelW = 52 * u + R.TW(R.F.Strong, "Cancel") + R.TW(R.F.Key, "Esc")
    local cx = x + cw - 28 * u - cancelW
    R.Btn(cx, y + 26 * u, cancelW, 40 * u, "ghost", "close")
    R.Icon("x", cx + 18 * u, y + 46 * u, 14 * u, U.text)
    R.T("Cancel", "Strong", cx + 32 * u, y + 46 * u, U.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    R.Chip("Esc", cx + 40 * u + R.TW(R.F.Strong, "Cancel"), y + 46 * u, U.muted)
    local ij = rs.indexJob
    local share = ij and ij.raw and #ij.raw > 0 and math.Clamp((ij.pos or 1) / #ij.raw, 0, 1) or nil
    R.T(rs.status or "Asking the server for the round…", "Body", x + 28 * u, y + 90 * u, U.text)
    local py, pw = y + 118 * u, cw - 56 * u
    draw.RoundedBox(math.floor(4 * u), x + 28 * u, py, pw, 8 * u, U.track)
    if share then
        draw.RoundedBox(math.floor(4 * u), x + 28 * u, py, pw * share, 8 * u, U.accent)
    else -- waiting on the server: a sweeping bar, since there is nothing to count yet
        local t = (RealTime() * 0.6) % 1
        local sx = x + 28 * u + (pw - pw * 0.25) * math.abs(t * 2 - 1)
        draw.RoundedBox(math.floor(4 * u), sx, py, pw * 0.25, 8 * u, U.accent)
    end
    R.T("It starts playing as soon as the first part is in.", "Small", x + 28 * u, y + 136 * u, U.muted)
end
-- A round that could not be opened keeps the panel up with the reason and a way back (the old viewer closed with a
-- console line nobody saw). `retry`: offer Try again.
function R.Fail(rs, title, text, retry)
    rs.failed = {title = title, text = text, retry = retry}
    rs.indexJob = nil
    MsgN("[Replay] " .. text)
end

----------------------------------------------------------------- bullet segments (the tape's `s` track)
-- The tape carries every traced bullet segment (sv_tape.lua "s": start and end in the world); the clip-shaped events
-- do not carry a shot point, so this is the round's tracer: each segment shown for 12 cs as it happens.
function R.DrawSegs(rs, cs)
    local segs = rs.segs
    if not segs or #segs == 0 then return end
    local lo, hi = 1, #segs + 1
    while lo < hi do
        local mid = math.floor((lo + hi) / 2)
        if segs[mid][1] < cs - 12 then lo = mid + 1 else hi = mid end
    end
    for k = lo, #segs do
        local s = segs[k]
        local age = cs - s[1]
        if age < 0 then break end
        render.DrawLine(s[3], s[4], R.SEG[math.floor(age)] or R.SEG[12], true)
    end
end
hook.Add("PostDrawOpaqueRenderables", "ZCKillcam.Round", function(_, sky)
    if sky or V.SceneDepth == 0 or R.segsOff then return end
    local rs = R.open
    if not rs or not rs.L or not rs.segs then return end
    -- GMod does not pcall hook callbacks: one log line, then this draw is off for the session
    local ok, err = pcall(R.DrawSegs, rs, rs.L.cs)
    if not ok then R.segsOff = true print("[Replay] bullet segments off: " .. tostring(err)) end
end)

----------------------------------------------------------------- loading watch, list, commands
-- Runs every frame, fenced like ZCKillcam.Life: while the index loads (there is no replay yet for the life player's
-- Think to drive), and to notice the life player letting go of our replay.
function R.Watch()
    local rs = R.open
    if rs and rs.L then
        if V.Life.State() ~= rs.L then R.Lost(rs) end
        return
    end
    if not rs then return end
    if R.Blocked(LocalPlayer()) then return R.Close("alive") end
    if rs.failed then return end
    local menu = gui.IsGameUIVisible()
    if menu and not rs.menuUp and not gui.IsConsoleVisible() then gui.HideGameUI() return R.Close("esc") end
    rs.menuUp = menu
    if rs.idx then return R.Start(rs) end
    if not rs.indexJob and RealTime() - rs.askedAt > R.INDEX_WAIT then
        return R.Fail(rs, "Couldn't load this round", "The server didn't answer in time. It may still be saving the round, or the recording is gone.", true)
    end
    R.Pump(rs, R.BUDGET)
end
hook.Add("Think", "ZCKillcam.Round", function()
    if not R.open then return end
    local ok, err = pcall(R.Watch)
    if ok then return end
    if not R.complained then R.complained = true print("[Replay] viewer: " .. tostring(err)) end
    pcall(R.Close, "error")
end)
function R.OnList(id, raw)
    local rows = {}
    local pos, line = 1, nil
    while true do
        line, pos = R.NextLine(raw or "", pos)
        if not line then break end
        local t = util.JSONToTable(line)
        if istable(t) and isstring(t.id) then rows[#rows + 1] = t end
    end
    R.listRows = R.listRows or {}
    for _, t in ipairs(rows) do
        R.listRows[#R.listRows + 1] = t
        if not R.listOldest or (tonumber(t.t) or 0) < R.listOldest then R.listOldest = tonumber(t.t) end
    end
    R.listNote = #rows == 0 and "No more rounds." or nil
    R.FillList()
end
function R.List(older)
    R.listWanted = true
    if not older then R.listRows, R.listOldest = {}, nil end
    R.Ask(older and ("tape:list:" .. string.format("%d", older)) or "tape:list") -- tapeserve takes bare digits only
    if IsValid(R.listFrame) then return R.FillList() end
    if not vgui or not vgui.Create then return end
    local f = vgui.Create("DFrame")
    if not IsValid(f) then return end
    f:SetSize(math.min(ScrW() - 40, 900), math.min(ScrH() - 40, 560))
    f:Center()
    f:SetTitle("Round replays (BETA) - double-click a round to watch it")
    f:MakePopup()
    f.OnClose = function() R.listWanted = false end
    local lv = vgui.Create("DListView", f)
    lv:Dock(FILL)
    lv:SetMultiSelect(false)
    for _, col in ipairs({"Round", "When", "Map", "Mode", "Length", "Players"}) do lv:AddColumn(col) end
    lv.DoDoubleClick = function(_, _, row) if row and row.zcRid then f:Close() V.OpenRound(row.zcRid) end end
    local more = vgui.Create("DButton", f)
    more:Dock(BOTTOM)
    more:SetText("Older rounds")
    more.DoClick = function() if R.listOldest then R.List(R.listOldest) end end
    f.zcList = lv
    R.listFrame = f
    R.FillList()
end
function R.FillList()
    local f = R.listFrame
    if not IsValid(f) or not IsValid(f.zcList) then return end
    local lv = f.zcList
    lv:Clear()
    for _, t in ipairs(R.listRows or {}) do
        local len = tonumber(t.len)
        local row = lv:AddLine(t.id, t.t and os.date("%d %b %H:%M", tonumber(t.t)) or "?", tostring(t.map or "?") .. ((t.map and t.map ~= game.GetMap()) and " (other map)" or ""),
            tostring(t.mode or "?"), len and R.Clock(len * 100) or "?", tostring(t.players or "?"))
        if row then row.zcRid = t.id end
    end
    if R.listNote then f:SetTitle("Round replays (BETA) - " .. R.listNote) end
end
concommand.Add("zc_replay", function(_, _, args)
    local a1 = string.Trim(args and args[1] or "")
    if a1 == "" then return R.List() end
    if a1 == "resume" then
        local r = R.resume
        if not r then return MsgN("[Replay] nothing to resume.") end
        return V.OpenRound(r.rid, r.cs, r)
    end
    local when
    local a2 = args and args[2] or ""
    if a2 ~= "" then
        when = V.Tape and V.Tape.ParseTime and V.Tape.ParseTime(a2)
        if not when then return MsgN("[Replay] could not read the time '" .. a2 .. "'. Use m:ss, or seconds.") end
    end
    V.OpenRound(a1, when)
end)
concommand.Add("zc_replay_stats", function()
    for _, row in ipairs({{"think (stream + pose + cull)", R.stats.think}, {"hud", R.stats.hud}, {"render (fullscreen)", V.FullStats}}) do
        local s = row[2]
        if s then MsgN(string.format("[Replay] %s: frames=%d avg=%.2fms max=%.2fms", row[1], s.n, s.n > 0 and s.sum / s.n or 0, s.max)) end
    end
    local rs = R.open
    if rs and rs.chunks then
        local ready = 0
        for _, c in ipairs(rs.chunks) do if c.state == "ready" then ready = ready + 1 end end
        MsgN(string.format("[Replay] round %s: %d/%d chunks decoded, window %s-%s, actors %d", rs.rid, ready, #rs.chunks, tostring(rs.lo), tostring(rs.hi), rs.clip and #rs.clip.actors or 0))
    end
end)
end
]========], 2)
