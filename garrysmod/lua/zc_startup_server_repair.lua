-- Server-only subscription repair. Does NOT call or replay any startup event.
assert(SERVER and engine.ActiveGamemode()=="zcity")
assert(util.SHA256(file.Read("autorun/sh_zc_perf2_toz.lua","LUA"))=="a3777a8d7effe559d8336bccfeb0a5e078a9e5353829f7e635290a9e5b1866fe")
assert(util.SHA256(file.Read("zc_guilt_justice/runtime.lua","LUA"))=="5b232afe129bdb6722f8429b830493aeef20e8a60cd394238060fe2d520fd3dc")
local T,J=assert(ZCPerf2TOZ),assert(ZCityGuiltJustice)
local originalT,originalJ=T.Install,J.InstallLegacy
local h=hook.GetTable()
for _,event in ipairs({"InitPostEntity","PostGamemodeLoaded"})do
    local fn=h[event] and h[event].ZCPerf2TOZ
    assert(fn==T.Install or fn==T.OnStartup,"Unexpected TOZ hook; refusing overwrite")
end
local legacy=assert(h.InitPostEntity.ZCityGuiltJustice_Legacy)
assert(legacy==J.InstallLegacy or debug.getinfo(legacy,"S").short_src:find("zc_guilt_justice/runtime.lua",1,true),"Unexpected justice hook")
function T.OnStartup()T.Install()end
hook.Add("InitPostEntity","ZCPerf2TOZ",T.OnStartup)
hook.Add("PostGamemodeLoaded","ZCPerf2TOZ",T.OnStartup)
hook.Add("InitPostEntity","ZCityGuiltJustice_Legacy",function()J.InstallLegacy()end)
T.StartupHookFix="20260916.2"
assert(T.Install==originalT and J.InstallLegacy==originalJ)
local r={time=os.time(),map=game.GetMap(),players=#player.GetHumans(),fix=T.StartupHookFix,
    tozPost=h.PostGamemodeLoaded.ZCPerf2TOZ==T.OnStartup,
    tozEntity=h.InitPostEntity.ZCPerf2TOZ==T.OnStartup,
    justiceStatusLeak=h.InitPostEntity.ZCityGuiltJustice_Legacy==J.InstallLegacy,
    installersUnchanged=true,startupReplayed=false,
    profilerActive=ZCPerfPass2 and ZCPerfPass2.active==true,
    legacyProfilerActive=ZCPERF and ZCPERF.wrapped==true}
file.CreateDir("zc_startup_repair");file.Write("zc_startup_repair/server.json",util.TableToJSON(r,true))
print("ZCITY_STARTUP_RETURN_REPAIRED",r.fix)
