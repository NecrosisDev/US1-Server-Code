-- ============================================================
-- Tick Governor v2.3: sheds eligible prop physics under sustained
-- tick pressure or physics cost. Physics pressure never expands gib removal.
-- v2.3 adds a mid-round CLUTTER pass that ships INERT (zc_governor_clutter 0
-- counts and logs what it would remove and removes nothing).
--
-- SCOPE: this manages PROP debris + gibs. Corpse ragdolls are
-- owned by the Corpse Sleeper (sv_corpse_sleeper.lua) - the two
-- no longer both touch bodies, so they can't fight over a thaw.
--
-- SAFETY RULES (hard guarantees):
--  * Only ever FREEZES props (never removes them, except the
--    existing narrow gib sweep under critical load)
--  * Freezes only AWAKE, settled-age debris - asleep props are
--    already free, so leaving them movable costs nothing
--  * A frozen prop thaws INSTANTLY + FULLY the moment a player
--    touches it (damage / use / physgun / grab-drag), then holds
--    a grace window so it can't re-freeze mid-interaction
--  * Physics pressure: stressed at 25%, critical at 50% of tick budget
--  * Recovery requires three healthy evaluations below 15% physics budget
--  * zc_governor 0 stops further enforcement (interaction thaw remains)
--
-- Commands: zc_governor_status  (superadmin)
-- Convars:  zc_governor (1)
--           zc_governor_freeze_props (1)
--           zc_governor_cap_props_stressed (30)  zc_governor_cap_props_critical (15)
--           zc_governor_grace (12)  [seconds a touched prop stays thawed]
-- ============================================================
if not SERVER then return end

local cvEnabled = CreateConVar("zc_governor", "1", FCVAR_ARCHIVE, "Tick governor on/off")
local cvProps   = CreateConVar("zc_governor_freeze_props", "1", FCVAR_ARCHIVE, "Freeze awake debris props under load")
local cvPropS   = CreateConVar("zc_governor_cap_props_stressed", "30", FCVAR_ARCHIVE, "Awake prop cap when stressed")
local cvPropC   = CreateConVar("zc_governor_cap_props_critical", "15", FCVAR_ARCHIVE, "Awake prop cap when critical")
local cvGrace   = CreateConVar("zc_governor_grace", "12", FCVAR_ARCHIVE, "Seconds a touched prop stays thawed before it may re-freeze")

-- ---------------- CLUTTER PASS convars (observe-only by default) ----------------
-- zc_governor_clutter 0 = OBSERVE: count and log candidates, remove NOTHING. 1 = act.
-- Evidence for shipping at 0 (measured 2026-09-22 from all 22 `census now` blocks in the
-- zc_perf captures): awake prop_physics peaks at 11 against this file's own caps of 30 and
-- 15, so EnforcePropCap can essentially never fire, and total prop_ragdoll peaks at 29.
-- Accumulation shows up only in the one sagging capture (ttt_rooftops_2016_v1 21:50:41,
-- header "tick 32.8 < 45"): prop_physics +248/-36 in 60 s, 2897 edicts against a ~2500
-- floor - and it had self-corrected to 2526 eleven minutes later. Nobody has ever measured
-- what REMOVING an entity buys on this box, so the honest first step is to count the
-- removable ones under load. That is exactly what 0 does.
local cvClutter  = CreateConVar("zc_governor_clutter", "0", FCVAR_ARCHIVE, "Mid-round clutter pass: 0 = observe and log only, 1 = actually remove", 0, 1)
local cvClutDist = CreateConVar("zc_governor_clutter_dist", "1500", FCVAR_ARCHIVE, "Clutter must be at least this far from EVERY conscious player", 256, 16384)
local cvClutAge  = CreateConVar("zc_governor_clutter_age", "45", FCVAR_ARCHIVE, "Minimum entity age in seconds before it can count as clutter", 10, 600)
local cvClutMax  = CreateConVar("zc_governor_clutter_budget", "12", FCVAR_ARCHIVE, "Maximum removals per pass (matches the corpse sleeper's batch of 12)", 1, 64)
local cvClutMs   = CreateConVar("zc_governor_clutter_ms", "1.0", FCVAR_ARCHIVE, "Wall-clock budget in ms for one clutter scan", 0.1, 10)

-- ledger survives hotloads so we never lose track of what WE froze
TickGov = TickGov or {}
local GovFrozen = TickGov.frozen or {}
TickGov.frozen  = GovFrozen
TickGov.frozenTotal = TickGov.frozenTotal or 0
TickGov.sweptTotal  = TickGov.sweptTotal or 0
TickGov.clutterSeen    = TickGov.clutterSeen or 0
TickGov.clutterRemoved = TickGov.clutterRemoved or 0
TickGov.clutterPeak    = TickGov.clutterPeak or 0
TickGov.clutterLast    = TickGov.clutterLast or 0

local samples, physicsSamples, sIdx, sCount = {}, {}, 0, 0
local recoveryPasses = 0
local lastTick = SysTime()
local state = "NORMAL"

hook.Add("Tick", "TickGov_Sample", function()
	local now = SysTime()
	sIdx = (sIdx % 100) + 1
	samples[sIdx] = now - lastTick
	local physics = physenv.GetLastSimulationTime()
	physicsSamples[sIdx] = physics >= 0 and physics < math.huge and physics or 0
	sCount = math.min(sCount + 1, 100)
	lastTick = now
end)

local function TickMetrics()
	if sCount < 50 then return 0, 0 end
	local sum, physicsSum = 0, 0
	for i = 1, sCount do
		sum = sum + samples[i]
		physicsSum = physicsSum + physicsSamples[i]
	end
	return sum / sCount, physicsSum / sCount
end

-- ---------------- EXPORTED LOAD SIGNAL (2026-09-22) ----------------
-- This file already answers, 66 times a second, the question every other
-- scheduler on the box needs: how loaded is the server right now. Until now
-- `state` and TickMetrics were file-locals and the only way to read them was
-- the zc_governor_status print, so ZCTickBudget fell back to a raw one-frame
-- gap heuristic and everything else (orgsched, gcsmooth, the killcam cutter,
-- the Justice writers) ran blind. The clutter pass at ClutterPass(loadState)
-- is already an in-file consumer of exactly this value - these accessors just
-- let out-of-file consumers read the same thing instead of each inventing one.
--
-- Read-only by construction: no new sampling, no writes, no hooks, no timers.
-- Nothing above this block changed, so the governor's own behaviour is
-- byte-for-byte what it was.

function TickGov.State()
	return state
end

-- avg tick interval, physics sim time, and the tick target - all in seconds,
-- the same units and the same rolling 100-sample window the governor acts on.
-- Returns 0, 0 until the window has filled (sCount < 50), so a consumer that
-- treats 0 as "no signal yet" gets the right answer during warmup.
function TickGov.Metrics()
	local avg, physics = TickMetrics()
	return avg, physics, engine.TickInterval()
end

-- Shed level for consumers that only want a number: 0 normal, 1 stressed,
-- 2 critical. A disabled governor (state "OFF") reports 0 - if the owner
-- turns the governor off, nothing downstream should start shedding on its own.
function TickGov.Level()
	if state == "CRITICAL" then return 2 end
	if state == "STRESSED" then return 1 end
	return 0
end

-- is a player interacting with this prop right now? homigrad grab-drag sets
-- .isheld + SetPhysicsAttacker; plus a fresh grace stamp or a physgun hold.
local function BeingUsed(ent)
	if ent.isheld then return true end
	if (ent._govGrace or 0) > CurTime() then return true end
	if ent.IsPlayerHolding and ent:IsPlayerHolding() then return true end
	local att = ent.GetPhysicsAttacker and ent:GetPhysicsAttacker(0)
	if IsValid(att) then return true end
	return false
end

-- ---------------- freeze / thaw ----------------
local function RemoveFromFrozen(ent)
	for i = #GovFrozen, 1, -1 do
		if GovFrozen[i] == ent then table.remove(GovFrozen, i) end
	end
end

local function Freeze(ent)
	for i = 0, ent:GetPhysicsObjectCount() - 1 do
		local phys = ent:GetPhysicsObjectNum(i)
		if IsValid(phys) then phys:EnableMotion(false) end
	end
	ent._govFrozen = true
	GovFrozen[#GovFrozen + 1] = ent
end

local function ThawEnt(ent)
	if IsValid(ent) then
		for i = 0, ent:GetPhysicsObjectCount() - 1 do
			local phys = ent:GetPhysicsObjectNum(i)
			if IsValid(phys) then phys:EnableMotion(true) phys:Wake() end
		end
		ent._govFrozen = false
		ent._govGrace  = CurTime() + cvGrace:GetFloat()
	end
	RemoveFromFrozen(ent)
end

-- ---------------- INTERACTION THAW ----------------
local function TouchThaw(ent)
	if not IsValid(ent) then return end
	if ent:GetClass() == "prop_physics" then ent._govGrace = CurTime() + cvGrace:GetFloat() end
	if ent._govFrozen then pcall(ThawEnt, ent) end
end
hook.Add("EntityTakeDamage", "TickGov_ThawDamage",  function(ent) TouchThaw(ent) end)
hook.Add("PlayerUse",        "TickGov_ThawUse",     function(_, ent) TouchThaw(ent) end)
hook.Add("PhysgunPickup",    "TickGov_ThawPhysgun", function(_, ent) TouchThaw(ent) end)

-- fast scan of ONLY our (small) frozen ledger: catches a grab-drag that wakes
-- the prop via .isheld / SetPhysicsAttacker rather than firing a hook.
timer.Create("TickGov_ThawScan", 0.25, 0, function()
	if not cvEnabled:GetBool() then return end
	local thaw
	for _, ent in ipairs(GovFrozen) do
		if not IsValid(ent) then thaw = thaw or {} thaw[#thaw + 1] = ent
		elseif ent.isheld or (ent.IsPlayerHolding and ent:IsPlayerHolding())
			or (ent.GetPhysicsAttacker and IsValid(ent:GetPhysicsAttacker(0))) then
			thaw = thaw or {} thaw[#thaw + 1] = ent
		end
	end
	if thaw then for _, e in ipairs(thaw) do ThawEnt(e) end end
end)

-- ---------------- freeze pass (awake debris props only) ----------------
-- Earlier intervention is deliberately narrower than the legacy lag emergency:
-- only slow, unconnected, single-body props away from living players.
local function QuietProp(ent, phys, positions)
	if ent:GetPhysicsObjectCount() ~= 1 or IsValid(ent:GetParent())
		or constraint.HasConstraints(ent) then return false end
	if phys:GetVelocity():LengthSqr() > 25 or phys:GetAngleVelocity():LengthSqr() > 100 then return false end
	local pos = ent:GetPos()
	for _, playerPos in ipairs(positions) do
		if pos:DistToSqr(playerPos) <= 256 * 256 then return false end
	end
	return true
end

local function EnforcePropCap(cap, physicsOnly)
	if not cvProps:GetBool() then return 0 end
	local active, positions = {}, {}
	if physicsOnly then
		for _, ply in player.Iterator() do
			if ply:Alive() then positions[#positions + 1] = ply:GetPos() end
		end
	end
	for _, e in ipairs(ents.FindByClass("prop_physics")) do
		if IsValid(e) and not e._govFrozen and not BeingUsed(e) then
			local phys = e:GetPhysicsObjectNum(0)
			if IsValid(phys) and phys:IsMotionEnabled() and not phys:IsAsleep()
				and (CurTime() - e:GetCreationTime()) > 5
				and (not physicsOnly or QuietProp(e, phys, positions)) then
				active[#active + 1] = e
			end
		end
	end
	if #active <= cap then return 0 end
	table.sort(active, function(a, b) return a:GetCreationTime() < b:GetCreationTime() end)
	local n = 0
	for i = 1, #active - cap do
		if pcall(Freeze, active[i]) then n = n + 1 end
	end
	return n
end

local function SweepGibs()
	local n = 0
	for _, e in ipairs(ents.FindByClass("prop_physics")) do
		if IsValid(e) then
			local mdl = (e:GetModel() or ""):lower()
			if mdl:find("gib") and (CurTime() - e:GetCreationTime()) > 10 then
				e:Remove()
				n = n + 1
			end
		end
	end
	return n
end

-- ---------------- CLUTTER PASS ----------------
-- Runs ONLY from the evaluate timer below and ONLY while the governor already says
-- STRESSED or CRITICAL, so a healthy server does no work here at all.
--
-- NOT TOUCHED, deliberately:
--  * prop_ragdoll - owned by sv_corpse_sleeper.lua and sv_zc_tdm_cleaner.lua. Two systems
--    removing bodies is how you get a double-remove and a fight over a thaw.
--  * map-created entities, which includes every info_player_start / info_player_deathmatch
--    spawn point: game.CleanUpMap removes and then RESPAWNS map entities every round
--    (captures show exactly matched churn, info_player_start +37/-37,
--    info_player_deathmatch +57/-57), so reaping them buys nothing and can only break
--    respawn. "Unutilized spawns" is therefore explicitly out of scope.
--  * decals - they are rendered CLIENT side. The only server-side lever is the
--    all-or-nothing RemoveAllDecals broadcast, which visibly wipes every blood mark on
--    every screen. Out of scope until someone shows a server-side decal entity cost.
local CLUTTER_CLASS = {prop_physics = true, prop_physics_multiplayer = true}
local CLUTTER_SCAN  = {"prop_physics", "prop_physics_multiplayer", "weapon_*"}
local CLUTTER_LOG_EVERY = 30

-- A player who can still see and act. An unconscious player (organism.otrub, the same flag
-- addons/ko_reaper/lua/autorun/server/sv_ko_reaper.lua uses) is not a reason to keep scenery
-- alive; a spectator IS, and is handled by Observed() below.
local function ConsciousPositions()
	local out = {}
	for _, ply in player.Iterator() do
		if IsValid(ply) and ply:Alive() and ply:Team() ~= TEAM_SPECTATOR then
			local org = ply.organism
			if not (org and org.otrub) then out[#out + 1] = ply:GetPos() end
		end
	end
	return out
end

-- anything a player is watching through a camera survives, however far away it is
local function Observed(ent)
	for _, ply in player.Iterator() do
		if ply:GetObserverTarget() == ent then return true end
	end
	return false
end

local function IsClutter(ent, positions, minAge, distSqr)
	if not IsValid(ent) then return false end
	local class = ent:GetClass()
	if class == "prop_ragdoll" then return false end          -- bodies belong to the corpse sleeper
	local weapon = ent:IsWeapon()
	if not CLUTTER_CLASS[class] and not weapon then return false end
	if ent:CreatedByMap() then return false end               -- CleanUpMap respawns these anyway
	if weapon and IsValid(ent:GetOwner()) then return false end -- somebody is carrying it
	if IsValid(ent:GetParent()) then return false end
	if CurTime() - ent:GetCreationTime() < minAge then return false end
	if BeingUsed(ent) then return false end                   -- held / dragged / just touched
	if constraint.HasConstraints(ent) then return false end   -- welded or roped to something live
	if Observed(ent) then return false end
	local pos = ent:GetPos()
	for i = 1, #positions do
		if pos:DistToSqr(positions[i]) <= distSqr then return false end
	end
	return true
end

local clutterLogAt = 0

local function ClutterPass(loadState)
	local positions = ConsciousPositions()
	if #positions == 0 then
		TickGov.clutterLast = 0 -- nobody conscious: never leave a stale count in the status line
		return
	end

	local minAge   = cvClutAge:GetFloat()
	local dist     = cvClutDist:GetFloat()
	local distSqr  = dist * dist
	local budget   = cvClutMax:GetInt()
	local deadline = SysTime() + cvClutMs:GetFloat() * 0.001
	local act      = cvClutter:GetBool()

	local seen, removed, scanned, complete = 0, 0, 0, true
	for _, class in ipairs(CLUTTER_SCAN) do
		local list = ents.FindByClass(class)
		for i = 1, #list do
			-- a wall-clock budget, not an iteration cap: a big map must not buy a long frame
			if SysTime() >= deadline then
				complete = false
				break
			end
			scanned = scanned + 1
			if IsClutter(list[i], positions, minAge, distSqr) then
				seen = seen + 1
				-- PROVISIONAL(2026-09-22, at zc_governor_clutter 1 a dropped weapon, loot box or
				-- debris prop older than zc_governor_clutter_age and further than
				-- zc_governor_clutter_dist from every conscious player vanishes, so a player
				-- walking back to a far corner can find loot gone, and a killcam replay of an
				-- earlier moment shows that object disappear partway through the replay
				-- (sv_tape.lua:1127 writes an "entgone" mark - the tape is not corrupted).
				-- Default is 0, so none of this happens until the owner reads the OBSERVE log.
				-- ratify-by: 2026-10-20
				if act and removed < budget then
					removed = removed + 1
					SafeRemoveEntity(list[i])
				end
			end
		end
		if not complete then break end
	end

	TickGov.clutterLast = seen
	if seen > TickGov.clutterPeak then TickGov.clutterPeak = seen end
	TickGov.clutterSeen = TickGov.clutterSeen + seen
	TickGov.clutterRemoved = TickGov.clutterRemoved + removed

	-- also log a scan that ran out of its ms budget before it found anything: a silent
	-- truncation would make the OBSERVE count look like a real zero.
	if (seen > 0 or not complete) and CurTime() >= clutterLogAt then
		clutterLogAt = CurTime() + CLUTTER_LOG_EVERY
		print(string.format(
			"[TickGov] clutter %s | state %s | %d candidates older than %ds and >%du from %d conscious | scanned %d%s | edicts %d%s",
			act and "ACT" or "OBSERVE (removed nothing)", loadState, seen, math.floor(minAge), math.floor(dist),
			#positions, scanned, complete and "" or " (ms budget hit - partial)", ents.GetCount(),
			act and (" | removed " .. removed .. " of a " .. budget .. " budget") or ""))
	end
end

timer.Create("TickGov_Evaluate", 2, 0, function()
	if not cvEnabled:GetBool() then state = "OFF" recoveryPasses = 0 return end

	local target = engine.TickInterval()
	local avg, physics = TickMetrics()
	if avg <= 0 then return end

	local tickCritical = avg > target * 1.4
	if tickCritical or physics > target * 0.50 then
		recoveryPasses = 0
		state = "CRITICAL"
		local frozen = 0
		if tickCritical then
			frozen = EnforcePropCap(cvPropC:GetInt())
		else
			-- Preserve the existing stressed pass if both signals are elevated.
			if avg > target * 1.15 then frozen = EnforcePropCap(cvPropS:GetInt(), avg <= target * 1.15) end
			frozen = frozen + EnforcePropCap(cvPropC:GetInt(), true)
		end
		TickGov.frozenTotal = TickGov.frozenTotal + frozen
		-- Keep the existing removal trigger; physics-only pressure just freezes.
		if tickCritical then TickGov.sweptTotal = TickGov.sweptTotal + SweepGibs() end
	elseif avg > target * 1.15 or physics > target * 0.25 then
		recoveryPasses = 0
		state = "STRESSED"
		TickGov.frozenTotal = TickGov.frozenTotal + EnforcePropCap(cvPropS:GetInt(), avg <= target * 1.15)
	else
		state = "NORMAL"
		-- healthy (hysteresis): give props their physics back a few at a time,
		-- newest first, so the thaw can't re-trigger the spike
		if avg < target * 1.05 and physics < target * 0.15 then
			recoveryPasses = math.min(recoveryPasses + 1, 3)
		else
			recoveryPasses = 0
		end
		if recoveryPasses >= 3 and #GovFrozen > 0 then
			recoveryPasses = 0
			local thawed = 0
			while thawed < 5 and #GovFrozen > 0 do
				ThawEnt(GovFrozen[#GovFrozen])
				thawed = thawed + 1
			end
		end
	end

	-- a healthy server never reaches this
	if state == "STRESSED" or state == "CRITICAL" then ClutterPass(state) end
end)

concommand.Add("zc_governor_status", function(ply)
	if IsValid(ply) and not ply:IsSuperAdmin() then return end
	local target = engine.TickInterval()
	local avg, physics = TickMetrics()
	print(string.format(
		"[TickGov] v2.3 (props+gibs; corpses -> CorpseSleeper) | state %s | avg %.1fms (target %.1f) | physics %.1fms | props frozen-by-us: %d | prop-freeze %s | grace %ds | lifetime: %d frozen, %d gibs swept | enabled %s",
		state, avg * 1000, target * 1000, physics * 1000, #GovFrozen, tostring(cvProps:GetBool()),
		cvGrace:GetInt(), TickGov.frozenTotal, TickGov.sweptTotal, tostring(cvEnabled:GetBool())))
	print(string.format(
		"[TickGov] clutter %s | last pass %d candidates, peak %d | lifetime %d sightings, %d removed | age >%ds, dist >%du, budget %d/pass, scan %.1fms",
		cvClutter:GetBool() and "ACT" or "OBSERVE (removes nothing)",
		TickGov.clutterLast, TickGov.clutterPeak, TickGov.clutterSeen, TickGov.clutterRemoved,
		cvClutAge:GetInt(), cvClutDist:GetInt(), cvClutMax:GetInt(), cvClutMs:GetFloat()))
end)

print("[TickGov] v2.3 loaded - props + gibs (corpses owned by CorpseSleeper); clutter pass OBSERVE-ONLY until zc_governor_clutter 1. zc_governor_status to inspect.")
