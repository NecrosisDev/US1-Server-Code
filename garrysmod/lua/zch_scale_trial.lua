local tag="e553fe786691" local sources={} local result={tag=tag,time=os.time(),pass=true,files={}}
for _,name in ipairs({"sh","sv","cl"}) do
 local src=file.Read("zch_scale_"..tag.."_"..name..".txt","DATA") sources[name]=src
 local f=CompileString(src,"ZCHScale_"..name,false)
 result.files[name]={compiled=isfunction(f),crc=util.CRC(src),error=isstring(f) and f or nil}
 result.pass=result.pass and isfunction(f)
end
file.Write("zch_scale_"..tag.."_compile.json",util.TableToJSON(result,true))
if not result.pass then return end
util.AddNetworkString("zch_scale_trial_ack")
net.Receive("zch_scale_trial_ack",function(len,p)
 if len>16384 or p:SteamID64()~="76561198011536179" then return end
 local r=util.JSONToTable(net.ReadString())
 if not istable(r) or r.tag~=tag or r.sh~=util.CRC(sources.sh) or r.cl~=util.CRC(sources.cl) then return end
 r.time=os.time() file.Write("zch_scale_"..tag.."_client.json",util.TableToJSON(r,true))
end)
timer.Create("ZCHScale.Trial",1,60,function()
 for _,p in ipairs(player.GetHumans()) do
  if p:SteamID64()=="76561198011536179" and ZCityHostage.Gameplay.Role(p)=="" then
   timer.Remove("ZCHScale.Trial")
   p:SendLua("ZCH_SCALE_TRIAL={tag='"..tag.."',sources={}}")
   for _,name in ipairs({"sh","cl"}) do
    p:SendLua("ZCH_SCALE_TRIAL.sources."..name.."=''")
    for i=1,#sources[name],2200 do
     p:SendLua("ZCH_SCALE_TRIAL.sources."..name.."=ZCH_SCALE_TRIAL.sources."..name..".."..string.format("%q",string.sub(sources[name],i,i+2199)))
    end
   end
   p:SendLua([=[local t=ZCH_SCALE_TRIAL ZCH_SCALE_TRIAL=nil
if ZCityHostage.Gameplay.Role(LocalPlayer())~="" then return end
local r={tag=t.tag,loaded=true,sh=util.CRC(t.sources.sh),cl=util.CRC(t.sources.cl)}
for _,name in ipairs({"sh","cl"}) do
 local f=CompileString(t.sources[name],"ZCHScaleTrial_"..name,false)
 if not isfunction(f) then r.loaded=false r.error=f break end
 local ok,err=xpcall(f,debug.traceback) if not ok then r.loaded=false r.error=err break end
end
r.reach=isfunction(ZCityHostage.Gameplay.Reach)
net.Start("zch_scale_trial_ack") net.WriteString(util.TableToJSON(r)) net.SendToServer()]=])
  end
 end
end)
print("ZCH_SCALE_STAGED",tag,result.pass)
