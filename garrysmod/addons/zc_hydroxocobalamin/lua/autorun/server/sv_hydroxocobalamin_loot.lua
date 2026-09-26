-- ============================================================
--  Hydroxocobalamin - hmcd loot injection
-- ------------------------------------------------------------
--  Adds weapon_hydroxocobalamin to BOTH homicide loot pools at
--  naloxone rarity (0.5), without editing gamemode files:
--    * MODE.LootTable          -> SOE rounds
--    * MODE.LootTableStandard  -> Standard / Gun Free Zone /
--                                 Wild West (and Fear, which
--                                 inherits hmcd's machinery)
--  It inserts into the medical group (the one holding
--  weapon_bandage_sh). Idempotent: safe to hotload, never
--  double-inserts.
-- ============================================================
if not SERVER then return end

local CLASS  = "weapon_hydroxocobalamin"
local WEIGHT = 0.5   -- = naloxone's weight in the SOE medical group

local function injectInto(tbl, label)
	if not istable(tbl) then return false end
	for _, group in ipairs(tbl) do
		local items = group[2]
		if istable(items) then
			local isMedGroup, already = false, false
			for _, it in ipairs(items) do
				if istable(it) then
					if it[2] == "weapon_bandage_sh" then isMedGroup = true end
					if it[2] == CLASS then already = true end
				end
			end
			if isMedGroup then
				if not already then
					items[#items + 1] = { WEIGHT, CLASS }
					print("[Hydroxocobalamin] added to " .. label .. " loot pool (weight " .. WEIGHT .. ")")
				end
				return true
			end
		end
	end
	return false
end

local function inject()
	local MODE = zb and zb.modes and zb.modes["hmcd"]
	if not MODE then return false end
	local a = injectInto(MODE.LootTable, "hmcd SOE")
	local b = injectInto(MODE.LootTableStandard, "hmcd Standard/GFZ/WildWest")
	return a or b
end

hook.Add("InitPostEntity", "Hydroxo_LootInject", function()
	timer.Simple(5, function()
		if not inject() then
			print("[Hydroxocobalamin] hmcd mode table not found - loot NOT injected")
		end
	end)
end)

-- hotload support: if the server is already running, inject right now
if zb and zb.modes then inject() end
