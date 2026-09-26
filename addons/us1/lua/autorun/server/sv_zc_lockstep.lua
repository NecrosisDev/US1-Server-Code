-- ============================================================
--  ZC LOCKSTEP - one load signal, one shed order.
-- ------------------------------------------------------------
--  US1 accumulated a lot of good, independent performance work, and that is
--  exactly the problem: each piece decides on its own when to run and when to
--  back off, and none of them can see each other.
--
--    sv_tick_governor.lua  samples tick + physics every Tick, keeps a rolling
--                          100-sample average and a NORMAL/STRESSED/CRITICAL
--                          state machine with hysteresis - then keeps all of
--                          it in file-locals. Only prop-freezing reads it.
--    zc_tick_budget.lua    runs a real cooperative 2ms/tick drain over four
--                          queues, but its only load input is a one-frame
--                          heuristic: "was the last gap > 1.5x the tick? then
--                          halve the allowance." One noisy frame either way.
--    everything else       (orgsched, gcsmooth, the killcam chunk cutter, the
--                          Justice lazy-save and shadow drain, the netopt and
--                          gasoline refreshes, the corpse sleeper) runs on a
--                          fixed private cadence and never backs off at all.
--
--  So under real load the server had one good load signal, one good budget,
--  and no wire between them. This file is that wire. It adds NO new sampling
--  and NO new drain loop of its own for the existing queues - it reads the
--  governor's answer and drives the budget's own published control surface.
--
--  WHAT IT DOES
--   1. Reads TickGov.Level() (0 normal / 1 stressed / 2 critical).
--   2. Sets zc_tick_budget_ms to the tier value for that level, so the
--      incumbent drain shrinks and grows with real measured load instead of
--      with the last single frame. The owner's own baseline value is captured
--      before we ever write, and restored on zc_lockstep 0.
--   3. Sheds vFire's expansion work at CRITICAL through ZCTickBudget.Fire's
--      OWN existing shed path (return true without queueing) - the same thing
--      it already does at queue capacity. Burn damage is on vfire's native
--      timer and is never touched.
--   4. Offers ZCLockstep.Every(name, interval, tier, fn) for periodic work,
--      with a stable phase derived from the task NAME so same-interval tasks
--      spread across the interval instead of stacking in one frame, and a
--      tier so they shed in a defined order rather than all at once.
--
--  TIERS (tier 1 is never shed)
--    1  essential   - always runs, every level
--    2  normal      - skipped at CRITICAL
--    3  deferrable  - skipped at STRESSED and CRITICAL
--
--  SAFETY
--   * zc_lockstep 0 is a full revert: baseline budget restored, Fire unwrapped,
--     drain stopped. Nothing it touched stays touched.
--   * zc_lockstep_enforce 0 is observe-only: it computes and logs every
--     decision but writes no convar and sheds nothing.
--   * If the owner changes zc_tick_budget_ms by hand we notice (the value is
--     not what we last wrote), adopt it as the new baseline, and keep our
--     ratios relative to it. The owner's value always wins.
--   * If TickGov is absent or the governor is off, Level() is 0 / missing and
--     this file holds everything at the NORMAL tier. It never sheds blind.
--
--  Convars (FCVAR_ARCHIVE, live):
--    zc_lockstep                 1     master (0 = full revert)
--    zc_lockstep_enforce         0     0 = observe and log only (ships inert)
--    zc_lockstep_stressed_frac   0.60  budget multiplier at STRESSED
--    zc_lockstep_critical_frac   0.30  budget multiplier at CRITICAL
--    zc_lockstep_shed_fire       1     shed vFire expansion at CRITICAL
--    zc_lockstep_task_ms         0.75  per-frame budget for Every() tasks
--  Commands:
--    zc_lockstep_status                admin; also writes data/zc_lockstep/status.json
--
--  Serverside only = hotloadable. Edits NO pinned file: sv_tick_governor.lua
--  gains read-only accessors (it is pinned by nothing), zc_tick_budget.lua is
--  not touched at all (it is pinned to its live hash by zc_perf_pass2_activate.lua).
-- ============================================================
if not SERVER then return end

ZCLockstep = ZCLockstep or {}
local L = ZCLockstep
L.Version = "20260922.1"

local cvOn       = CreateConVar("zc_lockstep", "1", FCVAR_ARCHIVE, "Tie the tick budget and periodic work to the governor's load signal", 0, 1)
-- Ships at 0: the file arrives inert and only observes. This server's house
-- style for anything that can shed work (TickGov's own clutter pass, ChatGuard,
-- sv_karma) is to land it observing and let the owner flip it after reading a
-- status line. Set to 1 to actually drive the budget and shed.
local cvEnforce  = CreateConVar("zc_lockstep_enforce", "0", FCVAR_ARCHIVE, "0 = observe and log only, change nothing", 0, 1)
local cvStressed = CreateConVar("zc_lockstep_stressed_frac", "0.60", FCVAR_ARCHIVE, "Budget multiplier while STRESSED", 0.1, 1)
local cvCritical = CreateConVar("zc_lockstep_critical_frac", "0.30", FCVAR_ARCHIVE, "Budget multiplier while CRITICAL", 0.1, 1)
local cvFloor    = CreateConVar("zc_lockstep_floor_ms", "0.5", FCVAR_ARCHIVE, "Never drive the tick budget below this, whatever the level", 0.25, 5)
local cvShedFire = CreateConVar("zc_lockstep_shed_fire", "1", FCVAR_ARCHIVE, "Shed vFire expansion work at CRITICAL", 0, 1)
local cvTaskMs   = CreateConVar("zc_lockstep_task_ms", "0.75", FCVAR_ARCHIVE, "Per-frame budget for ZCLockstep.Every tasks", 0.1, 5)

local SysTime, CurTime = SysTime, CurTime

L.tasks      = L.tasks or {}
L.order      = L.order or {}
L.cursor     = L.cursor or 1
L.level      = L.level or 0
L.levelName  = L.levelName or "NORMAL"
L.changes    = L.changes or 0
L.firedShed  = L.firedShed or 0
L.taskSkips  = L.taskSkips or 0
L.lastDecision = L.lastDecision or "none yet"

--------------------------------------------------------------------------------
-- The load signal. One source, read-only, with an explicit no-signal answer.
--------------------------------------------------------------------------------

-- Returns level (0/1/2), a name, and whether the governor is actually supplying
-- it. `supplied=false` means TickGov is missing, too old to export, or OFF - in
-- which case we hold at NORMAL rather than guessing from a private heuristic.
function L.Read()
	local gov = TickGov
	if not gov or not isfunction(gov.Level) or not isfunction(gov.State) then
		return 0, "NO-SIGNAL", false
	end
	local state = gov.State()
	if state == "OFF" then return 0, "GOVERNOR-OFF", false end
	return gov.Level(), state, true
end

--------------------------------------------------------------------------------
-- Half 1: drive the incumbent budget's own control surface.
--------------------------------------------------------------------------------

-- Resolved LAZILY, never at file scope. lua/autorun/server/ loads
-- alphabetically, so this file loads BEFORE zc_tick_budget.lua and the convar
-- does not exist yet while we are being read. Resolving it here would bind nil
-- for the lifetime of the server and silently disable half of this file.
local budgetCv
local function budgetConVar()
	if not budgetCv then budgetCv = GetConVar("zc_tick_budget_ms") end
	return budgetCv
end

-- zc_tick_budget_ms is FCVAR_ARCHIVE, so whatever value is live at shutdown is
-- what the server boots with next time. If we are CRITICAL when the box goes
-- down, 0.6 gets archived, and a naive next boot would capture 0.6 as "the
-- owner's baseline" and shed 30% off THAT - a ratchet that walks the budget to
-- the floor over a few restarts, with nothing in the logs to show why.
--
-- Two defences. The ShutDown hook below restores the baseline so the archived
-- value is always the owner's. This file covers the case that hook cannot: a
-- crash. We record what we believe the baseline is and what we last wrote, and
-- on boot, if the live value is one of OUR writes, we restore the baseline
-- instead of adopting it. A value that is not one of our writes is the owner's
-- (server.cfg, console, rcon) and always wins.
-- Only the baseline is persisted, and only when it changes (rare). We do NOT
-- write a file on every level change: file.Write costs 2-23ms on this box, and
-- spending that during CRITICAL - the one moment we are trying to save time -
-- would be self-defeating.
local PERSIST = "zc_lockstep/baseline.txt"

local function persist()
	file.CreateDir("zc_lockstep")
	file.Write(PERSIST, util.TableToJSON({ baseline = L.baseline, version = L.Version }))
end

-- A boot value that equals one of the shed values we could have written is
-- treated as ours and rolled back to the recorded baseline. A value that
-- matches nothing we would write is the owner's and is adopted as-is.
-- Known, accepted imprecision: if the owner hand-sets exactly baseline*frac we
-- read it as our own and restore. The ShutDown hook makes this path rare (it
-- only runs after an actual crash) and zc_lockstep_status reports `recovered`.
local function recover(current)
	local raw = file.Read(PERSIST, "DATA")
	if not raw then return current end
	local rec = util.JSONToTable(raw)
	if not istable(rec) or not isnumber(rec.baseline) then return current end
	local base = rec.baseline
	if math.abs(current - base) < 0.001 then return current end
	for _, frac in ipairs({ cvStressed:GetFloat(), cvCritical:GetFloat() }) do
		if math.abs(current - base * frac) < 0.001 then
			L.recovered = (L.recovered or 0) + 1
			print(string.format(
				"[Lockstep] boot value %.2fms is our own shed value - restoring baseline %.2fms (previous run did not shut down cleanly)",
				current, base))
			return base
		end
	end
	return current
end

-- Capture the owner's value ONCE, before we ever write it. L survives hotloads,
-- so a re-include never mistakes one of our own tier values for the baseline.
local function baseline()
	local cv = budgetConVar()
	if not cv then return nil end
	if L.baseline == nil then
		L.baseline = recover(cv:GetFloat())
		L.lastWrote = nil
		if math.abs(L.baseline - cv:GetFloat()) > 0.001 then cv:SetFloat(L.baseline) end
		persist()
	end
	-- The owner moved it by hand (it is not what we last wrote): adopt it.
	if L.lastWrote and math.abs(cv:GetFloat() - L.lastWrote) > 0.001 then
		L.baseline = cv:GetFloat()
		L.lastWrote = nil
		L.adopted = (L.adopted or 0) + 1
		persist()
	end
	return L.baseline
end

-- The floor matters because our multiplier is NOT the only backoff in play:
-- zc_tick_budget.lua's own B.Step independently halves its allowance after a
-- late tick, and a late tick is exactly what CRITICAL means. Left alone the two
-- compound (0.30 x 0.5 = 0.15x baseline), which can push the drain below what
-- it needs to keep the fire queue moving toward B.maxQueued 2048 - shedding via
-- overflow under precisely the load this file exists to relieve. We shed on
-- purpose; we do not stack two backoffs into an accidental stall.
local function targetBudget(level)
	local base = baseline()
	if not base then return nil end
	local target = base
	if level >= 2 then target = base * cvCritical:GetFloat()
	elseif level >= 1 then target = base * cvStressed:GetFloat() end
	return math.max(target, math.min(cvFloor:GetFloat(), base))
end

local function restoreBaseline()
	local cv = budgetConVar()
	if cv and L.baseline ~= nil and L.lastWrote ~= nil then
		cv:SetFloat(L.baseline)
		L.lastWrote = nil
	end
end

--------------------------------------------------------------------------------
-- Half 2: shed vFire expansion at CRITICAL, through the budget's OWN shed path.
--
-- ZCTickBudget.Fire already returns true-without-queueing when it is at
-- capacity ("shed expansion/merging work; never shed burn damage"). Callers in
-- vfire/shared.lua run the think inline only when Fire returns FALSE, so
-- returning true is the established way to drop the work. We reuse that exact
-- contract instead of inventing a second one, and only for the three expansion
-- thinks - burn damage never comes through here.
--------------------------------------------------------------------------------

local function installFireShed()
	local B = ZCTickBudget
	if not B or not isfunction(B.Fire) then return false end
	if L.fireOriginal and B.Fire == L.fireWrapper then return true end
	if L.fireWrapper and B.Fire ~= L.fireWrapper then
		-- Someone else rebound Fire under us; take their version as the new original.
		L.fireOriginal = nil
	end
	local original = L.fireOriginal or B.Fire
	L.fireOriginal = original
	local wrapper = function(e, key, argument)
		if cvOn:GetBool() and cvEnforce:GetBool() and cvShedFire:GetBool() and L.level >= 2 then
			L.firedShed = L.firedShed + 1
			return true -- shed: handled, do not run inline. Burn damage is elsewhere.
		end
		return original(e, key, argument)
	end
	L.fireWrapper = wrapper
	B.Fire = wrapper
	return true
end

local function removeFireShed()
	local B = ZCTickBudget
	if not B or not L.fireOriginal then return end
	if B.Fire == L.fireWrapper then B.Fire = L.fireOriginal end
	L.fireWrapper, L.fireOriginal = nil, nil
end

--------------------------------------------------------------------------------
-- Half 3: the tiered periodic registry.
--
-- Phase comes from the task NAME (stable across restarts and registration
-- order), so two tasks that share an interval land in different frames and
-- stay there. Same idea as the Trauma repo's hg.stagger, which was written for
-- this exact failure after playtest 2 - US1 has no copy of it, so the trick is
-- reproduced here rather than the whole scheduler being ported in.
--------------------------------------------------------------------------------

local function namePhase(name)
	return (tonumber(util.CRC(name)) or 0) % 4096 / 4096
end

-- timer.Create-compatible: re-registering the same name replaces the task.
function L.Every(name, interval, tier, fn)
	if not isstring(name) or name == "" then error("lockstep task name must be a non-empty string", 2) end
	if not isnumber(interval) or interval <= 0 then error("lockstep interval must be positive", 2) end
	if not isfunction(fn) then error("lockstep callback must be a function", 2) end
	tier = math.Clamp(math.floor(tonumber(tier) or 2), 1, 3)

	local task = L.tasks[name]
	if not task then
		task = { name = name }
		L.tasks[name] = task
		L.order[#L.order + 1] = name
	end
	task.interval = interval
	task.tier     = tier
	task.fn       = fn
	task.phase    = namePhase(name)
	task.nextRun  = CurTime() + interval * (0.1 + 0.9 * task.phase)
	task.calls    = task.calls or 0
	task.skips    = task.skips or 0
	task.totalMs  = task.totalMs or 0
	task.worstMs  = task.worstMs or 0
	return task
end

function L.Remove(name)
	if not L.tasks[name] then return false end
	L.tasks[name] = nil
	for i = #L.order, 1, -1 do
		if L.order[i] == name then table.remove(L.order, i) break end
	end
	if L.cursor > #L.order then L.cursor = 1 end
	return true
end

-- tier 1 always; tier 2 unless CRITICAL; tier 3 only while NORMAL.
local function tierRuns(tier, level)
	if tier <= 1 then return true end
	if tier == 2 then return level < 2 end
	return level < 1
end
L.TierRuns = tierRuns

local function drainTasks(level)
	local count = #L.order
	if count == 0 then return end
	local budget = cvTaskMs:GetFloat() / 1000
	if budget <= 0 then return end

	local start = SysTime()
	local deadline = start + budget
	local now = CurTime()
	if L.cursor > count then L.cursor = 1 end

	local index, scanned = L.cursor, 0
	while scanned < count do
		local task = L.tasks[L.order[index]]
		if task and now >= task.nextRun then
			if cvEnforce:GetBool() and not tierRuns(task.tier, level) then
				task.skips = task.skips + 1
				L.taskSkips = L.taskSkips + 1
				-- Re-arm from now: a shed task runs next cycle, it does not
				-- accumulate a catch-up burst for when load recovers.
				task.nextRun = now + task.interval
			else
				local at = SysTime()
				local ok, err = pcall(task.fn)
				local ms = (SysTime() - at) * 1000
				task.calls = task.calls + 1
				task.totalMs = task.totalMs + ms
				if ms > task.worstMs then task.worstMs = ms end
				task.nextRun = now + task.interval
				if not ok then
					task.errors = (task.errors or 0) + 1
					ErrorNoHalt(string.format("[Lockstep] task %s failed: %s\n", task.name, tostring(err)))
				end
			end
		end
		index = index % count + 1
		scanned = scanned + 1
		if SysTime() >= deadline then break end
	end
	L.cursor = index
	L.lastTaskMs = (SysTime() - start) * 1000
end

--------------------------------------------------------------------------------
-- The single evaluation. Runs on the governor's own 2s cadence, not faster:
-- the signal it reads is a 100-sample rolling average with hysteresis, so
-- sampling it more often would only add jitter, not resolution.
--------------------------------------------------------------------------------

local function evaluate()
	if not cvOn:GetBool() then
		if L.installed then
			restoreBaseline()
			removeFireShed()
			L.installed = false
			L.level, L.levelName = 0, "DISABLED"
			print("[Lockstep] disabled - tick budget restored to " .. tostring(L.baseline) .. "ms, fire shed removed")
		end
		return
	end

	if not L.installed then
		baseline()
		installFireShed()
		L.installed = true
		print(string.format("[Lockstep] %s active - baseline budget %.2fms, governor signal %s",
			L.Version, L.baseline or -1, (select(3, L.Read())) and "present" or "ABSENT"))
	end

	local level, name, supplied = L.Read()
	if level ~= L.level then
		L.changes = L.changes + 1
		L.levelChangedAt = CurTime()
	end
	L.level, L.levelName, L.supplied = level, name, supplied

	local target = targetBudget(level)
	if target then
		if cvEnforce:GetBool() then
			if L.lastWrote == nil or math.abs(target - L.lastWrote) > 0.001 then
				local cv = budgetConVar()
				cv:SetFloat(target)
				-- Record what the convar ACTUALLY holds, not what we asked for.
				-- zc_tick_budget_ms is declared with min 0.25, so a low enough
				-- target comes back clamped. Storing the unclamped intent would
				-- make the "owner moved it by hand" check below fire on our own
				-- write and overwrite L.baseline with the clamped value -
				-- losing the owner's real baseline for good.
				L.lastWrote = cv:GetFloat()
			end
			L.lastDecision = string.format("%s -> budget %.2fms", name, target)
		else
			L.lastDecision = string.format("%s -> WOULD set budget %.2fms (observe-only)", name, target)
		end
	end
end

timer.Create("ZCLockstep_Evaluate", 2, 0, function()
	local ok, err = pcall(evaluate)
	if not ok then ErrorNoHalt("[Lockstep] evaluate failed: " .. tostring(err) .. "\n") end
end)

hook.Add("Think", "ZCLockstep_Drain", function()
	if not cvOn:GetBool() then return end
	drainTasks(L.level)
end)

-- Put the owner's baseline back before the engine archives convars, so a
-- shutdown taken while STRESSED or CRITICAL cannot persist a shed value as
-- next boot's starting point. `recover()` above is only the crash fallback.
hook.Add("ShutDown", "ZCLockstep_RestoreBudget", function()
	restoreBaseline()
end)

--------------------------------------------------------------------------------
-- Status
--------------------------------------------------------------------------------

function L.Snapshot()
	local avg, physics, target = 0, 0, engine.TickInterval()
	if TickGov and isfunction(TickGov.Metrics) then avg, physics, target = TickGov.Metrics() end
	local tasks = {}
	for _, name in ipairs(L.order) do
		local t = L.tasks[name]
		if t then
			tasks[name] = { tier = t.tier, interval = t.interval, phase = t.phase, calls = t.calls,
				skips = t.skips, avgMs = t.calls > 0 and (t.totalMs / t.calls) or 0,
				worstMs = t.worstMs, errors = t.errors or 0 }
		end
	end
	return {
		version = L.Version, enabled = cvOn:GetBool(), enforcing = cvEnforce:GetBool(),
		level = L.level, levelName = L.levelName, signalSupplied = L.supplied == true,
		players = #player.GetAll(), map = game.GetMap(),
		tickAvgMs = avg * 1000, physicsMs = physics * 1000, tickTargetMs = target * 1000,
		baselineBudgetMs = L.baseline,
		currentBudgetMs = budgetConVar() and budgetConVar():GetFloat() or nil,
		lastWroteMs = L.lastWrote, ownerOverrides = L.adopted or 0, recovered = L.recovered or 0,
		levelChanges = L.changes, fireShedByUs = L.firedShed, taskSkips = L.taskSkips,
		lastTaskMs = L.lastTaskMs or 0, lastDecision = L.lastDecision, tasks = tasks,
	}
end

concommand.Add("zc_lockstep_status", function(ply)
	if IsValid(ply) and not ply:IsAdmin() then return end
	local r = L.Snapshot()
	file.CreateDir("zc_lockstep")
	file.Write("zc_lockstep/status.json", util.TableToJSON(r, true))
	local text = string.format(
		"[Lockstep] %s enabled=%s enforcing=%s | level %d (%s, signal=%s) | tick %.1fms/%.1fms physics %.1fms | budget %.2f -> %.2fms (baseline %.2f) | fire shed %d | task skips %d | %d tasks | %s",
		r.version, tostring(r.enabled), tostring(r.enforcing), r.level, r.levelName, tostring(r.signalSupplied),
		r.tickAvgMs, r.tickTargetMs, r.physicsMs, r.baselineBudgetMs or -1, r.currentBudgetMs or -1,
		r.baselineBudgetMs or -1, r.fireShedByUs, r.taskSkips, #L.order, r.lastDecision)
	if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, text) else print(text) end
	print("[Lockstep] details in data/zc_lockstep/status.json")
end, nil, "Admin: print Lockstep load level and budget (also written to data/zc_lockstep/status.json).")

print("[Lockstep] " .. L.Version .. " loaded - zc_lockstep_status to inspect, zc_lockstep 0 to revert")
