-- Manual, single-hook incident repair. Never execute a physics-error event here.
assert(SERVER and engine.ActiveGamemode()=="zcity")
assert(not ZCPhysicsWindowRepair,"Existing transaction must be reconciled")
assert(not physenv.GetPhysicsPaused(),"Physics already paused; no recovery interference")
assert(not timer.Exists("PhysicsCrashedSchedule"),"Recovery already scheduled")
local path="homigrad/sv_physics_handler.lua"
local source=assert(file.Read(path,"LUA"))
assert(util.SHA256(source)=="132a42d57a0499db2baedb12e5902f7a157f29c3b30a8cae05927e416a26b3e7","Source drift")
local old=assert((hook.GetTable().OnCrazyPhysics or {}).stop_physics)
local info=debug.getinfo(old,"S")
assert(info.short_src=="addons/zcity/lua/homigrad/sv_physics_handler.lua","Unexpected callback override")
local values={}
for i=1,16 do local n,v=debug.getupvalue(old,i);if not n then break end;values[n]=v end
assert(isnumber(values.CrazyPhysPerSec) and isnumber(values.CrazyPhysTime))
assert(values.CrazyPhysTrusthold==500 and values.physenv==physenv,"Unexpected guard policy")
local needle='hook.Add("OnCrazyPhysics", "stop_physics", function(ent, phys)'
local at=assert(source:find(needle,1,true))
local body=source:sub(at+#needle):gsub('end%)%s*$','end')
local header="local CrazyPhysPerSec,CrazyPhysTime,CrazyPhysTrusthold,physenv=...\nreturn function(ent,phys)"
local factory=CompileString(header..body,"@lw_guard_window_fix",false)
assert(isfunction(factory),tostring(factory))
-- Preserve the existing partial window; do not grant a fresh allowance on activation.
local replacement=factory(values.CrazyPhysPerSec,values.CrazyPhysTime,500,physenv)
assert(isfunction(replacement))
local priority=0
if hook.GetULibTable then
 local slots=assert(hook.GetULibTable().OnCrazyPhysics)
 for p=-2,2 do if slots[p] and slots[p].stop_physics then priority=p end end
end
local before={call=hook.Call,add=hook.Add,include=include,net=net.Start,hooks={}}
for event,t in pairs(hook.GetTable())do local c={};for id,fn in pairs(t)do c[id]=fn end;before.hooks[event]=c end
assert(hook.GetTable().OnCrazyPhysics.stop_physics==old,"Concurrent hook edit")
hook.Add("OnCrazyPhysics","stop_physics",replacement,priority)
local changed=0
for event,t in pairs(hook.GetTable())do
 for id,fn in pairs(t)do
  local previous=before.hooks[event] and before.hooks[event][id]
  if fn~=previous then assert(event=="OnCrazyPhysics" and id=="stop_physics");changed=changed+1 end
 end
end
assert(changed==1 and hook.Call==before.call and hook.Add==before.add and include==before.include and net.Start==before.net)
for event,t in pairs(before.hooks)do
 for id,fn in pairs(t)do
  if not(event=="OnCrazyPhysics" and id=="stop_physics")then assert((hook.GetTable()[event]or {})[id]==fn,"Unrelated hook changed")end
 end
end
local R={version="20260917.window1",previous=old,replacement=replacement,priority=priority}
function R.Rollback()
 assert(hook.GetTable().OnCrazyPhysics.stop_physics==R.replacement,"Concurrent edit; rollback refused")
 hook.Add("OnCrazyPhysics","stop_physics",R.previous,R.priority)
end
ZCPhysicsWindowRepair=R
file.CreateDir("zc_physics_window")
file.Write("zc_physics_window/receipt.json",util.TableToJSON({version=R.version,at=os.time(),map=game.GetMap(),
 countAtSwitch=values.CrazyPhysPerSec,deadlineAtSwitch=values.CrazyPhysTime,threshold=500,
 onlyOneCallbackChanged=true,otherHooksAndDispatchUnchanged=true,physicsPaused=physenv.GetPhysicsPaused(),
 recoveryScheduled=timer.Exists("PhysicsCrashedSchedule")},true))
print("LW_GUARD_ACTIVE",R.version,changed,values.CrazyPhysPerSec)
