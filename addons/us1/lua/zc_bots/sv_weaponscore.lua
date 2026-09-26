-- Situational weapon scoring, ported from Trauma's sv_weaponscore.lua.
--
-- VERIFIED DIVERGENCE (rule 8): US1's SWEP.Category strings carry a
-- "Weapons - " prefix and differ in spelling from Trauma's
-- ("Weapons - Machine-Pistols", "Weapons - Machineguns" vs Trauma's
-- "Machine Pistols", "Machine Guns") -- confirmed by grepping
-- main-design-source/lua/weapons/*.lua. CATEGORY_ROLE below uses the US1
-- spellings; using Trauma's table unmodified would have silently scored
-- every US1 gun as an unmapped "generalist rifle" fallback.

hg = hg or {}
hg.botdriver = hg.botdriver or {}

----------------------------------------------------------------------
-- TUNING (unchanged from Trauma)
----------------------------------------------------------------------

local ROLE = {
	melee   = { ideal = {0, 90},     hardMax = 170,  closeFloor = 1.00, base = 1.00 },
	shotgun = { ideal = {80, 450},   hardMax = 950,  closeFloor = 1.00, base = 1.05 },
	pistol  = { ideal = {120, 850},  hardMax = 1700, closeFloor = 0.85, base = 0.80 },
	smg     = { ideal = {150, 1000}, hardMax = 2000, closeFloor = 0.90, base = 0.90 },
	carbine = { ideal = {250, 1700}, hardMax = 3200, closeFloor = 0.70, base = 1.00 },
	rifle   = { ideal = {300, 2200}, hardMax = 4200, closeFloor = 0.60, base = 1.05 },
	lmg     = { ideal = {350, 2400}, hardMax = 4400, closeFloor = 0.55, base = 1.05 },
	sniper  = { ideal = {900, 6000}, hardMax = 9000, closeFloor = 0.30, base = 1.10 },
	launcher = { ideal = {600, 2500}, hardMax = 4000, closeFloor = 0.02, base = 0.90 },
}

-- Item 4 (2026-09-22, weapon-appropriate positioning): exported so
-- behaviors/sv_core_combat.lua can read each role's ideal engagement band
-- without a second copy of these numbers -- ROLE itself stays local/unchanged.
hg.botdriver.RoleBands = ROLE

local CATEGORY_ROLE = {
	["Weapons - Pistols"]         = "pistol",
	["Weapons - Machine-Pistols"] = "smg",
	["Weapons - Carbines"]        = "carbine",
	["Weapons - Assault Rifles"]  = "rifle",
	["Weapons - Sniper Rifles"]   = "sniper",
	["Weapons - Shotguns"]        = "shotgun",
	["Weapons - Machineguns"]     = "lmg",
	["Weapons - Melee"]           = "melee",
	["Weapons - Grenade Launchers"] = "launcher",
}

local MELEE_DPS   = 45
local PEN_BONUS   = 0.02
local PEN_CAP     = 35
local DRY_CLIP    = 0.30
local DRY_RELOAD_REF    = 4.0
local DRY_RELOAD_MAXPEN = 0.8
local SWITCH_MARGIN = 1.35
local SWITCH_CD     = 2.0

local function roleOf(wep)
	if wep.ismelee then return "melee" end
	local role = wep.Category and CATEGORY_ROLE[wep.Category]
	if role then return role end
	if ishgweapon(wep) and wep.ZoomPos ~= nil then return "rifle" end
	return nil
end

function hg.botdriver.WeaponProfile(wep)
	if not IsValid(wep) then return nil end
	local role = roleOf(wep)
	if not role then return nil end

	local prof
	if role == "melee" then
		prof = { role = role, dps = MELEE_DPS, pen = 0 }
	else
		local prim = wep.Primary or {}
		local ammo = hg.ammotypeshuy and hg.ammotypeshuy[prim.Ammo]
		local bs = ammo and ammo.BulletSettings
		local dmg = (bs and bs.Damage) or prim.Damage or 25
		local pellets = wep.NumBullet or 1
		local wait = math.max(prim.Wait or 0.1, 0.03)
		prof = {
			role = role,
			dps  = dmg * pellets / wait,
			pen  = math.min(wep.Penetration or 0, PEN_CAP),
		}
	end
	return prof
end

local function suitability(role, dist)
	local band = ROLE[role]
	if not band then return 0 end
	local lo, hi = band.ideal[1], band.ideal[2]
	if dist >= lo and dist <= hi then return 1 end
	if dist < lo then
		return Lerp(dist / math.max(lo, 1), band.closeFloor, 1)
	end
	if dist >= band.hardMax then return 0.05 end
	return Lerp((dist - hi) / (band.hardMax - hi), 1, 0.2)
end

local function ammoFactor(bot, wep, prof)
	if prof.role == "melee" then return 1 end

	local clip = wep.Clip1 and wep:Clip1() or 0
	local reserve = 0
	if hg.botdriver.EffectiveReserve then
		reserve = hg.botdriver.EffectiveReserve(bot, wep)
	elseif wep.GetPrimaryAmmoType then
		reserve = bot:GetAmmoCount(wep:GetPrimaryAmmoType())
	end

	if clip <= 0 then
		if reserve <= 0 then return 0 end
		local reload = wep.ReloadTime or 0
		local penalty = 1 - math.Clamp(reload / DRY_RELOAD_REF, 0, DRY_RELOAD_MAXPEN)
		return DRY_CLIP * penalty
	end

	local clipSize = (wep.GetMaxClip1 and wep:GetMaxClip1()) or (wep.Primary and wep.Primary.ClipSize) or clip
	local total = clip + reserve
	return 0.6 + 0.4 * math.Clamp(total / math.max(clipSize * 2, 1), 0, 1)
end

function hg.botdriver.ScoreWeapon(bot, wep, dist)
	local prof = hg.botdriver.WeaponProfile(wep)
	if not prof then return 0 end
	local af = ammoFactor(bot, wep, prof)
	if af <= 0 then return 0 end
	local band = ROLE[prof.role]
	return band.base * prof.dps * suitability(prof.role, dist) * af * (1 + PEN_BONUS * prof.pen)
end

function hg.botdriver.BestWeaponFor(bot, dist, exclude)
	local best, bestScore
	for _, wep in ipairs(bot:GetWeapons()) do
		if IsValid(wep) and not (exclude and exclude(wep)) then
			local s = hg.botdriver.ScoreWeapon(bot, wep, dist)
			if s > 0 and (not bestScore or s > bestScore) then
				best, bestScore = wep, s
			end
		end
	end
	return best, bestScore
end

local CQB_DIST = 200

function hg.botdriver.HasCQBAlternative(bot)
	for _, wep in ipairs(bot:GetWeapons()) do
		if IsValid(wep) then
			local prof = hg.botdriver.WeaponProfile(wep)
			if prof and prof.role ~= "sniper" and prof.role ~= "launcher" then
				if prof.role == "melee" then return true end
				if (wep.Clip1 and wep:Clip1() or 0) > 0 then return true end
				local reserve = 0
				if hg.botdriver.EffectiveReserve then
					reserve = hg.botdriver.EffectiveReserve(bot, wep)
				elseif wep.GetPrimaryAmmoType then
					reserve = bot:GetAmmoCount(wep:GetPrimaryAmmoType())
				end
				if reserve > 0 then return true end
			end
		end
	end
	return false
end

function hg.botdriver.CQBExcluded(bot, wep, dist)
	if (dist or math.huge) >= CQB_DIST then return false end
	local prof = hg.botdriver.WeaponProfile(wep)
	if not prof or (prof.role ~= "sniper" and prof.role ~= "launcher") then return false end
	return hg.botdriver.HasCQBAlternative(bot)
end

function hg.botdriver.EquipForRange(bot, brain, now, dist)
	local desired, dscore = hg.botdriver.BestWeaponFor(bot, dist, function(w)
		return hg.botdriver.CQBExcluded(bot, w, dist)
	end)
	if not IsValid(desired) then return false end

	local held = bot:GetActiveWeapon()
	if held == desired then return false end

	local heldUsable = IsValid(held) and ((ishgweapon(held) and held.ZoomPos ~= nil) or held.ismelee)

	if not heldUsable then
		bot:SelectWeapon(desired:GetClass())
		brain.wepSwitchAt = now
		return true
	end

	if hg.botdriver.CQBExcluded(bot, held, dist) then
		bot:SelectWeapon(desired:GetClass())
		brain.wepSwitchAt = now
		return true
	end

	if now < (brain.fireUntil or 0) then return false end
	if now - (brain.wepSwitchAt or 0) < SWITCH_CD then return false end

	local hscore = hg.botdriver.ScoreWeapon(bot, held, dist)
	if dscore > hscore * SWITCH_MARGIN then
		bot:SelectWeapon(desired:GetClass())
		brain.wepSwitchAt = now
		return true
	end

	return false
end

----------------------------------------------------------------------
-- Basic weapon-inventory queries. Ported from Trauma's sv_loot.lua (which is
-- otherwise dropped, rule 1 -- world-item pickup/corpse looting is out of
-- Phase 1 scope) because Engage/MedicalCheck/survival all need "what can this
-- bot fight with right now", which is an inventory query, not a loot plan.
----------------------------------------------------------------------

local cv_infreserve = ConVarExists("zc_bots_infinite_reserve") and GetConVar("zc_bots_infinite_reserve")
	or CreateConVar("zc_bots_infinite_reserve", "1", FCVAR_ARCHIVE,
		"Bots never exhaust magazine reserves (reload timing unchanged)", 0, 1)

function hg.botdriver.BotInfiniteReserve(bot)
	return cv_infreserve:GetBool() and IsValid(bot) and bot:IsBot()
end

function hg.botdriver.EffectiveReserve(bot, wep)
	local real = (wep.GetPrimaryAmmoType and bot:GetAmmoCount(wep:GetPrimaryAmmoType())) or 0
	if not hg.botdriver.BotInfiniteReserve(bot) then return real end
	local clipSize = (wep.GetMaxClip1 and wep:GetMaxClip1()) or 0
	return math.max(real, clipSize)
end

-- HGReloading verified: weapons/homigrad_base/sv_reload.lua.
hook.Add("HGReloading", "zc_bots_infinite_reserve", function(wep)
	if not IsValid(wep) then return end
	local owner = wep:GetOwner()
	if not IsValid(owner) or not owner.IsBot or not owner:IsBot() then return end
	if not hg.botdriver.BotInfiniteReserve(owner) then return end
	if not wep.GetPrimaryAmmoType or not wep.GetMaxClip1 then return end
	local ammoType = wep:GetPrimaryAmmoType()
	local clipSize = wep:GetMaxClip1()
	if not ammoType or ammoType < 0 or not clipSize or clipSize <= 0 then return end
	local deficit = clipSize + 2 - owner:GetAmmoCount(ammoType)
	if deficit > 0 then owner:GiveAmmo(deficit, ammoType, true) end
end)

function hg.botdriver.HasMelee(bot)
	for _, wep in ipairs(bot:GetWeapons()) do
		if IsValid(wep) and wep.ismelee then return wep:GetClass() end
	end
	return nil
end

function hg.botdriver.BestGun(bot)
	local fallback
	for _, wep in ipairs(bot:GetWeapons()) do
		if IsValid(wep) and ishgweapon(wep) and wep.ZoomPos ~= nil then
			if wep:Clip1() > 0 then return wep end
			if not fallback and hg.botdriver.EffectiveReserve(bot, wep) > 0 then
				fallback = wep
			end
		end
	end
	return fallback
end

function hg.botdriver.CanFight(bot)
	return hg.botdriver.BestGun(bot) ~= nil or hg.botdriver.HasMelee(bot) ~= nil
end

concommand.Add("zc_bots_debug_weaponscore", function(ply, _, args)
	if IsValid(ply) and not ply:IsSuperAdmin() then return end
	local dist = tonumber(args[1]) or 500
	if not IsValid(ply) then return end

	local function out(line) ply:PrintMessage(HUD_PRINTCONSOLE, line) end
	out(string.format("=== weapon scores @ %d u for %s ===", dist, ply:Nick()))
	local rows = {}
	for _, wep in ipairs(ply:GetWeapons()) do
		if IsValid(wep) then
			local prof = hg.botdriver.WeaponProfile(wep)
			if prof then
				local sc = hg.botdriver.ScoreWeapon(ply, wep, dist)
				rows[#rows + 1] = { score = sc, line = string.format("  %-26s %-8s dps=%-6.0f pen=%-3d score=%.1f",
					wep:GetClass(), prof.role, prof.dps, prof.pen, sc) }
			end
		end
	end
	table.sort(rows, function(a, b) return a.score > b.score end)
	for _, r in ipairs(rows) do out(r.line) end
end)
