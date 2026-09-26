-- Read-only final verification; no calls to gameplay actions.
local r={time=os.time(),map=game.GetMap(),players=#player.GetHumans(),checks={},functions={},sources={}}
local function source(f)if type(f)~='function' then return type(f) end;local d=debug.getinfo(f,'S');return {path=d.source,line=d.linedefined} end
for _,id in ipairs({'ZC48Passive_20260919t020013z','ZC48NetCensus_20260919t020013z','ZC48Scoped_20260919t020013z'}) do
 r.checks[id]={hookPresent=(hook.GetTable().Tick or {})[id]~=nil,watchdog=timer.Exists(id..'_guard'),globalPresent=_G[id]~=nil}
end
r.functions.crazyPhysics=source((hook.GetTable().OnCrazyPhysics or {}).crazy_physics)
r.functions.organism=source((hook.GetTable().Think or {})['homigrad-organism'])
r.functions.sendNetVar=source(FindMetaTable('Entity').SendNetVar)
r.functions.setNetVar=source(FindMetaTable('Entity').SetNetVar)
r.functions.screenShake=source(util.ScreenShake)
r.functions.syncVars=source(FindMetaTable('Player').SyncVars)
r.orgSchedulerLinked=ZCORGSCHED and (hook.GetTable().Think or {})['homigrad-organism']==ZCORGSCHED.mine or false
r.budgetSenderLinked=ZCTickBudget and ZCTickBudget.entitySender and FindMetaTable('Entity').SendNetVar==ZCTickBudget.entitySender.wrapper or false
r.poops=0;for e in pairs(ZCityPoop and ZCityPoop.owned or {}) do if IsValid(e) then r.poops=r.poops+1 end end
r.activeUrine=0;for p in pairs(ZCityUrine and ZCityUrine.active or {}) do if IsValid(p) then r.activeUrine=r.activeUrine+1 end end
r.luaPatcherEnabled=LUA_PATCHER and LUA_PATCHER.FIXED==true or false
r.patcherSites=0;r.patcherSuppressedSites=0
for _,n in pairs(LUA_PATCHER and LUA_PATCHER.tracebacks_logged or {}) do r.patcherSites=r.patcherSites+1;if n>=10 then r.patcherSuppressedSites=r.patcherSuppressedSites+1 end end
for _,path in ipairs({'homigrad/sh_utility.lua','homigrad/sh_physhandler.lua','homigrad/sv_physics_handler.lua','autorun/server/zc_poop_throw.lua','autorun/server/zc_urine.lua'}) do local s=file.Read(path,'LUA');r.sources[path]=s and util.SHA256(s) end
file.CreateDir('zc_48x60_audit');file.Write('zc_48x60_audit/final_20260919t020013z.json',util.TableToJSON(r,true))
print('ZC48_FINAL_CHECK',r.map,r.players)
