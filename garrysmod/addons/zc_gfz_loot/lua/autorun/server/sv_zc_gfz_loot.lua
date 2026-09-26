-- ============================================================
--  ZC GFZ LOOT v1.1 - gun-loot control for hmcd round types
-- ------------------------------------------------------------
--  Joey: "lower gun loot spawn in gun free zone" + "add wildwest,
--  sometimes people find modern weapons and its a bit goofy."
--
--  WHY THIS IS NEEDED: `MODE.Types.gunfreezone.LootTable =
--  MODE.LootTableStandard` (sv_homicide.lua:960) - the SAME table
--  standard (:741) and wildwest (:820) point at. "Gun free" is only
--  the STARTING loadout; ground spawns and loot boxes roll guns at
--  the standard rate (gun categories are 18/168 = ~10.7% of every
--  roll), and wildwest loot happily hands out glocks and AKs.
--
--  HOW LOOT ROLLS (sv_lootspawn.lua:182 `hg.GenerateLoot`, used by
--  ALL three callers - box contents :422 and both ground spawners
--  :697/:714): `cur = curRound.Types[rtype]` (MODE.Type is set, so
--  Types wins), `chances = cur.LootTable`, then
--  `hg.WeightedRandomSelect(chances, mul)` picks a CATEGORY by its
--  outer weight (sh_utility.lua:143 sums tab[i][1]) and a second
--  WeightedRandomSelect picks the item inside it. `mul` is the
--  karma/traitor/LootOnTime skew - it slides the roll along the
--  cumulative weight line, so category ORDER and weights are the
--  contract and both are preserved here.
--
--  TWO INDEPENDENT TREATMENTS, per round type:
--
--  1) CATEGORY SCALING (`zc_gfzloot_types`, default gunfreezone):
--     gun categories' outer weights x `zc_gfzloot_mul` (0.25 ->
--     ~2.9% guns, 0 -> none). Fewer guns of every kind.
--
--  2) ERA FILTER (`zc_gfzloot_eratypes`, default wildwest): gun
--     categories keep their stock weight, but INSIDE them every
--     `weapon_*` entry that is not on `zc_gfzloot_era_keep` gets its
--     item weight x `zc_gfzloot_era_mul` (default 0). Guns drop at
--     the normal rate - they're just period guns. The default keep
--     list is wildwest's own arsenal (yellowboy / winchester /
--     winchesterm1984 / python / doublebarrel(+short) / mauserred9 /
--     auto5 - what GunManLoot and TraitorLoot hand out, sv_homicide
--     :871-901/:827-835) plus the clearly-period loot-table pieces
--     (flintlock, musket, duplet, dupletlong, revolver2) and the
--     traitor's molotov + pipebomb. Non-weapon entries in gun
--     categories (*sight*/*barrel*) are never filtered.
--     If filtering empties a category (all item weights 0), its
--     OUTER weight is forced to 0 too - stock WeightedRandomSelect
--     returns the FIRST item of a zero-total list, which would
--     resurrect a modern gun.
--
--  A type listed in BOTH gets both (era filter, then scaled weight).
--  The shared LootTableStandard is NEVER touched - each treated type
--  gets its own outer copy; standard/soe keep rolling stock. Gun
--  categories are detected by SIGNATURE CLASSNAMES, not index, so a
--  gamemode reshuffle can't break it. Inner item lists are copied
--  ONLY for era-filtered gun categories; everything else shares the
--  original inner tables by reference (we never edit them).
--
--  Convars (FCVAR_ARCHIVE, live - changes rebuild within 1s):
--    zc_gfzloot           1            master (0 = restore stock references)
--    zc_gfzloot_types     gunfreezone  comma-separated: category scaling
--    zc_gfzloot_mul       0.25         gun-category weight multiplier
--    zc_gfzloot_eratypes  wildwest     comma-separated: era filter
--    zc_gfzloot_era_mul   0            non-period gun item multiplier
--    zc_gfzloot_era_keep  <list>       comma-separated classnames kept at
--                                      full weight ("weapon_" prefix optional)
--  Commands: zc_gfzloot_stats
--  Self-healing 1s sync (same shape as zc_wwkarma / zc_lootfast).
--  Serverside only = hotloadable.
-- ============================================================
if not SERVER then return end

ZCGFZLOOT = ZCGFZLOOT or {}
local K = ZCGFZLOOT
K.orig = K.orig or {}     -- [typeKey] = the LootTable reference the type had before us
K.copies = K.copies or {} -- [typeKey] = our treated outer copy

local DEFAULT_KEEP = "yellowboy,winchester,winchesterm1984,python,doublebarrel,doublebarrel_short,"
	.. "mauserred9,auto5,flintlock,musket,duplet,dupletlong,revolver2,hg_molotov_tpik,hg_pipebomb_tpik"

local cv_on       = CreateConVar("zc_gfzloot", "1", FCVAR_ARCHIVE, "Treat gun loot in the listed hmcd round types (0 = stock)", 0, 1)
local cv_types    = CreateConVar("zc_gfzloot_types", "gunfreezone", FCVAR_ARCHIVE, "Comma-separated Types keys: scale gun CATEGORY weights")
local cv_mul      = CreateConVar("zc_gfzloot_mul", "0.25", FCVAR_ARCHIVE, "Gun-category weight multiplier for zc_gfzloot_types (0 = no guns)", 0, 1)
local cv_eratypes = CreateConVar("zc_gfzloot_eratypes", "wildwest", FCVAR_ARCHIVE, "Comma-separated Types keys: era-filter gun ITEMS instead")
local cv_eramul   = CreateConVar("zc_gfzloot_era_mul", "0", FCVAR_ARCHIVE, "Item-weight multiplier for guns NOT on the keep list (era types)", 0, 1)
local cv_erakeep  = CreateConVar("zc_gfzloot_era_keep", DEFAULT_KEEP, FCVAR_ARCHIVE, "Comma-separated gun classnames kept at full weight in era types")

-- one classname from each stock gun category is enough; several per
-- category so a single weapon being removed can't blind us
local SIGNATURE_GUNS = {
	-- category {11, pistols}
	["weapon_mp-80"] = true, ["weapon_makarov"] = true, ["weapon_ruger"] = true, ["weapon_m1911"] = true,
	-- category {5, better pistols / shotguns / SMGs}
	["weapon_glock17"] = true, ["weapon_hk_usp"] = true, ["weapon_doublebarrel"] = true, ["weapon_moss500"] = true,
	-- category {2, rifles / SMGs}
	["weapon_mp5"] = true, ["weapon_ar15"] = true, ["weapon_remington870"] = true, ["weapon_kar98"] = true,
}

local function isGunCategory(items)
	if not istable(items) then return false end
	for i = 1, #items do
		local e = items[i]
		if istable(e) and SIGNATURE_GUNS[e[2]] then return true end
	end
	return false
end

local function parseList(str)
	local out = {}
	for m in string.gmatch(str or "", "[^,]+") do
		m = string.Trim(string.lower(m))
		if m ~= "" then out[#out + 1] = m end
	end
	return out
end

local function keepSet()
	local set = {}
	for _, name in ipairs(parseList(cv_erakeep:GetString())) do
		set[name] = true
		set["weapon_" .. name] = true -- prefix optional in the convar
	end
	return set
end

local function modeTable()
	return zb and zb.modes and zb.modes.hmcd
end

-- signature of every knob that shapes the copies; change -> rebuild
local function buildSig()
	return table.concat({
		cv_mul:GetFloat(), cv_types:GetString(),
		cv_eratypes:GetString(), cv_eramul:GetFloat(), cv_erakeep:GetString(),
	}, "|")
end

-- build a treated OUTER copy of `base`. Inner item lists are shared by
-- reference EXCEPT era-filtered gun categories, which get their own
-- copied list with scaled item weights.
local function buildCopy(base, catMul, keep, eraMul)
	local copy, gunCats, modernCut = {}, {}, 0
	for i = 1, #base do
		local cat = base[i]
		local w, items = cat[1], cat[2]
		if isGunCategory(items) then
			gunCats[#gunCats + 1] = i
			if keep then
				local newItems, total = {}, 0
				for j = 1, #items do
					local e = items[j]
					local iw, name = e[1], e[2]
					if isstring(name) and string.sub(name, 1, 7) == "weapon_" and not keep[name] then
						iw = iw * eraMul
						if iw < e[1] then modernCut = modernCut + 1 end
					end
					newItems[j] = { iw, name }
					total = total + iw
				end
				items = newItems
				-- stock WeightedRandomSelect returns the FIRST item of a
				-- zero-total list - never let an emptied category be picked
				if total <= 0 then w = 0 end
			end
			w = w * catMul
		end
		copy[i] = { w, items }
	end
	return copy, gunCats, modernCut
end

-- resolve what each listed type gets: catMul and/or era filter
local function typePlan()
	local plan = {}
	for _, key in ipairs(parseList(cv_types:GetString())) do
		plan[key] = plan[key] or {}
		plan[key].catMul = math.Clamp(cv_mul:GetFloat(), 0, 1)
	end
	for _, key in ipairs(parseList(cv_eratypes:GetString())) do
		plan[key] = plan[key] or {}
		plan[key].era = true
	end
	return plan
end

-- ------------------------------------------------------------
--  INSTALL / REVERT
-- ------------------------------------------------------------
local function install()
	local hmcd = modeTable()
	if not (hmcd and hmcd.Types) then return false end

	K.builtSig = buildSig()
	local keep = keepSet()
	local eraMul = math.Clamp(cv_eramul:GetFloat(), 0, 1)

	local done = {}
	for key, what in pairs(typePlan()) do
		local t = hmcd.Types[key]
		if t and istable(t.LootTable) then
			-- capture the type's true original exactly once: only when
			-- the current reference is not one of our own copies
			if t.LootTable ~= K.copies[key] then
				K.orig[key] = t.LootTable
			end
			local copy, gunCats, modernCut = buildCopy(K.orig[key],
				what.catMul or 1, what.era and keep or nil, eraMul)
			K.copies[key] = copy
			t.LootTable = copy
			done[#done + 1] = key
				.. (what.catMul and (" x" .. what.catMul) or "")
				.. (what.era and (" era(" .. modernCut .. " modern guns x" .. eraMul .. ")") or "")
				.. " [" .. #gunCats .. " gun cats]"
		end
	end

	if #done > 0 then
		print("[GFZLoot] installed: " .. table.concat(done, "; "))
	end
	return #done > 0
end

local function uninstall()
	local hmcd = modeTable()
	if not (hmcd and hmcd.Types) then K.copies = {} return end
	for key, copy in pairs(K.copies) do
		local t = hmcd.Types[key]
		if t and t.LootTable == copy and K.orig[key] then
			t.LootTable = K.orig[key]
			print("[GFZLoot] restored stock LootTable on " .. key)
		end
	end
	K.copies = {}
end

timer.Create("zc_gfzloot_sync", 1, 0, function()
	local hmcd = modeTable()
	if not (hmcd and hmcd.Types) then return end
	if cv_on:GetBool() then
		if buildSig() ~= K.builtSig then
			uninstall()
			install()
			return
		end
		-- reinstall if any planned type's slot is not ours (late load,
		-- another addon, or a gamemode reload put something else there)
		for key in pairs(typePlan()) do
			local t = hmcd.Types[key]
			if t and istable(t.LootTable) and t.LootTable ~= K.copies[key] then
				install()
				return
			end
		end
	else
		if next(K.copies) ~= nil then uninstall() end
	end
end)

-- ------------------------------------------------------------
--  COMMANDS
-- ------------------------------------------------------------
concommand.Add("zc_gfzloot_stats", function(ply)
	if IsValid(ply) and not ply:IsAdmin() then return end
	local function say(s)
		if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, s) else print(s) end
	end
	local hmcd = modeTable()
	say("=== zc_gfzloot (" .. (cv_on:GetBool() and "ACTIVE" or "OFF") .. ") ===")
	say("scale types [" .. cv_types:GetString() .. "] x" .. cv_mul:GetFloat()
		.. "  |  era types [" .. cv_eratypes:GetString() .. "] modern x" .. cv_eramul:GetFloat())
	if not (hmcd and hmcd.Types) then say("gamemode not loaded yet") return end
	for key, what in pairs(typePlan()) do
		local t = hmcd.Types[key]
		if not t then
			say(key .. ": NO SUCH TYPE on zb.modes.hmcd")
		elseif not istable(t.LootTable) then
			say(key .. ": type has no LootTable")
		else
			local live = t.LootTable == K.copies[key]
			local total, guns = 0, 0
			for i = 1, #t.LootTable do
				local cat = t.LootTable[i]
				total = total + cat[1]
				if isGunCategory(cat[2]) then guns = guns + cat[1] end
			end
			say(key .. ": slot " .. (live and "OURS" or (cv_on:GetBool() and "NOT OURS (sync will retake it)" or "stock"))
				.. "  |  gun-category share " .. string.format("%.1f", total > 0 and guns / total * 100 or 0) .. "%"
				.. " (" .. guns .. "/" .. total .. ")")
			for i = 1, #t.LootTable do
				local cat = t.LootTable[i]
				local tag = "      "
				if isGunCategory(cat[2]) then
					if what.era then
						local kept, cut = 0, 0
						for j = 1, #cat[2] do
							local e = cat[2][j]
							if isstring(e[2]) and string.sub(e[2], 1, 7) == "weapon_" then
								if e[1] > 0 then kept = kept + 1 else cut = cut + 1 end
							end
						end
						tag = "GUNS: " .. kept .. " period kept, " .. cut .. " modern cut"
					else
						tag = "GUNS <- weight scaled"
					end
				end
				say(string.format("   cat %d: weight %-6s %s (%d items)", i, cat[1], tag, #cat[2]))
			end
		end
	end
end)

print("[GFZLoot] loaded - installs on zb.modes.hmcd.Types once the gamemode exists (1s sync)")
