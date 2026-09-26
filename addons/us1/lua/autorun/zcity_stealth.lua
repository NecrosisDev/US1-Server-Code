ZCityStealth=ZCityStealth or {}
local S=ZCityStealth
S.Version="20260920.stealth3"
if SERVER then
    AddCSLuaFile()
    for _,name in ipairs({"sh_assets","sh_actions","sh_runtime","cl_interface","cl_presentation"}) do AddCSLuaFile("zcity_stealth/"..name..".lua") end
    for _,name in ipairs({"stealth_anims","stealth_anims_female","stealth_gameplay_male","stealth_gameplay_female"}) do
        resource.AddFile("models/zcity_stealth/"..name..".mdl")
    end
end
S.Assets=include("zcity_stealth/sh_assets.lua")
S.Actions=include("zcity_stealth/sh_actions.lua")
include("zcity_stealth/sh_runtime.lua")
if SERVER then include("zcity_stealth/sv_runtime.lua") else
    include("zcity_stealth/cl_interface.lua") include("zcity_stealth/cl_presentation.lua")
end
