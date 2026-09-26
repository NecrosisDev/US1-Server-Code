-- Size census only: encode then Abort. No messages sent or network functions replaced.
local id='ZC48NetCensus_20260919t020013z'
assert(not hook.GetTable().Tick[id],'net census already active')
assert(net.Abort and net.BytesWritten and zb and zb.net,'native encoder missing')
local r={time=os.time(),map=game.GetMap(),keys={},totals={globalBytes=0,globalMessages=0,entityBytes=0,entityMessages=0},failures={},skipped=0,measured=0,maximumSliceMs=0,encodingMs=0,playerLocalBytes={}}
local sources={};local index=1;local started=SysTime();local deadline=started+30
local refs={net.Start,net.Send,net.Broadcast,net.Abort,FindMetaTable('Player').SyncVars}
local info=debug.getinfo(refs[5],'S');r.syncSource={source=info.source,line=info.linedefined}
r.netBefore=ZCNETOPT and {sent=table.Copy(ZCNETOPT.sent),skip=table.Copy(ZCNETOPT.skip),since=ZCNETOPT.since}
for k in pairs(zb.net.globals or {}) do sources[#sources+1]={kind='global',key=k,values=zb.net.globals} end
for ent,t in pairs(zb.net.list or {}) do if IsValid(ent) then
 for k in pairs(t) do sources[#sources+1]={kind='entity',entity=ent,key=k,values=t} end
end end
for _,p in ipairs(player.GetHumans()) do
 local n=#r.playerLocalBytes+1;r.playerLocalBytes[n]={bytes=0,messages=0}
 for k in pairs((zb.net.locals or {})[p] or {}) do sources[#sources+1]={kind='local',ownerIndex=n,key=k,values=zb.net.locals[p]} end
end
r.humans=#r.playerLocalBytes;r.entries=#sources
local function finish(reason)
 hook.Remove('Tick',id);timer.Remove(id..'_guard');r.reason=reason;r.elapsed=SysTime()-started
 r.netAfter=ZCNETOPT and {sent=table.Copy(ZCNETOPT.sent),skip=table.Copy(ZCNETOPT.skip),since=ZCNETOPT.since}
 r.unchanged=refs[1]==net.Start and refs[2]==net.Send and refs[3]==net.Broadcast and refs[4]==net.Abort and refs[5]==FindMetaTable('Player').SyncVars
 r.transmissionPerformed=false
 file.CreateDir('zc_48x60_audit');file.Write('zc_48x60_audit/net_census_20260919t020013z.json',util.TableToJSON(r,true))
 print('ZC48_NET_CENSUS_FINISHED',reason,r.measured,#r.failures)
end
local function bounded(value,seen,budget,depth)
 if type(value)~='table' then return true end
 if depth>8 or seen[value] then return false end;seen[value]=true
 for k,v in pairs(value) do budget.n=budget.n+1;if budget.n>2048 then return false end
  if not bounded(k,seen,budget,depth+1) or not bounded(v,seen,budget,depth+1) then return false end
 end
 seen[value]=nil;return true
end
hook.Add('Tick',id,function()
 local begin=SysTime()
 if begin>=deadline then finish(index>#sources and 'complete' or 'deadline_incomplete');return end
 if net.BytesWritten()~=nil then return end
 for j=1,4 do
  local row=sources[index];if not row then break end;index=index+1
  local v=row.values[row.key]
  if (row.kind=='entity' and not IsValid(row.entity)) or not bounded(v,{},{n=0},0) then r.skipped=r.skipped+1
  else
   local at=SysTime()
   local ok,bytes=pcall(function()
    net.Start(row.kind=='entity' and 'zbNetVarSet' or row.kind=='global' and 'zbGlobalVarSet' or 'zbLocalVarSet')
    if row.kind=='entity' then net.WriteUInt(row.entity:EntIndex(),16) end
    net.WriteString(row.key);net.WriteType(v);return net.BytesWritten()
   end)
   net.Abort();r.encodingMs=r.encodingMs+(SysTime()-at)*1000
   if ok and type(bytes)=='number' then
    r.measured=r.measured+1
    local k=row.kind..':'..tostring(row.key);local s=r.keys[k] or {count=0,bytes=0,max=0,min=math.huge,empty=0};r.keys[k]=s
    s.count=s.count+1;s.bytes=s.bytes+bytes;s.max=math.max(s.max,bytes);s.min=math.min(s.min,bytes)
    if type(v)=='table' and next(v)==nil then s.empty=s.empty+1 end
    if row.kind=='entity' then r.totals.entityBytes=r.totals.entityBytes+bytes;r.totals.entityMessages=r.totals.entityMessages+1
    elseif row.kind=='global' then r.totals.globalBytes=r.totals.globalBytes+bytes;r.totals.globalMessages=r.totals.globalMessages+1
    else local q=r.playerLocalBytes[row.ownerIndex];q.bytes=q.bytes+bytes;q.messages=q.messages+1 end
   else r.failures[#r.failures+1]={kind=row.kind,key=tostring(row.key),error=tostring(bytes):sub(1,240)} end
  end
  if SysTime()-begin>=0.0005 then break end
 end
 r.maximumSliceMs=math.max(r.maximumSliceMs,(SysTime()-begin)*1000)
end)
timer.Create(id..'_guard',35,1,function()finish('watchdog')end)
print('ZC48_NET_CENSUS_STARTED',r.entries,r.humans)
