-- ============================================================
--  ZC SPIKEWATCH v2  (tick-spike autopsy + GC test)  |  server-side
-- ------------------------------------------------------------
--  Measures wall-clock BETWEEN ticks (SysTime delta in Think) = the FULL tick
--  duration, so it catches engine/physics/timer/GC spikes that per-hook Lua
--  profilers can't see. On a tick past the threshold it snapshots state and
--  correlates causes (round change / mass-spawn / ragdoll / GC).
--
--  v2 adds:
--   * GC ATTRIBUTION - per spike it records if a garbage-collection sweep ran
--     on that tick (heap dropped hard). The report shows what % of spikes were
--     GC. If that number is high, GC is your choppiness.
--   * SPAWN CLASS breakdown - on a mass-spawn spike it names the top entity
--     classes that spawned, so you can find what's dumping entities.
--   * A LIVE GC-SMOOTHING TEST - `spikewatch_gc 1` runs one incremental GC
--     step per tick, which keeps the collector caught up so it never does a big
--     stop-the-world sweep. Toggle it, watch the spike rate in spikewatch_report.
--     If spikes drop, GC was the cause and we make it permanent. Reversible.
--
--  Commands (superadmin console):
--    spikewatch_start [ms]   watch (default 40ms threshold)
--    spikewatch_stop
--    spikewatch_report       print + write data/spikewatch/report_<t>.txt
--    spikewatch_clear
--    spikewatch_gc [0/1]     toggle the live incremental-GC smoothing test
-- ============================================================
if not SERVER then return end

ZCSpike = ZCSpike or {}
ZCSpike.active    = ZCSpike.active or false
ZCSpike.threshold = ZCSpike.threshold or 0.040
ZCSpike.spikes    = ZCSpike.spikes or {}
ZCSpike.keep      = 150
ZCSpike.worst     = ZCSpike.worst or 0
ZCSpike.gcStep    = ZCSpike.gcStep or false     -- live GC-smoothing test
ZCSpike._last     = nil
ZCSpike._prevHeap = ZCSpike._prevHeap or nil     -- KB, previous tick
ZCSpike._roundAt  = ZCSpike._roundAt or 0
ZCSpike._base     = ZCSpike._base or { n = 0, ents = 0, rag = 0, props = 0 }

-- ---- spawn-rate + class tracker (4 x 0.25s buckets = last ~1s) ----
local spawnBuckets = { 0, 0, 0, 0 }
local classBuckets = { {}, {}, {}, {} }
local spawnCur = 1
hook.Add("OnEntityCreated", "ZCSpike_Spawns", function(e)
	spawnBuckets[spawnCur] = spawnBuckets[spawnCur] + 1
	local ok, c = pcall(function() return IsValid(e) and e:GetClass() or "?" end)
	if ok and c then
		local b = classBuckets[spawnCur]
		b[c] = (b[c] or 0) + 1
	end
end)
timer.Create("ZCSpike_SpawnRotate", 0.25, 0, function()
	spawnCur = (spawnCur % 4) + 1
	spawnBuckets[spawnCur] = 0
	classBuckets[spawnCur] = {}
end)
local function spawnsLast1s()
	return spawnBuckets[1] + spawnBuckets[2] + spawnBuckets[3] + spawnBuckets[4]
end
local function topSpawnClasses()
	local merged = {}
	for i = 1, 4 do for c, n in pairs(classBuckets[i]) do merged[c] = (merged[c] or 0) + n end end
	local arr = {}
	for c, n in pairs(merged) do arr[#arr + 1] = { c = c, n = n } end
	table.sort(arr, function(a, b) return a.n > b.n end)
	local parts = {}
	for i = 1, math.min(3, #arr) do parts[#parts + 1] = arr[i].c .. " x" .. arr[i].n end
	return table.concat(parts, ", ")
end

-- ---- round-change stamp ----
local function stampRound() ZCSpike._roundAt = SysTime() end
hook.Add("ZB_StartRound", "ZCSpike_Round", stampRound)
hook.Add("ZB_EndRound",   "ZCSpike_RoundEnd", stampRound)

-- ---- snapshot (only on a spike; ok to be heavy) ----
local function snapshot(dtMS, gcDropMB)
	local ragdolls, props, npcs = 0, 0, 0
	for _, e in ipairs(ents.GetAll()) do
		if e:IsRagdoll() then ragdolls = ragdolls + 1
		elseif e:IsNPC() then npcs = npcs + 1
		else
			local c = e:GetClass()
			if c == "prop_physics" or c == "prop_ragdoll" then props = props + 1 end
		end
	end
	local alive = 0
	for _, p in ipairs(player.GetAll()) do if p:Alive() then alive = alive + 1 end end
	local spawns = spawnsLast1s()
	return {
		t = os.time(), dt = math.Round(dtMS, 1),
		humans = #player.GetHumans(), alive = alive,
		ents = ents.GetCount(), ragdolls = ragdolls, props = props, npcs = npcs,
		spawns1s = spawns,
		topSpawns = (spawns >= 5) and topSpawnClasses() or nil,
		round = (zb and zb.CROUND) or "?",
		sinceRnd = math.Round(SysTime() - (ZCSpike._roundAt or 0), 1),
		heapMB = math.Round(collectgarbage("count") / 1024, 1),
		gc = (gcDropMB or 0) >= 5,       -- a collection swept this tick
		gcDrop = math.Round(gcDropMB or 0, 1),
	}
end

-- ---- the watcher ----
hook.Add("Think", "ZCSpike_Watch", function()
	-- keep GC incremental if the live test is on (do this even when not watching)
	if ZCSpike.gcStep then collectgarbage("step", 0) end
	if not ZCSpike.active then return end

	local now = SysTime()
	local heapKB = collectgarbage("count")
	local prevHeap = ZCSpike._prevHeap
	ZCSpike._prevHeap = heapKB

	local last = ZCSpike._last
	ZCSpike._last = now
	if not last then return end

	local dt = now - last
	if dt >= 2.0 or #player.GetHumans() == 0 then return end

	if dt >= ZCSpike.threshold then
		local gcDropMB = (prevHeap and (prevHeap - heapKB) / 1024) or 0   -- MB freed this tick
		local snap = snapshot(dt * 1000, gcDropMB)
		ZCSpike.spikes[#ZCSpike.spikes + 1] = snap
		if #ZCSpike.spikes > ZCSpike.keep then table.remove(ZCSpike.spikes, 1) end
		if snap.dt > ZCSpike.worst then ZCSpike.worst = snap.dt end
	end
end)

-- ---- calm-state baseline ----
timer.Create("ZCSpike_Baseline", 20, 0, function()
	if not ZCSpike.active or #player.GetHumans() == 0 then return end
	if (SysTime() - (ZCSpike._last or 0)) > 1 then return end
	local ragdolls, props = 0, 0
	for _, e in ipairs(ents.GetAll()) do
		if e:IsRagdoll() then ragdolls = ragdolls + 1
		elseif e:GetClass() == "prop_physics" then props = props + 1 end
	end
	local b = ZCSpike._base
	b.n = b.n + 1
	b.ents  = b.ents  + (ents.GetCount() - b.ents)  / b.n
	b.rag   = b.rag   + (ragdolls        - b.rag)   / b.n
	b.props = b.props + (props           - b.props) / b.n
end)

-- ---------------- commands ----------------
local function isAdmin(ply) return not IsValid(ply) or ply:IsSuperAdmin() end

concommand.Add("spikewatch_start", function(ply, _, args)
	if not isAdmin(ply) then return end
	local ms = tonumber(args[1])
	if ms and ms > 0 then ZCSpike.threshold = ms / 1000 end
	ZCSpike.active = true ZCSpike._last = nil ZCSpike._prevHeap = nil
	print(string.format("[SpikeWatch] watching - threshold %dms. Play some busy rounds, then spikewatch_report.",
		math.Round(ZCSpike.threshold * 1000)))
end)

concommand.Add("spikewatch_stop", function(ply)
	if not isAdmin(ply) then return end
	ZCSpike.active = false
	print("[SpikeWatch] stopped. " .. #ZCSpike.spikes .. " spikes on record.")
end)

concommand.Add("spikewatch_clear", function(ply)
	if not isAdmin(ply) then return end
	ZCSpike.spikes = {} ZCSpike.worst = 0
	ZCSpike._base = { n = 0, ents = 0, rag = 0, props = 0 }
	print("[SpikeWatch] cleared.")
end)

concommand.Add("spikewatch_gc", function(ply, _, args)
	if not isAdmin(ply) then return end
	if args[1] == "1" or args[1] == "on" then ZCSpike.gcStep = true
	elseif args[1] == "0" or args[1] == "off" then ZCSpike.gcStep = false
	else ZCSpike.gcStep = not ZCSpike.gcStep end
	print("[SpikeWatch] live incremental-GC smoothing -> " .. (ZCSpike.gcStep and "ON" or "OFF") ..
		(ZCSpike.gcStep and "  (spikewatch_clear, let it run, spikewatch_report - did the GC % and spike rate drop?)" or ""))
end)

concommand.Add("spikewatch_report", function(ply)
	if not isAdmin(ply) then return end
	local s = ZCSpike.spikes
	local out = {}
	local function line(str) out[#out + 1] = str print("[SpikeWatch] " .. str) end

	line(string.format("==== report %s | %d spikes | worst %.1fms | threshold %dms | %s | gc-smoothing %s ====",
		os.date("%Y-%m-%d %H:%M:%S"), #s, ZCSpike.worst, math.Round(ZCSpike.threshold * 1000),
		ZCSpike.active and "WATCHING" or "stopped", ZCSpike.gcStep and "ON" or "off"))

	if #s == 0 then
		line("no spikes recorded - spikewatch_start, play busy rounds, then spikewatch_report")
	else
		local nearRound, massSpawn, ragHeavy, gcHits, gcKnown = 0, 0, 0, 0, 0
		local sumDt, sumRag, sumSpawn = 0, 0, 0
		for _, e in ipairs(s) do
			sumDt = sumDt + e.dt sumRag = sumRag + e.ragdolls sumSpawn = sumSpawn + e.spawns1s
			if e.sinceRnd >= 0 and e.sinceRnd <= 3 then nearRound = nearRound + 1 end
			if e.spawns1s >= 15 then massSpawn = massSpawn + 1 end
			if e.ragdolls >= 20 then ragHeavy = ragHeavy + 1 end
			if e.gc ~= nil then gcKnown = gcKnown + 1 if e.gc then gcHits = gcHits + 1 end end
		end
		local n = #s
		local b = ZCSpike._base
		line(string.format("avg spike %.0fms | avg ragdolls %.1f (calm baseline %.1f) | avg spawns/1s %.1f",
			sumDt / n, sumRag / n, b.rag, sumSpawn / n))
		line(string.format("CAUSES: GC-sweep %d/%d (%.0f%%) | round-change %d | mass-spawn %d | ragdoll-pile %d",
			gcHits, gcKnown, gcKnown > 0 and (100 * gcHits / gcKnown) or 0, nearRound, massSpawn, ragHeavy))
		-- verdict
		if gcKnown > 0 and (gcHits / gcKnown) >= 0.4 then
			line(">> VERDICT: GARBAGE COLLECTION is the main cause. Try:  spikewatch_gc 1  then spikewatch_clear, play, re-report.")
		elseif nearRound / n >= 0.4 then
			line(">> VERDICT: ROUND TRANSITIONS dominate.")
		elseif massSpawn / n >= 0.4 then
			line(">> VERDICT: MASS-SPAWN bursts dominate - see the spawn classes below.")
		elseif ragHeavy / n >= 0.4 then
			line(">> VERDICT: RAGDOLL/physics load dominates.")
		else
			line(">> VERDICT: mixed / engine+timers+networking - see the rows.")
		end
		line("---- recent spikes (newest last) ----")
		for i = math.max(1, n - 30), n do
			local e = s[i]
			line(string.format("%s  %6.1fms  ents %-4d rag %-3d props %-3d npc %-3d spawns %-3d %s round %-10s +%.0fs heap %.0fMB%s",
				os.date("%H:%M:%S", e.t), e.dt, e.ents, e.ragdolls, e.props, e.npcs, e.spawns1s,
				e.gc and "[GC]" or "    ", tostring(e.round), e.sinceRnd, e.heapMB,
				e.topSpawns and ("  spawned: " .. e.topSpawns) or ""))
		end
	end

	file.CreateDir("spikewatch")
	local fn = "spikewatch/report_" .. os.time() .. ".txt"
	file.Write(fn, table.concat(out, "\n"))
	print("[SpikeWatch] written to data/" .. fn)
end)

print("[SpikeWatch] v2 loaded - superadmin: spikewatch_start ... spikewatch_report ... spikewatch_gc 1 to test the GC fix")
