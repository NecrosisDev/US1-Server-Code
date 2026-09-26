-- Core UI must exist before entity/weapon markup and independently of InitPostEntity.
if SERVER then
    AddCSLuaFile("autorun/sh_zc_ui_bootstrap.lua")
    AddCSLuaFile("zc_ui_recovery/fonts.lua")
    AddCSLuaFile("initpost/menu-n-derma/derma/cl_frame.lua")
    AddCSLuaFile("zc_ui_recovery/voice.lua")
    local function sendTree(dir)
        local files,dirs=file.Find(dir.."/*","LUA")
        for _,name in ipairs(files)do
            if name:sub(-4)==".lua" and name:sub(1,3)~="sv_" then AddCSLuaFile(dir.."/"..name)end
        end
        for _,name in ipairs(dirs)do sendTree(dir.."/"..name)end
    end
    sendTree("initpost")
    return
end
hg=hg or {}
ZCUIRecovery=ZCUIRecovery or {errors={}}
local U=ZCUIRecovery
U.Version="20260916.2"
function U.Load(path)
    local ok,err=xpcall(function()include(path)end,debug.traceback)
    if not ok then
        U.errors[path]=tostring(err)
        ErrorNoHalt("[ZCity UI] Failed to load "..path..": "..tostring(err).."\n")
    else U.errors[path]=nil end
    return ok
end
local earlyFonts=U.Load("zc_ui_recovery/fonts.lua")
-- Fonts/frame alone are not the complete interface. Load the original skin,
-- settings and pause menu without depending on the InitPostEntity hook chain.
local coreVersion="20260916.2"
U.CoreOrder={"zc_ui_recovery/fonts.lua","initpost/cl_derma_skin.lua",
    "initpost/menu-n-derma/derma/cl_frame.lua",
    "initpost/menu-n-derma/derma/cl_menu_options.lua",
    "initpost/menu-n-derma/derma/cl_menu_panel.lua"}
U.CoreFiles={};for _,path in ipairs(U.CoreOrder)do U.CoreFiles[path]=true end
U.CoreLoaded=U.CoreReadyVersion==coreVersion and U.CoreLoaded or {}
if earlyFonts then U.CoreLoaded["zc_ui_recovery/fonts.lua"]=coreVersion end
function U.LoadCore()
    if U.CoreReadyVersion==coreVersion then return true end
    if not derma or not derma.SkinList or not derma.SkinList.Default then return false end
    for _,path in ipairs(U.CoreOrder)do
        if U.CoreLoaded[path]~=coreVersion then
            if not U.Load(path)then return false end
            U.CoreLoaded[path]=coreVersion
        end
    end
    if not derma.SkinList.ZCity or not vgui.GetControlTable("ZMainMenu")
        or not isfunction(hg.DrawSettings) then return false end
    U.CoreReadyVersion=coreVersion
    derma.RefreshSkins()
    timer.Remove("ZCityUI_CoreReady")
    hook.Remove("OnGamemodeLoaded","ZCityUI_CoreReady")
    return true
end
hook.Add("OnGamemodeLoaded","ZCityUI_CoreReady",function()U.LoadCore()end)
timer.Create("ZCityUI_CoreReady",0.25,20,function()U.LoadCore()end)
U.LoadCore()

U.Load("zc_ui_recovery/voice.lua")
hook.Add("OnScreenSizeChanged","ZCityUIFonts",function()U.Load("zc_ui_recovery/fonts.lua")end)
