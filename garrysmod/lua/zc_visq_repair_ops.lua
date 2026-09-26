-- Manual one-hook repair. Do not include or execute the full ragdoll module.
assert(SERVER and engine.ActiveGamemode()=="zcity")
assert(not ZCVisibilityQueueRepair,"An earlier transaction must be reconciled first")
local path="homigrad/fake/sv_tier_0.lua"
local before="178793573f6a34e7aa5ad430514070b077e5903c5ba3b728cabed4bd1ed0dd81"
local after="51fe46e26a5d935c06d7ee28d036b15cd1f29cf85ce0720dcbeb99f5142e958c"
local originalSource=assert(file.Read(path,"LUA"))
local candidate=assert(file.Read("zc_visq_20260917_072458/candidate.txt","DATA"))
assert(util.SHA256(originalSource)==before,"Live source drift")
assert(util.SHA256(candidate)==after,"Candidate drift")
assert(isfunction(CompileString(candidate,"visq_compile_only",false)),"Syntax check failed")
local event,name="SetupPlayerVisibility","fuckragdolls"
local function compileHook(text)
 local a=assert(text:find('hook.Add("SetupPlayerVisibility", "fuckragdolls"',1,true))
 local b=assert(text:find('hook.Add("SetupPlayerVisibility", "ragdollview"',a+1,true))
 local captured
 local env=setmetatable({hook={Add=function(e,n,fn)
  assert(e==event and n==name and not captured);captured=fn
 end}},{__index=_G})
 local fn=CompileString(text:sub(a,b-1),"@visq/isolated_hook_factory",false)
 assert(isfunction(fn),tostring(fn));setfenv(fn,env);fn();assert(isfunction(captured))
 setfenv(captured,_G);return captured
end
local old=assert((hook.GetTable()[event]or {})[name])
local oldCode,newCode=compileHook(originalSource),compileHook(candidate)
local function matches(a,b)return isfunction(a) and string.dump(a,true)==string.dump(b,true)end
assert(matches(old,oldCode),"Unrecognized live hook implementation")
local initial={hook.Call,hook.Add,include,net.Start,net.Send,net.Broadcast,FindMetaTable("Entity").SetNetVar,FindMetaTable("Entity").SendNetVar,FindMetaTable("Player").SyncVars}
local startup={}
for _,ev in ipairs({"Initialize","PostGamemodeLoaded","InitPostEntity"})do
 startup[ev]={};for k,v in pairs(hook.GetTable()[ev]or {})do startup[ev][k]=v end
end
local function invariant()
 local now={hook.Call,hook.Add,include,net.Start,net.Send,net.Broadcast,FindMetaTable("Entity").SetNetVar,FindMetaTable("Entity").SendNetVar,FindMetaTable("Player").SyncVars}
 for i,v in ipairs(initial)do if now[i]~=v then return false end end
 for ev,registered in pairs(startup)do
  local current=hook.GetTable()[ev]or {}
  for k,v in pairs(registered)do if current[k]~=v then return false end end
  for k,v in pairs(current)do if registered[k]~=v then return false end end
 end
 return true
end
local R={before=before,after=after,old=old,replacement=newCode}
function R.Verify()
 local r={at=os.time(),map=game.GetMap(),players=#player.GetHumans(),activation=R.activation,
  hashMatches=util.SHA256(assert(file.Read(path,"LUA")))==after,
  callbackMatches=matches((hook.GetTable()[event]or {})[name],newCode),
  startupAndDispatchUnchanged=invariant(),queueEntries=table.Count(hg.queue_ragdolls or {})}
 file.CreateDir("zc_visq_20260917_072458")
 file.Write("zc_visq_20260917_072458/verification.json",util.TableToJSON(r,true))
 print("VISQ_VERIFY",r.hashMatches,r.callbackMatches,r.startupAndDispatchUnchanged,r.queueEntries)
 return r.hashMatches and r.callbackMatches and r.startupAndDispatchUnchanged
end
function R.Apply()
 assert(invariant(),"Unrelated runtime drift")
 assert(util.SHA256(assert(file.Read(path,"LUA")))==after,"Candidate not installed")
 local current=(hook.GetTable()[event]or {})[name]
 if matches(current,newCode)then R.activation="matching automatic refresh adopted"
 else
  assert(current==old,"Concurrent visibility-hook change")
  hook.Add(event,name,newCode);R.activation="single named callback replaced"
 end
 R.live=(hook.GetTable()[event]or {})[name];assert(R.Verify())
end
function R.Rollback()
 assert(invariant(),"Unrelated runtime drift")
 assert(util.SHA256(assert(file.Read(path,"LUA")))==before,"Restore original disk file before runtime rollback")
 local current=(hook.GetTable()[event]or {})[name]
 if not matches(current,oldCode) then
  assert(current==R.live,"Concurrent hook change; rollback refused")
  hook.Add(event,name,old)
 end
 assert(matches((hook.GetTable()[event]or {})[name],oldCode))
 R.activation="rolled back";print("VISQ_ROLLED_BACK")
end
ZCVisibilityQueueRepair=R
print("VISQ_PREPARED",game.GetMap(),invariant())
