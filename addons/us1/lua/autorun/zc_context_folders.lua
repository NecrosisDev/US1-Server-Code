if SERVER then
    AddCSLuaFile("zc_context_folders/client.lua")
    return
end
include("zc_context_folders/client.lua")
