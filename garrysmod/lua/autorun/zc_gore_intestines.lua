-- Companion to the existing ZCity Gore V2 torso caps. Staged, disabled by default.
if SERVER then
    AddCSLuaFile()
    AddCSLuaFile('zc_gore_intestines/client.lua')
    include('zc_gore_intestines/server.lua')
else
    include('zc_gore_intestines/client.lua')
end
