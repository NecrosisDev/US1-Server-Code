-- HD character textures (opt-in). Owner 2026-09-25: off by default, toggled from GoobOS
-- Settings > Graphics (convar zc_hd_textures). When on, a Workshop pack downloads once in the
-- background and mounts; each appearance material this client meets then has its $basetexture
-- pointed at zc_hd/<original texture path>: faces at 2x (AI upscale, per-area mix that keeps
-- skin grain), and full mipmaps for textures that shipped without them. Off restores the
-- original texture objects at once. Built by work/appearance-hd/build_pack.py.
-- Safety: nothing touches a zc_hd path before the pack is mounted (game.MountGMA never reloads a
-- material or texture already cached as missing), and a swap that lands on the error texture is
-- undone on the spot, so a missing or partial pack always falls back to the standard look.
if not CLIENT then return end

local HD = ZCHDTextures or {}
ZCHDTextures = HD
HD.Version = "20260925.2"

local WSID = "PENDING" -- Workshop id of zc_hd_textures.gma; "PENDING" until the owner publishes it
local PROBE = "materials/zc_hd/models/bloo_ltcom_zel/citizens/facemaps/art_facemap.vtf"
local PACK_MB = 305
-- A byte-exact local copy in garrysmod/data wins over the download (the owner's pre-publish test).
-- pack2.dat = faces + default faces + weapons + accessories (the 1st build used pack.dat, left for the old client).
local LOCAL_PACK, LOCAL_BYTES = "zc_hd/pack2.dat", 304957772

local cv = CreateClientConVar("zc_hd_textures", "0", true, false,
    "Sharper character faces and smoother distant clothing.", 0, 1)

-- material name -> HD texture name. Built from manifest.lua: per directory, space-separated
-- material names; "name=texture" where the material's texture is not at its own path.
local MANIFEST_DIRS = {
    ["bubba/bubba_spam"] = "spam_lid spam_texture",
    ["combine_sniper"] = "bolt bolt_metal=combine_sniper/rubber rubber",
    ["comida"] = "lata_jtun=comida/jataatun",
    ["distac/41"] = "big_glassis032 brows=distac/41/hair feminine_mask folding glass_of_glassissiisi=distac/41/ct_sas_glass mfdoom=distac/41/mask1 monocl_glass=distac/41/ct_sas_glass red=distac/41/ct_sas_glas remen scotch scotch_prop viktor vjyjrkm=distac/41/untitled z",
    ["glide/weapons"] = "homing_launcher_decals homing_launcher_sight",
    ["griggs"] = "aviators_black_colorable aviators_white_colorable aviators_whole_colorable bigglasses_black_colorable bigglasses_white_colorable bigglasses_whole_colorable cap_colorable fedora_black_line_colorable fedora_colorable fedora_line_colorable hat01_black_line_colorable hat01_colorable hat01_white_line_colorable hat03_colorable hat03_lines_colorable hat03_two_lines_colorable headphones_colorable ringster_mask_01_colorable ringster_mask_01_reverse_colorable ringster_mask_01_whole_colorable ringster_mask_02_colorable ringster_mask_02_reverse_colorable ringster_mask_02_whole_colorable scarf_colorable snowbeanie_colorable tophat_black_line_colorable tophat_white_colorable tophat_white_line_colorable",
    ["griggs/models"] = "2011x_cap",
    ["jaanus"] = "shuriken",
    ["maxofs2d/models"] = "camera",
    ["models/arctic_nvgs/aviators"] = "item_equipment_glasses_aviator=models/arctic_nvgs/aviators/item_equipment_glasses_aviator_diff",
    ["models/bloo_ltcom_zel/citizens/facemaps"] = "art_facemap art_facemap3 art_facemap4 art_facemap5 art_facemap6 art_facemap7 art_facemap8 art_facemap9 chau_facemap chau_facemap2 chau_facemap3 chau_facemap4 chau_facemap5 erdim_facemap erdim_facemap10 erdim_facemap11 erdim_facemap2 erdim_facemap3 erdim_facemap4 erdim_facemap5 erdim_facemap6 erdim_facemap7 erdim_facemap8 erdim_facemap9 eric_facemap eric_facemap2 eric_facemap3 eric_facemap4 eric_facemap5 eric_facemap6 eric_facemap7 eric_facemap8 eric_facemap9 joe_facemap joe_facemap2 joe_facemap3 joe_facemap4 joe_facemap5 joe_facemap6 joe_facemap7 joe_facemap8 joe_facemap9 joey_facemap joey_facemap2 joey_facemap3 joey_facemap4 joey_facemap5 joey_facemap6 kanisha_cylmap kanisha_cylmap2 kanisha_cylmap3 kanisha_cylmap4 kanisha_cylmap5 kanisha_cylmap6 kim_facemap kim_facemap2 kim_facemap3 kim_facemap4 kim_facemap6 lakeetra_facemap lakeetra_facemap2 lakeetra_facemap3 lakeetra_facemap4 lakeetra_facemap5 mike_facemap mike_facemap2 mike_facemap3 mike_facemap4 mike_facemap5 mike_facemap6 mike_facemap7 mike_facemap8 naomi_facemap naomi_facemap2 naomi_facemap3 naomi_facemap4 naomi_facemap5 naomi_facemap6 naomi_facemap_new sandro_facemap sandro_facemap10 sandro_facemap2 sandro_facemap3 sandro_facemap4 sandro_facemap5 sandro_facemap6 sandro_facemap7 sandro_facemap8 sandro_facemap9 ted_facemap ted_facemap10 ted_facemap2 ted_facemap4 ted_facemap5 ted_facemap6 ted_facemap7 ted_facemap8 ted_facemap9 van_facemap van_facemap2 van_facemap3 van_facemap4 van_facemap5 van_facemap6 van_facemap7 van_facemap8 vance_facemap vance_facemap2 vance_facemap3 vance_facemap4 vance_facemap5 vance_facemap6 vance_facemap7 vance_facemap8 vance_facemap9",
    ["models/bloocobalt/l4d/items"] = "adrenaline_shot w_eq_adrenaline=models/bloocobalt/l4d/items/adrenaline_shot w_eq_painpills",
    ["models/brick"] = "brick",
    ["models/captainbigbutt/skeyler/accessories/glasses"] = "glasses01 glasses04",
    ["models/captainbigbutt/skeyler/hats/cowboyhat"] = "cowboyhat",
    ["models/captainbigbutt/skeyler/hats/fedora"] = "fedora_black",
    ["models/captainbigbutt/skeyler/hats/strawhat"] = "strawhat",
    ["models/captainbigbutt/skeyler/hats/sunhat"] = "sunhat",
    ["models/captainbigbutt/skeyler/hats/zhat"] = "z_gold",
    ["models/characters/citizen/male/facemaps"] = "erdim_facemap=models/characters/citizen/male/facemaps/erdim_facemap1_d eric_facemap=models/characters/citizen/male/facemaps/eric_facemap1_d sandro_facemap6=models/characters/citizen/male/facemaps/sandro_facemap6_d vance_facemap=models/characters/citizen/male/facemaps/vance_facemap1_d",
    ["models/codzombies"] = "_-gmtl_t6_wpn_claymore_col",
    ["models/combine_mine"] = "combine_mine03",
    ["models/eft/ags30"] = "receiver0_d receiver1_d receiver2_d tripod1_d",
    ["models/eli"] = "eli_tex4z",
    ["models/eu_homicide/handcuffs"] = "metal",
    ["models/fc5/weapons/_shared"] = "bullets=models/fc5/weapons/_shared/bullets_a crosshairs=models/fc5/weapons/_shared/crosshairs_a",
    ["models/fello"] = "f_matchboxtex",
    ["models/gibs/hgibs"] = "skull1 spine",
    ["models/gleb"] = "kickme nerd zcap",
    ["models/gregrogers/warren"] = "gregrogers_warren_facemap gregrogers_warren_facemap_g02 gregrogers_warren_facemap_g03 gregrogers_warren_facemap_g03m",
    ["models/griggs/de_train"] = "train_metalceiling_02=de_train/train_metalceiling_02",
    ["models/griggs/griggs/zcity_accessories"] = "john_grace_cross=griggs/zcity_accessories/john_grace_cross",
    ["models/grinchfox/head_wear"] = "baseballhat_camo baseballhat_mayor baseballhat_nx baseballhat_pornhub baseballhat_rf baseballhat_sippas baseballhat_topkek caphat_camo=models/grinchfox/head_wear/baseballhat_camo caphat_mayor=models/grinchfox/head_wear/baseballhat_mayor caphat_nurse caphat_nx=models/grinchfox/head_wear/baseballhat_nx caphat_pacman caphat_pine caphat_pornhub=models/grinchfox/head_wear/baseballhat_pornhub caphat_rf=models/grinchfox/head_wear/baseballhat_rf caphat_sippas=models/grinchfox/head_wear/baseballhat_sippas caphat_topkek=models/grinchfox/head_wear/baseballhat_topkek christmas_hat jewhat jewhat_cosher longhair=models/grinchfox/head_wear/hair tophat tophat2 tophat3",
    ["models/grinchfox/weapons"] = "handcuffs",
    ["models/healthvial"] = "healthvial",
    ["models/hmc/weapons"] = "hmc_wpn_metal_01b=models/hmc/weapons/hmc_wpn_metal_01a hmc_wpn_rifle_m4a1_02a",
    ["models/humans/female/group01"] = "chau_facemap joey_facemap kanisha_cylmap kim_facemap lakeetra_facemap naomi_facemap",
    ["models/humans/male/group01"] = "art_facemap camoflage_colorable comfy_colorable cub_facemap erdim_cylmap eric_facemap joe_facemap mailman_colorable miami_colorable mike_facemap sandro_facemap ted_facemap van_facemap vance_facemap winter_colorable wolker_colorable",
    ["models/humans/male/group02"] = "cub_facemap",
    ["models/humans/male/group03"] = "cub_facemap",
    ["models/humans/male/group03m"] = "cub_facemap",
    ["models/humans/modern/male/male_02"] = "facemap_01",
    ["models/humans/modern/male/male_03"] = "facemap_03 facemap_04 facemap_06",
    ["models/humans/modern/male/male_04"] = "facemap_01 facemap_02 facemap_03 facemap_04",
    ["models/humans/modern/male/male_05"] = "facemap_05",
    ["models/humans/modern/male/male_06"] = "facemap_02 facemap_03 facemap_04 facemap_05",
    ["models/humans/modern/male/male_07"] = "facemap_01",
    ["models/humans/modern/male/male_08"] = "facemap_02",
    ["models/humans/modern/male/male_09"] = "facemap_01 facemap_02 facemap_04",
    ["models/humans/slav"] = "desert dksclothes6 epstein1 gunsmith1 gunsmith2 multi trap_sheet_10=models/humans/slav/trap_sheet_10_d trap_sheet_11=models/humans/slav/trap_sheet_11_d trap_sheet_2=models/humans/slav/trap_sheet_2_d trap_sheet_8=models/humans/slav/trap_sheet_8_d trap_sheet_9=models/humans/slav/trap_sheet_9_d woodland",
    ["models/humans/slav/art"] = "art_facemap1 art_facemap2 art_facemap3 art_facemap4",
    ["models/humans/slav/barney"] = "barneyface donaldface",
    ["models/humans/slav/cohrt"] = "cohrt",
    ["models/humans/slav/dobrogradstuff"] = "advanced_aller american_face_old_male07 bobr_1 carmine_face_belch facenr07 facenr0901 facenr0902 golova_stick golovastik golovastik_nordd1 lacharro_face lybitelpivasa nrider_face serface sergey vepran xv_erik_susig xv_greg_bandizam xv_nicholas_bandizam xv_nikitashevchuk_bandizam xv_simonrus_bandizam",
    ["models/humans/slav/dobrogradstuff/clothes"] = "advanced_leon alfred_clothes_mrthepro blackjacket bobr_2 dpsport_1 dpsport_b evrei foo_clothes forest green_clothes_zeeke hoodsport jenssuitblue jenssuitgreen jimmy_clothes_belch kennet_sheet piter_clothes_zeeke rigocchisuit stanli_clothes_belch vincenzosuit xv_puhovik_bandizam zeeke",
    ["models/humans/slav/mossman"] = "mossman_goth_hair",
    ["models/humans/slav/octo"] = "autumn06_sheet autumn08_sheet autumn09_sheet autumn10_sheet autumn11_sheet autumn12_sheet halloween14_sheet_women halloween15_sheet_women halloween16_sheet_women halloween19_sheet halloween20_sheet halloween22_sheet halloween24_sheet halloween25_sheet modern01_sheet modern02_sheet modern03_sheet modern04_sheet modern05_sheet modern06_sheet modern07_sheet modern08_sheet seaman_d spring09_sheet spring10_sheet spring11_sheet spring12_sheet spring13_sheet spring14_sheet spring15_sheet spring16_sheet spring17_sheet spring18_sheet spring19_sheet spring20_sheet spring21_sheet spring22_sheet spring23_sheet winter10_sheet_woman winter12_sheet_woman winter13_sheet_woman winter15_sheet_woman winter16_sheet_woman winter17_sheet winter17_sheet_woman winter19_sheet winter20_sheet winter21_sheet winter22_sheet winter23_sheet winter28_sheet winter29_sheet winter32_sheet winter9_sheet_woman wolfslag01_sheet",
    ["models/humans/slav/octo/1"] = "halloween22_sheet=models/humans/slav/octo/halloween22_sheet halloween24_sheet=models/humans/slav/octo/halloween24_sheet",
    ["models/items"] = "healthkit01 w_grenadesheet",
    ["models/items/phalanx"] = "item_phalanx_d",
    ["models/jmod_tower"] = "baseballcap",
    ["models/joe/nomad"] = "wpn_ak104_mount_dovetail_diff wpn_ak104_muzzle_troy_claymore_diff wpn_akm_sight_rear_diff wpn_foregrip_magpul_rvg_diff",
    ["models/kleiner"] = "glassesfront_walter mouth",
    ["models/morphine_syrette"] = "label plastic rubber",
    ["models/mossman"] = "mossman_hair",
    ["models/mu_hmcd_mansion"] = "marble",
    ["models/mu_hmcd_mansion/weapon_cuestick"] = "wood",
    ["models/mu_hmcd_mansion/weapon_knives"] = "metal_knife=models/mu_hmcd_mansion/weapon_knives/metal_knife3 wood_knife",
    ["models/mu_hmcd_mansion/weapon_pencils"] = "rubber wood wood_colored",
    ["models/mu_hmcd_mansion/weapon_poker"] = "metal_poker wood_poker",
    ["models/nh2_bdg"] = "bandages",
    ["models/player/items"] = "top_hat",
    ["models/props/cs_militia"] = "axe",
    ["models/props_c17"] = "furniture_detailprops001a potspans001a tools_vise01a",
    ["models/props_junj"] = "flare flare_burnt=models/props_junk/flare_burnt",
    ["models/props_junk"] = "garbage003a_01 glassbottle01a glassbottle01b popcan01a popcan02a popcan03a shovel01a wood_palletcrate001a woodcrates01a woodcrates02a",
    ["models/rawjesus/wear"] = "anon",
    ["models/tacint_extras/tec9"] = "ext=models/tacint_extras/tec9/ext_df stock=models/tacint_extras/tec9/stock_df",
    ["models/tourniquet"] = "tourniquet tourniquet_white",
    ["models/w_models/eq_medkit"] = "w_eq_medkit",
    ["models/w_models/eq_pipebomb"] = "w_jj_pipebomb=models/v_models/weapons/eq_pipebomb/v_jj_pipebomb",
    ["models/weapons/awoi/w_models/english_dragoon_pistol"] = "english_dragoon_pistol",
    ["models/weapons/m84"] = "weapon_w_m84_dm",
    ["models/weapons/shak12"] = "shak12_bullets=models/weapons/shak12/bullets_df shak12_mag=models/weapons/shak12/magazine_df",
    ["models/weapons/tfa_cso/bunkerbuster"] = "bunkerbusterltd_v",
    ["models/weapons/tfa_ins2/ak_pack/ak74n"] = "ak74n_rail=models/weapons/tfa_ins2/ak_pack/ak74n/ak_siderail_diffuse",
    ["models/weapons/tfa_ins2/hk416"] = "bullet=models/weapons/tfa_ins2/hk416/bullet_dm mag=models/weapons/tfa_ins2/hk416/mag_dm",
    ["models/weapons/tfa_ins2/m67"] = "weapon_w_m67_dm",
    ["models/weapons/tfa_nmrih/me_crowbar"] = "w_me_crowbar_d",
    ["models/weapons/tfa_nmrih/me_hatchet"] = "w_me_hatchet_d",
    ["models/weapons/tfa_nmrih/me_machete"] = "w_me_machete_d",
    ["models/weapons/tfa_nmrih/me_pipe_lead"] = "w_me_pipe_lead_d",
    ["models/weapons/tfa_nmrih/me_sledge"] = "w_me_sledge_d",
    ["models/weapons/tfa_nmrih/tool_extinguisher"] = "w_tool_extinguisher_d",
    ["models/weapons/v_bugbait"] = "bugbait_new_detail",
    ["models/weapons/v_crossbow"] = "string",
    ["models/weapons/v_models/ar16"] = "ar16_sp_diff ar16_sp_diff_m=models/weapons/v_models/ar16/ar16_sp_diff",
    ["models/weapons/v_supplmg"] = "suppressor_sight",
    ["models/weapons/v_toolgun"] = "screen=models/weapons/v_toolgun/screen_bg toolgun2 toolgun3",
    ["models/weapons/w_357"] = "w_357",
    ["models/weapons/w_alyx_gun_xsi"] = "alexgun",
    ["models/weapons/w_annabelle"] = "gun",
    ["models/weapons/w_irifle"] = "w_irifle",
    ["models/weapons/w_models/jgd-5"] = "additions=models/weapons/v_models/jgd-5/additions substance=models/weapons/v_models/jgd-5/substance",
    ["models/weapons/w_models/shadowshammer"] = "hammer",
    ["models/weapons/w_models/w_mach_m249"] = "w_mach_m249",
    ["models/weapons/w_models/w_pist_deagle"] = "w_pist_deagle",
    ["models/weapons/w_models/w_pist_elite"] = "w_pist_elite",
    ["models/weapons/w_models/w_pist_fiveseven"] = "w_pist_fiveseven",
    ["models/weapons/w_models/w_pist_glock18"] = "w_pist_glock18",
    ["models/weapons/w_models/w_pist_p228"] = "w_pist_p228",
    ["models/weapons/w_models/w_pist_usp"] = "w_pist_usp",
    ["models/weapons/w_models/w_rif_ak47"] = "w_rif_ak47",
    ["models/weapons/w_models/w_rif_m4a1"] = "w_rif_m4a1",
    ["models/weapons/w_models/w_shot_m3super90"] = "w_shot_m3super90",
    ["models/weapons/w_models/w_shot_xm1014"] = "w_shot_xm1014",
    ["models/weapons/w_models/w_smg_mac10"] = "w_smg_mac10",
    ["models/weapons/w_models/w_smg_mp5"] = "w_smg_mp5",
    ["models/weapons/w_models/w_smg_p90"] = "w_smg_p90",
    ["models/weapons/w_models/w_smg_tmp"] = "w_smg_tmp",
    ["models/weapons/w_models/w_smg_ump45"] = "w_smg_ump45",
    ["models/weapons/w_models/w_snip_awp"] = "w_snip_awp",
    ["models/weapons/w_models/w_snip_g3sg1"] = "w_snip_g3sg1",
    ["models/weapons/w_models/w_snip_scout"] = "w_snip_scout",
    ["models/weapons/w_pistol"] = "pistol",
    ["models/weapons/w_rocket_launcher"] = "w_rpg_sheet",
    ["models/weapons/w_shotgun"] = "w_shotgun",
    ["models/weapons/w_smg1"] = "w_smg2",
    ["models/z_city/glass"] = "glasswindowbreak070a=glass/glasswindowbreak070a",
    ["models/z_city/z_city"] = "zcity_ducttape=z_city/zcity_ducttape",
    ["nmrih/models/weapons/bow_deerhunter"] = "w_bow_deerhunter_bits_d w_bow_deerhunter_d",
    ["pwb/models/weapons/w_hk23e"] = "vgrip=pwb/models/weapons/v_hk23e/vgrip",
    ["pwb/models/weapons/w_m98b"] = "huy-glass=decals/huy-glass",
    ["pwb/models/weapons/w_sg552"] = "sg55_grip=pwb/models/weapons/v_sg552/sg55_grip sg55_internals=pwb/models/weapons/v_sg552/sg55_internals sg55_magazine=pwb/models/weapons/v_sg552/sg55_magazine sg55_rail=pwb/models/weapons/v_sg552/sg55_rail",
    ["pwb2/models/weapons/w_p90"] = "barrel=pwb2/models/weapons/v_p90/barrel_diff bullet=pwb2/models/weapons/v_p90/bullet rmr=pwb2/models/weapons/v_p90/rmr_diff",
    ["pwb2/models/weapons/w_pkm"] = "decals_d=pwb2/models/weapons/v_pkm/decals",
    ["sal/acc"] = "backpack_1 backpack_1_2 backpack_1_3 backpack_3 backpack_3_2 scarf01 scarf01_2 scarf01_3 scarf01_4 scarf01_5 scarf01_6 scarf01_7",
    ["sal/hats"] = "hat01 hat01_2 hat01_3 hat01_4 hat01_5 hat01_6 hat01_7 hat01_8 hat03 hat03_2 hat03_3 hat03_4 hat03_5 hat07 hat07_10 hat07_11 hat07_2 hat07_3 hat07_4 hat07_5 hat07_6 hat07_7 hat07_8 hat07_9 headphones headphones_2 headphones_3 headphones_4",
    ["zcity"] = "pinklizard_body",
    ["zcity/weapons/zoraki"] = "mat1 phys=zcity/weapons/zoraki/mat1",
}
local MANIFEST = {}
for dir, list in pairs(MANIFEST_DIRS) do
    for item in string.gmatch(list, "%S+") do
        local name, tex = string.match(item, "^([^=]+)=(.+)$")
        name = name or item
        MANIFEST[dir .. "/" .. name] = "zc_hd/" .. (tex or (dir .. "/" .. name))
    end
end
HD.Manifest = MANIFEST

HD.granted = HD.granted or false
HD.mounted = HD.mounted or false -- a mounted GMA stays mounted for the session, so keep it across refreshes
HD.swapped = HD.swapped or {} -- material name -> { IMaterial, original ITexture }
HD.failed = HD.failed or {}

local function say(text)
    local N = ZCGoobApps and ZCGoobApps.Notify
    if N and N.Enabled and N.Banner and N.Enabled() then
        N.Banner(text)
        return
    end
    chat.AddText(Color(150, 200, 255), "[HD textures] ", color_white, text)
end

-- Pack -------------------------------------------------------------------------------------------

local function mountFile(path)
    local ok = game.MountGMA(path)
    if not ok or not file.Exists(PROBE, "GAME") then return false end
    HD.mounted = true
    return true
end
HD.MountLocal = mountFile -- test hook: mount a local copy, e.g. "data/zc_hd/pack.dat"

local waiting = {}
local function ensurePack(done)
    if HD.mounted then done(true) return end
    -- FastDL route (owner 2026-09-25): the server registers the textures for download at join,
    -- so they are already in the game filesystem and nothing needs mounting.
    if file.Exists(PROBE, "GAME") then
        HD.mounted = true
        done(true)
        return
    end
    if file.Size(LOCAL_PACK, "DATA") == LOCAL_BYTES then
        done(mountFile("data/" .. LOCAL_PACK), "mount failed")
        return
    end
    if WSID == "PENDING" then done(false, "not published yet") return end
    waiting[#waiting + 1] = done
    if #waiting > 1 then return end -- a download is already running
    steamworks.DownloadUGC(WSID, function(path)
        local ok = path ~= nil and mountFile(path)
        local list = waiting
        waiting = {}
        for _, cb in ipairs(list) do cb(ok, path and "mount failed" or "download failed") end
    end)
end

-- Swap -------------------------------------------------------------------------------------------

local function swap(name)
    local hdName = MANIFEST[name]
    if not hdName or HD.swapped[name] or HD.failed[name] then return end
    local mat = Material(name)
    local orig = mat and not mat:IsError() and mat:GetTexture("$basetexture")
    if not orig then
        HD.failed[name] = true
        return
    end
    mat:SetTexture("$basetexture", hdName)
    local now = mat:GetTexture("$basetexture")
    if not now or now:IsErrorTexture() then
        mat:SetTexture("$basetexture", orig)
        HD.failed[name] = true
        return
    end
    HD.swapped[name] = { mat, orig }
end

local function active()
    return HD.granted and HD.mounted and cv:GetBool()
end

function HD.ScanEntity(ent)
    if not (active() and IsValid(ent)) then return end
    local mats = ent:GetMaterials()
    if not mats then return end
    for i = 1, #mats do
        local sub = ent:GetSubMaterial(i - 1)
        local name = string.lower((sub ~= nil and sub ~= "") and sub or mats[i])
        if MANIFEST[name] and not HD.swapped[name] then swap(name) end
    end
end

-- Worn accessories are client-side models in ent.modelAccess (new_appearance/cl_init.lua).
local function scanAccessories(ent)
    local acc = ent.modelAccess
    if not istable(acc) then return end
    for _, m in pairs(acc) do HD.ScanEntity(m) end
end

-- Players (body, face, accessories, the gun in hand: firearms have no viewmodel, first person
-- shows the world model), ragdolls with their accessories, and weapons lying on the ground.
function HD.Scan()
    if not active() then return end
    for _, ply in ipairs(player.GetAll()) do
        HD.ScanEntity(ply)
        scanAccessories(ply)
        HD.ScanEntity(ply:GetActiveWeapon())
    end
    for _, rag in ipairs(ents.FindByClass("prop_ragdoll")) do
        HD.ScanEntity(rag)
        scanAccessories(rag)
    end
    for _, wep in ipairs(ents.FindByClass("weapon_*")) do HD.ScanEntity(wep) end
end
timer.Create("ZCHDTextures.Scan", 1, 0, HD.Scan)

function HD.RestoreAll()
    for _, s in pairs(HD.swapped) do
        s[1]:SetTexture("$basetexture", s[2])
    end
    HD.swapped = {}
    HD.failed = {}
end

-- Toggle -----------------------------------------------------------------------------------------

local function start()
    if not (HD.granted and cv:GetBool()) then return end
    if HD.mounted then
        HD.Scan()
        return
    end
    if WSID ~= "PENDING" then say("Downloading HD character textures (" .. PACK_MB .. " MB). They switch on when ready.") end
    ensurePack(function(ok, why)
        if not ok then
            say("HD character textures are unavailable right now (" .. tostring(why) .. "). Using standard textures.")
            return
        end
        if cv:GetBool() and HD.granted then
            say("HD character textures on.")
            HD.Scan()
        end
    end)
end

cvars.AddChangeCallback("zc_hd_textures", function(_, _, new)
    if tobool(new) then start() else HD.RestoreAll() end
end, "ZCHDTextures")

-- Settings row -----------------------------------------------------------------------------------
-- hg.settings:AddOpt feeds the legacy ZCity options menu and GoobOS Settings, which copies
-- hg.settings.tbl by category and draws a 0..1 convar as a toggle. Only granted players get the
-- row (tester lock); only our own row is ever removed from "Graphics".

local function registerSettings()
    if not (hg and istable(hg.settings) and hg.settings.AddOpt) then return false end
    local S = hg.settings
    if S.tbl.Graphics then
        S.tbl.Graphics.zc_hd_textures = nil
        if next(S.tbl.Graphics) == nil then S.tbl.Graphics = nil end
    end
    if HD.granted then
        S:AddOpt("Graphics", "zc_hd_textures", "HD character textures")
        S.tbl.Graphics.zc_hd_textures[8] = 1
    end
    return true
end

local function registerWhenReady()
    if registerSettings() then return end
    timer.Create("ZCHDTextures.Settings", 1, 30, function()
        if registerSettings() then timer.Remove("ZCHDTextures.Settings") end
    end)
end

-- Tester grant (sv_zc_hd_textures.lua) -----------------------------------------------------------

net.Receive("zc_hd_textures_grant", function()
    HD.granted = net.ReadBool()
    registerWhenReady()
    if HD.granted then start() else HD.RestoreAll() end
end)

local function hello()
    net.Start("zc_hd_textures_hello")
    net.SendToServer()
end
hook.Add("InitPostEntity", "ZCHDTextures.Hello", hello)
if IsValid(LocalPlayer()) then hello() end
