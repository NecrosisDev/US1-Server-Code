-- Bounded manual diagnostic; no message suppression, extra sends, or player actions.
assert(SERVER and engine.ActiveGamemode()=="zcity")
local ID="ZC_AmmoRates_20260917_0532"
assert(not timer.Exists(ID) and not timer.Exists(ID.."_watch"))
local em=FindMetaTable("Entity")
local originalSend=assert(em.SendNetVar)
local originalAmmo=assert(hook.GetTable().PlayerAmmoChanged["homigrad-inventory"])
local source=assert(file.Read("homigrad/libraries/core/sh_networking.lua","LUA"))
assert(util.SHA256(source)=="76aaa93a673e6e5ad437e28e9e9f616def54195172049613c344de67905524be")
local a=assert(source:find("    function entityMeta:SendNetVar",1,true))
local b=assert(source:find("    function entityMeta:ClearNetVars",a,true))
local report={at=os.time(),map=game.GetMap(),players=#player.GetHumans(),modes={},keys={},
 ammoCalls=0,ammoInventory=0,ammoBytes=0,ammoRecipientBytes=0,errors=0,
 scope="Natural sender calls; encoding bytes and recipient copies, not transport bandwidth."}
local initial={net.Start,net.Send,net.Broadcast,hook.Call,hook.Add,include}
local start=SysTime();local done=false;local depth=0;local context
local function pack(...)return {n=select("#",...),...}end
local function sameError(err)return err end
local function recipients(target)
 if target==nil then return #player.GetAll() end
 if IsValid(target) and target:IsPlayer() then return 1 end
 if istable(target) then return #target end
 return nil -- Unknown recipient filters are not guessed.
end
local function record(bytes,count)
 if not context or not isnumber(bytes) then return end
 local key=tostring(context.key);local row=report.keys[key]
 if not row then row={calls=0,bytes=0,recipientBytes=0,unknownAudience=0};report.keys[key]=row end
 row.calls=row.calls+1;row.bytes=row.bytes+bytes
 if count then row.recipientBytes=row.recipientBytes+bytes*count else row.unknownAudience=row.unknownAudience+1 end
 if key=="Inventory" and depth>0 then
  report.ammoInventory=report.ammoInventory+1;report.ammoBytes=report.ammoBytes+bytes
  if count then report.ammoRecipientBytes=report.ammoRecipientBytes+bytes*count end
 end
end
local proxy=setmetatable({}, {__index=net})
proxy.Broadcast=function(...)
 local bytes=net.BytesWritten();local n=recipients(nil)
 local result=pack(net.Broadcast(...));record(bytes,n);return unpack(result,1,result.n)
end
proxy.Send=function(target,...)
 local bytes=net.BytesWritten();local n=recipients(target)
 local result=pack(net.Send(target,...));record(bytes,n);return unpack(result,1,result.n)
end
local env=setmetatable({net=proxy},{__index=getfenv(originalSend)})
local fn=CompileString("local entityMeta={}\n"..source:sub(a,b-1).."\nreturn entityMeta.SendNetVar","@ammo_rate_native_copy",false)
assert(isfunction(fn),tostring(fn));setfenv(fn,env);local observed=fn()
assert(string.dump(observed,true)==string.dump(originalSend,true),"Unrecognized sender implementation")
local sendReplacement=function(self,key,...)
 if done then return originalSend(self,key,...) end
 local previous=context;context={key=key}
 local result=pack(xpcall(observed,sameError,self,key,...));context=previous
 if not result[1] then report.errors=report.errors+1;error(result[2],0) end
 return unpack(result,2,result.n)
end
local ammoReplacement=function(...)
 if done then return originalAmmo(...) end
 report.ammoCalls=report.ammoCalls+1;depth=depth+1
 local result=pack(xpcall(originalAmmo,sameError,...));depth=depth-1
 if not result[1] then report.errors=report.errors+1;error(result[2],0) end
 return unpack(result,2,result.n)
end
local function finish(reason)
 if done then return end;done=true
 timer.Remove(ID);timer.Remove(ID.."_watch")
 report.senderRestored=em.SendNetVar==sendReplacement
 if report.senderRestored then em.SendNetVar=originalSend end
 report.ammoRestored=hook.GetTable().PlayerAmmoChanged["homigrad-inventory"]==ammoReplacement
 if report.ammoRestored then hook.Add("PlayerAmmoChanged","homigrad-inventory",originalAmmo) end
 report.functionsUnchanged=net.Start==initial[1] and net.Send==initial[2] and net.Broadcast==initial[3]
  and hook.Call==initial[4] and hook.Add==initial[5] and include==initial[6]
 report.elapsed=SysTime()-start;report.playersEnd=#player.GetHumans();report.reason=reason
 file.CreateDir("zc_ammo_rates");file.Write("zc_ammo_rates/20260917_0532.json",util.TableToJSON(report,true))
 print("AMTX_RATES_DONE",report.ammoCalls,report.ammoInventory,report.senderRestored,report.ammoRestored)
end
em.SendNetVar=sendReplacement
hook.Add("PlayerAmmoChanged","homigrad-inventory",ammoReplacement)
timer.Create(ID,0.25,0,function()
 local mode=tostring(zb.CROUND);report.modes[mode]=(report.modes[mode] or 0)+1
 if em.SendNetVar~=sendReplacement or hook.GetTable().PlayerAmmoChanged["homigrad-inventory"]~=ammoReplacement then
  finish("implementation changed")
 elseif SysTime()-start>=90 then finish("complete") end
end)
timer.Create(ID.."_watch",95,1,function()finish("watchdog")end)
print("AMTX_RATES_STARTED",report.at,report.map)
