-- Manual, bounded sampling only. Never replaces a sender or suppresses a message.
assert(SERVER and engine.ActiveGamemode()=="zcity")
assert(zb and zb.net and zb.net.list and ZCNETOPT and ZCNETOPT.sent)
local id="ZCPubObserve_20260916_1415"
assert(not timer.Exists(id),"This observation is already running")
local S=include("zc_pub_observe_20260916_1415/snapshot.lua")
local started=SysTime();local finished=false
local keys={"Inventory","wounds","arterialwounds"}
local rows,cache,cursor={},setmetatable({},{__mode="k"}),0
local result={version="20260916.1",started=os.time(),map=game.GetMap(),seconds=60,
 mode="SAMPLING_ONLY_NO_SUPPRESSION",samples={},timeline={},errors={},
 ammo={events=0,unchanged=0,increased=0,decreased=0,invalid=0,byType={}},
 costs={sampleMs=0,maxSampleMs=0,refreshMs=0,maxRefreshMs=0,ammoMs=0,maxAmmoMs=0},
 limitations="Samples can miss changes between polls. Counter deltas are calls, not packets or bytes; neither proves a publication can be suppressed."}
for _,key in ipairs(keys)do result.samples[key]={observations=0,equal=0,changed=0,first=0,unknown=0,empty=0,absent=0,maxGap=0}end
local em=FindMetaTable("Entity");local pm=FindMetaTable("Player")
local function identity()
 return {netStart=net.Start,netSend=net.Send,netBroadcast=net.Broadcast,hookAdd=hook.Add,
 hookCall=hook.Call,setter=em.SetNetVar,sender=em.SendNetVar,sync=pm.SyncVars,
 ammo=(hook.GetTable().PlayerAmmoChanged or {})["homigrad-inventory"]}
end
local original=identity()
local function counters()
 local t={};for _,key in ipairs(keys)do t[key]=(ZCNETOPT.sent[key] or 0)end;return t
end
result.before=counters()
local function finish(reason)
 if finished then return end;finished=true
 timer.Remove(id);timer.Remove(id.."_watchdog")
 hook.Remove("PlayerAmmoChanged",id)
 result.reason=reason;result.elapsed=SysTime()-started;result.after=counters()
 result.callDelta={}
 for _,key in ipairs(keys)do result.callDelta[key]=result.after[key]-result.before[key]end
 result.identitiesUnchanged=true;result.identityChanges={}
 local final=identity()
 for name,fn in pairs(original)do
  if final[name]~=fn then result.identitiesUnchanged=false;result.identityChanges[#result.identityChanges+1]=name end
 end
 result.timerRemoved=not timer.Exists(id)
 result.ammoHookRemoved=(hook.GetTable().PlayerAmmoChanged or {})[id]==nil
 file.CreateDir("zc_publication_observe")
 file.Write("zc_publication_observe/20260916_1415.json",util.TableToJSON(result,true))
 rows={};cache={}
end
local nextRefresh=0;local lastRound
local function refresh()
 local begin=SysTime();rows={}
 local mode=CurrentRound and CurrentRound() or {}
 local round=tostring(zb.ROUND_START)..":"..tostring(zb.CROUND)..":"..tostring(zb.ROUND_STATE)
 if round~=lastRound then cache=setmetatable({},{__mode="k"});lastRound=round end
 local owners=0;local omitted=0
 for e,data in pairs(zb.net.list)do
  if IsValid(e) and istable(data) and (data.Inventory~=nil or data.wounds~=nil or data.arterialwounds~=nil)then
   if owners>=128 then omitted=omitted+1
   else
    owners=owners+1
    for _,key in ipairs(keys)do rows[#rows+1]={e=e,key=key}end
   end
  end
 end
 local humans=player.GetHumans();local alive=0
 for _,p in ipairs(humans)do if p:Alive()then alive=alive+1 end end
 result.timeline[#result.timeline+1]={t=SysTime()-started,players=#humans,alive=alive,
 mode=mode.name or zb.CROUND,roundState=zb.ROUND_STATE,owners=owners,omitted=omitted,
 entities=ents.GetCount(),counts=counters()}
 local cost=(SysTime()-begin)*1000
 result.costs.refreshMs=result.costs.refreshMs+cost
 result.costs.maxRefreshMs=math.max(result.costs.maxRefreshMs,cost)
 if cost>2 then finish("refresh_budget_exceeded")end
 nextRefresh=SysTime()+1
end
local function sample()
 local begin=SysTime();local deadline=begin+0.0005
 for i=1,math.min(12,#rows)do
  if SysTime()>=deadline then break end
  cursor=cursor%#rows+1;local row=rows[cursor];local e,key=row.e,row.key
  if IsValid(e)then
   local owner=cache[e];if not owner then owner={};cache[e]=owner end
   local previous=owner[key];local now=SysTime()
   if not previous or now-previous.at>=0.2 then
    local data=zb.net.list[e];local value=data and data[key]
    local fingerprint,why=S.Take(value,math.min(deadline,now+0.00015))
    local stat=result.samples[key];stat.observations=stat.observations+1
    if value==nil then stat.absent=stat.absent+1
    elseif istable(value) and next(value)==nil then stat.empty=stat.empty+1 end
    if previous then stat.maxGap=math.max(stat.maxGap,now-previous.at)end
    if not fingerprint then stat.unknown=stat.unknown+1
    elseif not previous or not previous.fingerprint then stat.first=stat.first+1
    elseif fingerprint==previous.fingerprint then stat.equal=stat.equal+1
    else stat.changed=stat.changed+1 end
    owner[key]={at=now,fingerprint=fingerprint}
   end
  end
 end
 local ms=(SysTime()-begin)*1000
 result.costs.sampleMs=result.costs.sampleMs+ms
 result.costs.maxSampleMs=math.max(result.costs.maxSampleMs,ms)
 if ms>2 then finish("sample_budget_exceeded")end
end
local function step()
 if finished then return end
 if SysTime()-started>=60 then finish("complete");return end
 if SysTime()>=nextRefresh then refresh();if finished then return end end
 sample()
end
local function ammo(p,ammoID,old,new)
 if finished then return end
 local begin=SysTime();local a=result.ammo;a.events=a.events+1
 local category
 if not isnumber(old) or not isnumber(new) or old~=old or new~=new then category="invalid"
 elseif old==new then category="unchanged"
 elseif new>old then category="increased" else category="decreased"end
 a[category]=a[category]+1
 local name=isnumber(ammoID) and ammoID>=0 and ammoID<=255 and tostring(ammoID) or "other"
 local entry=a.byType[name]
 if not entry then entry={events=0,unchanged=0,increased=0,decreased=0,invalid=0};a.byType[name]=entry end
 entry.events=entry.events+1;entry[category]=entry[category]+1
 local ms=(SysTime()-begin)*1000
 result.costs.ammoMs=result.costs.ammoMs+ms
 result.costs.maxAmmoMs=math.max(result.costs.maxAmmoMs,ms)
end
local function safe(fn,...)
 local ok,err=pcall(fn,...)
 if not ok then result.errors[#result.errors+1]=tostring(err);finish("observer_error")end
end
hook.Add("PlayerAmmoChanged",id,function(...)safe(ammo,...)end)
timer.Create(id,0.05,0,function()safe(step)end)
timer.Create(id.."_watchdog",75,1,function()finish("watchdog")end)
file.CreateDir("zc_publication_observe")
file.Write("zc_publication_observe/20260916_1415_started.json",util.TableToJSON({started=result.started,map=result.map,source="manual-observer",noSuppression=true}))
