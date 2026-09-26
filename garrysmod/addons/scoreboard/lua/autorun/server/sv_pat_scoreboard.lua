if not SERVER then return end
AddCSLuaFile("zc_scoreboard/cl_boot.lua")
AddCSLuaFile("zc_scoreboard/cl_self_status.lua")
AddCSLuaFile("zc_scoreboard/cl_services.lua")
AddCSLuaFile("zc_scoreboard/cl_model.lua")
AddCSLuaFile("zc_scoreboard/cl_skin.lua")
AddCSLuaFile("zc_scoreboard/cl_view.lua")
AddCSLuaFile("zc_scoreboard/cl_controller.lua")
include("zc_scoreboard/sv_settings.lua")
include("zc_scoreboard/sv_playtime.lua")
include("zc_scoreboard/sv_round.lua")
ZCScoreboardServerVersion="20260923.roster3"
