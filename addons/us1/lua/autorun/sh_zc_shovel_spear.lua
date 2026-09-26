-- ============================================================
--  ZC SHOVEL SPEAR - "Break off shovel head" in the Q radial
-- ------------------------------------------------------------
--  Snap the head off a shovel and you are left holding a long
--  sharpened shaft: weapon_hg_spear.
--
--  HOW IT PLUGS IN (no gamemode files touched):
--  homigrad's Q wheel is built from `hg.radialOptions`, refilled
--  by every handler on the public "radialOptions" hook
--  (cl_hud.lua:214). The wheel re-runs those handlers every 0.25s
--  WHILE IT IS OPEN (cl_hud.lua:259 menuPanel.Think), so the
--  "must be holding a shovel" gate is LIVE - draw the shovel and
--  the option appears, holster it and it disappears, without
--  closing the menu. This is the same public hook the WWE wedge
--  uses.
--
--  MODELLED ON ZCITY'S OWN CRAFTABLE (weapon_hg_glassshard.lua:161
--  "Tape glass shard" = shard + duct tape -> taped shard): a
--  clientside radialOptions entry that only fires a concommand,
--  plus a SERVERSIDE concommand that re-validates everything and
--  does the actual swap. The client never decides anything - it
--  only asks.
--
--  DIFFERENCE FROM THE STOCK CRAFT, ON PURPOSE: the stock one
--  gates on ply:HasWeapon(). This one gates on the ACTIVE weapon,
--  per Joey - it must be the shovel IN YOUR HANDS.
--
--  INVENTORY CORRECTNESS (the subtle part). homigrad tracks carried
--  weapons in `ply.inventory.Weapons[class]`, filled by the
--  WeaponEquip hook and cleared by PlayerDroppedWeapon
--  (sv_inventory.lua:83 / :109). Removing a weapon entity fires
--  NEITHER hook, so a naive StripWeapon leaves a STALE inventory
--  entry pointing at a dead entity - the stock tape craft has
--  exactly that bug. We clear the entry ourselves, the same way
--  PlayerDroppedWeapon does, before removing the entity. Giving the
--  spear then fires WeaponEquip normally and re-syncs the netvar.
--
--  We also remove the EXACT weapon entity in hand rather than
--  calling StripWeapon(class), so a second shovel stashed in the
--  inventory is never destroyed along with it.
--
--  Convars (FCVAR_ARCHIVE + FCVAR_REPLICATED so the client can hide
--  the option when it is off):
--    zc_shovelspear      1    master
--    zc_shovelspear_cd   1    per-player cooldown in seconds
--  Shared file: serverside concommand + clientside radial entry.
--  The SERVER half hotloads; the radial entry needs clients to have
--  the file, so it appears after the next RESTART.
-- ============================================================

if SERVER then AddCSLuaFile() end

local SHOVEL = "weapon_hg_shovel"
local SPEAR  = "weapon_hg_spear"
local LABEL  = "Break off shovel head"

-- The convars are CREATED serverside only - creating a replicated convar
-- on the client errors - and read back lazily by name on both realms, so
-- the client works whether or not the replicated value has arrived yet.
if SERVER then
	CreateConVar("zc_shovelspear", "1", FCVAR_ARCHIVE + FCVAR_REPLICATED,
		"Allow breaking the head off a shovel to make a spear", 0, 1)
	CreateConVar("zc_shovelspear_cd", "1", FCVAR_ARCHIVE + FCVAR_REPLICATED,
		"Per-player cooldown between shovel breaks (seconds)", 0, 30)
end

local function cvBool(name, def)
	local c = GetConVar(name)
	if not c then return def end
	return c:GetBool()
end

local function cvFloat(name, def)
	local c = GetConVar(name)
	if not c then return def end
	return c:GetFloat()
end

-- shared gate, so the client shows exactly what the server will allow
local function canBreak(ply)
	if not cvBool("zc_shovelspear", true) then return false end
	if not IsValid(ply) or not ply:IsPlayer() or not ply:Alive() then return false end

	local org = ply.organism
	if org and org.otrub then return false end -- unconscious

	local wep = ply:GetActiveWeapon()
	if not IsValid(wep) or wep:GetClass() ~= SHOVEL then return false end

	-- already carrying a spear: refuse rather than eat the shovel for nothing
	if ply:HasWeapon(SPEAR) then return false, "spear" end

	return true, nil, wep
end

-- ------------------------------------------------------------
--  SERVER - the only place anything actually happens
-- ------------------------------------------------------------
if SERVER then

	local function tell(ply, msg)
		if ply.Notify then ply:Notify(msg, 20) else ply:ChatPrint(msg) end
	end

	concommand.Add("zc_break_shovel", function(ply)
		if not IsValid(ply) or not ply:IsPlayer() then return end
		if (ply.zc_shovelspear_cd or 0) > CurTime() then return end

		local ok, why, wep = canBreak(ply)
		if not ok then
			if why == "spear" then tell(ply, "I am already carrying a spear.") end
			return
		end

		ply.zc_shovelspear_cd = CurTime() + cvFloat("zc_shovelspear_cd", 1)

		-- 1. drop the inventory entry the way PlayerDroppedWeapon would,
		--    but ONLY if it points at this exact weapon
		local inv = ply.inventory
		if inv and inv.Weapons and inv.Weapons[SHOVEL] == wep then
			inv.Weapons[SHOVEL] = nil
			ply:SetNetVar("Inventory", inv)
		end

		-- 2. consume the shovel in hand (this entity, not the class)
		wep:Remove()

		-- 3. hand over the shaft. Give fires WeaponEquip, which puts the
		--    spear into ply.inventory.Weapons and re-broadcasts the netvar.
		local spear = ply:Give(SPEAR)
		if IsValid(spear) then
			ply:SelectWeapon(SPEAR)
		else
			tell(ply, "The shaft splintered - nothing usable left.")
			return
		end

		-- 4. the snap: wood shaft cracking + the metal head hitting the deck
		ply:EmitSound("physics/wood/wood_plank_break" .. math.random(1, 4) .. ".wav", 70, math.random(95, 105), 1, CHAN_ITEM)
		ply:EmitSound("physics/metal/metal_box_impact_hard" .. math.random(1, 3) .. ".wav", 65, math.random(110, 125), 0.8, CHAN_ITEM)

		hook.Run("ZC_ShovelSpear", ply, spear) -- for anything that wants to react
	end, nil, "Break the head off your shovel to make a spear (also in the Q radial).")

	print("[ShovelSpear] loaded - `zc_break_shovel` live (radial entry needs clients to have the file: next restart)")
	return
end

-- ------------------------------------------------------------
--  CLIENT - the radial entry, nothing more
-- ------------------------------------------------------------
local function breakShovel()
	RunConsoleCommand("zc_break_shovel")
end

hook.Add("radialOptions", "zc_shovel_spear", function()
	if not canBreak(LocalPlayer()) then return end
	hg.radialOptions[#hg.radialOptions + 1] = { breakShovel, LABEL }
end)
