-- Replicated enable variables must exist in both realms. Clients only render;
-- admission still checks the server-owned values and permissions.
if SERVER then AddCSLuaFile() end
local flags=SERVER and (FCVAR_ARCHIVE+FCVAR_REPLICATED) or FCVAR_REPLICATED
CreateConVar("zch_gameplay_enabled","0",flags,"Enable reviewed hostage gameplay",0,1)
CreateConVar("zsf_enabled","0",flags,"Enable reviewed stealth gameplay",0,1)
