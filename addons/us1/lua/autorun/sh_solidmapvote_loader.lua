local root = "solidmapvote/"

local function LoadClient(path)
    if SERVER then 
        AddCSLuaFile(path)
    else 
        include(path)
    end
end

local function LoadServer(path)
    if SERVER then 
        include(path) 
    end
end

local function LoadShared(path)
    if SERVER then 
        AddCSLuaFile(path) 
    end
    include(path)
end

print("[SolidMapVote] Starting Manual Load...")

SolidMapVote = SolidMapVote or {}
SolidMapVote.ZCityRepair = "1.0.1"
if SERVER then resource.AddFile("sound/rtv.wav"); resource.AddFile("sound/nortv.wav") end

if file.Exists(root .. "sh_mapvote_config.lua", "LUA") then
    LoadShared(root .. "sh_mapvote_config.lua")
elseif file.Exists(root .. "mapvote_config.lua", "LUA") then
    LoadShared(root .. "mapvote_config.lua")
end

LoadClient(root .. "core/lib/b-draw_lib.lua")

LoadClient(root .. "core/client/cl_net.lua")
LoadClient(root .. "core/client/cl_mapvote.lua")

LoadServer(root .. "core/server/sv_net.lua")
LoadServer(root .. "core/server/sv_mapvote.lua")
LoadServer(root .. "core/server/sv_reroll.lua")
LoadServer(root .. "core/server/sv_hooks.lua")

local vgui_files = file.Find(root .. "vgui/*.lua", "LUA")
for _, f in ipairs(vgui_files) do
    LoadClient(root .. "vgui/" .. f)
end

print("[SolidMapVote] ZCity repair 1.0.1 loaded")
