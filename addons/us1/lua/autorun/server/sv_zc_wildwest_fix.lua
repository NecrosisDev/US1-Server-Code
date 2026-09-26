-- ============================================================
--  ZC WILDWEST FIX - unfreeze the cowboy gun rolls
-- ------------------------------------------------------------
--  Something server-side reseeds the shared math.random, freezing
--  any deterministic call pattern (proven on juggernaut kits: the
--  same picks every round). Wildwest rolls with math.random in two
--  places, so its hands were almost certainly frozen too:
--    * the traitor's revolver: Winchester M1894 OR Colt Python
--    * every innocent's cowboy gun: one of EIGHT
--  This addon replaces Types.wildwest.TraitorLoot + GunManLoot at
--  runtime (juggernaut/GFZ injection pattern - NO gamemode edits)
--  with faithful copies whose rolls use a PRIVATE RNG nothing can
--  reseed. Behavior otherwise identical (kits, cosmetics, sling,
--  cloak, gunner gear all copied exactly).
--
--  v1.1 (deliberate change, per Joey): the traitor's gun now rolls
--  from the SAME 8-gun pool as the innocents, instead of stock's
--  Winchester M1894 | Colt Python coin flip. He still gets 1 spare
--  mag on top of the loaded clip (innocents stay full-clip-only).
--
--  zc_wildwest_fix 0 reverts to the stock functions live.
--  Serverside only = hotloadable. DRIFT CAVEAT: copied from the
--  8/21 "ZCITY from server" snapshot - if the gamemode ever
--  updates wildwest's kits, re-sync these copies.
-- ============================================================
if not SERVER then return end

ZCWWFIX = ZCWWFIX or {}

local cv_on = CreateConVar("zc_wildwest_fix", "1", FCVAR_ARCHIVE, "Wildwest: private-RNG loadout rolls (0 = stock frozen rolls)", 0, 1)

-- private RNG - v1.2: Park-Miller (Lehmer) LCG. The old constants
-- (state * 1103515245) overflowed Lua's double precision (~2^61,
-- where doubles quantize to steps of 512), permanently zeroing the
-- LOW bits of the state - and `state % n` reads exactly those bits,
-- so every power-of-2 pool froze at index 1: rnd(8) returned 1
-- forever and the whole server spawned with the Yellowboy. 16807 *
-- state stays under 2^53 = exact math, and the roll now scales from
-- the FULL state instead of the low bits.
local seedState = (math.floor(SysTime() * 1000) % 2147483646) + 1
local function rnd(n)
	seedState = (seedState * 16807) % 2147483647
	return math.floor(seedState / 2147483647 * n) + 1
end

local INNO_GUNS = {
	"weapon_yellowboy",
	"weapon_winchesterm1984",
	"weapon_winchester",
	"weapon_python",
	"weapon_doublebarrel",
	"weapon_doublebarrel_short",
	"weapon_mauserred9",
	"weapon_auto5",
}

-- stock wildwest TraitorLoot + v1.1 change: the gun rolls from the
-- SAME 8-pool as the innocents (was winchesterm1984 | python)
local function FixedTraitorLoot(ply)
	if not cv_on:GetBool() and ZCWWFIX.origTraitorLoot then
		return ZCWWFIX.origTraitorLoot(ply)
	end

	ply:Give("weapon_sogknife")
	ply:Give("weapon_hg_type59_tpik")
	ply:Give("weapon_adrenaline")
	local gun = ply:Give(INNO_GUNS[rnd(#INNO_GUNS)])
	if IsValid(gun) then
		ply:GiveAmmo(gun:GetMaxClip1() * 1, gun:GetPrimaryAmmoType(), true)
	end
	ply:Give("weapon_traitor_ied")
	ply:Give("weapon_hg_molotov_tpik")
	ply:Give("weapon_hg_smokenade_tpik")

	if ply.organism then
		ply.organism.recoilmul = 1.0
		if ply.organism.stamina then ply.organism.stamina.range = 220 end
	end

	ply:SetNetVar("CurPluv", "pluvfancy")

	local inv = ply:GetNetVar("Inventory")
	if istable(inv) then
		inv["Weapons"] = inv["Weapons"] or {}
		inv["Weapons"]["hg_sling"] = true
		ply:SetNetVar("Inventory", inv)
	end
end

-- faithful copy of the stock wildwest GunManLoot, rnd() for the inno gun
local function FixedGunManLoot(gunner)
	if not cv_on:GetBool() and ZCWWFIX.origGunManLoot then
		return ZCWWFIX.origGunManLoot(gunner)
	end

	for _, v in player.Iterator() do
		if IsValid(v) and v:Team() ~= TEAM_SPECTATOR then
			-- cowboy cosmetics for everyone (stock: stetson + formal + tint)
			local pv = v
			timer.Simple(1, function()
				if not IsValid(pv) then return end
				local Appearance = pv:GetNetVar("Accessories", {"none"})
				if istable(Appearance) then
					Appearance[1] = "stetson"
				else
					Appearance = "stetson"
				end
				pv:SetNetVar("Accessories", Appearance)
				local tbl = pv.CurAppearance
				if istable(tbl) and istable(tbl.AClothes) then
					tbl.AClothes["main"] = "formal"
					tbl.AClothes["pants"] = "formal"
					tbl.AClothes["boots"] = "formal"
					tbl.AColor = Color(255, 176, 137)
					if hg and hg.Appearance and hg.Appearance.ForceApplyAppearance then
						pcall(hg.Appearance.ForceApplyAppearance, pv, tbl)
					end
				end
			end)

			if v.isTraitor then
				-- traitor keeps his own kit
			elseif v.isGunner then
				v:Give("weapon_yellowboy")
				v:Give("weapon_python")
				v:Give("weapon_handcuffs")
				v:Give("weapon_handcuffs_key")
			else
				local weapon = v:Give(INNO_GUNS[rnd(#INNO_GUNS)], true)
				if IsValid(weapon) then
					pcall(function() weapon:SetClip1(weapon:GetMaxClip1()) end)
				end
			end

			v:SetNetVar("CurPluv", "pluvfancy")

			local inv = v:GetNetVar("Inventory")
			if istable(inv) then
				inv["Weapons"] = inv["Weapons"] or {}
				inv["Weapons"]["hg_sling"] = true
				v:SetNetVar("Inventory", inv)
			end
		end
	end
end

local function inject()
	local hmcd = zb and zb.modes and zb.modes["hmcd"]
	local ww = hmcd and hmcd.Types and hmcd.Types.wildwest
	if not ww or not ww.TraitorLoot then return false end

	ZCWWFIX.origTraitorLoot = ZCWWFIX.origTraitorLoot or ww.TraitorLoot
	ZCWWFIX.origGunManLoot = ZCWWFIX.origGunManLoot or ww.GunManLoot
	ww.TraitorLoot = FixedTraitorLoot
	ww.GunManLoot = FixedGunManLoot

	print("[Wildwest Fix] loadout rolls unfrozen (private RNG); zc_wildwest_fix 0 reverts")
	return true
end

local function startInject()
	if inject() then return end
	local tries = 0
	timer.Create("zc_wwfix_inject", 2, 15, function()
		tries = tries + 1
		if inject() or tries >= 15 then timer.Remove("zc_wwfix_inject") end
	end)
end

hook.Add("InitPostEntity", "zc_wwfix_boot", startInject)
startInject()
