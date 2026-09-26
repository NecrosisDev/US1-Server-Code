-- superfighters (folder sfd) mode profile: an unarmed-beyond-fists bot seeks
-- the nearest live loot entity while steering clear of visibly armed
-- enemies, until it picks up a real melee weapon and falls through to the
-- normal COMBAT band.
--
-- VERIFIED (US1 tree, main-design-source/lua -> us1/addons/zcity):
--   modes/sfd/sv_sfd.lua:3 -- MODE.name = "superfighters" is the real round
--     key (loader.lua:59,80 stores zb.modes[MODE.name] = MODE); the folder
--     name "sfd" is never used as a lookup key anywhere in this tree
--     (grepped modes/sfd, libraries/, loader.lua), so no alias is needed --
--     RegisterModeProfile is called with "superfighters" directly.
--   modes/sfd/sv_sfd.lua:60-87 -- MODE:RoundStart gives every bot exactly
--     weapon_hands_sh (+ walkie_talkie + hg_sling inventory unlock, neither a
--     combat weapon) and SelectWeapon("weapon_hands_sh"); real weapons only
--     arrive via loot (below).
--   modes/sfd/sv_sfd.lua:143-149 -- MODE:RoundThink runs hook.Run("Boxes
--     Think") every 2s while the round is live.
--   libraries/sv_lootspawn.lua:609-711 ("Boxes Think" / SpawnBoxes) -- each
--     tick either (a) spawns a "prop_physics" crate (model from
--     hg.loot_boxes) that must be broken (PropBreak hook, line 448-461) to
--     release its contents as separate weapon_*/ent_ammo_*/ent_armor_*/
--     ent_att_* entities, or (b) spawns one such entity directly into the
--     world via `ents.Create(entName)` with `huy.IsSpawned = true` (line
--     701-706, mirrored at line 367-374/703/720 for the crate-break case).
--     `.IsSpawned` is the one field this repo actually sets on every loot
--     entity spawned by this system, so it is the filter used below instead
--     of a bare classname/wildcard scan of every entity on the map.
--   No IN_USE / :Use hook exists anywhere in this us1 snapshot for
--     ent_ammo_*/ent_armor_*/weapon_* pickup (grepped for
--     PlayerCanPickupWeapon, PlayerCanPickupItem, SetPickupPrompt, :AllowPickup
--     -- only one unrelated hit, homicide's traitor-radio special case at
--     modes/homicide/sv_homicide.lua:1675). GMod's stock weapon-touch pickup
--     is therefore unmodified for these entities, so simply pathing onto the
--     entity (a touch, not a keypress) is the correct acquisition input.
--     BEHAVIOR CHOICE (not in the brief): a still-unbroken "prop_physics"
--     loot crate is NOT targeted by this behavior -- opening one needs an
--     attack/damage input, not a locomotion primitive, and this file only
--     owns movement; a bot with nothing but fists breaking crates open is
--     left to a later phase (COMBAT band already handles melee once the bot
--     has one).
--   sv_weaponscore.lua's hg.botdriver.BestGun / hg.botdriver.HasMelee (the
--     two functions the porting brief itself names for "has a gun" / "has a
--     real melee weapon") are used for the "unarmed beyond fists" gate
--     instead of a hardcoded GetClass()=="weapon_hands_sh" check: both key
--     off wep.ismelee / ishgweapon(wep) with wep.ZoomPos ~= nil, and
--     weapon_hands_sh (a fists placeholder, not in the sniper/carbine/etc.
--     role table and never flagged ismelee anywhere greppable in this repo)
--     satisfies neither, so BestGun/HasMelee both return nil for a bot
--     holding only fists -- the same outcome the brief's suggested check
--     would give, without hardcoding the class name.

hg = hg or {}
hg.botdriver = hg.botdriver or {}

local RB = hg.botdriver.RegisterBehavior

hg.botdriver.DeclareBrainState("sfd", { fields = { "sfdLootScanAt", "sfdLootTarget" } })

local AVOID_RANGE = 400
local AVOID_RANGE_SQR = AVOID_RANGE * AVOID_RANGE
local LOOT_RADIUS = 48
local LOOT_TTL = 3
-- Hard constraint: no unbounded whole-map entity scans. Bounded to a radius
-- and rate-limited, with the chosen entity cached on the brain between scans
-- (this used to scan every entity on the map, unthrottled, every call).
local LOOT_SCAN_RADIUS = 3000
local LOOT_SCAN_INTERVAL = 1.5

local LOOT_PREFIXES = { "^weapon_", "^ent_ammo_", "^ent_armor_", "^ent_att_" }

local function isLootEntity(ent)
	if not IsValid(ent) or not ent.IsSpawned then return false end
	local class = ent:GetClass()
	for i = 1, #LOOT_PREFIXES do
		if string.find(class, LOOT_PREFIXES[i]) then return true end
	end
	return false
end

local function nearestLoot(bot, brain, now)
	if isLootEntity(brain.sfdLootTarget) then
		return brain.sfdLootTarget:GetPos()
	end
	brain.sfdLootTarget = nil
	if now < (brain.sfdLootScanAt or 0) then return nil end
	brain.sfdLootScanAt = now + LOOT_SCAN_INTERVAL

	local pos = bot:GetPos()
	local best, bestDistSqr
	for _, ent in ipairs(ents.FindInSphere(pos, LOOT_SCAN_RADIUS)) do
		if isLootEntity(ent) then
			local distSqr = pos:DistToSqr(ent:GetPos())
			if not bestDistSqr or distSqr < bestDistSqr then
				best, bestDistSqr = ent, distSqr
			end
		end
	end
	brain.sfdLootTarget = best
	return IsValid(best) and best:GetPos() or nil
end

local function armedEnemyNearby(ctx)
	local bot = ctx.bot
	local isEnemy = ctx:EnemyOf()
	if not isfunction(isEnemy) then return false end
	local pos = bot:GetPos()
	for _, ent in ipairs(hg.botdriver.Actors()) do
		if isEnemy(ent) and pos:DistToSqr(ent:GetPos()) <= AVOID_RANGE_SQR then
			local wep = ent:GetActiveWeapon()
			local armed = IsValid(wep) and wep:GetClass() ~= "weapon_hands_sh"
			if armed and hg.botdriver.lib.CanSeeTarget(bot, ent) then
				return true
			end
		end
	end
	return false
end

RB({
	name = "sfd.loot-seek",
	band = "MODE",
	order = 20,
	default = false,
	finalize = { path = true },
	CanRun = function(ctx)
		local bot = ctx.bot
		if hg.botdriver.BestGun(bot) then return false end
		if hg.botdriver.HasMelee(bot) then return false end
		return true
	end,
	Run = function(ctx)
		local bot, brain, now = ctx.bot, ctx.brain, ctx.now
		if armedEnemyNearby(ctx) then
			-- Hold rather than path through/near a visible armed enemy.
			brain.path = nil
			return true
		end
		local lootPos = nearestLoot(bot, brain, now)
		if not lootPos then return false end
		hg.botdriver.SetObjective(bot, lootPos, LOOT_RADIUS, LOOT_TTL, "soft", "sfd.loot-seek")
		hg.botdriver.lib.ObjectiveTravel(bot, brain, now)
		return true
	end,
})

hg.botdriver.RegisterModeProfile("superfighters", {
	behaviors = { "sfd.loot-seek" },
})
