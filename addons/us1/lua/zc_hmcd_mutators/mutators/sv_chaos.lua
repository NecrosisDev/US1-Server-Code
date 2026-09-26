local M = ZC_HMCD_MUTATORS
local GUN_CHANCE = 0.60
local Loot = include("zc_hmcd_mutators/chaos_loot.lua")

-- WFA 3666245817 firearms verified against its source archive.
-- Disabled upstream stubs (Goshan18, OCIPR Type 2, RFB) are excluded.
-- Explicit classes: shared bases/categories also include launchers and specials.
local guns = {}
for _, class in ipairs({
    "weapon_aa12", "weapon_aa12labs", "weapon_abakan94", "weapon_abzats",
    "weapon_adar215", "weapon_ak101", "weapon_ak102", "weapon_ak103d",
    "weapon_ak104d", "weapon_ak105d", "weapon_ak12", "weapon_ak308",
    "weapon_ak74modern", "weapon_akalpha", "weapon_akmnboss", "weapon_apsss",
    "weapon_ar10", "weapon_ar6951", "weapon_ark77", "weapon_armaguera",
    "weapon_avtsvo", "weapon_barret82", "weapon_bechowiec", "weapon_bizon",
    "weapon_blyskawichka", "weapon_colt733", "weapon_coltlec", "weapon_conan357",
    "weapon_cs5", "weapon_cz75sp01", "weapon_devochkaump", "weapon_dp27",
    "weapon_dsr1", "weapon_duplet", "weapon_dupletlong", "weapon_famasf1",
    "weapon_fg42", "weapon_fivsevn", "weapon_fn2000", "weapon_fnfal",
    "weapon_fnfalpara", "weapon_fnfnc", "weapon_fnmodeld", "weapon_g3a3",
    "weapon_gaussssrifffle", "weapon_gewehr43", "weapon_glock22",
    "weapon_grach", "weapon_grizzlymkv", "weapon_groza14a", "weapon_groza4",
    "weapon_hk11lmg", "weapon_hkp7", "weapon_hla_gruntsmg", "weapon_hla_ordrifle",
    "weapon_hla_suppmg", "weapon_hla_wallhshot", "weapon_ia2",
    "weapon_ithaca37", "weapon_kp31", "weapon_ksvk", "weapon_l42a1",
    "weapon_l85a2", "weapon_lapti26", "weapon_lr300", "weapon_m12beret",
    "weapon_m14", "weapon_m14dmr", "weapon_m16a2manohota", "weapon_m16a4",
    "weapon_m24remington", "weapon_m3greasegun", "weapon_m60e621", "weapon_m70",
    "weapon_m70zastavapist", "weapon_m712", "weapon_m9berettacommando", "weapon_madguylmg",
    "weapon_makarovpistolpb", "weapon_mat49", "weapon_mauserred9", "weapon_maverickshot",
    "weapon_mcxspear", "weapon_mg34", "weapon_mg36", "weapon_microuzi",
    "weapon_minebea", "weapon_minebeap220", "weapon_minimi", "weapon_miniuzi",
    "weapon_mjolnirmk18", "weapon_mk1", "weapon_mk18", "weapon_mk23",
    "weapon_moss500", "weapon_mp18", "weapon_mp18smg", "weapon_mp2ger",
    "weapon_mp40", "weapon_mp510mm", "weapon_mp5sd", "weapon_mpi81",
    "weapon_mpikm", "weapon_mpikm74", "weapon_mpl", "weapon_p250",
    "weapon_p320alligator", "weapon_p38", "weapon_p99", "weapon_pechenka",
    "weapon_pernachots", "weapon_ppk", "weapon_ppk42", "weapon_ppsh",
    "weapon_ppshboss", "weapon_protecta", "weapon_psg1", "weapon_python",
    "weapon_qbz97", "weapon_remington870oiblyat", "weapon_revolver412rex", "weapon_revolverequiem",
    "weapon_revolvermodel29", "weapon_revolvermts255", "weapon_revolversh12", "weapon_revolversw686",
    "weapon_revolverswr8", "weapon_rk62vel", "weapon_rk95sak",
    "weapon_rpd", "weapon_rpk16", "weapon_rpk74m", "weapon_rpk762",
    "weapon_sa58", "weapon_sakosnip", "weapon_sam180", "weapon_scarh",
    "weapon_scarl", "weapon_scarssr", "weapon_scorpievo3", "weapon_sjirgen",
    "weapon_spasik15", "weapon_sterling", "weapon_stoner63", "weapon_stonerlmg",
    "weapon_svds", "weapon_svtsvo", "weapon_swmp9", "weapon_t5000",
    "weapon_thompson", "weapon_tkpdbear", "weapon_toz194", "weapon_tti2011",
    "weapon_ttibenelli", "weapon_tticglock", "weapon_type79smg", "weapon_ublydok",
    "weapon_uzicarbine", "weapon_vityaz", "weapon_vp9hk", "weapon_vss",
    "weapon_vulkan", "weapon_vz58", "weapon_winchestersupa3", "weapon_wz28lmg",
    "weapon_xm8", "weapon_yellowboy", "weapon_zastavam93"
}) do guns[class] = true end


local weightBoost = {
    ["weapon_aa12"] = 3,
    ["weapon_aa12labs"] = 3,
    ["weapon_abakan94"] = 3,
    ["weapon_abzats"] = 3,
    ["weapon_adar215"] = 3,
    ["weapon_ak101"] = 3,
    ["weapon_ak102"] = 3,
    ["weapon_ak103d"] = 3,
    ["weapon_ak104d"] = 3,
    ["weapon_ak105d"] = 3,
    ["weapon_ak12"] = 3,
    ["weapon_ak308"] = 3,
    ["weapon_ak74modern"] = 3,
    ["weapon_akalpha"] = 3,
    ["weapon_akmnboss"] = 6,
    ["weapon_ar10"] = 3,
    ["weapon_ar6951"] = 3,
    ["weapon_ark77"] = 3,
    ["weapon_avtsvo"] = 3,
    ["weapon_barret82"] = 3,
    ["weapon_colt733"] = 3,
    ["weapon_coltlec"] = 3,
    ["weapon_cs5"] = 3,
    ["weapon_dp27"] = 3,
    ["weapon_dsr1"] = 3,
    ["weapon_famasf1"] = 3,
    ["weapon_fg42"] = 3,
    ["weapon_fn2000"] = 3,
    ["weapon_fnfal"] = 3,
    ["weapon_fnfalpara"] = 3,
    ["weapon_fnfnc"] = 3,
    ["weapon_fnmodeld"] = 3,
    ["weapon_g3a3"] = 3,
    ["weapon_gaussssrifffle"] = 6,
    ["weapon_gewehr43"] = 3,
    ["weapon_groza14a"] = 3,
    ["weapon_groza4"] = 3,
    ["weapon_hk11lmg"] = 3,
    ["weapon_hla_gruntsmg"] = 6,
    ["weapon_hla_ordrifle"] = 6,
    ["weapon_hla_suppmg"] = 6,
    ["weapon_hla_wallhshot"] = 6,
    ["weapon_ia2"] = 3,
    ["weapon_ksvk"] = 3,
    ["weapon_l42a1"] = 3,
    ["weapon_l85a2"] = 3,
    ["weapon_lapti26"] = 3,
    ["weapon_lr300"] = 3,
    ["weapon_m14"] = 3,
    ["weapon_m14dmr"] = 3,
    ["weapon_m16a2manohota"] = 3,
    ["weapon_m16a4"] = 3,
    ["weapon_m24remington"] = 3,
    ["weapon_m60e621"] = 3,
    ["weapon_m70"] = 3,
    ["weapon_madguylmg"] = 3,
    ["weapon_mcxspear"] = 3,
    ["weapon_mg34"] = 3,
    ["weapon_mg36"] = 3,
    ["weapon_minimi"] = 3,
    ["weapon_mjolnirmk18"] = 3,
    ["weapon_mk1"] = 3,
    ["weapon_mk18"] = 3,
    ["weapon_mp18"] = 3,
    ["weapon_mpikm"] = 3,
    ["weapon_mpikm74"] = 3,
    ["weapon_pechenka"] = 3,
    ["weapon_ppshboss"] = 6,
    ["weapon_psg1"] = 3,
    ["weapon_qbz97"] = 3,
    ["weapon_rk62vel"] = 3,
    ["weapon_rk95sak"] = 3,
    ["weapon_rpd"] = 3,
    ["weapon_rpk16"] = 3,
    ["weapon_rpk74m"] = 3,
    ["weapon_rpk762"] = 3,
    ["weapon_sa58"] = 3,
    ["weapon_sakosnip"] = 3,
    ["weapon_scarh"] = 3,
    ["weapon_scarl"] = 3,
    ["weapon_scarssr"] = 3,
    ["weapon_stoner63"] = 3,
    ["weapon_stonerlmg"] = 3,
    ["weapon_svds"] = 3,
    ["weapon_svtsvo"] = 3,
    ["weapon_t5000"] = 3,
    ["weapon_tkpdbear"] = 3,
    ["weapon_uzicarbine"] = 3,
    ["weapon_vss"] = 3,
    ["weapon_vulkan"] = 3,
    ["weapon_vz58"] = 3,
    ["weapon_wz28lmg"] = 3,
    ["weapon_xm8"] = 3,
    ["weapon_yellowboy"] = 3,
    ["weapon_zastavam93"] = 3,
}

local function positive(value)
    return type(value) == "number" and value == value and value > 0 and value <= 1000000
end

local function sourcePool(mode)
    local variant = type(mode.Types) == "table" and mode.Types[mode.Type]
    return type(variant) == "table" and variant.LootTable or mode.LootTable
end

local function buildPool(mode)
    if type(mode) ~= "table" or not mode.LootSpawn then
        return nil, "Homicide loot spawning is unavailable"
    end
    -- Respect unknown/custom selectors instead of silently bypassing them.
    if mode.GetLootTable ~= nil then return nil, "A custom loot selector is already installed" end
    if not weapons or type(weapons.GetStored) ~= "function" then
        return nil, "Weapon definitions are unavailable"
    end
    local ready, why = Loot.Ready()
    if not ready then return nil, why end
    local source = sourcePool(mode)
    if type(source) ~= "table" or #source > 128 then return nil, "Unsupported loot pool" end
    local pool, scanned = {}, 0
    for _, group in ipairs(source) do
        if type(group) == "table" and positive(group[1]) and type(group[2]) == "table" then
            local entries, total = group[2], 0
            scanned = scanned + #entries
            if scanned > 4096 then return nil, "Loot pool exceeds the Chaos safety limit" end
            for _, entry in ipairs(entries) do
                if type(entry) == "table" and positive(entry[1]) then total = total + entry[1] end
            end
            if total > 0 then
                for _, entry in ipairs(entries) do
                    if type(entry) == "table" and positive(entry[1]) and guns[entry[2]]
                        and weapons.GetStored(entry[2]) then
                        -- Preserve category rarity and rarity within the category.
                        pool[#pool + 1] = {group[1] * entry[1] / total * (weightBoost[entry[2]] or 1), entry[2]}
                    end
                end
            end
        end
    end
    if #pool == 0 then return nil, "No supported WFA firearms exist in the Chaos source pool" end
    return pool, nil, source
end

M:Register({
    ID = "chaos",
    Title = "Stable Chaos",
    Description = "More WFA guns, stronger and unique finds, and random compatible attachments. No launchers are boosted. Combat karma loss is halved.",
    Types = {standard = true, soe = true},
    MinPlayers = 2,
    Weight = 1,
    MidRound = true,
    CanStart = function(mode)
        local pool, reason = buildPool(mode)
        return pool ~= nil, reason
    end,
    Start = function(ctx)
        local mode = ctx.mode
        local pool, reason, source = buildPool(mode)
        if not pool then error(reason) end
        local selector
        selector = function(self)
            -- A retained closure cannot keep Chaos alive after cancellation,
            -- a mode change, or replacement of the source loot table.
            if self ~= mode or not ctx:Valid() or not mode.LootSpawn
                or sourcePool(mode) ~= source then return end
            if M:Random() < GUN_CHANCE then return pool end
            -- nil delegates to GenerateLoot's original time/karma/category logic.
        end
        ctx:Cleanup(function()
            if mode.GetLootTable == selector then mode.GetLootTable = nil end
        end)
        mode.GetLootTable = selector
        Loot.Install(ctx, guns, function() return sourcePool(mode) == source and mode.LootSpawn end)
        ctx.data.gunChance, ctx.data.gunEntries = GUN_CHANCE, #pool
    end
})
