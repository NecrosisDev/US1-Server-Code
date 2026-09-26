-- This release is observer-only. It contains no enforcement activation command.
if not SERVER then return end
local existing=ZCJusticeV3Shadow
if existing and existing.version=="3.3.0-shadow.2" and existing.enabled
    and ZCJusticeV3Integration and ZCJusticeV3Integration.enabled then return end
if ZCJusticeV3Integration and ZCJusticeV3Integration.Stop then ZCJusticeV3Integration:Stop()end
if existing and type(existing.Stop)=="function" then existing:Stop()end
local function install()
    if engine.ActiveGamemode()~="zcity" then return end
    local ok,result=pcall(function()
        local B=include("zc_justice_v3/bootstrap.lua")
        assert(B.C.enforcement_available==false,"shadow enforcement guard")
        local Class=include("zc_justice_v3/shadow.lua")(B)
        local runtime=Class.new()
        -- Scoring callbacks stay owned by legacy code; source methods are observed through restorable delegates.
        ZCJusticeV3Shadow=runtime;runtime:Install()
        local Geometry=include("zc_justice_v3/geometry.lua")(B.U)
        local Bridge=include("zc_justice_v3/bridge.lua")(B,Geometry)
        include("zc_justice_v3/effects.lua")(Bridge,B)
        include("zc_justice_v3/physical.lua")(Bridge,B)
        include("zc_justice_v3/controls.lua")(Bridge,B)
        include("zc_justice_v3/terminals.lua")(Bridge,B)
        local Medical=include("zc_justice_v3/medical_core.lua")(B.U,B.C)
        include("zc_justice_v3/medical.lua")(Bridge,B,Medical)
        local integrated=Bridge.new(runtime)
        ZCJusticeV3Integration=integrated;integrated:Install()
        return runtime
    end)
    if not ok then
        if ZCJusticeV3Integration and ZCJusticeV3Integration.Stop then ZCJusticeV3Integration:Stop()end
        if ZCJusticeV3Shadow and ZCJusticeV3Shadow.Stop then ZCJusticeV3Shadow:Stop()end
        ErrorNoHalt("[JusticeV3 shadow] load failed: "..tostring(result).."\n")
    end
end
if GAMEMODE and hg and hg.organism and isfunction(hg.AddHarmToAttacker) then install()
else hook.Add("InitPostEntity","ZCJusticeV3Shadow_Load",function()
    hook.Remove("InitPostEntity","ZCJusticeV3Shadow_Load");install()
end)end
