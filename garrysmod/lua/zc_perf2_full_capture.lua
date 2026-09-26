-- One bounded FULL-hook capture after the SWEP probe, with settings restored.
assert(SERVER and ZCPERF and not ZCPERF.wrapped)
assert(not (ZCPerfPass2 and ZCPerfPass2.active))
local on,light=assert(GetConVar("zc_perf")),assert(GetConVar("zc_perf_light"))
assert(not on:GetBool(),"Manual profiler already requested")
local original=light:GetString()
local active=true
local function restore()
    if not active then return end;active=false
    on:SetInt(0);light:SetString(original)
    hook.Remove("ShutDown","ZCPerf2_FullRestore")
end
hook.Add("ShutDown","ZCPerf2_FullRestore",restore)
light:SetInt(0);on:SetInt(1)
timer.Create("ZCPerf2_FullFinish",20,1,function()
    if ZCPERF.wrapped then RunConsoleCommand("zc_perf_report")end
    timer.Simple(0.2,restore)
end)
timer.Simple(22,function()
    file.Write("zc_perf_pass2/full_capture_restored.json",util.TableToJSON({time=os.time(),
        profilerEnabled=on:GetBool(),light=light:GetString(),previousLight=original,
        wrapped=ZCPERF.wrapped~=nil and ZCPERF.wrapped~=false,probeActive=ZCPerfPass2.active==true},true))
end)
