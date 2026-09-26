-- Melee brain. Replaces the close-and-swing loop with spacing, reading the
-- opponent's swing state, block/parry, kick-vs-blocker, stamina discipline and
-- a refusal to cross open ground at a gunman.
--
-- US1 contracts this file leans on (weapon_melee.lua / weapon_hands_sh.lua):
--   swing start : GetInAttack() true, GetLastAttack() = time the hit trace fires
--   block       : IN_ATTACK2 held, stamina[1] > 90, 3 s lockout after LastBlocked,
--                 a new block needs > 1 s since the previous StartedBlocking;
--                 directional (defender must look at the strike); the first
--                 0.5 s of a block is a parry on weapon_melee (fists: no parry)
--   heavy       : IN_ATTACK while blocking
--   kick        : ply:LegAttack(), grounded, not sprinting, ~82 u
--   fists       : first IN_ATTACK raises them; IN_SPEED lowers them
--
-- KICK CONTRACT re-derived this session (legkick/sv_legkick.lua): gates are
-- alive, not ragdolled, GetNWFloat("InLegKick") <= CurTime(), on ground, NOT
-- IsSprinting(), and a PlayerCanLegAttack hook (:5-14); the hit trace fires at
-- anim frame 0.33 as a TraceHull from EyePos (or a lowered duck position) out
-- ang:Forward()*82, mins/maxs +-5 (:97-109) -- UNTARGETED: whatever is in that
-- cone gets hit, ally or enemy, hence lib.TryLegKick's own ally-clear trace
-- below. Cost is org.stamina.subadd + (curbstomp and 12 or 20) (:40),
-- self.InLegKick = CurTime() + speed - animstopAdjust afterward (:266-267,
-- roughly 1-3s depending on stamina). US1's kick_catch addon (bots/us1/
-- addons/kick_catch/lua/autorun/server/sv_kick_catch.lua) lets a bare-handed
-- player RMB-counter a GROUND kick within ~95u/2s cooldown while facing it --
-- it explicitly cannot catch an airborne kick, but PLAYER:LegAttack always
-- requires IsOnGround() (line 11), so every kick this file or sv_doors.lua
-- throws is a catchable ground kick by construction. A separate airborne
-- ability (pat's_jump_kick, PAT_JumpKick:StartJumpKick -- referenced only
-- indirectly this session, e.g. a killcam wrapper comment; no source file
-- found in either US1 truth tree) is a DIFFERENT mechanic bots never call.
-- Because a caught/countered kick is a real punish, kicks here are rate-
-- limited hard (lib.TryLegKick) rather than thrown on every opportunity.

local lib = hg.botdriver.lib

hg.botdriver.DeclareBrainState("melee", { fields = {
	"meleeFastUntil", "meleeCoverAt", "meleeCoverPos", "meleeSwingSeen", "meleeReactAt", "meleeReadOk",
	"meleeBlockUntil", "meleeWinded", "meleeNextSwingAt", "nextBashAt", "bashUntil",
	-- 2026-09-22 (kick expansion, owner ask): lastKickReason/lastKickAt are
	-- read back by zc_bots_diagnose (sv_diagnose.lua); nextKickAt is the
	-- single shared cooldown clock lib.TryLegKick enforces across every kick
	-- reason (door breach included, sv_doors.lua) so a bot can never stack
	-- triggers into a kick flurry.
	"nextKickAt", "lastKickReason", "lastKickAt",
	"meleeCommitUntil", "meleePositionWeapon", "meleePositionTarget",
} })

local BODY_PAD = 22          -- origin-to-origin slack on top of the weapon's trace reach
local HOVER_PAD = 26         -- stand-off outside strike range while waiting for an opening
local THREAT_WINDOW = 0.38   -- react to swings landing within this many seconds
local BLOCK_STAMINA = 92     -- weapon gate is > 90
local TIRED_STAMINA = 70
local RESTED_STAMINA = 110
local COMMIT_RANGE = 250     -- inside this a melee bot always commits against a gun
local KICK_RANGE = 74
local FAST_LANE_RANGE = 150
-- SAFETY (owner ask, rate limit / "not every bot is a kicker"): cooldown
-- scales with personality.aggression -- a hothead (~0.9) kicks roughly 3x as
-- often as a cautious bot (~0.2). Shared by every trigger in this file plus
-- sv_doors.lua's breach, via the one brain.nextKickAt clock.
local KICK_COOLDOWN_MAX = 6.5 -- aggression 0
local KICK_COOLDOWN_MIN = 2.2 -- aggression 1
local KICK_CATCH_RISK_RANGE = 115 -- kick_catch reaches ~95u; leave margin
local KICK_MIN_STAMINA = 50   -- matches the pre-existing turtle-guard kick's own floor
local KICK_TRACE_RANGE = 84   -- >= legkick's 82u hull reach (sv_legkick.lua:105)

local function stamina(ply)
	local org = ply.organism
	local st = org and org.stamina
	return istable(st) and tonumber(st[1]) or 180
end

-- Shared leg-kick gate + cooldown + ally-safety, used by every kick trigger
-- in this file (turtle-guard punish, crowd space, heal/plant interrupt,
-- finish-downed, fists-only last resort) and by sv_doors.lua's door breach.
-- Centralising this means: (a) one cooldown clock, so no reason can spam
-- independently of the others: (b) one ally-check, so a teammate standing
-- between the bot and its target is never the one who eats the kick -- the
-- kick's own trace (see header) is untargeted, so this is the only thing
-- standing between "kicked my target" and "kicked my squadmate"; (c) one
-- place zc_bots_diagnose reads for "why did/didn't this bot just kick".
function lib.TryLegKick(bot, brain, now, reason)
	if not hg.botdriver.RoundAllowsCombat() then return false end -- pre-round freeze / combat lock
	if now < (brain.nextKickAt or 0) then return false end
	if not IsValid(bot) or not bot.LegAttack or not bot:IsOnGround() then return false end
	if bot:IsSprinting() then return false end -- legkick's own gate (sv_legkick.lua:11); check it directly, don't approximate
	if bot:GetNWFloat("InLegKick", 0) > now then return false end
	if stamina(bot) < KICK_MIN_STAMINA then return false end

	local eyePos = bot:EyePos()
	local aim = bot:GetAimVector()
	local tr = util.TraceLine({
		start = eyePos,
		endpos = eyePos + aim * KICK_TRACE_RANGE,
		filter = bot,
		mask = MASK_SHOT,
	})
	local hitEnt = tr.Entity
	if IsValid(hitEnt) and hitEnt:IsPlayer() and hitEnt:Alive() and hg.botdriver.AllyOf(bot)(hitEnt) then
		return false -- an ally is in the kick's own cone -- never risk it
	end

	-- kick_catch (addons/kick_catch/lua/autorun/server/sv_kick_catch.lua): a BARE-HANDED
	-- player within ~95u, facing us with clear LOS, catches any GROUND kick and dumps the
	-- kicker. LegAttack always requires IsOnGround, so every kick we throw is catchable by
	-- construction. Don't feed a free counter to someone holding fists and looking at us.
	if IsValid(hitEnt) and hitEnt:IsPlayer() and hitEnt:Alive() then
		local theirWep = hitEnt:GetActiveWeapon()
		local bareHanded = IsValid(theirWep) and theirWep:GetClass() == "weapon_hands_sh"
		if bareHanded and eyePos:DistToSqr(hitEnt:EyePos()) < (KICK_CATCH_RISK_RANGE * KICK_CATCH_RISK_RANGE) then
			local toBot = bot:WorldSpaceCenter() - hitEnt:WorldSpaceCenter()
			if toBot:LengthSqr() > 1 then
				toBot:Normalize()
				if hitEnt:GetAimVector():Dot(toBot) > 0.6 then
					brain.lastKickReason = "skipped: catcher"
					return false
				end
			end
		end
	end

	bot:LegAttack()
	local aggression = (brain.personality and brain.personality.aggression) or 0.5
	brain.nextKickAt = now + Lerp(aggression, KICK_COOLDOWN_MAX, KICK_COOLDOWN_MIN)
	brain.lastKickReason = reason
	brain.lastKickAt = now
	return true
end

-- Case B/C (owner ask): kick to interrupt a target reaching for a medical
-- item -- wep.Heal ~= nil is the exact field sv_brain.lua's own MedicalCheck
-- already keys off for OUR bots, so it is a verified, load-bearing signal for
-- "this player is using/about to use a consumable", not a guess -- or to
-- finish one that is currently down (hg.botdriver.IsDowned) or just barely
-- back up (fake/sv_tier_0.lua's hg.FakeUp stamps ply.fakecd = CurTime() + 2
-- as its own "just got up" cooldown; verified this session, read directly).
-- Independent of the bot's own loadout -- callable from ranged Engage too
-- (sv_brain.lua) so a gun-bot at point-blank range can use it, not only a
-- melee one.
function lib.TryOpportunisticKick(bot, brain, now, target, dist)
	if not IsValid(target) or (dist or math.huge) > KICK_RANGE then return false end
	local reason
	if hg.botdriver.IsDowned(target) or (target.fakecd and target.fakecd > now) then
		reason = "finish"
	else
		local tw = target:GetActiveWeapon()
		if IsValid(tw) and tw.Heal ~= nil then reason = "interrupt" end
	end
	if not reason then return false end
	return lib.TryLegKick(bot, brain, now, reason)
end

local function reachOf(wep)
	if not IsValid(wep) then return 40 end
	return tonumber(wep.AttackLen1) or tonumber(wep.ReachDistance) or 55
end

local function isGun(wep)
	if not IsValid(wep) or wep.ismelee then return false end
	if isfunction(ishgweapon) then return ishgweapon(wep) and true or false end
	return wep.ZoomPos ~= nil
end

local function facing(from, to, minDot)
	local dir = to:WorldSpaceCenter() - from:EyePos()
	if dir:LengthSqr() < 1 then return true end
	dir:Normalize()
	return from:GetAimVector():Dot(dir) > minDot
end

-- Incoming swing: seconds until the opponent's hit trace fires, or nil.
local function incomingSwing(bot, target, tw, dist, now)
	if not IsValid(tw) or not tw.ismelee then return nil end
	if dist > reachOf(tw) + BODY_PAD + 25 then return nil end
	if not facing(target, bot, 0.6) then return nil end
	if tw.GetInAttack and tw:GetInAttack() and tw.GetLastAttack then
		local eta = tw:GetLastAttack() - now
		if eta > -0.05 and eta < THREAT_WINDOW then return eta, tw:GetLastAttack() end
		return nil
	end
	-- Fists carry no swing netvars; their cooldown stamp is the only tell.
	if tw.GetFists and tw:GetFists() and tw.GetNextPrimaryFire then
		local since = 0.5 - (tw:GetNextPrimaryFire() - now)
		if since >= 0 and since < 0.12 then return 0.1, tw:GetNextPrimaryFire() end
	end
	return nil
end

local function canBlock(bot, wep, now)
	if not IsValid(wep) or not wep.GetBlocking then return false end
	if wep.GetFists and not wep:GetFists() then return false end
	if stamina(bot) < BLOCK_STAMINA then return false end
	if wep.GetLastBlocked and now - wep:GetLastBlocked() < 3 then return false end
	if wep:GetBlocking() then return true end
	if wep.GetStartedBlocking and now - wep:GetStartedBlocking() < 1.05 then return false end
	return true
end

-- True when a melee-only bot should close on this target right now.
local function shouldCommit(bot, target, tw, dist)
	if not isGun(tw) then return true end
	if dist < COMMIT_RANGE then return true end
	if tw.reload then return true end
	if not facing(target, bot, 0.3) then return true end
	return false
end

local function meleeEngage(bot, brain, now, skill, target, dist, buttons, wep)
	skill = skill or 0.5
	dist = dist or 0

	-- Item 2 (NPC targeting): dispatch to the NPC-specific routine (sv_npc.lua)
	-- BEFORE touching target:GetActiveWeapon()/GetAimVector() below -- those
	-- are player-only assumptions this file's header documents. NPCs do not
	-- telegraph via GetInAttack, so incomingSwing/canBlock/shouldCommit (all
	-- below) never see an NPC target.
	if not target:IsPlayer() and ((target.IsNPC and target:IsNPC()) or (target.IsNextBot and target:IsNextBot())) then
		return lib.MeleeEngageNPC(bot, brain, now, skill, target, dist, buttons, wep)
	end

	local tw = target:GetActiveWeapon()

	if dist < FAST_LANE_RANGE then brain.meleeFastUntil = now + 0.3 end

	if wep.GetFists and not wep:GetFists() then
		if now >= (brain.fistsRaisedAt or 0) then
			brain.fistsRaisedAt = now + 0.4
			buttons = bit.bor(buttons, IN_ATTACK)
		end
		return buttons
	end

	-- Never run at a gun across open ground: break line of sight and work closer.
	if not shouldCommit(bot, target, tw, dist) then
		brain.state = "melee-evade"
		if now >= (brain.meleeCoverAt or 0) then
			brain.meleeCoverAt = now + 1.5
			-- sv_cover.lua: shared cover finder (was this file's own hiddenSpot()).
			brain.meleeCoverPos = lib.KeepCover(bot, brain, "melee", target, 700)
		end
		if brain.meleeCoverPos then
			brain.sprint = true
			lib.PathTo(bot, brain, brain.meleeCoverPos, now, 1.5)
		else
			brain.path = nil
			brain.side = (bot:EntIndex() % 2 == 0) and 300 or -300
			brain.forward = -150
		end
		return bit.band(buttons, bit.bnot(IN_ATTACK))
	end
	brain.meleeCoverPos = nil
	brain.state = "melee"

	-- Case "finish"/"interrupt" (owner ask): checked every decision regardless
	-- of the spacing/defence/offence state below -- lib.TryOpportunisticKick
	-- internally no-ops past KICK_RANGE and shares lib.TryLegKick's cooldown,
	-- so this never doubles up with the turtle-guard or crowd kicks further
	-- down (whichever fires first this decision wins, the rest just see
	-- brain.nextKickAt already in the future).
	lib.TryOpportunisticKick(bot, brain, now, target, dist)

	local st = stamina(bot)
	local strike = reachOf(wep) + BODY_PAD
	local hover = strike + HOVER_PAD

	if now > (brain.meleeStrafeTime or 0) then
		brain.meleeStrafeTime = now + math.Rand(0.6, 1.4)
		brain.meleeStrafeDir = math.random(2) == 1 and -1 or 1
	end
	local strafe = brain.meleeStrafeDir * 220

	-- Still far: travel, but walk the last stretch so fists stay up and a kick
	-- stays available.
	if dist > hover + 140 then
		brain.sprint = dist > 320
		brain.forward = 400
		lib.PathTo(bot, brain, target:GetPos(), now, 1)
		return bit.band(buttons, bit.bnot(IN_ATTACK))
	end
	brain.path = nil
	brain.sprint = nil

	-- Follow the weapon's real strike window, including stamina-scaled windup.
	-- Backpedaling on the next decision used to pull our own hit out of reach.
	local attacking = wep.GetInAttack and wep:GetInAttack()
	local attackEnd = wep.GetAttackTime and wep:GetAttackTime() or 0
	if attacking and attackEnd > now then
		brain.meleeCommitUntil = attackEnd
		brain.meleeRetreatUntil = math.max(brain.meleeRetreatUntil or 0, attackEnd + 0.25)
	end
	if now < (brain.meleeCommitUntil or 0) then
		brain.forward = dist > strike - 10 and 100 or 0
		brain.side = 0
		return bit.band(buttons, bit.bnot(IN_ATTACK))
	end

	-- Defence. One reaction roll per opposing swing, so a missed read stays missed.
	local eta, swingId = incomingSwing(bot, target, tw, dist, now)
	if eta then
		if brain.meleeSwingSeen ~= swingId then
			brain.meleeSwingSeen = swingId
			brain.meleeReactAt = now + math.Rand(0.10, 0.26) * (1.5 - skill)
			brain.meleeReadOk = math.Rand(0, 1) < (0.35 + 0.5 * skill)
		end
		if brain.meleeReadOk and now >= (brain.meleeReactAt or 0) then
			if canBlock(bot, wep, now) then
				brain.meleeBlockUntil = now + math.max(eta, 0) + 0.3
			else
				brain.meleeRetreatUntil = now + 0.45
			end
		end
	end
	if now < (brain.meleeBlockUntil or 0) then
		brain.forward = 0
		brain.side = 0
		buttons = bit.bor(bit.band(buttons, bit.bnot(IN_ATTACK)), IN_ATTACK2)
		-- Punish straight out of a held guard: heavy is IN_ATTACK while blocking.
		if not eta and wep.GetBlocking and wep:GetBlocking() and dist <= strike and st > TIRED_STAMINA then
			buttons = bit.bor(buttons, IN_ATTACK)
			brain.meleeBlockUntil = 0
			brain.meleeNextSwingAt = now + math.Rand(0.7, 1.0)
		end
		return buttons
	end

	-- Winded: make space and recover rather than swinging at half speed.
	if st < TIRED_STAMINA then brain.meleeWinded = true
	elseif st > RESTED_STAMINA then brain.meleeWinded = nil end
	if brain.meleeWinded and not isGun(tw) then
		brain.forward = dist < hover + 60 and -220 or 0
		brain.side = strafe
		return bit.band(buttons, bit.bnot(IN_ATTACK))
	end

	if now < (brain.meleeRetreatUntil or 0) then
		brain.forward = -260
		brain.side = strafe
		return bit.band(buttons, bit.bnot(IN_ATTACK))
	end

	-- They are turtling: kick the guard, otherwise circle for the flank.
	local oppBlocking = IsValid(tw) and tw.GetBlocking and tw:GetBlocking()
	if oppBlocking then
		if dist < KICK_RANGE and lib.TryLegKick(bot, brain, now, "blocker") then
			brain.meleeRetreatUntil = now + 0.35
			return bit.band(buttons, bit.bnot(bit.bor(IN_ATTACK, IN_SPEED)))
		end
		brain.forward = dist > KICK_RANGE - 8 and 160 or 0
		brain.side = strafe * 1.3
		return bit.band(buttons, bit.bnot(IN_ATTACK))
	end

	-- LAST RESORT (owner ask, "out of ammo with no melee weapon"): mayhem's
	-- round-start weapon_hands_sh-only rule and criresp's handcuffed force-
	-- switch (both verified this session, modes/sv_mayhem.lua's header /
	-- modes/sv_criresp.lua:48) are the real routes into fighting bare-handed --
	-- fists have no reach/damage a kick doesn't already beat, so mix kicks
	-- into the punch rotation instead of only punching.
	if wep.GetFists and wep:GetFists() and dist < KICK_RANGE then
		lib.TryLegKick(bot, brain, now, "unarmed")
	end

	-- Offence: step in only when they are not mid-windup, swing, step out.
	local ready = now >= math.max(brain.meleeNextSwingAt or 0,
		wep.GetNextPrimaryFire and wep:GetNextPrimaryFire() or 0)
	if ready and dist <= strike and facing(bot, target, 0.8) then
		brain.fireUntil = now + 0.12
		local wait = (tonumber(wep.WaitTime1) or 0.5) + (tonumber(wep.AttackTime) or 0.2)
		brain.meleeNextSwingAt = now + wait + math.Rand(0.1, 0.45) * (1.4 - skill)
		brain.meleeCommitUntil = now + (tonumber(wep.AttackTime) or 0.2) + (tonumber(wep.AttackTimeLength) or 0.15)
		brain.meleeRetreatUntil = brain.meleeCommitUntil + math.Rand(0.2, 0.35)
		brain.forward = 120
		brain.side = 0
	elseif ready and not eta then
		brain.forward = 300
		brain.side = strafe * 0.4
	elseif dist < strike - 12 then
		-- CROWDED (owner ask, "create space when an enemy is crowding the bot
		-- at melee range"): a kick knocks the attacker back (sv_legkick.lua:
		-- 150u/s unblocked, 60u/s blocked) as well as damaging them, so throw
		-- one before just backpedaling.
		lib.TryLegKick(bot, brain, now, "crowd")
		brain.forward = -180
		brain.side = strafe
	elseif dist > hover + 15 then
		brain.forward = 200
		brain.side = strafe
	else
		brain.forward = 0
		brain.side = strafe
	end

	if now < (brain.fireUntil or 0) then
		buttons = bit.bor(buttons, IN_ATTACK)
	end
	return buttons
end

function lib.MeleeEngage(bot, brain, now, skill, target, dist, buttons, wep)
	if brain.meleePositionWeapon ~= wep or brain.meleePositionTarget ~= target then
		brain.meleeCommitUntil, brain.meleeRetreatUntil, brain.meleeBlockUntil = nil, nil, nil
		brain.meleePositionWeapon, brain.meleePositionTarget = wep, target
	end
	brain.moveAngles = Angle(0, (target:GetPos() - bot:GetPos()):Angle().y, 0)
	local result = meleeEngage(bot, brain, now, skill, target, dist, buttons, wep)
	if lib.SafeCombatMove then lib.SafeCombatMove(bot, brain, now) end
	return result
end

-- Gun bash: the held firearm cannot fire (dry, cycling, deploying) and the
-- enemy is on top of us. IN_ATTACK + IN_USE, which the control layer otherwise
-- strips, so flag the window.
function lib.TryGunBash(bot, brain, now, dist, buttons)
	if (dist or 0) > 78 then return nil end
	if bot:GetVelocity():Length2DSqr() > 240 * 240 then return nil end
	if now < (brain.nextBashAt or 0) then return nil end
	brain.nextBashAt = now + math.Rand(1.1, 1.6)
	brain.bashUntil = now + 0.15
	return bit.band(bit.bor(buttons, IN_ATTACK, IN_USE), bit.bnot(IN_SPEED))
end
