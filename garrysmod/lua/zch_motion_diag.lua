util.AddNetworkString("zch_motion_diag")
net.Receive("zch_motion_diag",function(len,p)
 if len>16384 or p:SteamID64()~="76561198011536179" then return end
 file.Write("zch_motion_diag.json",net.ReadString())
end)
for _,p in ipairs(player.GetHumans()) do
 if p:SteamID64()=="76561198011536179" then
  p:SendLua([=[local t=ZCH_MOTION_TRIAL local r={time=os.time(),revision=ZCityHostage.Gameplay.MotionRevision,buffer=t~=nil,arm=hg.ZCHRightArmSolver==hg.DoTPIK,camera=debug.getinfo(hg.CalcView,"S").short_src}
if t then r.lengths={} for k,v in pairs(t.sources) do r.lengths[k]=#v end end
net.Start("zch_motion_diag") net.WriteString(util.TableToJSON(r)) net.SendToServer()]=])
 end
end
