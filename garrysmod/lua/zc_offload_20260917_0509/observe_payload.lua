-- Manual bounded payload-size census. No messages sent or gameplay state changed.
assert(SERVER and engine.ActiveGamemode()=="zcity")
local id="ZCOffloadSize_20260917_0509"
assert(not timer.Exists(id),"Census already running")
local measure=include("zc_offload_20260917_0509/measure_payload.lua")
local rows={};local clipped=false
for ent,data in pairs(zb.net.list)do
 if IsValid(ent) and istable(data.Inventory)then
  if #rows<96 then rows[#rows+1]={entity=ent,creation=ent:GetCreationID()}else clipped=true end
 end
end
local out={started=os.time(),map=game.GetMap(),mode=zb.CROUND,players=#player.GetHumans(),
 samples={},candidates=#rows,clipped=clipped,errors={},scope="Current encoded payload sizes; no observed publication rates or wire bandwidth"}
local funcs={net.Start,net.Send,net.Broadcast,hook.Call,hook.Add,include}
local index=0;local finished=false;local start=SysTime()
local function finish(reason)
 if finished then return end;finished=true
 timer.Remove(id);timer.Remove(id.."watchdog")
 out.reason=reason;out.elapsed=SysTime()-start
 out.functionsUnchanged=net.Start==funcs[1] and net.Send==funcs[2] and net.Broadcast==funcs[3]
  and hook.Call==funcs[4] and hook.Add==funcs[5] and include==funcs[6]
 out.timerRemoved=not timer.Exists(id);out.watchdogRemoved=not timer.Exists(id.."watchdog")
 file.CreateDir("zc_offload_evaluation")
 file.Write("zc_offload_evaluation/payload_20260917_0509.json",util.TableToJSON(out,true))
 print("OFFLOAD_PAYLOAD_DONE",reason,#out.samples,out.functionsUnchanged)
end
timer.Create(id,0.1,0,function()
 local ok,err=xpcall(function()
  index=index+1;local row=rows[index]
  if not row then finish("complete");return end
  local e=row.entity
  if not IsValid(e) or e:GetCreationID()~=row.creation then return end
  local data=zb.net.list[e];local inv=data and data.Inventory
  if not istable(inv)then return end
  local r=measure(e:EntIndex(),inv)
  r.kind=e:IsPlayer() and "player" or e:IsRagdoll() and "ragdoll" or "other"
  r.alive=e:IsPlayer() and e:Alive() or false
  r.mode=zb.CROUND;r.weapons=istable(inv.Weapons) and table.Count(inv.Weapons) or 0
  r.ammoTypes=istable(inv.Ammo) and table.Count(inv.Ammo) or 0
  out.samples[#out.samples+1]=r
  if r.elapsedMs>2 then finish("sample_budget_exceeded")end
 end,debug.traceback)
 if not ok then net.Abort();out.errors[#out.errors+1]=tostring(err);finish("error")end
end)
timer.Create(id.."watchdog",20,1,function()finish("watchdog")end)
print("OFFLOAD_PAYLOAD_STARTED",#rows)
