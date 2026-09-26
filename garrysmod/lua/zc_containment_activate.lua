-- Manual, owner-authorized incident repair. No loader replay or startup hooks.
assert(SERVER and engine.ActiveGamemode()=="zcity")
assert(not ZCPhysicsCleanupRepair,"Reconcile the existing transaction first")
local path="homigrad/sh_physhandler.lua"
local source=assert(file.Read("zc_containment_stage.txt","DATA"))
assert(util.SHA256(source)=="4fd4f887ccfa3d871e9fe7ef8e14913635aa55539de6e8e4ba74726a901fbedc")
local old=assert((hook.GetTable().OnCrazyPhysics or {}).crazy_physics)
assert(debug.getinfo(old,"S").short_src:find("sh_physhandler.lua",1,true),"Unexpected callback")
local replacement
local env=setmetatable({SERVER=true,CLIENT=false,math=setmetatable({},{__index=math}),hook={}}, {__index=_G})
env.hook.Add=function(event,name,fn)
 assert(event=="OnCrazyPhysics" and name=="crazy_physics" and not replacement)
 replacement=fn
end
local compiled=CompileString(source,"@zc_containment/sh_physhandler.lua",false)
assert(isfunction(compiled),tostring(compiled));setfenv(compiled,env);compiled();assert(replacement)
local R={old=old,replacement=replacement,version="20260917.containment1"}
local function snapshot()
 local out={}
 for event,values in pairs(hook.GetTable())do
  out[event]={};for key,value in pairs(values)do out[event][key]=value end
 end
 return out
end
local original={hook.Call,hook.Add,include,net.Start}
local function dispatchUnchanged()
 return hook.Call==original[1] and hook.Add==original[2] and include==original[3] and net.Start==original[4]
end
function R.Apply()
 assert(not R.applied and dispatchUnchanged())
 assert((hook.GetTable().OnCrazyPhysics or {}).crazy_physics==old,"Callback changed concurrently")
 assert(util.SHA256(assert(file.Read(path,"LUA")))==util.SHA256(source),"Installed source mismatch")
 assert(not physenv.GetPhysicsPaused(),"Resolve paused physics before activation")
 local before=snapshot()
 hook.Add("OnCrazyPhysics","crazy_physics",replacement)
 local after=snapshot();local unchanged=dispatchUnchanged();local changed=0
 for event,values in pairs(before)do
  for key,value in pairs(values)do
   if event=="OnCrazyPhysics" and key=="crazy_physics" then
    if after[event][key]==replacement then changed=changed+1 else unchanged=false end
   elseif not after[event] or after[event][key]~=value then unchanged=false end
  end
 end
 for event,values in pairs(after)do for key in pairs(values)do
  if not before[event] or before[event][key]==nil then unchanged=false end
 end end
 assert(unchanged and changed==1,"Unexpected registration change")
 R.applied=true
 file.CreateDir("zc_containment")
 file.Write("zc_containment/activation.json",util.TableToJSON({version=R.version,at=os.time(),map=game.GetMap(),
  applied=true,otherHooksAndDispatchUnchanged=unchanged,changedCallbacks=changed},true))
 print("CONTAINMENT_ACTIVE",R.version,changed,unchanged)
end
function R.Rollback()
 assert((hook.GetTable().OnCrazyPhysics or {}).crazy_physics==replacement,"Concurrent callback edit")
 hook.Add("OnCrazyPhysics","crazy_physics",old);R.applied=false
end
ZCPhysicsCleanupRepair=R
print("CONTAINMENT_PREPARED",R.version)
