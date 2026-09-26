-- ACQUIRE band: item/container/body looting (WS-C). A bot walks to and
-- picks up dropped weapons/medical items/ammo/armor, and opens loot boxes /
-- searches bodies, the same way a human does it on this server.
--
-- VERIFIED this session (file:line against work/bots/live-client-20260923
-- unless noted) and reused directly:
--   * addons/zcity/lua/homigrad/sv_inventory.lua:376-401 ("loot-fellows"
--     Player Think): a human opens a box/body by holding IN_ATTACK2+IN_USE
--     while looking at it; `hg.eyeTrace(ply, 60)` finds the target, ragdolls
--     resolve via `hg.RagdollOwner(ent)`, and `hook.Run("ZB_InventoryChecked",
--     ply, ent)` fills `ent.inventory`.
--   * addons/zcity/gamemodes/zcity/gamemode/libraries/sv_lootspawn.lua:176
--     `hg.loot_boxes[model:lower()]` is the container model table; the
--     "LootSpawn" ZB_InventoryChecked handler (~410-436) gates generation on
--     `ent.was_opened` and on `curRound.LootSpawn or curRound.Lootables[model]`
--     -- independently confirms the exact round-permission formula this file
--     uses (`round.LootSpawn or round.Lootables[model]`, per-model, not a
--     blanket "Lootables non-empty" check).
--   * addons/zcity/lua/homigrad/sv_inventory.lua:264-292 (`functions` table
--     behind the human `ply_take_item` net receiver): the exact per-kind
--     transfer recipe -- `hg.TransferInventoryWeapon(ply, ent, class)` for
--     weapons; `ply:GiveAmmo(amt, game.GetAmmoName(id), true)` then clear
--     `ent.inventory.Ammo[id]` for ammo; `hg.AddArmor(ply, armor)` then clear
--     `ent.armors[placement]` for armor; `ply:SetNetVar/SyncArmor` and
--     `ent:SetNetVar/SyncArmor` afterward (line ~340-346). Bots bypass the
--     `ply_take_item` net message (no client) and call this same recipe
--     directly server-side, per the task brief.
--   * `hg.armor[placement][armor]` shape (armor name -> its placement) is
--     confirmed by the same file's read at line 281/329; the table itself
--     (`hg.armor = {}`, `hg.armor.torso/head/ears/face = {...}`) lives in
--     Trauma's lua/homigrad/sh_armorstuff.lua and was NOT present in any
--     pulled reference tree for this session -- carried over from Trauma
--     (same fork lineage, reference-only per the blueprint) as the shape,
--     not independently reproduced against US1 source.
--   * `ent_ammo_*`/`ent_armor_*`/`ent_att_*` loose-loot entity class prefixes
--     are corroborated independently by sv_steer.lua's own whisker-passable
--     check (`string.sub(class,1,4)=="ent_"`) and by sv_lootspawn.lua's
--     `functions_break` spawn table (`ents.Create("ent_ammo_"..ammo)` /
--     `"ent_armor_"..armor`), which also confirms the loose ammo entity's
--     `.AmmoCount` field.
--   * hg.botdriver.WeaponProfile / BestGun / EffectiveReserve / RoleBands:
--     sv_weaponscore.lua (this file's own package, read this session).
--   * hg.botdriver.BestCarriedMedical / the medical whitelist shape:
--     sv_survival.lua (this file's own package, read this session) -- the
--     MED_WHITELIST below duplicates its WOUND_CARE+PAIN_RELIEF+NOURISHMENT
--     composition locally (that table is a local in sv_survival.lua, not
--     exported) rather than re-deriving BestCarriedMedical's *priority*
--     logic, since "does the bot carry ANY whitelisted medical at all" is a
--     different question than "is treatment currently indicated".
--   * lib.PathTo / lib.LookAt / lib.VisualContact / lib.Finalize / the
--     actionPolicy/lockMove contract / IN_USE-never-with-IN_ATTACK rule:
--     sv_brain.lua (this file's own package, read this session).
--
-- NOT FOUND in any pulled reference tree this session (searched
-- live-client-20260923, main-design-source, us1, live-pull-20260923,
-- client-20260923, live-data-20260923, pre-immersion-backup -- grepped for
-- "GetUseEntity", "sh_weaponsInv", "sv_util.lua", "force_pickup",
-- "hg.TransferInventoryWeapon" definition, "ZCityInteractions.CanLoot"
-- definition, and the ent_ammo_*/ent_armor_*/ent_att_* ENT files
-- themselves): the weapon-pickup GetUseEntity()+KeyPressed(IN_USE) contract
-- and the sv_util.lua force_pickup fallback the task brief cites at
-- sh_weaponsInv.lua:113 / sv_util.lua:600-612. I could not independently
-- confirm these two file:line citations; I implemented them exactly as
-- given because the fallback makes the behavior correct either way -- if
-- ordinary proximity/touch pickup turns out to be sufficient instead (see
-- next paragraph), the IN_USE taps are simply inert and the entity is
-- already gone by the time force_pickup would fire (guarded by IsValid).
--
-- CONFLICTING PRIOR CLAIM in this same package: behaviors/sv_core_acquire.lua
-- (this session's neighbour file)'s own header says it grepped the whole
-- US1 tree for PlayerCanPickupWeapon/SetPickupPrompt/AllowPickup and found
-- no Touch override, concluding a dropped weapon is picked up by simple
-- proximity, no keypress needed. That claim and this file's task-brief-given
-- contract disagree about the actual mechanism (though not about the
-- outcome). See the ACQUIRE-ordering note below for how this file resolves
-- the overlap without relying on either claim being right.
--
-- ACQUIRE ordering vs sv_core_acquire.lua ("acquire.scavenge", order=20):
-- this file registers at order=15, i.e. strictly BEFORE it in the same
-- band, so whenever this file's scan finds ANY candidate (gun, medical,
-- ammo, armor, container or body) it claims the tick first and
-- acquire.scavenge never runs that decision (RunArbiter stops at the first
-- CanRun+Run that returns true). acquire.scavenge is left untouched and
-- still exists as a fallback: if this file's CanRun gate fails (e.g. an
-- enemy was seen too recently) or its scan finds nothing this tick,
-- acquire.scavenge can still walk an unarmed bot onto a gun via its own
-- touch-based path. This file is the de facto single owner of scored
-- picking (medical/ammo/armor/container/body, and weapon-vs-BestGun
-- scoring) since acquire.scavenge only ever compares "has any gun" vs "has
-- none" and only targets guns.
--
-- LOGGED assumptions/choices not dictated by the brief (player-visible
-- effect noted):
--   * Cross-category candidate ranking (medical > unarmed-grab-any-gun >
--     weapon-upgrade > ammo > armor > container > body) is this file's own
--     tiering, via large flat score offsets per kind -- the brief gives
--     per-kind eligibility rules but not a cross-kind order. Effect: a bot
--     that is simultaneously eligible to grab a med kit AND a better rifle
--     ten feet apart goes for the med kit first.
--   * The medical whitelist reused from sv_survival.lua's WHITELIST includes
--     painkillers and both consumable classes (food), not just wound-care
--     items -- "medical items" in the task brief is treated as "whatever
--     BestCarriedMedical would ever pick up", not a narrower bandage-only set.
--   * ent_att_* (attachments) are deliberately NOT scanned -- the brief's
--     candidate list (a)/(b)/(c) never lists attachments as a lootable
--     category, only mentions the class prefix once for the press mechanism.
--   * Ammo-type matching for ent_ammo_* compares `game.GetAmmoName(id)`
--     (lowercased) against the entity class's suffix after "ent_ammo_",
--     since no ammo-id<->loose-entity-suffix mapping function was found in
--     any pulled tree; sv_lootspawn.lua's own spawn path suggests these are
--     usually the same string but goes through an `hg.ammotypes` normalizer
--     I don't have local access to, so an ammo pickup could rarely be
--     skipped on a name mismatch this file can't see.

local RB = hg.botdriver.RegisterBehavior
local lib = hg.botdriver.lib

hg.botdriver.DeclareBrainState("loot", {
	fields = {
		"lootLifeStartAt", "lootScanAt", "lootTarget", "lootKind",
		"lootPressCount", "lootPressState",
		"lootHoldStart", "lootInvChecked", "lootTransferred", "lootRummageUntil",
		"lootActionsThisLife", "lootInterest",
	},
})

hg.botdriver.stats = hg.botdriver.stats or {}
local stats = hg.botdriver.stats

local SCAN_RADIUS = 700
local SCAN_INTERVAL = 2.0
local APPROACH_RANGE = 80
local PATH_CADENCE = 1.5
local MAX_USE_PRESSES = 3
local HOLD_TIME = 0.35
local SPAWN_GRACE = 5
local NO_ENEMY_WINDOW = 4
local BODY_NO_ENEMY_WINDOW = 6
local BODY_SPORTS_MAX = 0.7
local AMMO_LOW_MAGS = 2
local MAX_LOOT_ACTIONS = 4
local HANDLED_TTL = 120
local AIM_SETTLED_DOT = 0.95

-- Tier offsets: see "LOGGED assumptions" above. Wide margins so no
-- WeaponProfile power value (roughly tens to low hundreds) can cross a tier.
local TIER_BODY = 100
local TIER_CONTAINER = 500
local TIER_ARMOR = 1500
local TIER_AMMO = 2500
local TIER_WEAPON_UPGRADE = 5000
local TIER_WEAPON_UNARMED = 15000
local TIER_MED = 25000

-- sv_survival.lua's WHITELIST composition (WOUND_CARE+PAIN_RELIEF+
-- NOURISHMENT), duplicated locally -- that table is a file-local there.
local MED_WHITELIST = {
	weapon_bandage_sh = true, weapon_bigbandage_sh = true,
	weapon_tourniquet = true, weapon_medkit_sh = true,
	weapon_painkillers = true,
	weapon_bigconsumable = true, weapon_smallconsumable = true,
}

-- mirrors sv_weaponscore.lua's own local PEN_BONUS (not exported).
local PEN_BONUS = 0.02

-- Per-bot memory of containers/bodies/items this bot already opened or gave
-- up on, so it never re-tries the same one inside the TTL. Weak-keyed both
-- levels so a removed bot or a removed loot entity can be collected.
local handledByBot = setmetatable({}, { __mode = "k" })

local function isHandled(bot, ent, now)
	local set = handledByBot[bot]
	local until_ = set and set[ent]
	return until_ ~= nil and until_ > now
end

local function markHandled(bot, ent, now)
	local set = handledByBot[bot]
	if not set then
		set = setmetatable({}, { __mode = "k" })
		handledByBot[bot] = set
	end
	set[ent] = now + HANDLED_TTL
end

local function weaponPower(prof)
	if not prof then return 0 end
	local band = hg.botdriver.RoleBands and hg.botdriver.RoleBands[prof.role]
	local base = band and band.base or 1
	return base * (prof.dps or 0) * (1 + PEN_BONUS * (prof.pen or 0))
end

local function hasCarriedMedClass(bot)
	for _, wep in ipairs(bot:GetWeapons()) do
		if IsValid(wep) and MED_WHITELIST[wep:GetClass()] then return true end
	end
	return false
end

local function gunWantsAmmo(bot, ammoSuffix)
	for _, wep in ipairs(bot:GetWeapons()) do
		if IsValid(wep) and hg.botdriver.IsGun(wep) and wep.GetPrimaryAmmoType then
			local id = wep:GetPrimaryAmmoType()
			if id and id >= 0 then
				local name = string.lower(game.GetAmmoName(id) or "")
				if name ~= "" and name == ammoSuffix then
					local clipSize = (wep.GetMaxClip1 and wep:GetMaxClip1())
						or (wep.Primary and wep.Primary.ClipSize) or 1
					local reserve = hg.botdriver.EffectiveReserve and hg.botdriver.EffectiveReserve(bot, wep) or 0
					if reserve < AMMO_LOW_MAGS * math.max(clipSize, 1) then return true end
				end
			end
		end
	end
	return false
end

local function armorPlacementOf(name)
	if not istable(hg.armor) then return nil end
	for placement, tbl in pairs(hg.armor) do
		if istable(tbl) and tbl[name] then return placement end
	end
	return nil
end

local function resolveRagdollOwner(ent)
	if isfunction(hg.RagdollOwner) then
		local owner = hg.RagdollOwner(ent)
		if IsValid(owner) then return owner end
	end
	return ent
end

local function roundLootProfile()
	if not zb or not zb.modes then return nil end
	local rk = zb.CROUND_MAIN or zb.CROUND
	return rk and zb.modes[rk] or nil
end

-- Single classify pass; returns kind, score or nil, nil.
local function classify(bot, brain, ent, now, bestGun, bestGunPower, hasAnyMed, roundProfile, sports)
	if not IsValid(ent) or ent == bot then return nil end

	if ent:IsWeapon() then
		if ent.IsSpawned ~= true then return nil end
		if IsValid(ent:GetOwner()) then return nil end
		local class = ent:GetClass()
		if MED_WHITELIST[class] then
			if hasAnyMed then return nil end
			return "med", TIER_MED
		end
		if hg.botdriver.IsGun(ent) then
			local prof = hg.botdriver.WeaponProfile(ent)
			if not prof then return nil end
			local power = weaponPower(prof)
			if not bestGun then return "weapon", TIER_WEAPON_UNARMED + power end
			if power > bestGunPower then return "weapon", TIER_WEAPON_UPGRADE + power end
		end
		return nil
	end

	local class = ent:GetClass()

	if string.sub(class, 1, 9) == "ent_ammo_" then
		local suffix = string.lower(string.sub(class, 10))
		if suffix ~= "" and gunWantsAmmo(bot, suffix) then return "ammo", TIER_AMMO end
		return nil
	end

	if string.sub(class, 1, 10) == "ent_armor_" then
		local name = string.sub(class, 11)
		local placement = name ~= "" and armorPlacementOf(name) or nil
		if placement and not (bot.armors and bot.armors[placement]) then
			return "armor", TIER_ARMOR
		end
		return nil
	end

	if class == "prop_physics" or class == "prop_physics_multiplayer" then
		if ent.was_opened then return nil end
		local model = string.lower(ent:GetModel() or "")
		if model == "" or not (hg.loot_boxes and hg.loot_boxes[model]) then return nil end
		local permitted = roundProfile and (roundProfile.LootSpawn == true
			or (istable(roundProfile.Lootables) and roundProfile.Lootables[model]))
		if not permitted then return nil end
		if bestGun and not brain.lootInterest then return nil end
		return "container", TIER_CONTAINER
	end

	if ent.IsRagdoll and ent:IsRagdoll() then
		if now - (brain.lastSeenTime or -math.huge) < BODY_NO_ENEMY_WINDOW then return nil end
		if sports >= BODY_SPORTS_MAX then return nil end
		local owner = resolveRagdollOwner(ent)
		-- Bodies only (2026-09-25): a downed player's fake ragdoll -- or a
		-- corpse whose owner has since respawned -- resolves to a LIVING
		-- player, and transferLoot then stripped that player's current
		-- weapons/ammo/armor (teammates and humans included).
		if IsValid(owner) and owner.IsPlayer and owner:IsPlayer() and owner:Alive() then return nil end
		if not isfunction(owner.GetNetVar) then return nil end
		local inv = owner:GetNetVar("Inventory")
		if not (istable(inv) and istable(inv.Weapons) and next(inv.Weapons)) then return nil end
		return "body", TIER_BODY
	end

	return nil
end

local function scanForLoot(bot, brain, now)
	if brain.lootInterest == nil then brain.lootInterest = math.random() < 0.6 end

	local pos = bot:GetPos()
	local bestGun = hg.botdriver.BestGun(bot)
	local bestGunPower = bestGun and weaponPower(hg.botdriver.WeaponProfile(bestGun)) or 0
	local hasAnyMed = hasCarriedMedClass(bot)
	local roundProfile = roundLootProfile()
	local personality = brain.personality
	local sports = (personality and personality.sportsmanship) or 0.5

	local candidates = {}
	local found = ents.FindInSphere(pos, SCAN_RADIUS)
	for i = 1, #found do
		local ent = found[i]
		if IsValid(ent) and not isHandled(bot, ent, now) then
			local kind, score = classify(bot, brain, ent, now, bestGun, bestGunPower, hasAnyMed, roundProfile, sports)
			if kind then
				candidates[#candidates + 1] = { ent = ent, kind = kind, score = score }
			end
		end
	end
	if #candidates == 0 then return nil, nil end

	table.sort(candidates, function(a, b) return a.score > b.score end)

	local checkCount = math.min(3, #candidates)
	for i = 1, checkCount do
		local c = candidates[i]
		if IsValid(c.ent) and lib.VisualContact and lib.VisualContact(bot, c.ent, brain, false, now) then
			return c.ent, c.kind
		end
	end
	return nil, nil
end

local function onLootProgress(bot, brain)
	brain.lootActionsThisLife = (brain.lootActionsThisLife or 0) + 1
end

local function clearLootTarget(brain)
	brain.lootTarget, brain.lootKind = nil, nil
	brain.lootPressCount, brain.lootPressState = nil, nil
	brain.lootHoldStart, brain.lootInvChecked, brain.lootTransferred, brain.lootRummageUntil = nil, nil, nil, nil
end

-- Weapons AND medical items (both are weapon-classed world pickups):
-- IN_USE tapped once per decision, released the next; after
-- MAX_USE_PRESSES taps, the server-only force_pickup fallback the task
-- brief gives verbatim. Loose ent_ammo_*/ent_armor_* items get the same
-- look+tap gesture with no documented fallback -- if 3 taps don't remove
-- the entity, give up on it (mark handled, count lootFailed).
local function runUsePickup(bot, brain, now, ent, kind)
	brain.lootPressCount = brain.lootPressCount or 0

	if brain.lootPressCount >= MAX_USE_PRESSES then
		if kind == "weapon" or kind == "med" then
			bot.force_pickup = true
			if hook.Run("PlayerCanPickupWeapon", bot, ent) then
				bot:PickupWeapon(ent)
			end
			bot.force_pickup = nil
		end
		if IsValid(ent) then
			markHandled(bot, ent, now)
			stats.lootFailed = (stats.lootFailed or 0) + 1
		else
			onLootProgress(bot, brain)
			stats.itemsLooted = (stats.itemsLooted or 0) + 1
		end
		clearLootTarget(brain)
		return true
	end

	if brain.lootPressState then
		brain.lootPressState = false
	else
		brain.buttons = bit.bor(brain.buttons or 0, IN_USE)
		brain.lootPressState = true
		brain.lootPressCount = brain.lootPressCount + 1
	end

	if not IsValid(ent) then
		onLootProgress(bot, brain)
		stats.itemsLooted = (stats.itemsLooted or 0) + 1
		clearLootTarget(brain)
	end
	return true
end

-- Container/body transfer recipe: addons/zcity/lua/homigrad/sv_inventory.lua
-- :264-292 (the human ply_take_item functions table), applied directly
-- server-side instead of through that net message.
local function transferLoot(bot, ent)
	if not IsValid(ent) or not IsValid(bot) then return end

	if istable(ent.inventory) and istable(ent.inventory.Weapons) and isfunction(hg.TransferInventoryWeapon) then
		local classes = {}
		for class in pairs(ent.inventory.Weapons) do classes[#classes + 1] = class end
		for _, class in ipairs(classes) do
			hg.TransferInventoryWeapon(bot, ent, class)
		end
	end

	if istable(ent.inventory) and istable(ent.inventory.Ammo) and isfunction(bot.GiveAmmo) then
		for id, count in pairs(ent.inventory.Ammo) do
			local ammoID = tonumber(id)
			count = tonumber(count) or 0
			if ammoID and count > 0 then
				local ammoName = game.GetAmmoName(ammoID)
				if ammoName then
					bot:GiveAmmo(count, ammoName, true)
					-- Same branch the gamemode's own transfer takes: a player
					-- source (downed, still alive) loses the ammo from its real
					-- pool; a container just clears the table entry.
					if ent:IsPlayer() and isfunction(ent.SetAmmo) then
						ent:SetAmmo(0, ammoName)
					else
						ent.inventory.Ammo[id] = nil
					end
					stats.itemsLooted = (stats.itemsLooted or 0) + 1
				end
			end
		end
	end

	if istable(ent.armors) and isfunction(hg.AddArmor) then
		for placement, armorName in pairs(ent.armors) do
			if not (bot.armors and bot.armors[placement]) and hg.AddArmor(bot, armorName) then
				ent.armors[placement] = nil
			end
		end
	end

	if isfunction(ent.SetNetVar) then
		ent:SetNetVar("Inventory", ent.inventory)
		ent:SetNetVar("Armor", ent.armors)
	end
	if isfunction(bot.SetNetVar) then
		bot:SetNetVar("Inventory", bot.inventory)
	end
	if isfunction(bot.SyncArmor) then bot:SyncArmor() end
	if isfunction(ent.SyncArmor) then ent:SyncArmor() end
end

-- Containers/bodies: hold IN_ATTACK2+IN_USE 0.35s, fire ZB_InventoryChecked
-- once (belt-and-braces -- the gamemode's own "loot-fellows" Player Think
-- also does this while the bits are held; idempotent via ent.was_opened),
-- transfer, then an 0.8-2.0s rummage pause still looking at it.
local function runContainerOrBody(bot, brain, now, ent, kind)
	-- IN_ATTACK2 means different things per weapon (ADS on a gun is harmless;
	-- on a grenade/melee/medicine it is an action). Hold a gun or bare hands
	-- while rummaging, never anything else.
	local active = bot:GetActiveWeapon()
	local activeIsGun = IsValid(active) and hg.botdriver.IsGun and hg.botdriver.IsGun(active)
	if not activeIsGun and (not IsValid(active) or active:GetClass() ~= "weapon_hands_sh") then
		if bot:HasWeapon("weapon_hands_sh") then
			bot:SelectWeapon("weapon_hands_sh")
			brain.lootHoldStart = nil
			return true
		end
	end
	brain.lootHoldStart = brain.lootHoldStart or now
	brain.buttons = bit.bor(brain.buttons or 0, IN_ATTACK2, IN_USE)

	if now - brain.lootHoldStart < HOLD_TIME then return true end

	if kind == "body" then
		-- Re-checked at the moment of transfer: the owner may have got up (or
		-- respawned) while this bot walked over.
		local owner = resolveRagdollOwner(ent)
		if IsValid(owner) and owner.IsPlayer and owner:IsPlayer() and owner:Alive() then
			markHandled(bot, ent, now)
			clearLootTarget(brain)
			return true
		end
	end

	if not brain.lootInvChecked then
		local resolved = kind == "body" and resolveRagdollOwner(ent) or ent
		if isfunction(hook.Run) then hook.Run("ZB_InventoryChecked", bot, resolved) end
		brain.lootInvChecked = true
	end

	if not brain.lootTransferred then
		local resolved = kind == "body" and resolveRagdollOwner(ent) or ent
		transferLoot(bot, resolved)
		brain.lootTransferred = true
		brain.lootRummageUntil = now + math.Rand(0.8, 2.0)
		stats.boxesOpened = (stats.boxesOpened or 0) + 1
	end

	if now < (brain.lootRummageUntil or 0) then return true end

	markHandled(bot, ent, now)
	onLootProgress(bot, brain)
	clearLootTarget(brain)
	return true
end

RB({
	name = "acquire.loot",
	band = "ACQUIRE",
	order = 15, -- before acquire.scavenge (order=20): see header note.
	finalize = { path = true },
	CanRun = function(ctx)
		if ctx.downed then return false end
		if IsValid(ctx:AcquireTarget()) then return false end
		if ctx.now - (ctx.brain.lastSeenTime or -math.huge) < NO_ENEMY_WINDOW then return false end
		if ctx.now < (ctx.brain.damageUntil or 0) then return false end
		return true
	end,
	Run = function(ctx)
		local bot, brain, now = ctx.bot, ctx.brain, ctx.now

		if not brain.lootLifeStartAt then brain.lootLifeStartAt = now end
		if now - brain.lootLifeStartAt < SPAWN_GRACE then return false end

		local ent, kind = brain.lootTarget, brain.lootKind
		if IsValid(ent) and kind == "container" and ent.was_opened and not brain.lootInvChecked then
			-- Someone else opened it first while we were en route.
			markHandled(bot, ent, now)
			clearLootTarget(brain)
			ent, kind = nil, nil
		end
		if not IsValid(ent) then
			clearLootTarget(brain)
			if (brain.lootActionsThisLife or 0) >= MAX_LOOT_ACTIONS then return false end
			if now < (brain.lootScanAt or 0) then return false end
			brain.lootScanAt = now + SCAN_INTERVAL + (bot:EntIndex() % 5) * 0.08
			ent, kind = scanForLoot(bot, brain, now)
			if not ent then return false end
			brain.lootTarget, brain.lootKind = ent, kind
		end

		brain.state = "loot"
		local dist = bot:GetPos():Distance(ent:GetPos())
		local center = ent:WorldSpaceCenter()

		if dist > APPROACH_RANGE then
			lib.PathTo(bot, brain, ent:GetPos(), now, PATH_CADENCE)
			lib.LookAt(bot, brain, center, "loot", false)
			return true
		end

		brain.path = nil
		brain.forward, brain.side = 0, 0
		lib.LookAt(bot, brain, center, "loot", true)

		local dir = center - bot:EyePos()
		if dir:LengthSqr() < 1 then return true end
		if bot:GetAimVector():Dot(dir:GetNormalized()) < AIM_SETTLED_DOT then return true end

		brain.actionPolicy = { owner = "loot", lockMove = true }

		if kind == "weapon" or kind == "med" or kind == "ammo" or kind == "armor" then
			return runUsePickup(bot, brain, now, ent, kind)
		end
		return runContainerOrBody(bot, brain, now, ent, kind)
	end,
})
