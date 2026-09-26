-- Manual diagnostic only: observe natural full syncs; never request or defer one.
assert(SERVER and engine.ActiveGamemode()=="zcity")
local ID="ZC_SyncObserve_20260917_0433"
assert(not timer.Exists(ID) and not (hook.GetTable().Tick or {})[ID])
local path="homigrad/libraries/core/sh_networking.lua"
local src=assert(file.Read(path,"LUA"))
assert(util.SHA256(src)=="76aaa93a673e6e5ad437e28e9e9f616def54195172049613c344de67905524be","Source drift")
local a=assert(src:find("    function playerMeta:SyncVars()",1,true))
local b=assert(src:find("    function playerMeta:GetLocalVar",a+1,true))
local body="local playerMeta={}\n"..src:sub(a,b-1).."\nreturn playerMeta.SyncVars"
local pm=FindMetaTable("Player");local original=assert(pm.SyncVars)
local initial={net.Start,net.Send,net.Broadcast,net.WriteType,hook.Call,include}
local report={map=game.GetMap(),started=os.time(),duration=90,rows={},slowTicks={},errors=0,
 totalCalls=0,totalMessages=0,totalBytes=0,maxSyncMs=0,scope="Natural full-sync calls; native message sizes, not transport bytes or bandwidth saturation."}
local active;local observedNet=setmetatable({}, {__index=net})
observedNet.Send=function(...)
 local bytes=net.BytesWritten()
 if active and isnumber(bytes) then
  active.messages=active.messages+1;active.bytes=active.bytes+bytes
  active.maxMessage=math.max(active.maxMessage,bytes)
 end
 return net.Send(...)
end
local env=setmetatable({net=observedNet},{__index=getfenv(original)})
local fn=CompileString(body,"@sync_observer_native_copy",false)
assert(isfunction(fn),tostring(fn));setfenv(fn,env);local observed=fn()
assert(string.dump(observed,true)==string.dump(original,true),"Current SyncVars has a different implementation")
local start=SysTime();local finished=false;local replacement
local function pack(...)return {n=select("#",...),...}end
replacement=function(self,...)
 if finished or report.totalCalls>=64 then return original(self,...) end
 local row={at=SysTime()-start,messages=0,bytes=0,maxMessage=0}
 local parent=active;active=row;local begin=SysTime()
 local result=pack(xpcall(observed,debug.traceback,self,...))
 row.ms=(SysTime()-begin)*1000;row.ok=result[1];active=parent
 report.totalCalls=report.totalCalls+1
 report.totalMessages=report.totalMessages+row.messages;report.totalBytes=report.totalBytes+row.bytes
 report.maxSyncMs=math.max(report.maxSyncMs,row.ms)
 if not row.ok then report.errors=report.errors+1 end
 report.rows[#report.rows+1]=row
 if not result[1] then error(result[2],0) end
 return unpack(result,2,result.n)
end
local function finish()
 if finished then return end;finished=true
 timer.Remove(ID);hook.Remove("Tick",ID)
 report.restored=pm.SyncVars==replacement
 if report.restored then pm.SyncVars=original end
 report.globalFunctionsUnchanged=net.Start==initial[1] and net.Send==initial[2]
  and net.Broadcast==initial[3] and net.WriteType==initial[4] and hook.Call==initial[5] and include==initial[6]
 report.elapsed=SysTime()-start;report.playersAtEnd=#player.GetHumans()
 report.diagnosticHookRemoved=(hook.GetTable().Tick or {})[ID]==nil
 file.CreateDir("zc_sync_observe")
 file.Write("zc_sync_observe/20260917_0433.json",util.TableToJSON(report,true))
 print("SYNC_OBSERVER_COMPLETE",report.totalCalls,report.totalMessages,report.maxSyncMs,report.restored)
end
local last=SysTime();local calls=0
pm.SyncVars=replacement
hook.Add("Tick",ID,function()
 local now=SysTime();local gap=(now-last)*1000;last=now
 if gap>40 and #report.slowTicks<128 then
  report.slowTicks[#report.slowTicks+1]={at=now-start,gapMs=gap,
   physicsMs=physenv.GetLastSimulationTime()*1000,fullSyncs=report.totalCalls-calls}
 end
 calls=report.totalCalls
 if now-start>=report.duration or pm.SyncVars~=replacement then finish() end
end)
timer.Create(ID,95,1,finish)
print("SYNC_OBSERVER_STARTED",report.started,report.map)
