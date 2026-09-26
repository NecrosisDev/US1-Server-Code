-- Manual single-function incident repair; never include the inventory module.
assert(SERVER and engine.ActiveGamemode()=="zcity")
assert(not ZCStoragePositionRepair,"Reconcile existing transaction")
local path="homigrad/sv_inventory.lua"
local before="f093d904cc82e63174bceb15fd99d0033e4e40cd9b7411cb57e190adb9169c70"
local after="9362c75b08e6ff02ac0cfe3dff3336abdef7d2c2fff17300647485210d8a61b3"
assert(util.SHA256(assert(file.Read(path,"LUA")))==before,"Live source drift")
local source=assert(file.Read("sn_storage_candidate.txt","DATA"));assert(util.SHA256(source)==after)
assert(isfunction(CompileString(source,"sn_storage_syntax",false)))
local old=assert(hg.RenewInv);local bl
for i=1,20 do local n,v=debug.getupvalue(old,i);if n=="blackList" then bl=v;break end end
assert(istable(bl),"Unexpected inventory closure")
local a=assert(source:find("function hg.RenewInv",1,true))
local b=assert(source:find('hook.Add("Player Spawn"',a,true))
local factory=CompileString("return function(blackList) local hg={}\n"..source:sub(a,b-1).."\nreturn hg.RenewInv end","@sn_storage/RenewInv",false)
assert(isfunction(factory),tostring(factory));local replacement=factory()(bl)
local original={hook.Call,hook.Add,include,net.Start,net.Send,net.Broadcast,FindMetaTable("Entity").SetNetVar,FindMetaTable("Player").SyncVars}
local startup={}
for _,ev in ipairs({"Initialize","PostGamemodeLoaded","InitPostEntity"})do
 startup[ev]={};for k,v in pairs(hook.GetTable()[ev]or {})do startup[ev][k]=v end
end
local function invariant()
 local now={hook.Call,hook.Add,include,net.Start,net.Send,net.Broadcast,FindMetaTable("Entity").SetNetVar,FindMetaTable("Player").SyncVars}
 for i,v in ipairs(original)do if now[i]~=v then return false end end
 for ev,oldHooks in pairs(startup)do
  local current=hook.GetTable()[ev]or {}
  for k,v in pairs(oldHooks)do if current[k]~=v then return false end end
  for k,v in pairs(current)do if oldHooks[k]~=v then return false end end
 end
 return true
end
local R={before=before,after=after,old=old,replacement=replacement,at=os.time()}
local function matches(fn)return isfunction(fn) and string.dump(fn,true)==string.dump(replacement,true)end
function R.Verify()
 local r={at=os.time(),map=game.GetMap(),players=#player.GetHumans(),
  hashMatches=util.SHA256(assert(file.Read(path,"LUA")))==after,
  functionMatches=matches(hg.RenewInv),startupAndDispatchUnchanged=invariant(),activation=R.activation}
 file.CreateDir("zc_storage_native");file.Write("zc_storage_native/activation.json",util.TableToJSON(r,true))
 print("SN_REPAIR_VERIFY",r.hashMatches,r.functionMatches,r.startupAndDispatchUnchanged)
 return r.hashMatches and r.functionMatches and r.startupAndDispatchUnchanged
end
function R.Apply()
 assert(invariant(),"Unrelated runtime drift")
 assert(util.SHA256(assert(file.Read(path,"LUA")))==after,"Candidate not installed")
 if matches(hg.RenewInv)then R.activation="matching automatic refresh adopted"
 else assert(hg.RenewInv==old,"Concurrent inventory edit");hg.RenewInv=replacement;R.activation="single function replacement" end
 R.live=hg.RenewInv;assert(R.Verify())
end
function R.Rollback()
 assert(hg.RenewInv==R.live,"Concurrent function change; do not roll back blindly")
 hg.RenewInv=old;R.activation="runtime rollback; disk restoration separate"
end
ZCStoragePositionRepair=R
print("SN_REPAIR_PREPARED",game.GetMap(),invariant())
