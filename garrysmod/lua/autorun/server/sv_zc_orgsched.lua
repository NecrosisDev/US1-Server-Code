-- ============================================================
--  ZC ORGSCHED - spread the organism pass across engine ticks
-- ------------------------------------------------------------
--  Stock homigrad runs ALL organisms in ONE frame every 0.1s
--  (tier_0/sv_tier_0.lua "homigrad-organism" Think: gate on CurTime,
--  then the full 10-handler "Org Think" chain for every entry in
--  hg.organism.list). Profiled live 8/26 with 31 players: those
--  burst frames hit 4-9ms of organism work on top of the ~20ms
--  baseline = the 25-33ms late frames during firefights.
--
--  This addon RE-REGISTERS that same Think hook (hook.Add with the
--  same name replaces it - no gamemode file edits) with a
--  round-robin slicer: each engine tick processes a slice of the
--  list sized so every organism still gets thought once per
--  zc_orgsched_interval (default 0.1s = stock cadence). Same math,
--  same rates - handlers already scale by the timeValue argument,
--  and we pass each organism its OWN elapsed time (SysTime delta
--  since ITS last think, x game.GetTimeScale, exactly what stock
--  passed globally per pass). Per-org bookkeeping:
--   * first sight: stamp the clock, skip once (stock's baseline
--     pass behaved the same)
--   * godmode: skip but keep the clock warm, so a cleared godmode
--     resumes with a normal ~0.1s delta like stock
--   * queue holds OWNERS, org looked up live at think time - so
--     entries removed mid-cycle (our cleaner) or replaced on
--     respawn are never touched stale
--  "Org Think Call" (the manual single-org path) is untouched.
--
--  SELF-HEALING INSTALL: a 1s sync timer verifies our function is
--  still the registered hook and (re)installs when the gamemode
--  loads late, a hotload ships new code, or zc_perf disarms over
--  us. zc_orgsched 0 restores the captured stock function live.
--  zc_perf NOTE: arm the profiler AFTER this is installed and the
--  "Think/homigrad-organism" line then measures the slices - the
--  verification is that its 4-9ms spike entries disappear.
--
--  Convars (FCVAR_ARCHIVE, live):
--    zc_orgsched           1    master (0 = stock single-frame pass)
--    zc_orgsched_interval  0.1  per-organism cadence; raising it
--         (e.g. 0.15) genuinely SHEDS organism load - rates stay
--         correct via timeValue, only sim granularity coarsens
--  Serverside only = hotloadable.
-- ============================================================
if not SERVER then return end

ZCORGSCHED = ZCORGSCHED or {}

local cv_on  = CreateConVar("zc_orgsched", "1", FCVAR_ARCHIVE, "Spread the organism pass across engine ticks (0 = stock single-frame pass)", 0, 1)
local cv_int = CreateConVar("zc_orgsched_interval", "0.1", FCVAR_ARCHIVE, "Per-organism think cadence in seconds (stock = 0.1)", 0.05, 1)

local hook_Run = hook.Run
local SysTime = SysTime

local queue, qpos = {}, 1

-- v1.1 SELF-REPORTING TO zc_perf.
-- The profiler wraps hooks by name, but our 1s sync re-installs our own
-- closure over that wrapper and never calls it - so the organism pass
-- was invisible in every capture (it silently landed in "unmeasured").
-- Rather than make Joey run `zc_orgsched 0` before every measurement,
-- we time ourselves and write straight into the profiler's own tables
-- (same shape: stats[key] = {calls, total}, plus frame[key] so the
-- spike log can attribute us too). Costs two SysTime reads, and only
-- while the profiler is actually armed.
local PERF_KEY = "Think/homigrad-organism [orgsched]"

local function perfBegin()
	if ZCPERF and ZCPERF.wrapped and ZCPERF.stats then return SysTime() end
end

local function perfEnd(t0)
	if not t0 then return end
	local stats = ZCPERF and ZCPERF.stats
	if not stats then return end
	local st = stats[PERF_KEY]
	if not st then st = { calls = 0, total = 0 } stats[PERF_KEY] = st end
	local dt = SysTime() - t0
	st.calls = st.calls + 1
	st.total = st.total + dt
	local fr = ZCPERF.frame
	if fr then fr[PERF_KEY] = (fr[PERF_KEY] or 0) + dt end
end

local function schedThink()
	local t0 = perfBegin()
	local list = hg and hg.organism and hg.organism.list
	if not list then perfEnd(t0) return end

	-- rebuild the round-robin queue when the cycle completes
	if qpos > #queue then
		queue, qpos = {}, 1
		for owner in pairs(list) do
			queue[#queue + 1] = owner
		end
		if #queue == 0 then perfEnd(t0) return end
	end

	local ticksPerCycle = math.max(1, math.Round(cv_int:GetFloat() / engine.TickInterval()))
	local slice = math.ceil(#queue / ticksPerCycle)
	local timescale = game.GetTimeScale()
	local now = SysTime()

	for i = 1, slice do
		local owner = queue[qpos]
		if owner == nil then break end
		qpos = qpos + 1

		local org = list[owner] -- live lookup: stale/removed entries skip
		if org then
			if org.godmode then
				org.zc_lastThink = now -- keep the clock warm like stock
			else
				local last = org.zc_lastThink
				org.zc_lastThink = now
				if last then
					hook_Run("Org Think", owner, org, (now - last) * timescale)
				end
			end
		end
	end
	perfEnd(t0)
end

local myClosure = function() schedThink() end -- fresh per file load

local function currentHook()
	local t = hook.GetTable()
	t = t and t["Think"]
	return t and t["homigrad-organism"]
end

local function install()
	local cur = currentHook()
	if cur == nil then return false end -- gamemode hook not registered yet
	if cur ~= ZCORGSCHED.mine then
		ZCORGSCHED.orig = cur -- capture whatever genuinely runs now (stock)
	end
	ZCORGSCHED.mine = myClosure
	hook.Add("Think", "homigrad-organism", myClosure)
	print("[OrgSched] installed - organism pass now spreads across engine ticks (zc_orgsched 0 reverts)")
	return true
end

local function uninstall()
	if currentHook() ~= ZCORGSCHED.mine then ZCORGSCHED.mine = nil return end
	if ZCORGSCHED.orig then
		hook.Add("Think", "homigrad-organism", ZCORGSCHED.orig)
		print("[OrgSched] reverted to the stock single-frame organism pass")
	end
	ZCORGSCHED.mine = nil
end

timer.Create("zc_orgsched_sync", 1, 0, function()
	if cv_on:GetBool() then
		if currentHook() ~= ZCORGSCHED.mine or ZCORGSCHED.mine ~= myClosure then install() end
	else
		uninstall()
	end
end)

print("[OrgSched] loaded - installs once the gamemode's organism hook exists (1s sync)")
