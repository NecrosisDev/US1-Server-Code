-- Read-only runtime inventory; no hook/net wrappers or player-state writes.
local r={time=os.time(),map=game.GetMap(),version=VERSIONSTR,branch=BRANCH,arch=jit.arch,tickInterval=engine.TickInterval(),mode=zb and zb.CROUND,round=zb and zb.ROUND_STATE,hooks={},cvars={},functions={},systems={},players={},addons={}}
local function src(f)
 if type(f)~='function' then return {type=type(f)} end
 local d=debug.getinfo(f,'S');return {source=d.source,line=d.linedefined,last=d.lastlinedefined}
end
for event,t in pairs(hook.GetTable()) do
 r.hooks[event]={}
 for name,f in pairs(t) do r.hooks[event][tostring(name)]=src(f) end
end
for _,n in ipairs({'sv_maxrate','sv_minrate','sv_maxupdaterate','sv_minupdaterate','sv_parallel_sendsnapshot','sv_parallel_packentities','net_compresspackets','net_maxfragments','net_splitpacket_maxrate','sv_maxusrcmdprocessticks','sv_maxunlag','gmod_physiterations','host_timescale','zc_orgsched','zc_orgsched_interval','zc_tick_budget','zc_tick_budget_ms','zc_perf','zc_perf_auto','zc_governor','zc_gcsmooth','sv_hibernate_think'}) do
 local c=GetConVar(n);if c then r.cvars[n]=c:GetString() end
end
local P=FindMetaTable('Player');local E=FindMetaTable('Entity')
r.functions.SyncVars=src(P.SyncVars);r.functions.SendNetVar=src(E.SendNetVar)
r.functions.SetNetVar=src(E.SetNetVar);r.functions.FireLuaBullets=src(E.FireLuaBullets)
r.functions.hookCall=src(hook.Call);r.functions.netStart=src(net.Start)
r.functions.LuaPatcher=tostring(_G.LuaPatcher)
for _,p in ipairs(player.GetAll()) do
 r.players[#r.players+1]={alive=p:Alive(),team=p:Team(),observer=p:GetObserverMode(),fake=IsValid(p.FakeRagdoll),bot=p:IsBot(),loss=p:PacketLoss(),ping=p:Ping(),rate=p:GetInfo('rate'),updates=p:GetInfo('cl_updaterate'),cmdrate=p:GetInfo('cl_cmdrate'),weapons=#p:GetWeapons()}
end
for _,a in ipairs(engine.GetAddons()) do if a.mounted then r.addons[#r.addons+1]={id=a.wsid,title=a.title,updated=a.updated} end end
local function count(t) if type(t)~='table' then return 0 end;local n=0;for _ in pairs(t) do n=n+1 end;return n end
r.net={entities=count(zb and zb.net and zb.net.list),globals=count(zb and zb.net and zb.net.globals),sent=ZCNETOPT and table.Copy(ZCNETOPT.sent),skip=ZCNETOPT and table.Copy(ZCNETOPT.skip),since=ZCNETOPT and ZCNETOPT.since}
for _,name in ipairs({'ZCTickBudget','ZCORGSCHED','ZCPERF','ZCPerfPass2','ZCityPoop','ZCityPoopThrow','ZCityPoopEat','ZCityPoopOdor','ZCityPoopInvoluntary','ZCityUrine','ZCFartPuff','ZCMakeCrawler','ZCityPillCompat','ZCSpike'}) do
 local s=_G[name];if type(s)=='table' then
  local d={version=s.Version,functions={},stats=type(s.stats)=='table' and table.Copy(s.stats) or nil}
  for k,v in pairs(s) do if type(v)=='function' then d.functions[k]=src(v) end end
  for _,k in ipairs({'active','wrapped','enabled','gcStep','networkDrift'}) do if type(s[k])=='boolean' then d[k]=s[k] end end
  r.systems[name]=d
 end
end
if ZCTickBudget and ZCTickBudget.Snapshot then r.budget=ZCTickBudget.Snapshot() end
r.classes={};r.physics={total=0,awake=0,byClass={}};r.ownedPoops=count(ZCityPoop and ZCityPoop.owned)
local start=SysTime()
for _,e in ipairs(ents.GetAll()) do if IsValid(e) then
 local c=e:GetClass();r.classes[c]=(r.classes[c] or 0)+1
 local q=r.physics.byClass[c] or {entities=0,total=0,awake=0,map=0};r.physics.byClass[c]=q
 q.entities=q.entities+1;if e:CreatedByMap() then q.map=q.map+1 end
 for i=0,e:GetPhysicsObjectCount()-1 do local p=e:GetPhysicsObjectNum(i);if IsValid(p) then
  q.total=q.total+1;r.physics.total=r.physics.total+1
  if p:IsMotionEnabled() and not p:IsAsleep() then q.awake=q.awake+1;r.physics.awake=r.physics.awake+1 end
 end end
end end
r.censusMs=(SysTime()-start)*1000
r.physics.lastMs=physenv.GetLastSimulationTime()*1000;r.physics.paused=physenv.GetPhysicsPaused()
file.CreateDir('zc_48x60_audit')
file.Write('zc_48x60_audit/inventory_20260919t020013z.json',util.TableToJSON(r,true))
print('ZC48_INVENTORY_SAVED',#r.players,r.map)
