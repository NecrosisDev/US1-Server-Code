-- ACQUIRE band, ported from Trauma's behaviors/sv_core_acquire.lua.
--
-- Originally empty (Trauma's ACQUIRE behaviors all depended on sv_loot.lua,
-- dropped by rule 1). This file now owns the one ACQUIRE-band case a real
-- loot backend was never required for: an unarmed/dry bot walking onto a
-- dropped firearm that is already lying in the world (stock GMod weapon-touch
-- pickup -- no loot planner needed).
--
-- VERIFIED (US1 tree, main-design-source/lua + bots/us1/addons/zcity):
--   grepped the whole tree for PlayerCanPickupWeapon, PlayerCanPickupItem,
--   SetPickupPrompt, AllowPickup -- the only hit is homicide's traitor-radio
--   special case (modes/homicide/sv_homicide.lua), gated on ply.isTraitor and
--   a specific weapon class; it does not block a bot picking up an ordinary
--   dropped firearm. No SWEP/ENT Touch override exists for weapon pickup
--   anywhere in main-design-source/lua/weapons/. So a dropped weapon entity
--   is picked up by simple proximity (a touch), not a keypress -- pathing
--   onto it is the correct and complete acquisition input.
--   A dropped weapon entity keeps its original weapon class and SWEP table
--   (drop path is ply:DropWeapon(wep, ...), not a re-parent to a generic
--   entity class), so hg.botdriver.IsGun (sv_brain.lua:55-60, itself
--   ishgweapon(wep)-or-wep.ZoomPos~=nil) works unmodified on the entity.

local RB = hg.botdriver.RegisterBehavior

hg.botdriver.DeclareBrainState("acquire", { fields = { "scavengeScanAt", "scavengeTarget", "scavengeArrivedAt", "scavengeFailed" } })

local SCAN_RADIUS = 600
local SCAN_INTERVAL = 2
local PICKUP_RADIUS = 48
-- CORRECTION 2026-09-25: touch pickup is NOT enough on US1 --
-- weapons/homigrad_base/sh_weaponsInv.lua:122 refuses an initialised weapon
-- unless the player +USEs it or ply.force_pickup is set, so a bot could park
-- on a gun forever. After standing on it this long, take it the way the
-- gamemode's own server code does (sv_util.lua force_pickup, also
-- behaviors/sv_loot.lua); if that is refused too, skip that gun for a while.
local PICKUP_WAIT = 1.5
local FAILED_TTL = 60

RB({
	name = "acquire.scavenge",
	band = "ACQUIRE",
	order = 20,
	finalize = { path = true },
	CanRun = function(ctx)
		if ctx:HardObjective() then return false end
		if hg.botdriver.BestGun(ctx.bot) then return false end
		-- "no threat known": a visible target means COMBAT should own the
		-- tick instead of walking toward a gun in the open.
		return not IsValid(ctx:AcquireTarget())
	end,
	Run = function(ctx)
		local bot, brain, now = ctx.bot, ctx.brain, ctx.now

		if not IsValid(brain.scavengeTarget) or not hg.botdriver.IsGun(brain.scavengeTarget) then
			brain.scavengeTarget = nil
			if now < (brain.scavengeScanAt or 0) then return false end
			brain.scavengeScanAt = now + SCAN_INTERVAL

			local pos = bot:GetPos()
			local failed = brain.scavengeFailed
			local best, bestDistSqr
			for _, ent in ipairs(ents.FindInSphere(pos, SCAN_RADIUS)) do
				if IsValid(ent) and not IsValid(ent:GetOwner()) and hg.botdriver.IsGun(ent)
					and not (failed and (failed[ent] or 0) > now) then
					local d = pos:DistToSqr(ent:GetPos())
					if not bestDistSqr or d < bestDistSqr then best, bestDistSqr = ent, d end
				end
			end
			brain.scavengeTarget = best
			brain.scavengeArrivedAt = nil
			if not best then return false end
		end

		local target = brain.scavengeTarget
		if bot:GetPos():DistToSqr(target:GetPos()) <= PICKUP_RADIUS * PICKUP_RADIUS then
			brain.scavengeArrivedAt = brain.scavengeArrivedAt or now
			if now - brain.scavengeArrivedAt >= PICKUP_WAIT then
				bot.force_pickup = true
				if hook.Run("PlayerCanPickupWeapon", bot, target) then bot:PickupWeapon(target) end
				bot.force_pickup = nil
				if IsValid(target) and not IsValid(target:GetOwner()) then
					brain.scavengeFailed = brain.scavengeFailed or setmetatable({}, { __mode = "k" })
					brain.scavengeFailed[target] = now + FAILED_TTL
				end
				brain.scavengeTarget, brain.scavengeArrivedAt = nil, nil
				return false
			end
		else
			brain.scavengeArrivedAt = nil
		end

		hg.botdriver.SetObjective(bot, target:GetPos(), PICKUP_RADIUS, SCAN_INTERVAL + 1, "soft", "acquire.scavenge")
		hg.botdriver.lib.ObjectiveTravel(bot, brain, now)
		return true
	end,
})
