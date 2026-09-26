local tag="9231cc0728a9"
local sources={} local result={time=os.time(),tag=tag,files={},pass=true}
for _,name in ipairs({"shared","server"}) do
 local src=file.Read("zch_follow_"..tag.."_"..name..".txt","DATA")
 local fn=CompileString(src,"ZCHFollowReview_"..name,false)
 sources[name]=src
 result.files[name]={compiled=isfunction(fn),crc=util.CRC(src)}
 if not isfunction(fn) then result.pass=false result.files[name].error=fn end
end
file.Write("zch_follow_"..tag.."_compile.json",util.TableToJSON(result,true))
if not result.pass then return end
util.AddNetworkString("zch_follow_trial_ack")
net.Receive("zch_follow_trial_ack",function(len,p)
 if len>16384 or p:SteamID64()~="76561198011536179" then return end
 local receipt=util.JSONToTable(net.ReadString())
 file.Write("zch_follow_trial_raw.json",util.TableToJSON(receipt or {},true))
 if not istable(receipt) or receipt.tag~=tag then return end
 for _,name in ipairs({"shared"}) do
  if receipt[name]~=util.CRC(sources[name]) then return end
 end
 receipt.time=os.time()
 file.Write("zch_follow_"..tag.."_client.json",util.TableToJSON(receipt,true))
end)
timer.Create("ZCHFollowReview.TrialDelivery",1,60,function()
 for _,p in ipairs(player.GetHumans()) do
  if p:SteamID64()=="76561198011536179" and ZCityHostage.Gameplay.Role(p)=="" then
   timer.Remove("ZCHFollowReview.TrialDelivery")
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
 local fn=CompileString(src,"ZCHFollowReviewTrial_"..name,false)
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
receipt.aim=ZCityHostage.Gameplay.AimRevision
-- Controlled client trial: temporary hidden models, no live player actions.
receipt.follow=ZCityHostage.Gameplay.FollowRevision
receipt.bones={pass=true,models={}}
for _,path in ipairs({"models/zcity_hostage/gameplay_male.mdl","models/zcity_hostage/gameplay_female.mdl"}) do
 local model=ClientsideModel(path,RENDERGROUP_OPAQUE)
 local row={model=path,pass=false}
 local ok,err=xpcall(function()
  assert(IsValid(model),"missing trial model")
  model:SetNoDraw(true) model:SetPos(Vector()) model:SetAngles(Angle()) model:SetupBones()
  local before={} local count=0
  for b=0,model:GetBoneCount()-1 do
   local m=model:GetBoneMatrix(b)
   if m then before[b]=m:GetTranslation() count=count+1 end
  end
  assert(count>20,"too few bone matrices")
  local calls=0 local offset=Vector(7,0,0)
  local id=model:AddCallback("BuildBonePositions",function(ent,n)
   calls=calls+1 ZCityHostage.Gameplay.ApplyFollowerBoneOffset(ent,n,offset)
  end)
  local worst=0
  for pass=1,2 do
   model:InvalidateBoneCache() model:SetupBones()
   for b,pos in pairs(before) do
    local m=model:GetBoneMatrix(b) assert(m,"missing rebuilt matrix")
    worst=math.max(worst,m:GetTranslation():Distance(pos+offset))
   end
  end
  assert(model:GetPos():LengthSqr()==0,"entity origin changed")
  model:RemoveCallback("BuildBonePositions",id)
  model:InvalidateBoneCache() model:SetupBones()
  local restored=0
  for b,pos in pairs(before) do restored=math.max(restored,model:GetBoneMatrix(b):GetTranslation():Distance(pos)) end
  row.bones=count row.calls=calls row.maxError=worst row.restoreError=restored
  row.pass=calls>=2 and worst<.02 and restored<.02
 end,debug.traceback)
 if IsValid(model) then model:Remove() end
 if not ok then row.error=err end
 receipt.bones.models[#receipt.bones.models+1]=row
 receipt.bones.pass=receipt.bones.pass and row.pass
end

ZCityHostage.Gameplay.MotionTrialReceipt=receipt
net.Start("zch_follow_trial_ack") net.WriteString(util.TableToJSON(receipt)) net.SendToServer()
]=])
  end
 end
end)
print("ZCH_MOTION_S9231cc0728a9E",tag,result.pass)
