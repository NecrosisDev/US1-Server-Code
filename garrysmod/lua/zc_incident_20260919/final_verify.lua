assert(SERVER)
local em,pm=FindMetaTable("Entity"),FindMetaTable("Player")
local r={time=os.time(),map=game.GetMap(),players=#player.GetHumans(),tickInterval=engine.TickInterval(),
    version=ZCWoundQueue and ZCWoundQueue.Version,queueEnabled=GetConVar("zc_wound_net_queue"):GetBool(),
    counters=ZCWoundQueue and ZCWoundQueue.Stats,sourceHash=util.SHA256(file.Read("homigrad/libraries/core/sh_networking.lua","LUA")),
    setterSource=debug.getinfo(em.SetNetVar,"S").source,sendSource=debug.getinfo(em.SendNetVar,"S").source,
    syncSource=debug.getinfo(pm.SyncVars,"S").source,clearSource=debug.getinfo(em.ClearNetVars,"S").source,
    samplerInactive=ZCIncidentHookSample==nil,passiveCaptureInactive=not ZCIncidentObserve or not ZCIncidentObserve.active,
    organismSchedulerEnabled=GetConVar("zc_orgsched"):GetBool()}
-- The scheduler's self-reinstaller captured the temporary sampler as its
-- fallback. Recreate only its dormant stock fallback from the current source;
-- never execute the organism pass or replace its active scheduling function.
if ZCORGSCHED and ZCORGSCHED.orig==ZCORGSCHED.mine then
    local source=assert(file.Read("homigrad/organism/tier_0/sv_tier_0.lua","LUA"))
    local a=assert(source:find("local tickrate = 1 / 10",1,true))
    local b=assert(source:find("local lastcall = SysTime()",a, true))
    local text="local captured local hook_Run=hook.Run local hook={Add=function(event,name,fn) assert(event=='Think' and name=='homigrad-organism') captured=fn end}\n"..source:sub(a,b-1).."\nreturn captured"
    local factory=CompileString(text,"zc_incident_stock_fallback_restoration",false)
    assert(isfunction(factory),tostring(factory))
    local fallback=factory()
    assert(isfunction(fallback))
    ZCORGSCHED.orig=fallback
    r.schedulerFallbackRecreated=true
    r.schedulerFallbackSourceHash=util.SHA256(source)
end
r.schedulerActive=hook.GetTable().Think["homigrad-organism"]==ZCORGSCHED.mine
r.flushHookActive=hook.GetTable().Tick.ZC_WoundNetFlush==ZCWoundQueue.Flush
assert(r.sourceHash=="89c049bb20c6da8b23cc13687a038681cfafe752fec6ac92ef49186714c6c75d")
assert(r.version=="20260919.1" and r.queueEnabled and r.flushHookActive)
assert(r.setterSource:find("sv_zc_netopt.lua",1,true))
assert(r.samplerInactive and r.passiveCaptureInactive and r.schedulerActive)
ZCIncidentObserve=nil ZCIncidentObserveLabel=nil ZCIncidentCleanupApply=nil
file.Write("zc_incident_20260919/final_verify.json",util.TableToJSON(r,true))
print("ZC_INCIDENT_FINAL_VERIFIED",r.version,r.players,r.map)
