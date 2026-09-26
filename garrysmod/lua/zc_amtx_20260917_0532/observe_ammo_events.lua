-- Counts natural reserve callbacks only. Leaves the equipment-budget sender untouched.
assert(SERVER and engine.ActiveGamemode()=="zcity")
local ID="ZC_AmmoEvents_20260917_0532"
assert(not timer.Exists(ID))
local old=assert(hook.GetTable().PlayerAmmoChanged["homigrad-inventory"])
local source=assert(file.Read("homigrad/sv_inventory.lua","LUA"))
assert(util.SHA256(source)=="9362c75b08e6ff02ac0cfe3dff3336abdef7d2c2fff17300647485210d8a61b3")
local a=assert(source:find('hook.Add("PlayerAmmoChanged"',1,true))
local b=assert(source:find("local vecZero",a,true));local expected
local env=setmetatable({hook={Add=function(_,_,f)expected=f end}},{__index=getfenv(old)})
local fn=CompileString(source:sub(a,b-1),"@ammo_event_identity",false)
assert(isfunction(fn));setfenv(fn,env);fn()
assert(string.dump(old,true)==string.dump(expected,true),"Unrecognized ammo callback")
local start=SysTime();local done=false;local wrapper
local report={started=os.time(),map=game.GetMap(),players=#player.GetHumans(),calls=0,
 completedWithInventory=0,errors=0,byMode={},scope="Callback counts, not observed network sends or bytes."}
local globals={net.Start,net.Send,net.Broadcast,hook.Call,include,FindMetaTable("Entity").SendNetVar}
local function pack(...)return {n=select("#",...),...}end
wrapper=function(ply,...)
 if done then return old(ply,...)end
 report.calls=report.calls+1;local hadInventory=ply.inventory~=nil
 local result=pack(xpcall(old,function(err)return err end,ply,...))
 if not result[1] then report.errors=report.errors+1;error(result[2],0)end
 if hadInventory then
  report.completedWithInventory=report.completedWithInventory+1
  local mode=tostring(zb.CROUND);report.byMode[mode]=(report.byMode[mode] or 0)+1
 end
 return unpack(result,2,result.n)
end
local function finish()
 if done then return end;done=true;timer.Remove(ID)
 report.restored=hook.GetTable().PlayerAmmoChanged["homigrad-inventory"]==wrapper
 if report.restored then hook.Add("PlayerAmmoChanged","homigrad-inventory",old)end
 report.elapsed=SysTime()-start;report.playersEnd=#player.GetHumans()
 report.networkUnchanged=net.Start==globals[1] and net.Send==globals[2] and net.Broadcast==globals[3]
  and hook.Call==globals[4] and include==globals[5] and FindMetaTable("Entity").SendNetVar==globals[6]
 file.CreateDir("zc_ammo_rates");file.Write("zc_ammo_rates/events_20260917_0532.json",util.TableToJSON(report,true))
 print("AMTX_EVENTS_DONE",report.calls,report.completedWithInventory,report.restored,report.networkUnchanged)
end
hook.Add("PlayerAmmoChanged","homigrad-inventory",wrapper)
timer.Create(ID,0.5,0,function()
 if SysTime()-start>=60 or hook.GetTable().PlayerAmmoChanged["homigrad-inventory"]~=wrapper then finish()end
end)
print("AMTX_EVENTS_STARTED",report.started,report.map)
