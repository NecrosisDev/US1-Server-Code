local tag="17356047da3c"
local sources={} local result={time=os.time(),tag=tag,files={},pass=true}
for _,name in ipairs({"shared","server","camera","inertia","tpik"}) do
 local src=file.Read("zch_motion_"..tag.."_"..name..".txt","DATA")
 local fn=CompileString(src,"ZCHMotion_"..name,false)
 sources[name]=src
 result.files[name]={compiled=isfunction(fn),crc=util.CRC(src)}
 if not isfunction(fn) then result.pass=false result.files[name].error=fn end
end
file.Write("zch_motion_"..tag.."_compile.json",util.TableToJSON(result,true))
if not result.pass then return end
util.AddNetworkString("zch_motion_trial_ack")
net.Receive("zch_motion_trial_ack",function(len,p)
 if len>16384 or p:SteamID64()~="76561198011536179" then return end
 local receipt=util.JSONToTable(net.ReadString())
 file.Write("zch_motion_trial_raw.json",util.TableToJSON(receipt or {},true))
 if not istable(receipt) or receipt.tag~=tag then return end
 for _,name in ipairs({"shared","camera","inertia","tpik"}) do
  if receipt[name]~=util.CRC(sources[name]) then return end
 end
 receipt.time=os.time()
 file.Write("zch_motion_"..tag.."_client.json",util.TableToJSON(receipt,true))
end)
timer.Create("ZCHMotion.TrialDelivery",1,60,function()
 for _,p in ipairs(player.GetHumans()) do
  if p:SteamID64()=="76561198011536179" and ZCityHostage.Gameplay.Role(p)=="" then
   timer.Remove("ZCHMotion.TrialDelivery")
   p:SendLua("ZCH_MOTION_TRIAL={tag='"..tag.."',sources={}}")
   for _,name in ipairs({"shared","camera","inertia","tpik"}) do
    p:SendLua("ZCH_MOTION_TRIAL.sources."..name.."=''")
    local src=sources[name]
    for i=1,#src,2200 do
     p:SendLua("ZCH_MOTION_TRIAL.sources."..name.."=ZCH_MOTION_TRIAL.sources."..name..".."..string.format("%q",string.sub(src,i,i+2199)))
    end
   end
   p:SendLua([=[local trial=ZCH_MOTION_TRIAL ZCH_MOTION_TRIAL=nil
if ZCityHostage.Gameplay.Role(LocalPlayer())~="" then return end
local receipt={tag=trial.tag,loaded=true} local functions={}
for _,name in ipairs({"shared","camera","inertia","tpik"}) do
 local src=trial.sources[name] receipt[name]=util.CRC(src)
 local fn=CompileString(src,"ZCHMotionTrial_"..name,false)
 if not isfunction(fn) then receipt.loaded=false receipt.error=tostring(fn) break end
 functions[name]=fn
end
if receipt.loaded then
 for _,name in ipairs({"shared","camera","inertia","tpik"}) do
  local ok,err=xpcall(functions[name],debug.traceback)
  if not ok then receipt.loaded=false receipt.error=tostring(err) break end
 end
end
receipt.armOwner=hg.ZCHRightArmSolver==hg.DoTPIK
receipt.cameraSource=debug.getinfo(hg.CalcView,"S").short_src
receipt.revision=ZCityHostage.Gameplay.MotionRevision
ZCityHostage.Gameplay.MotionTrialReceipt=receipt
net.Start("zch_motion_trial_ack") net.WriteString(util.TableToJSON(receipt)) net.SendToServer()
]=])
  end
 end
end)
print("ZCH_MOTION_S17356047da3cE",tag,result.pass)
