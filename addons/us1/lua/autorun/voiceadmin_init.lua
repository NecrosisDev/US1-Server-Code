VoiceAdmin = VoiceAdmin or {}

if SERVER then
    AddCSLuaFile("voiceadmin/sh_core.lua")
    AddCSLuaFile("voiceadmin/cl_main.lua")
end

include("voiceadmin/sh_core.lua")

if SERVER then
    include("voiceadmin/sv_main.lua")
else
    include("voiceadmin/cl_main.lua")
end
