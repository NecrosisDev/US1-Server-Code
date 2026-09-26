local source=file.Read("zch_quickgrab_source.txt","DATA")
local result={time=os.time(),compiled=type(CompileString(source,"ZCHQuickGrab",false))=="function"}
file.Write("zch_quickgrab_compile.json",util.TableToJSON(result,true))
util.AddNetworkString("zch_quickgrab_ack")
net.Receive("zch_quickgrab_ack",function(len,p)
 if len>512 or not IsValid(p) or p:SteamID64()~="76561198011536179" then return end
 local crc=net.ReadString()
 if crc~=util.CRC(source) then return end
 file.Write("zch_quickgrab_client.json",util.TableToJSON({time=os.time(),crc=crc,loaded=true},true))
end)
function ZCH_QuickGrabTrial()
 for _,p in ipairs(player.GetHumans()) do
  if p:SteamID64()=="76561198011536179" then
   if ZCityHostage.Gameplay.Role(p)~="" then return "tester busy" end
   p:SendLua("ZCH_QUICKGRAB_UPLOAD=''")
   for i=1,#source,2200 do p:SendLua("ZCH_QUICKGRAB_UPLOAD=ZCH_QUICKGRAB_UPLOAD.."..string.format("%q",string.sub(source,i,i+2199))) end
   p:SendLua([[local s=ZCH_QUICKGRAB_UPLOAD ZCH_QUICKGRAB_UPLOAD=nil if not ZCityHostage or ZCityHostage.Gameplay.Role(LocalPlayer())~="" then return end local f=CompileString(s,"ZCHQuickGrab",false) if type(f)~="function" then return end f() net.Start("zch_quickgrab_ack") net.WriteString(util.CRC(s)) net.SendToServer()]])
   return "sent to tester"
  end
 end
 return "tester not in game"
end
print("ZCH_QUICKGRAB",result.compiled,ZCH_QuickGrabTrial())
