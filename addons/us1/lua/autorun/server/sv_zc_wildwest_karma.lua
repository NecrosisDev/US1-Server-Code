-- ============================================================
--  ZC WILDWEST KARMA - halve karma loss in chosen hmcd round types
-- ------------------------------------------------------------
--  Joey: "drop karma loss and penalties by 50% in the wildwest
--  gamemode."
--
--  HOW KARMA LOSS WORKS (gamemodes/zcity/gamemode/libraries/guilt/
--  sv_guilt.lua:114, hook "HomigradDamage"/"GuiltReg"). Every
--  damage event that survives the exemption gates computes:
--      add = amt * MaximumHarm * 2 * PlayerClassEvent("Guilt")
--      if rnd.GuiltCheck then
--          mul, shouldBanGuilt = rnd.GuiltCheck(Attacker, Victim, add, harm, amt)
--          add = add * (mul or 1)          <-- THE MODE MULTIPLIER SLOT
--      end
--      Karma = Karma - add * max(1 - GuiltTable[Victim][Attacker], 0)
--  `rnd` is the MODE table - for every hmcd round type
--  (standard/soe/gunfreezone/wildwest) that is zb.modes.hmcd, and
--  `zb.CROUND` holds the round TYPE key. NO MODE IN THE GAMEMODE
--  DEFINES GuiltCheck; the slot is empty. This addon fills it.
--
--  WHAT IT DELIBERATELY DOES NOT TOUCH:
--   * `Attacker.Guilt += amt * 60` - the retaliation bookkeeping
--     (stock computes it from raw `amt` right after the GuiltCheck
--     call; our multiplier never touches `amt`). It feeds the
--     discount the VICTIM gets for shooting back - halving it would
--     make self-defence LESS forgiving. Left alone on purpose.
--   * Pat's Guilt overhaul (sv_pat_guilt_overhaul.lua). It sits ON
--     TOP of stock: it reads zb.HarmDoneKarma, which stock fills
--     with the POST-GuiltCheck `add` (sv_guilt:228). So the overhaul
--     sees the halved figure, Forgive refunds the halved figure, and
--     its self-defence window is untouched. Its manual Punish presets
--     (-5/-10/-15) and AutoExpire (-2) are flat and mode-blind - by
--     design; a victim choosing "Severe Punish" means it.
--   * Bans, seizures (<50), vomiting (<35), loot cut (<70/<30), aim
--     shake (<70), traitor eligibility - every one is a threshold on
--     the karma NUMBER, so cutting the loss makes all of them
--     proportionally rarer without touching their code.
--
--  ALREADY IN STOCK, WORTH KNOWING: a victim who is armed AND facing
--  the attacker (dot >= 0.8) costs HALF (sv_guilt:212). Wildwest arms
--  every non-traitor, so face-to-face duels are already 10 karma not
--  20; back-shots are full price. This addon halves on top of that.
--
--  SELF-HEALING INSTALL (same shape as zc_orgsched / zc_lootfast): a
--  1s sync verifies our function is still in the slot and reinstalls
--  after a late gamemode load or a hotload. If a future gamemode
--  update ever ships a real hmcd GuiltCheck, it is CAPTURED and
--  CHAINED - we call it first and multiply its result - so nothing
--  is silently overwritten. v1.2 uses immutable delegates and a shared modifier API.
--
--  Convars (FCVAR_ARCHIVE, live):
--    zc_wwkarma          1           master (0 = restore whatever was there)
--    zc_wwkarma_mul      0.5         karma-loss multiplier in the listed types
--    zc_wwkarma_types    wildwest    comma-separated zb.CROUND keys
--    zc_wwkarma_notify   0           tell the attacker their loss was reduced
--  Commands: zc_wwkarma_stats
--  Serverside only. Upgrading legacy v1.1 requires a clean server restart.
-- ============================================================
if not SERVER then return end

-- Legacy closures read a mutable K.orig. Do not attempt to migrate an already
-- installed legacy chain in place: a clean restart is required for this update.
if ZCWWKARMA and ZCWWKARMA.MultiplierAPI ~= 2 then
    ErrorNoHalt("[WWKarma] v1.2.0 requires a server restart to replace legacy callbacks safely.\n")
    return
end
ZCWWKARMA = ZCWWKARMA or {}
local K = ZCWWKARMA
K.Version, K.MultiplierAPI = "1.2.0", 2
K.modifiers = K.modifiers or {}
function K.AddMultiplier(key, fn)
    assert(type(key)=="string" and type(fn)=="function", "invalid karma multiplier")
    K.modifiers[key] = fn
    if K.Sync then K.Sync() end
end
function K.RemoveMultiplier(key, fn)
    if K.modifiers[key] == fn then
        K.modifiers[key] = nil
        if K.Sync then K.Sync() end
    end
end
K.stats = K.stats or { hits = 0, saved = 0, since = CurTime() }

local cv_on     = CreateConVar("zc_wwkarma", "1", FCVAR_ARCHIVE, "Scale karma loss in the listed round types (0 = stock)", 0, 1)
local cv_mul    = CreateConVar("zc_wwkarma_mul", "0.5", FCVAR_ARCHIVE, "Karma-loss multiplier in the listed round types", 0, 1)
local cv_types  = CreateConVar("zc_wwkarma_types", "wildwest", FCVAR_ARCHIVE, "Comma-separated zb.CROUND keys the multiplier applies to")
local cv_notify = CreateConVar("zc_wwkarma_notify", "0", FCVAR_ARCHIVE, "Chat-notify the attacker when their karma loss was reduced", 0, 1)

-- parsed once per convar change, not per damage event
local typeSet, typeSrc = {}, nil
local function activeType()
	local src = cv_types:GetString()
	if src ~= typeSrc then
		typeSet, typeSrc = {}, src
		for m in string.gmatch(src, "[^,]+") do
			m = string.Trim(string.lower(m))
			if m ~= "" then typeSet[m] = true end
		end
	end
	local cur = zb and zb.CROUND
	return cur ~= nil and typeSet[string.lower(tostring(cur))] == true
end

-- ------------------------------------------------------------
--  THE MULTIPLIER
--  Signature and return contract are the gamemode's:
--    mul, shouldBanGuilt = GuiltCheck(Attacker, Victim, add, harm, amt)
--  Preserve the delegated shouldBanGuilt decision; never add a ban ourselves.
-- ------------------------------------------------------------
local function guiltCheck(original, Attacker, Victim, add, harm, amt)
    -- Every closure captures its delegate permanently. Old wrappers never read
    -- a newly assigned K.orig. Nested WW wrappers pass through without scaling twice.
    local nested = (K.callDepth or 0) > 0
    local baseMul, baseBan
    if original then
        K.callDepth = (K.callDepth or 0) + 1
        local ok, m, b = pcall(original, Attacker, Victim, add, harm, amt)
        K.callDepth = K.callDepth - 1
        if ok then baseMul, baseBan = m, b end
    end
    if nested then return baseMul, baseBan end
    local keys = {}
    for key in pairs(K.modifiers) do keys[#keys+1] = key end
    table.sort(keys)
    for _,key in ipairs(keys) do
        local fn = K.modifiers[key]
        if fn then
            local ok, mul = pcall(fn, Attacker, Victim, add, harm, amt)
            if ok and type(mul)=="number" and mul==mul and mul>=0 and mul<math.huge then
                baseMul = (baseMul or 1) * mul
            else ErrorNoHalt("[WWKarma] Ignored invalid multiplier: " .. key .. "\n") end
        end
    end
    if not cv_on:GetBool() or not activeType() then return baseMul, baseBan end

	local mul = math.Clamp(cv_mul:GetFloat(), 0, 1)
	local finalMul = (baseMul or 1) * mul

	-- bookkeeping: what stock is ABOUT to subtract is
	--   add * finalMul * max(1 - GuiltTable[Victim][Attacker], 0)
	-- so the karma we saved is the same expression with (1 - mul).
	local retal = 1
	if zb and zb.GuiltTable and zb.GuiltTable[Victim] then
		retal = math.max(1 - (zb.GuiltTable[Victim][Attacker] or 0), 0)
	end
	local saved = (add or 0) * (baseMul or 1) * (1 - mul) * retal
	K.stats.hits = K.stats.hits + 1
	K.stats.saved = K.stats.saved + saved

	if false then -- Replaced by the silent, server-side karma review ledger.
		Attacker:ChatPrint(string.format("[Karma] Wild West: loss reduced by %d%% (-%.1f instead of -%.1f)",
			math.Round((1 - mul) * 100), (add or 0) * finalMul * retal, (add or 0) * (baseMul or 1) * retal))
	end

	return finalMul, baseBan
end

local myClosure -- assigned on install; each delegate is immutable

-- ------------------------------------------------------------
--  INSTALL / REVERT
-- ------------------------------------------------------------
local function modeTable()
	return zb and zb.modes and zb.modes.hmcd
end

local function install()
	local hmcd = modeTable()
	if not hmcd then return false end
    local cur = hmcd.GuiltCheck
    local original = cur
    if cur == K.mine then original = K.orig end
    if not isfunction(original) then original = nil end
    myClosure = function(...) return guiltCheck(original, ...) end
    K.orig, K.mine = original, myClosure
    hmcd.GuiltCheck = myClosure
	print("[WWKarma] installed on zb.modes.hmcd.GuiltCheck - x" .. cv_mul:GetFloat()
		.. " karma loss in [" .. cv_types:GetString() .. "]"
		.. (K.orig and " (chaining an existing GuiltCheck)" or ""))
	return true
end

local function uninstall()
	local hmcd = modeTable()
	if not hmcd then K.mine = nil return end
	-- K.mine must be checked: once uninstalled, both sides are nil and
	-- a bare == would "restore" (and print) every sync tick forever
	if K.mine and hmcd.GuiltCheck == K.mine then
		hmcd.GuiltCheck = K.orig -- nil in stock = slot back to empty
		print("[WWKarma] restored stock GuiltCheck slot")
	end
	K.mine = nil
end

K.Sync = function()
	if cv_on:GetBool() or next(K.modifiers) ~= nil then
		local hmcd = modeTable()
		if hmcd and (not K.mine or hmcd.GuiltCheck ~= K.mine or K.mine ~= myClosure) then install() end
	else
		uninstall()
	end
end
timer.Create("zc_wwkarma_sync", 1, 0, K.Sync)

-- ------------------------------------------------------------
--  COMMANDS
-- ------------------------------------------------------------
concommand.Add("zc_wwkarma_stats", function(ply)
	if IsValid(ply) and not ply:IsAdmin() then return end
	local function say(s)
		if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, s) else print(s) end
	end
	local hmcd = modeTable()
	local live = hmcd and hmcd.GuiltCheck == K.mine
	local modifierCount = 0
	for _ in pairs(K.modifiers) do modifierCount = modifierCount + 1 end
	local span = math.max(CurTime() - (K.stats.since or CurTime()), 1)
	say("=== zc_wwkarma v" .. K.Version .. " (" .. (cv_on:GetBool() and "ACTIVE" or "OFF") .. ") ===")
	say("installed : " .. (live and "yes" or "NO - slot is not ours") .. (K.orig and "  (chaining an original GuiltCheck)" or ""))
	say("modifier API: " .. K.MultiplierAPI .. " | registered modifiers: " .. modifierCount)
	say("multiplier: x" .. cv_mul:GetFloat() .. "  in types [" .. cv_types:GetString() .. "]")
	say("current   : zb.CROUND = " .. tostring(zb and zb.CROUND) .. "  -> " .. (activeType() and "SCALED" or "stock"))
	say("this map  : " .. K.stats.hits .. " penalised hits scaled, " .. string.format("%.1f", K.stats.saved)
		.. " karma saved total (" .. string.format("%.0f", span / 60) .. " min)")
end, nil, "Admin: print Wild West karma-loss savings.")

concommand.Add("zc_wwkarma_reset", function(ply)
	if IsValid(ply) and not ply:IsAdmin() then return end
	K.stats = { hits = 0, saved = 0, since = CurTime() }
	print("[WWKarma] stats reset")
end, nil, "Admin: reset the Wild West karma stats.")

print("[WWKarma] loaded - installs on zb.modes.hmcd once the gamemode exists (1s sync)")
