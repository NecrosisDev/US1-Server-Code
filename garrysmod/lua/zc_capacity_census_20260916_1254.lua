-- One-shot server observation. No gameplay setters, network/hook replacements or startup hooks.
assert(SERVER and engine.ActiveGamemode()=="zcity")
local key="ZC48Census_20260916_1254"
assert(not hook.GetTable().Tick or not hook.GetTable().Tick[key],"Census already active")
local clock=SysTime
local r={version=1,started=os.time(),map=game.GetMap(),snapshots={},frames={},errors={}}
local started=clock();local previous=started;local nextScan=started;local scan
local function index(e)return IsValid(e) and e:EntIndex() or nil end
local function ref(e)return IsValid(e) and {id=e:EntIndex(),creation=e:GetCreationID()} or nil end
local function counters()
 return {sent=table.Copy(ZCNETOPT and ZCNETOPT.sent or {}),skip=table.Copy(ZCNETOPT and ZCNETOPT.skip or {})}
end
local function begin()
 local entities=ents.GetAll()
 local s={at=clock()-started,time=os.time(),mode=zb.CROUND,round=zb.ROUND_STATE,
  total=#entities,edicts=ents.GetEdictCount(),players={},entities={},netKeys={},netopt=counters()}
 local cvars={}
 for _,name in ipairs({"sv_minrate","sv_maxrate","sv_minupdaterate","sv_maxupdaterate","sv_maxcmdrate","net_maxcleartime","zc_netopt","zc_perf","zc_perf_auto"})do
  local cv=GetConVar(name);if cv then cvars[name]=cv:GetString()end
 end
 s.cvars=cvars;s.tickInterval=engine.TickInterval()
 s.physicsMs=physenv.GetLastSimulationTime()*1000
 for _,p in ipairs(player.GetHumans())do
  local t=p:GetTable();local entry={id=p:EntIndex(),creation=p:GetCreationID(),alive=p:Alive(),team=p:Team(),weapons={},armor={},fake=ref(p.FakeRagdoll),ping=p:Ping()}
  for slot,item in pairs(t.armors or {})do if isstring(slot) and isstring(item)then entry.armor[slot]=item end end
  for _,wep in ipairs(p:GetWeapons())do entry.weapons[#entry.weapons+1]=wep:EntIndex()end
  s.players[#s.players+1]=entry
 end
 scan={list=entities,cursor=1,s=s,cpuMs=0,maxBatchMs=0};r.snapshots[#r.snapshots+1]=s
end
local fields={"worldModel","worldmodel","weapon","Weapon","owner","Owner","ply","ent","entity","ragdoll","FakeRagdoll","boneManipulator","ManipulateBone"}
local function inspect(e,s)
 if not IsValid(e)then return end
 local t=e:GetTable()
 local row={id=e:EntIndex(),creation=e:GetCreationID(),class=e:GetClass(),model=e:GetModel(),
  fromMap=e:CreatedByMap(),mapID=e:MapCreationID(),nodraw=e:GetNoDraw(),owner=index(e:GetOwner()),parent=index(e:GetParent()),
  isWeapon=e:IsWeapon(),isNPC=e:IsNPC(),physics=0,awake=0,links={}}
 for _,name in ipairs(fields)do local v=rawget(t,name);if isentity(v) and IsValid(v)then row.links[name]=v:EntIndex()end end
 if row.isWeapon then
  row.attachments={}
  for slot,value in pairs(t.attachments or {})do
   if isstring(slot) then row.attachments[slot]=isstring(value) and value or (istable(value) and value[1]) or type(value)end
  end
 end
 local count=e:GetPhysicsObjectCount()
 for i=0,math.min(count,64)-1 do local ph=e:GetPhysicsObjectNum(i)
  if IsValid(ph)then row.physics=row.physics+1;if not ph:IsAsleep()then row.awake=row.awake+1 end end
 end
 row.physicsTruncated=count>64
 s.entities[#s.entities+1]=row
 local vars=zb.net and zb.net.list and zb.net.list[e]
 if istable(vars)then
  for name,value in pairs(vars)do if isstring(name)then
   local k=s.netKeys[name] or {entities=0,types={},tableEntries=0};s.netKeys[name]=k;k.entities=k.entities+1
   local typ=type(value);k.types[typ]=(k.types[typ]or 0)+1
   if istable(value)then local n=0;for _ in pairs(value)do n=n+1;if n>=4096 then break end end;k.tableEntries=k.tableEntries+n end
  end end
 end
end
local function finish(reason)
 hook.Remove("Tick",key);timer.Remove(key)
 r.finished=os.time();r.reason=reason;r.duration=clock()-started;r.netoptEnd=counters()
 r.profileActive=ZCPerfPass2 and ZCPerfPass2.active or false;r.legacyWrapped=ZCPERF and ZCPERF.wrapped or false
 if scan then scan.s.incomplete=true end
 file.CreateDir("zc_capacity_audit")
 file.Write("zc_capacity_audit/census_20260916_1254.json",util.TableToJSON(r))
 print("ZC48_CENSUS_FINISHED",reason,#r.snapshots)
end
local function step()
 local now=clock();local gap=now-previous;previous=now
 r.frames[#r.frames+1]=gap*1000
 if game.GetMap()~=r.map then finish("map_changed");return end
 if not scan and now>=nextScan and #r.snapshots<3 then begin();nextScan=now+30 end
 if scan then
  local workStart=clock();local count=0
  while scan.cursor<=#scan.list and count<24 and clock()-workStart<0.0004 do
   inspect(scan.list[scan.cursor],scan.s);scan.cursor=scan.cursor+1;count=count+1
  end
  local ms=(clock()-workStart)*1000;scan.cpuMs=scan.cpuMs+ms;scan.maxBatchMs=math.max(scan.maxBatchMs,ms)
  if scan.cursor>#scan.list then scan.s.workMs=scan.cpuMs;scan.s.maxBatchMs=scan.maxBatchMs;scan.s.endAt=clock()-started;scan=nil end
 end
 if #r.snapshots>=3 and not scan then finish("complete")end
end
hook.Add("Tick",key,function()
 local ok,err=xpcall(step,debug.traceback)
 if not ok then r.errors[#r.errors+1]=err;finish("error")end
end)
timer.Create(key,95,1,function()finish("timeout")end)
