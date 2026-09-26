-- Manual incident repair operations. No autorun/startup subscriptions or loader replay.
assert(SERVER and engine.ActiveGamemode()=="zcity","Wrong target gamemode")
assert(not ZC36RepairOps,"An existing repair transaction must be reconciled first")
local R={version="20260916.36r1",changes={},before={},audit={started=os.time(),map=game.GetMap()}}
local function read(name,hash)
 local s=assert(file.Read("zc_36repair_stage/"..name..".txt","DATA"),"Missing staged source")
 assert(util.SHA256(s)==hash,"Staged hash mismatch: "..name)
 assert(isfunction(CompileString(s,"zc36_syntax/"..name,false)),"Candidate syntax failed: "..name)
 return s
end
local tape=read("tape","f5faff36e93a866e1b31285c8b1e57d02d8c801d219aade4285e5744fd649508")
local grenade=read("grenade","74ebf2a6778bae0e7c6bf8b81a9a5c5fb20e33af21c6dc5bd9b1e74561653918")
R.trainSource=read("train","c718148d134aca2ea52af1985994ec53dca4125b3df7abfe62465b8f631050fd")
local function make(s,first,last,prefix,result,tag)
 local a=assert(s:find(first,1,true));local b=assert(s:find(last,a+1,true))
 local fn=CompileString(prefix..s:sub(a,b-1).."\nreturn "..result,"@zc36repair/"..tag,false)
 assert(isfunction(fn),tostring(fn));return fn()
end
R.tape=make(tape,"function SWEP:FindObjects()","function SWEP:PrimaryAttack()","local SWEP={}\n","SWEP.FindObjects","tape")
R.grenade=make(grenade,"function ENT:Explode()","function ENT:PlaySndExplosion", "local ENT={} local vecCone=Vector(0,0,0)\n","ENT.Explode","grenade")
R.before.hookCall=hook.Call;R.before.hookAdd=hook.Add;R.before.include=include;R.before.netStart=net.Start
R.before.startup={}
for _,event in ipairs({"Initialize","PostGamemodeLoaded","InitPostEntity"})do
 local copy={};for k,v in pairs(hook.GetTable()[event] or {})do copy[k]=v end
 R.before.startup[event]=copy
end
local function save()file.CreateDir("zc_36repair");file.Write("zc_36repair/live_receipt.json",util.TableToJSON(R.audit,true))end
function R.Verify()
 local ok=hook.Call==R.before.hookCall and hook.Add==R.before.hookAdd and include==R.before.include and net.Start==R.before.netStart
 for event,old in pairs(R.before.startup)do
  local now=hook.GetTable()[event] or {}
  for k,v in pairs(old)do if now[k]~=v then ok=false end end
  for k,v in pairs(now)do if old[k]~=v then ok=false end end
 end
 R.audit.startupAndDispatchUnchanged=ok;R.audit.checked=os.time();save()
 print("ZC36_VERIFY",ok,R.audit.tapeApplied or false,R.audit.grenadeApplied or false,R.audit.trainApplied or false)
 return ok
end
local function replace(t,key,old,new)
 if t[key]~=old then return end
 R.changes[#R.changes+1]={table=t,key=key,previous=rawget(t,key),applied=new}
 t[key]=new
end
function R.Apply(kind)
 assert(kind=="tape" or kind=="grenade");assert(not R.audit[kind.."Applied"],"Already applied")
 assert(R.Verify(),"Startup/dispatcher changed; reconcile first")
 local key=kind=="tape" and "FindObjects" or "Explode"
 local root=kind=="tape" and weapons.GetStored("weapon_ducttape") or scripted_ents.GetStored("ent_hg_grenade").t
 local old=assert(root[key]);local info=debug.getinfo(old,"S")
 assert(info.short_src:find(kind=="tape" and "weapon_ducttape.lua" or "ent_hg_grenade/init.lua",1,true),"Unexpected runtime override")
 local fn=R[kind];local seen={};local before=#R.changes
 local function visit(t,depth)
  if not istable(t) or seen[t] or depth>4 then return end;seen[t]=true
  replace(t,key,old,fn);visit(rawget(t,"BaseClass"),depth+1)
 end
 if kind=="tape" then
  for _,v in ipairs(weapons.GetList())do visit(weapons.GetStored(v.ClassName),0)end
 else
  for class in pairs(scripted_ents.GetList())do local v=scripted_ents.GetStored(class);if v then visit(v.t,0)end end
 end
 visit(root,0);visit(baseclass.Get(kind=="tape" and "weapon_ducttape" or "ent_hg_grenade"),0)
 for _,e in ipairs(ents.GetAll())do
  if IsValid(e) and e[key]==old then replace(e:GetTable(),key,old,fn);if e[key]==old then
   R.changes[#R.changes+1]={table=e:GetTable(),key=key,previous=rawget(e:GetTable(),key),applied=fn};e[key]=fn
  end end
 end
 assert(root[key]==fn,"Registered function not replaced")
 R.audit[kind.."Applied"]=true;R.audit[kind.."Changes"]=#R.changes-before
 assert(R.Verify(),"Unexpected startup mutation after narrow method repair")
end
function R.RollbackMethods()
 local conflicts=0
 for i=#R.changes,1,-1 do local c=R.changes[i]
  if c.table[c.key]==c.applied then c.table[c.key]=c.previous else conflicts=conflicts+1 end
 end
 R.audit.rollbackConflicts=conflicts;save();return conflicts
end
local function upvalue(fn,name)
 for i=1,80 do local n,v=debug.getupvalue(fn,i);if not n then break end;if n==name then return v end end
 error("Missing expected train closure: "..name)
end
R.trainOriginal=assert(ulx.traincrash)
R.trainCommand=assert(ULib.cmds.translatedCmds["ulx traincrash"])
assert(R.trainCommand.fn==R.trainOriginal,"Unexpected train command override")
R.trainQueue=upvalue(upvalue(R.trainOriginal,"QueueTrainSpawn"),"spawn_queue")
assert(istable(R.trainQueue),"Train queue unavailable")
R.originalTrainSource=assert(file.Read("ulx/modules/sh/mr_traincrash.lua","LUA"))
assert(util.SHA256(R.originalTrainSource)=="367eb466f44995f2bf84c45c6ffd6a7bd0244cf121cbd62dcd3cac58f0c61c15","Mounted train source drift")
function R.PauseTrains()
 assert(not R.trainPaused);assert(ulx.traincrash==R.trainOriginal and R.trainCommand.fn==R.trainOriginal)
 R.trainBlock=function(ply)ULib.tsayError(ply,"Train effects are temporarily paused for the stability repair.",true)end
 ulx.traincrash=R.trainBlock;R.trainCommand.fn=R.trainBlock
 R.audit.cancelledQueuedTrains=#R.trainQueue
 for i=#R.trainQueue,1,-1 do R.trainQueue[i]=nil end
 R.trainPaused=true;R.trainIdleAfter=CurTime()+8;save()
end
function R.TrainReady()
 if not R.trainPaused or CurTime()<R.trainIdleAfter or #R.trainQueue>0 then return false end
 R.trainReadyTick=R.trainReadyTick or engine.TickCount()
 return engine.TickCount()>R.trainReadyTick+2
end
function R.ApplyTrain()
 assert(R.TrainReady(),"Wait for previously active trains to finish")
 assert(R.Verify(),"Unexpected startup/dispatcher change")
 local path="ulx/modules/sh/mr_traincrash.lua";local source=assert(file.Read(path,"LUA"))
 assert(source==R.trainSource,"Installed train source differs from tested candidate")
 local f=CompileString(source,"@lua/"..path,false);assert(isfunction(f),tostring(f))
 timer.Remove("ulx_traincrash_tick");timer.Remove("ulx_traincrash_spawnq")
 local ok,err=xpcall(f,debug.traceback)
 if not ok then
  timer.Remove("ulx_traincrash_tick");timer.Remove("ulx_traincrash_spawnq")
  local restore=CompileString(R.originalTrainSource,"@lua/"..path,false);assert(isfunction(restore));restore();error(err)
 end
 assert(timer.Exists("ulx_traincrash_tick") and timer.Exists("ulx_traincrash_spawnq"),"Train timers not registered")
 assert(ULib.cmds.translatedCmds["ulx traincrash"].fn==ulx.traincrash,"Train registration mismatch")
 R.audit.trainApplied=true;R.audit.trainAppliedAt=os.time();assert(R.Verify())
end
R.audit.prepared=true
ZC36RepairOps=R
save()
print("ZC36_PREPARED",game.GetMap(),#player.GetHumans(),R.Verify())
