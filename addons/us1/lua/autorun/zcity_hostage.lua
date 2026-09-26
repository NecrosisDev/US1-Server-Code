if SERVER then
    AddCSLuaFile()
    AddCSLuaFile("zcity_hostage/catalog.lua")
    AddCSLuaFile("zcity_hostage/cl_preview.lua")
    AddCSLuaFile("zcity_hostage/sh_gameplay.lua")
    AddCSLuaFile("zcity_hostage/sh_generated.lua")
    AddCSLuaFile("zcity_hostage/cl_gameplay.lua")
    resource.AddFile("models/zcity_hostage/gameplay_male.mdl")
    resource.AddFile("models/zcity_hostage/gameplay_female.mdl")
    resource.AddFile("models/zcity_hostage/hostage_embedded_male.mdl")
    resource.AddFile("models/zcity_hostage/hostage_embedded_female.mdl")
end

ZCityHostage = ZCityHostage or {}
ZCityHostage.Catalog = include("zcity_hostage/catalog.lua")
ZCityHostage.BySequence = {}
for _, clip in ipairs(ZCityHostage.Catalog) do
    ZCityHostage.BySequence[clip.sequence] = clip
end

include("zcity_hostage/sh_gameplay.lua")
if SERVER then
    include("zcity_hostage/sv_playback.lua")
    include("zcity_hostage/sv_gameplay.lua")
else
    include("zcity_hostage/cl_preview.lua")
    include("zcity_hostage/cl_gameplay.lua")
end
