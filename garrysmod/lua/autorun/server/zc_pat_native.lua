-- Goob's ZCity: Pat's add-ons, nativized 2026-09-25 (owner: every Pat item leaves workshop collection 3736343437).
-- Byte-identical copies now live loose at their original paths, so hook ids, classes, convars and data are unchanged:
-- ULX Commands 3684466601, Persistent Props 3684346989, Defibrilator 3684389164, Hemostatic Syringe 3685875391 and
-- Bear Trap 3687832222 (lua/ plus their models/materials/sound). Revamped Punishment 3685034437 went native 2026-09-24
-- (lua/autorun/zc_guilt_legacy.lua, lua/zc_guilt_legacy/, the Justice-delegating server file, the guiltadmin module);
-- Spectator HUD 3686174019 needs no port because zc_observer retires it.
-- This file ships the two things a loose copy cannot ship by itself:
--   1. The Punishment client half. zc_guilt_legacy.lua includes zc_guilt_legacy/cl_guilt.lua on CLIENT, but only
--      lua/autorun/ and lua/autorun/client/ are sent automatically, so every client failed that include.
--   2. The item models/materials/sounds. Clients got them from the workshop download; once the items leave the
--      collection they come from FastDL (sv_downloadurl). A client that already has a file skips it.
-- data/zc_pat_native/receipt.txt proves each load from SSH. Rollback: pat_native_backup/<stamp>/rollback.sh in the
-- SSH home deletes exactly the files this port added.
if not SERVER then return end

AddCSLuaFile("zc_guilt_legacy/cl_guilt.lua")

local content = {
    -- Defibrilator (3684389164)
    "materials/effects/flat_normal.vtf",
    "materials/entities/weapon_defibrilator.png",
    "materials/entities/weapon_defibrilator_admin.png",
    "materials/models/v_models/weapons/eq_defibrillator/defibrillator.vmt",
    "materials/models/v_models/weapons/eq_defibrillator/defibrillator.vtf",
    "materials/models/v_models/weapons/eq_defibrillator/v_eq_defibrillator.vmt",
    "models/weapons/defib/v_defibrillator.dx80.vtx",
    "models/weapons/defib/v_defibrillator.dx90.vtx",
    "models/weapons/defib/v_defibrillator.mdl",
    "models/weapons/defib/v_defibrillator.vvd",
    "models/weapons/defib/w_eq_defibrillator.dx80.vtx",
    "models/weapons/defib/w_eq_defibrillator.dx90.vtx",
    "models/weapons/defib/w_eq_defibrillator.mdl",
    "models/weapons/defib/w_eq_defibrillator.phy",
    "models/weapons/defib/w_eq_defibrillator.sw.vtx",
    "models/weapons/defib/w_eq_defibrillator.vvd",
    "models/weapons/defib/w_eq_defibrillator_no_paddles.dx80.vtx",
    "models/weapons/defib/w_eq_defibrillator_no_paddles.dx90.vtx",
    "models/weapons/defib/w_eq_defibrillator_no_paddles.mdl",
    "models/weapons/defib/w_eq_defibrillator_no_paddles.phy",
    "models/weapons/defib/w_eq_defibrillator_no_paddles.sw.vtx",
    "models/weapons/defib/w_eq_defibrillator_no_paddles.vvd",
    "models/weapons/defib/w_eq_defibrillator_paddles.dx80.vtx",
    "models/weapons/defib/w_eq_defibrillator_paddles.dx90.vtx",
    "models/weapons/defib/w_eq_defibrillator_paddles.mdl",
    "models/weapons/defib/w_eq_defibrillator_paddles.sw.vtx",
    "models/weapons/defib/w_eq_defibrillator_paddles.vvd",
    "sound/ambient/energy/powerdown2.wav",
    "sound/defibl/charged.wav",
    "sound/defibl/defibrillator_use.wav",
    "sound/defibl/defibrillator_use_start.wav",
    "sound/defibl/deploy.wav",
    "sound/defibl/warmup.wav",
    "sound/heli/damage_alarm1.wav",
    "sound/heli/damage_alarm2.wav",
    "sound/heli/damage_alarm3.wav",
    "sound/heli/damage_alarm4.wav",
    "sound/player/survivor/hit/rifle_swing_hit_infected10.wav",
    "sound/player/survivor/hit/rifle_swing_hit_infected11.wav",
    "sound/player/survivor/hit/rifle_swing_hit_infected12.wav",
    "sound/player/survivor/hit/rifle_swing_hit_infected7.wav",
    "sound/player/survivor/hit/rifle_swing_hit_infected8.wav",
    "sound/player/survivor/hit/rifle_swing_hit_infected9.wav",
    "sound/player/survivor/hit/rifle_swing_hit_world.wav",
    "sound/weapons/bat/bat_swing_miss1.wav",
    "sound/weapons/bat/bat_swing_miss2.wav",
    "sound/weapons/empgun/arc1.wav",
    "sound/weapons/empgun/arc2.wav",
    "sound/weapons/empgun/emp.mp3",
    -- Hemostatic Syringe (3685875391)
    "materials/vgui/hemostaticinjector.png",
    "materials/vgui/hemostaticinjector.vmt",
    -- Bear Trap (3687832222)
    "materials/models/freeman/beartrap_diffuse.vtf",
    "materials/models/freeman/beartrap_specular.vtf",
    "materials/models/freeman/trap_dif.vmt",
    "materials/vgui/weapon_beartrap_homigrad.png",
    "materials/vgui/weapon_beartrap_homigrad.vmt",
    "models/stiffy360/beartrap.dx80.vtx",
    "models/stiffy360/beartrap.dx90.vtx",
    "models/stiffy360/beartrap.mdl",
    "models/stiffy360/beartrap.phy",
    "models/stiffy360/beartrap.sw.vtx",
    "models/stiffy360/beartrap.vvd",
    "models/stiffy360/beartrap.xbox.vtx",
    "models/stiffy360/c_beartrap.dx80.vtx",
    "models/stiffy360/c_beartrap.dx90.vtx",
    "models/stiffy360/c_beartrap.mdl",
    "models/stiffy360/c_beartrap.sw.vtx",
    "models/stiffy360/c_beartrap.vvd",
    "models/stiffy360/c_beartrap.xbox.vtx",
    "sound/beartrap.wav",
}
local registered = 0
for _, path in ipairs(content) do
    if file.Exists(path, "GAME") then
        resource.AddSingleFile(path)
        registered = registered + 1
    end
end

local pat = {
    ["3684466601"] = "ULX Commands", ["3684346989"] = "Persistent Props", ["3684389164"] = "Defibrilator",
    ["3685875391"] = "Hemostatic Syringe", ["3687832222"] = "Bear Trap", ["3685034437"] = "Revamped Punishment",
    ["3686174019"] = "Spectator HUD"
}
hook.Add("InitPostEntity", "ZCPatNative_Receipt", function()
    local lines = {os.date("!%Y-%m-%d %H:%M:%S UTC ") .. game.GetMap(), "content " .. registered .. "/" .. #content}
    for _, class in ipairs({"weapon_defibrilator_homigrad", "weapon_bloodclotter_sh", "weapon_beartrap_homigrad"}) do
        lines[#lines + 1] = class .. " " .. tostring(weapons.GetStored(class) ~= nil)
    end
    lines[#lines + 1] = "ent_pat_beartrap " .. tostring(scripted_ents.GetStored("ent_pat_beartrap") ~= nil)
    lines[#lines + 1] = "ulx.setkarma " .. tostring(ulx ~= nil and isfunction(ulx.setkarma))
    lines[#lines + 1] = "ulx.persistentpropsmenu " .. tostring(ulx ~= nil and isfunction(ulx.persistentpropsmenu))
    local boot = hook.GetTable().InitPostEntity or {}
    lines[#lines + 1] = "PersistentProps_LoadMapProps " .. tostring(boot.PersistentProps_LoadMapProps ~= nil)
    for _, addon in ipairs(engine.GetAddons()) do
        if pat[addon.wsid] then
            lines[#lines + 1] = "workshop " .. addon.wsid .. " " .. pat[addon.wsid] .. " mounted=" .. tostring(addon.mounted)
        end
    end
    file.CreateDir("zc_pat_native")
    file.Write("zc_pat_native/receipt.txt", table.concat(lines, "\n") .. "\n")
end)
