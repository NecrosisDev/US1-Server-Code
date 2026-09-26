-- Door handling + staged stuck escalation, restoring behaviour the slim
-- sv_traverse.lua port intentionally dropped. Wraps lib.TraverseStep
-- (defined in sv_traverse.lua, which loads first per the include list)
-- instead of replacing it outright, so vault/unstick/break/fast-diagnosis
-- states still own the tick ahead of door handling when they're active.
--
-- Door classes (func_door, func_door_rotating, prop_door_rotating) are stock
-- Source-engine entity classes, not project symbols -- used unchanged, same
-- as sv_nav.lua's treatment of navmesh.*.
--
-- 2026-09-22 rewrite (open-detection + impassable doors): verified against
-- US1 truth (main-design-source/lua/homigrad/sv_util.lua's DoorIsOpen2 and
-- weapon_hammer.lua's DoorIsOpen, both read below):
--   * func_door/func_door_rotating expose Source's m_toggle_state (0 == fully
--     open; DoorIsOpen2 line 799).
--   * prop_door_rotating exposes its own m_eDoorState (0 == closed, anything
--     else opening/open/closing; DoorIsOpen2 line 803).
--   * ALL three read m_bLocked directly (weapon_hammer.lua:262's DoorIsOpen,
--     `not door:GetInternalVariable("m_bLocked")`) -- this is also exactly
--     what criresp's weapon_hammer/weapon_ducttape fortify behaviour
--     (zc_bots/modes/sv_criresp.lua's criresp.suspect_fortify) sets via
--     Fire("lock") when it seals a door, so a locked-door check here already
--     recognises a criresp-sealed door as impassable with no extra plumbing
--     back to that file's local `sealedDoors` table.
--   * prop_door (the fourth class hgIsDoor recognises) is deliberately NOT
--     added here: DoorIsOpen2 has no case for it and always returns false,
--     which would make a real, opening prop_door look permanently "never
--     opens" and get blacklisted -- worse than the plain tap+escalate
--     fallback it would otherwise get from sv_brain.lua's own StuckCheck.
--
-- "Opens toward the bot": nothing in either US1 truth tree exposes a door's
-- hinge/swing direction to Lua, so rather than simulate an arc this always
-- stands off DOOR_STANDOFF short of the door before pressing use (Trauma's
-- own handleOwnDoor did the same thing unconditionally, not just for doors
-- it detected opening inward) -- a bot can never be pinned by a door swinging
-- into the spot it was standing.
--
-- Double doors: no special-casing needed. Using one leaf and re-scanning
-- (findDoorAhead runs again next decision) naturally finds the SECOND leaf
-- once it's the one still blocking the path.

if not SERVER then return end

hg = hg or {}
hg.botdriver = hg.botdriver or {}
hg.botdriver.lib = hg.botdriver.lib or {}
local lib = hg.botdriver.lib

hg.botdriver.DeclareBrainState("doors", { fields = {
	"doorUseAt", "doorStuckAt", "doorStuckPos", "doorStuckStage",
	"doorSidestepUntil", "doorSidestepDir", "doorGiveUpAt",
	"doorTarget", "doorPhase", "doorPhaseAt", "doorOpenAttempts",
	-- 2026-09-22 (breach locked doors, owner ask): zc_bots_diagnose
	-- (sv_diagnose.lua) reads these back to show the breach phase without
	-- guessing.
	"doorBreachDoor", "doorBreachUntil", "doorBreachStartedAt",
	"doorBreachPhase", "doorBreachAttempts",
} })

local DOOR_CLASSES = { func_door = true, func_door_rotating = true, prop_door_rotating = true }
local DOOR_RANGE = 70
local DOOR_STANDOFF = 46        -- stop this far short before pressing use, clear of any swing
local DOOR_USE_COOLDOWN = 0.8
local DOOR_OPEN_GRACE = 1.0     -- settle time after a press before re-checking DoorIsOpen2
local DOOR_MAX_ATTEMPTS = 3     -- distinct presses before treating it as impassable
local DOOR_IMPASSABLE_TTL = 20  -- shared blacklist window, stamped on the door entity itself
local DOOR_TOKEN_TTL = 4        -- an ally's claim on a door goes stale after this long unrefreshed

local STUCK_NO_PROGRESS = 1.2
local SIDESTEP_TIME = 0.5
local STUCK_RESET_EPS = 24
local GIVE_UP_TIME = 6

-- `reach` (2026-09-23): look along the current path leg, up to DOOR_LOOKAHEAD,
-- not just DOOR_RANGE -- so the standoff/approach starts before the bot is
-- already nose-to-door (and before local steering tries to slide along it).
local DOOR_LOOKAHEAD = 140

local function findDoorAhead(bot, dir, reach)
	local eyeish = bot:GetPos() + Vector(0, 0, 36)
	local tr = util.TraceLine({
		start = eyeish,
		endpos = eyeish + dir * math.Clamp(reach or DOOR_RANGE, DOOR_RANGE, DOOR_LOOKAHEAD),
		filter = bot,
		mask = MASK_SOLID,
	})
	if tr.Hit and IsValid(tr.Entity) and DOOR_CLASSES[tr.Entity:GetClass()] then
		return tr.Entity
	end
	return nil
end

-- Exported (Part A.2, criresp fortification): the same bounded forward-door
-- trace this file already uses for the traverse-step door tap, reused by
-- modes/sv_criresp.lua's suspect fortify behavior instead of duplicating a
-- second door-detection trace.
lib.FindDoorAhead = findDoorAhead

-- Door state (2026-09-23): the old boolean treated a prop_door_rotating in
-- ANY non-closed state as open -- including OPENING (1) and CLOSING (3) -- so
-- bots walked into a half-open leaf. Source's states: prop_door_rotating
-- m_eDoorState 0 closed / 1 opening / 2 open / 3 closing / 4 ajar;
-- func_door(_rotating) m_toggle_state 0 at-top(open) / 1 at-bottom(closed) /
-- 2 going-up / 3 going-down. Only "open" is passable; "opening" is a wait.
local function doorState(door)
	if door:GetNoDraw() then return "open" end
	local class = door:GetClass()
	if class == "func_door" or class == "func_door_rotating" then
		local ts = door:GetInternalVariable("m_toggle_state")
		if ts == 0 then return "open" end
		if ts == 2 then return "opening" end
		if ts == 3 then return "closing" end
		return "closed"
	elseif class == "prop_door_rotating" then
		local st = door:GetInternalVariable("m_eDoorState")
		if st == 2 or st == 4 then return "open" end
		if st == 1 then return "opening" end
		if st == 3 then return "closing" end
		return "closed"
	end
	return "closed"
end
lib.DoorState = doorState

local function doorIsOpen(door)
	-- A breached door (updateBreach below, or a human with the same tools) is
	-- blown off its hinges via hgBlastThatDoor (main-design-source/lua/
	-- homigrad/sv_util.lua:812-825): SetNoDraw(true) + SetNotSolid(true), the
	-- same flag PLAYER:LegAttack's own door-damage block checks before
	-- bothering to hit a door again (legkick/sv_legkick.lua:233,
	-- `hgIsDoor(ent) and !ent:GetNoDraw()`) -- treat it identically here so a
	-- breach that already succeeded is recognised immediately instead of
	-- riding out the rest of BREACH_MAX_TIME hitting a dead door.
	if door:GetNoDraw() then return true end
	local class = door:GetClass()
	if class == "func_door" or class == "func_door_rotating" then
		return door:GetInternalVariable("m_toggle_state") == 0
	elseif class == "prop_door_rotating" then
		return door:GetInternalVariable("m_eDoorState") ~= 0
	end
	return false
end

local function doorIsLocked(door)
	return door:GetInternalVariable("m_bLocked") and true or false
end

-- A locked/sealed/jammed door: block the nav connection hard (bypassing the
-- slow single-point learning bump -- a door that refuses three presses is a
-- much stronger static-cause signal than an ordinary stuck sidestep) and hand
-- the goal back to A* to route around, instead of tapping it forever.
local function markImpassable(bot, brain, door, now)
	door.zcBotDoorImpassableUntil = now + DOOR_IMPASSABLE_TTL
	if navmesh.IsLoaded() then
		local hereArea = navmesh.GetNearestNavArea(bot:GetPos(), false, 220, true, true)
		local doorArea = navmesh.GetNearestNavArea(door:GetPos(), false, 220, true, true)
		if IsValid(hereArea) and hg.botdriver.PenalizeArea then
			hg.botdriver.PenalizeArea(hereArea:GetID(), 12)
		end
		if IsValid(hereArea) and IsValid(doorArea) and hereArea ~= doorArea and hg.botdriver.PenalizeEdge then
			hg.botdriver.PenalizeEdge(hereArea:GetID(), doorArea:GetID(), 12)
		end
	end
	if door.zcBotDoorHolder == bot then
		door.zcBotDoorHolder = nil
		door.zcBotDoorHolderAt = nil
	end
	brain.doorTarget = nil
	brain.doorPhase = nil
	brain.doorPhaseAt = nil
	brain.doorOpenAttempts = nil
	brain.path = nil
	brain.nextRepath = 0
end

-- Breach a locked/sealed door (owner ask, 2026-09-22): "attack a locked/
-- failed door with the best means they have, give up after a bounded effort,
-- and only then markImpassable". Verified US1 destructibility (both
-- main-design-source and bots/us1/addons agree, this session):
--   * Gunfire never damages a door -- grepped homigrad_base/sh_bullet.lua's
--     bullet callback end to end; its only hgIsDoor use is opening an
--     areaportal for sound/vis, never HP/hgBlastThatDoor. Ranged bots have no
--     door-breaking tool at all, so this never even offers gunfire.
--   * A melee weapon's own Attack() already rolls a per-hit chance to blast
--     the door open via SWEP:PrimaryAttackAdd (weapon_hg_axe.lua:123,
--     weapon_hg_sledgehammer.lua:98, weapon_hatchet.lua:150,
--     weapon_tomahawk.lua:120, weapon_hg_crowbar[_gordon].lua:144/140 at 20%,
--     weapon_ram.lua:84 at 40%) -- holding IN_ATTACK on a melee weapon in
--     range is already the correct "attack the door" input; nothing extra to
--     wire up.
--   * PLAYER:LegAttack (the kick) does real, guaranteed HP damage to a door
--     regardless of loadout (legkick/sv_legkick.lua:178-203: ent.HP = (ent.HP
--     or 200) - dmg * (metal and 1 or 2), hgBlastThatDoor(ent) at HP<=0) --
--     this is the fallback (and the literal "kick doors" the owner asked
--     for) whenever the bot has no melee weapon in hand.
--   * Bare fists do NOT damage a door for an ordinary player class -- only
--     clawClasses do (weapon_hands_sh.lua:1796, a zombie/infected-only path
--     this Phase-1 package's bots never occupy per sv_brain.lua's file
--     header, "bots fight players only") -- so fists fall through to the kick
--     branch below like any other non-melee loadout, never a punch.
-- SAFETY: never even start (or continue) a breach while genuinely fighting --
-- brain.aimLocked (Engage is actively aiming at a live target this decision)
-- or a hit within DAMAGE_MEMORY (sv_brain.lua's brain.damageUntil) aborts
-- straight to markImpassable so the bot reroutes instead of standing at a
-- door while it's being shot at.
local BREACH_MAX_TIME = 9 -- bounded total effort per door before giving up
-- Exported so zc_bots_diagnose (sv_diagnose.lua) can print "elapsed/bound"
-- without hardcoding a second copy of this constant that could drift.
hg.botdriver.DOOR_BREACH_MAX_TIME = BREACH_MAX_TIME

local function updateBreach(bot, brain, door, now)
	if brain.aimLocked or now < (brain.damageUntil or 0) then
		brain.doorBreachDoor = nil
		brain.doorBreachUntil = nil
		brain.doorBreachPhase = nil
		markImpassable(bot, brain, door, now)
		return true
	end

	if brain.doorBreachDoor ~= door then
		brain.doorBreachDoor = door
		brain.doorBreachStartedAt = now
		brain.doorBreachUntil = now + BREACH_MAX_TIME
		brain.doorBreachAttempts = 0
	end
	if now >= brain.doorBreachUntil then
		brain.doorBreachDoor = nil
		brain.doorBreachUntil = nil
		brain.doorBreachPhase = "gave up"
		markImpassable(bot, brain, door, now)
		return true
	end

	brain.doorTarget = door
	brain.forward, brain.side = 0, 0
	if not brain.lookLocked then lib.LookAt(bot, brain, door:WorldSpaceCenter(), "door:breach", false) end

	local wep = bot:GetActiveWeapon()
	if IsValid(wep) and wep.ismelee then
		-- Let the weapon's own Attack()/PrimaryAttackAdd do the work (see
		-- header) -- holding IN_ATTACK in range is the whole input.
		brain.doorBreachPhase = "melee"
		brain.traverseButtons = bit.bor(brain.traverseButtons or 0, IN_ATTACK)
	elseif lib.TryLegKick and lib.TryLegKick(bot, brain, now, "door") then
		brain.doorBreachPhase = "kick"
		brain.doorBreachAttempts = (brain.doorBreachAttempts or 0) + 1
	else
		-- Off kick cooldown/stamina, or lib.TryLegKick not loaded yet (very
		-- early autorefresh window) -- hold position and try again next
		-- decision rather than burning the give-up clock doing nothing useful.
		brain.doorBreachPhase = "wait"
	end
	return true
end

-- Team-mate courtesy only (never gates on a hostile): "stack while an ally
-- already has this door" is exactly the Trauma-original squadmove behaviour
-- (one allied bot through at a time), scoped here to whichever ally reached
-- the door first rather than a full squad-slot simulation.
local function isDoorAlly(bot, other)
	if hg.botdriver.IsFFA() then return false end
	return hg.botdriver.TeamOf(bot) == hg.botdriver.TeamOf(other)
end

-- Approach/standoff/press/verify state machine for one door. Returns true
-- when it owns the tick (movement is being authored here, skip normal path
-- steering); false lets the caller fall through to whatever comes next
-- (normal path following, or the staged stuck escalation below).
local function updateDoorPhase(bot, brain, door, now)
	if door.zcBotDoorImpassableUntil and now < door.zcBotDoorImpassableUntil then
		markImpassable(bot, brain, door, now) -- re-blacklist + force a fresh repath, no new press
		return true
	end

	local state = doorState(door)
	if state == "open" then
		if door.zcBotDoorHolder == bot then
			door.zcBotDoorHolder = nil
			door.zcBotDoorHolderAt = nil
		end
		if brain.doorPhase == "opening" then
			hg.botdriver.stats = hg.botdriver.stats or {}
			hg.botdriver.stats.doorsOpened = (hg.botdriver.stats.doorsOpened or 0) + 1
		end
		brain.doorTarget = nil
		brain.doorPhase = nil
		brain.doorPhaseAt = nil
		brain.doorOpenAttempts = nil
		return false
	end

	local doorPos = door:GetPos()
	local toDoor = doorPos - bot:GetPos()
	toDoor.z = 0
	local dist = toDoor:Length()

	-- A fight cancels all door politeness instantly.
	if not brain.aimLocked then
		local holder = door.zcBotDoorHolder
		if IsValid(holder) and holder ~= bot and holder:Alive()
			and (now - (door.zcBotDoorHolderAt or 0)) < DOOR_TOKEN_TTL and isDoorAlly(bot, holder) then
			-- Someone already has this door: stack to a wall side instead of
			-- contesting the same interaction range (two independent IN_USE
			-- taps used to collide and both stall/bounce off the frame).
			brain.doorTarget = door
			brain.doorPhase = "stack"
			if dist > DOOR_STANDOFF * 1.5 then return false end -- still walking up; let normal steering carry it there
			if not brain.lookLocked then lib.LookAt(bot, brain, door:WorldSpaceCenter(), "door:stack", false) end
			brain.forward = dist < DOOR_STANDOFF and -60 or 0
			brain.side = (bot:EntIndex() % 2 == 0) and 90 or -90
			return true
		end
	end

	if dist > DOOR_RANGE then
		brain.doorTarget = door
		brain.doorPhase = nil
		return false -- not close enough yet; let normal path steering carry the approach
	end

	brain.doorTarget = door
	door.zcBotDoorHolder = bot
	door.zcBotDoorHolderAt = now

	if not brain.lookLocked then lib.LookAt(bot, brain, door:WorldSpaceCenter(), "door", false) end

	-- Stand off clear of the swing arc instead of pressing use nose-to-door.
	if dist < DOOR_STANDOFF then
		brain.forward = -80
		brain.side = 0
		return true
	end

	if doorIsLocked(door) then
		-- Sealed (criresp's hammer/ducttape fortify) and ordinary map-locked
		-- doors both read m_bLocked; neither opens from a plain +USE, so try
		-- to break through (updateBreach above) instead of giving up on the
		-- first press -- bounded, and it still ends at markImpassable.
		return updateBreach(bot, brain, door, now)
	end

	brain.forward = 0
	brain.side = 0

	-- The leaf is swinging toward open: stand and wait, never re-press (a
	-- second +USE on an opening prop_door reverses it).
	if state == "opening" then
		brain.doorPhase = "opening"
		brain.doorPhaseAt = brain.doorPhaseAt or now
		if now - brain.doorPhaseAt < DOOR_OPEN_GRACE * 3 then return true end
		-- Still swinging after 3 s: the leaf is blocked (a prop in the arc).
		-- Re-pressing would reverse it; route around instead.
		markImpassable(bot, brain, door, now)
		return true
	end

	if brain.doorPhase == "opening" then
		if state ~= "closing" and now - (brain.doorPhaseAt or now) < DOOR_OPEN_GRACE then
			return true -- pressed, still settling; wait before re-checking
		end
		if (brain.doorOpenAttempts or 0) >= DOOR_MAX_ATTEMPTS then
			markImpassable(bot, brain, door, now)
			return true
		end
		brain.doorPhase = nil -- retry: fall through to press again below
	end

	if now >= (brain.doorUseAt or 0) and bit.band(brain.buttons or 0, IN_ATTACK) == 0 then
		brain.doorUseAt = now + DOOR_USE_COOLDOWN
		brain.doorOpenAttempts = (brain.doorOpenAttempts or 0) + 1
		brain.doorPhase = "opening"
		brain.doorPhaseAt = now
		if SwingDoors and SwingDoors.OpenFor and SwingDoors.Enabled() and door:GetClass() ~= "func_door" then
			SwingDoors.OpenFor(bot, door, true)
		else
			brain.traverseButtons = bit.bor(brain.traverseButtons or 0, IN_USE)
		end
	end
	return true
end

-- Wrap once: if this file re-runs under autorefresh, `original` would
-- otherwise be re-captured as our OWN previous wrapper, growing a call
-- chain. Guard with a stored reference to the wrapper we installed.
local original = (lib.TraverseStep ~= hg.botdriver._doorsWrappedStep) and lib.TraverseStep or hg.botdriver._doorsOriginalStep
hg.botdriver._doorsOriginalStep = original

local function wrappedTraverseStep(bot, brain)
	local hopped = original and original(bot, brain)
	if hopped then return true end -- a vault/unstick/break/fast-diagnosis state already owns this tick
	if not brain.path or not IsValid(bot) then return false end
	local now = CurTime()

	----------------------------------------------------------------
	-- Door: find the one ahead on the current leg, then drive its own
	-- approach/standoff/press/verify state machine (updateDoorPhase above).
	----------------------------------------------------------------
	local wp = brain.path[brain.pathIdx]
	local handledDoor = false
	if isvector(wp) then
		local dir = wp - bot:GetPos()
		dir.z = 0
		if dir:LengthSqr() > 1 then
			dir:Normalize()
			local legLen = (wp - bot:GetPos()):Length2D()
			local door = IsValid(brain.doorTarget) and brain.doorTarget or findDoorAhead(bot, dir, legLen)
			if IsValid(door) then
				handledDoor = updateDoorPhase(bot, brain, door, now)
			else
				-- Nothing ahead (or the previous target went invalid, e.g. the
				-- map removed it) -- drop any stale target/phase rather than
				-- leaving it set with nothing left to resolve it.
				brain.doorTarget = nil
				brain.doorPhase = nil
			end
		end
	end

	----------------------------------------------------------------
	-- Staged stuck escalation (own progress sample, independent of
	-- sv_brain.lua's StuckCheck): jump -> sidestep 0.5s -> forced repath ->
	-- give up the goal at 6s. Suppressed while a door is deliberately holding
	-- the bot in place (standoff/opening/stacking) -- that stillness is
	-- intentional, not a stall, and layering a jump on top of it reads as a
	-- spasm, not a recovery.
	----------------------------------------------------------------------
	if handledDoor or brain.doorPhase then
		brain.doorStuckPos = nil
		brain.doorStuckAt = nil
		brain.doorStuckStage = nil
		brain.doorGiveUpAt = nil
		return handledDoor
	end

	local pos = bot:GetPos()
	if not brain.doorStuckPos or pos:DistToSqr(brain.doorStuckPos) > STUCK_RESET_EPS * STUCK_RESET_EPS then
		brain.doorStuckPos = pos
		brain.doorStuckAt = now
		brain.doorStuckStage = 0
		brain.doorGiveUpAt = nil
	elseif now - (brain.doorStuckAt or now) > STUCK_NO_PROGRESS then
		brain.doorGiveUpAt = brain.doorGiveUpAt or (brain.doorStuckAt + GIVE_UP_TIME)
		if now >= brain.doorGiveUpAt then
			brain.path = nil
			brain.roamPath = nil
			brain.roamGoal = nil
			brain.doorStuckStage = nil
			brain.doorGiveUpAt = nil
            brain.doorStuckAt, brain.doorStuckPos = now, pos
            brain.nextRepath = 0
			return true -- new routes get a fresh recovery episode
		end

		local stage = brain.doorStuckStage or 0
		if stage == 0 then
			if not (lib.OnStairs and lib.OnStairs(bot, brain, now)) then
				brain.traverseButtons = bit.bor(brain.traverseButtons or 0, IN_JUMP)
			end
			brain.doorStuckStage = 1
		elseif stage == 1 then
			if now < (brain.doorSidestepUntil or 0) then
				brain.side = (brain.doorSidestepDir or 1) * 200
			else
				brain.doorSidestepDir = (brain.doorSidestepDir or 1) * -1
				brain.doorSidestepUntil = now + SIDESTEP_TIME
				brain.doorStuckStage = 2
			end
		elseif stage == 2 then
			brain.nextRepath = 0
			brain.path = nil
			brain.doorStuckStage = 3
		end
	end

	return false
end

lib.TraverseStep = wrappedTraverseStep
hg.botdriver._doorsWrappedStep = wrappedTraverseStep
