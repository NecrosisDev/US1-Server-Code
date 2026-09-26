local sv=file.Read("zch_grab_sv_gameplay.lua.txt","DATA")
local cl=file.Read("zch_grab_cl_gameplay.lua.txt","DATA")
local r={time=os.time(),server=type(CompileString(sv,"ZCHGrabServer",false))=="function",client=type(CompileString(cl,"ZCHGrabClient",false))=="function",idle=next(ZCityHostage.Gameplay.Sessions)==nil}
file.Write("zch_grab_compile.json",util.TableToJSON(r,true))
util.AddNetworkString("zch_grab_fix_ack")
net.Receive("zch_grab_fix_ack",function(len,p)
 if len>512 or not IsValid(p) or p:SteamID64()~="76561198011536179" then return end
 local crc=net.ReadString() if crc~=util.CRC(cl) then return end
 file.Write("zch_grab_fix_client.json",util.TableToJSON({time=os.time(),loaded=true,crc=crc},true))
end)
for _,p in ipairs(player.GetHumans()) do
 if p:SteamID64()=="76561198011536179" and ZCityHostage.Gameplay.Role(p)=="" then
  p:SendLua("ZCH_GRAB_FIX=''")
  for i=1,#cl,2200 do p:SendLua("ZCH_GRAB_FIX=ZCH_GRAB_FIX.."..string.format("%q",string.sub(cl,i,i+2199))) end
  p:SendLua([[local s=ZCH_GRAB_FIX ZCH_GRAB_FIX=nil if ZCityHostage.Gameplay.Role(LocalPlayer())~="" then return end local f=CompileString(s,"ZCHGrabClient",false) if type(f)~="function" then return end f() net.Start("zch_grab_fix_ack") net.WriteString(util.CRC(s)) net.SendToServer()]])
 end
end
print("ZCH_GRAB_COMPILE",util.TableToJSON(r))
