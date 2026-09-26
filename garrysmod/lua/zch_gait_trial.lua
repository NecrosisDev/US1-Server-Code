local tag="360831489608"
local sources={} local result={time=os.time(),tag=tag,files={},pass=true}
for _,name in ipairs({"shared"}) do
 local src=file.Read("zch_gait_"..tag.."_"..name..".txt","DATA")
 local fn=CompileString(src,"ZCHGait_"..name,false)
 sources[name]=src
 result.files[name]={compiled=isfunction(fn),crc=util.CRC(src)}
 if not isfunction(fn) then result.pass=false result.files[name].error=fn end
end
file.Write("zch_gait_"..tag.."_compile.json",util.TableToJSON(result,true))
if not result.pass then return end
util.AddNetworkString("zch_gait_trial_ack")
net.Receive("zch_gait_trial_ack",function(len,p)
 if len>16384 or p:SteamID64()~="76561198011536179" then return end
 local receipt=util.JSONToTable(net.ReadString())
 file.Write("zch_gait_trial_raw.json",util.TableToJSON(receipt or {},true))
 if not istable(receipt) or receipt.tag~=tag then return end
 for _,name in ipairs({"shared"}) do
  if receipt[name]~=util.CRC(sources[name]) then return end
 end
 receipt.time=os.time()
 file.Write("zch_gait_"..tag.."_client.json",util.TableToJSON(receipt,true))
end)
timer.Create("ZCHGait.TrialDelivery",1,60,function()
 for _,p in ipairs(player.GetHumans()) do
  if p:SteamID64()=="76561198011536179" and ZCityHostage.Gameplay.Role(p)=="" then
   timer.Remove("ZCHGait.TrialDelivery")
   p:SendLua("ZCH_MOTION_TRIAL={tag='"..tag.."',sources={}}")
   for _,name in ipairs({"shared"}) do
    p:SendLua("ZCH_MOTION_TRIAL.sources."..name.."=''")
    local src=sources[name]
    for i=1,#src,2200 do
     p:SendLua("ZCH_MOTION_TRIAL.sources."..name.."=ZCH_MOTION_TRIAL.sources."..name..".."..string.format("%q",string.sub(src,i,i+2199)))
    end
   end
   p:SendLua([=[local trial=ZCH_MOTION_TRIAL ZCH_MOTION_TRIAL=nil
if ZCityHostage.Gameplay.Role(LocalPlayer())~="" then return end
local receipt={tag=trial.tag,loaded=true} local functions={}
for _,name in ipairs({"shared"}) do
 local src=trial.sources[name] receipt[name]=util.CRC(src)
 local fn=CompileString(src,"ZCHGaitTrial_"..name,false)
 if not isfunction(fn) then receipt.loaded=false receipt.error=tostring(fn) break end
 functions[name]=fn
end
if receipt.loaded then
 for _,name in ipairs({"shared"}) do
  local ok,err=xpcall(functions[name],debug.traceback)
  if not ok then receipt.loaded=false receipt.error=tostring(err) break end
 end
end
receipt.armOwner=hg.ZCHRightArmSolver==hg.DoTPIK
receipt.cameraSource=debug.getinfo(hg.CalcView,"S").short_src
receipt.revision=ZCityHostage.Gameplay.MotionRevision
receipt.presentation=ZCityHostage.Gameplay.PresentationRevision
receipt.viewOrigin=isfunction(ZCityHostage.Gameplay.ViewOrigin)
-- Hidden, temporary animation entities; no changes to live player state.
receipt.gait=ZCityHostage.Gameplay.GaitRevision
receipt.gaitNative={pass=false,frames=0,maxPairError=0,maxStep=0}
local G=ZCityHostage.Gameplay
local models={}
local hookID="ZCHGaitTrial.Check"
local completed=false
local function finish(err)
 if completed then return end
 completed=true
 hook.Remove("Think",hookID) timer.Remove(hookID)
 for _,m in ipairs(models) do
  if IsValid(m) then G.ResetWalkCycle(m) m:Remove() end
 end
 if err then receipt.gaitNative.error=tostring(err) end
 receipt.gaitNative.pass=not err and receipt.gaitNative.frames>=20
 G.MotionTrialReceipt=receipt
 net.Start("zch_gait_trial_ack") net.WriteString(util.TableToJSON(receipt)) net.SendToServer()
end
local ok,err=xpcall(function()
 for _,path in ipairs({"models/zcity_hostage/gameplay_male.mdl","models/zcity_hostage/gameplay_female.mdl"}) do
  local m=ClientsideModel(path,RENDERGROUP_OPAQUE)
  assert(IsValid(m),"missing trial model") models[#models+1]=m
  m:SetNoDraw(true) m:SetPos(Vector())
 end
 local a,v=models[1],models[2]
 local start=CurTime()
 for i,p in ipairs(models) do
  p:SetNWString("zch_role",i==1 and "captor" or "victim")
  p:SetNWEntity("zch_partner",i==1 and v or a)
  p:SetNWInt("zch_session",2147480000)
  p:SetNWBool("zch_motion_v2",true)
  p:SetNWString("zch_phase","hold") p:SetNWFloat("zch_phase_start",start)
  local seq="zcg_paired_pistol_grabhostage_walkforward_"..(i==1 and "att" or "vic")
  p:SetNWString("zch_sequence",seq) p:SetNWString("hg_CustomAnim",seq)
  p:SetNWFloat("zch_walk_cycle",i==1 and .4 or .1)
  p:SetNWFloat("zch_walk_time",start) p:SetNWFloat("zch_walk_rate",1)
 end
 local previous=G.Cycle(a,0,1)
 assert(previous==G.Cycle(v,0,1),"pair clocks differ at initialization")
 local frame,time=FrameNumber(),CurTime()
 hook.Add("Think",hookID,function()
  local success,failure=xpcall(function()
   if frame==FrameNumber() then return end
   local now=CurTime() local dt=now-time
   if dt<=0 then return end
   assert(dt<=.25,"trial frame stalled; rerun")
   a:SetNWFloat("zch_walk_time",now)
   a:SetNWFloat("zch_walk_cycle",(.4+now-start+math.sin(receipt.gaitNative.frames)*.15)%1)
   local current=G.Cycle(v,0,1)
   local pairError=math.abs(current-G.Cycle(a,0,1))
   local step=(current-previous+.5)%1-.5
   assert(pairError<.000001,"pair clocks differ")
   assert(step>=dt*.5-.00001 and step<=dt*1.5+.00001,"phase correction jumped or reversed")
   assert(a:GetPos():LengthSqr()==0 and v:GetPos():LengthSqr()==0,"origin changed")
   receipt.gaitNative.frames=receipt.gaitNative.frames+1
   receipt.gaitNative.maxPairError=math.max(receipt.gaitNative.maxPairError,pairError)
   receipt.gaitNative.maxStep=math.max(receipt.gaitNative.maxStep,step)
   frame=FrameNumber() time=now previous=current
   if receipt.gaitNative.frames>=20 then finish() end
  end,debug.traceback)
  if not success then finish(failure) end
 end)
 timer.Create(hookID,10,1,function() finish("trial timed out") end)
end,debug.traceback)
if not ok then finish(err) end

]=])
  end
 end
end)
print("ZCH_MOTION_S360831489608E",tag,result.pass)
