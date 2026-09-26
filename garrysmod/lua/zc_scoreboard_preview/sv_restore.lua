if not SERVER then return end
local source=assert(file.Read("zc_scoreboard_successor_candidate.txt","DATA"))
assert(util.SHA256(source)=="56fc0a43aec385d6cd0e8dcedb346824d451de2785aef6c081c5b2a31c8fa117","successor candidate changed")
assert(util.SHA256(file.Read("autorun/client/cl_pat_scoreboard.lua","LUA")or"")=="e05b364e24f9fef4766a4c0cb6e0d96afe8371760e02e62c4c6baea0656071f4","scoreboard baseline changed")
assert(isfunction(CompileString(source,"ZCScoreboardSuccessor",false)))
util.AddNetworkString("ZCScoreboardSuccessorPayload");util.AddNetworkString("ZCScoreboardSuccessorAck")
local state={sent={},ack={}};ZCScoreboardSuccessorPreview=state
net.Receive("ZCScoreboardSuccessorAck",function(bits,p)
 if bits>8192 or not state.sent[p] or p:SteamID64()~="76561198011536179"then return end
 state.ack[p:SteamID64()]={ok=net.ReadBool(),detail=net.ReadString(),userid=p:UserID(),at=os.time()}
 file.Write("zc_scoreboard_successor_ack.json",util.TableToJSON(state.ack,true))
end)
local bootstrap=[=[
net.Receive("ZCScoreboardSuccessorPayload",function()
 local length=net.ReadUInt(16);local source=util.Decompress(net.ReadData(length))
 local safeRollback=false
 local ok,err=xpcall(function()
  local allowed={["addons/scoreboard/lua/autorun/client/cl_pat_scoreboard.lua"]=true,["autorun/client/cl_pat_scoreboard.lua"]=true,["zc_scoreboard_voice_trial_20260920"]=true,["ZCScoreboardRepair"]=true}
  for event,name in pairs({ScoreboardShow="PATSB_Show",ScoreboardHide="PATSB_Hide"})do
   local callback=(hook.GetTable()[event]or{})[name]
   if isfunction(callback)then assert(allowed[debug.getinfo(callback,"S").short_src],"Scoreboard owner changed")end
  end
  safeRollback=true
  assert(isstring(source)and util.SHA256(source)=="56fc0a43aec385d6cd0e8dcedb346824d451de2785aef6c081c5b2a31c8fa117","scoreboard checksum")
  local fn=CompileString(source,"ZCScoreboardSuccessor",false);assert(isfunction(fn),tostring(fn));fn()
  assert(ZCScoreboard.Version=="20260923.roster3")
 end,debug.traceback)
 if not ok and safeRollback then
  if ZCScoreboard and ZCScoreboard.Close then pcall(ZCScoreboard.Close)end
  for e,n in pairs({ScoreboardShow="ZCScoreboard.Show",ScoreboardHide="ZCScoreboard.Hide",InitPostEntity="ZCScoreboard.Settings",OnScreenSizeChanged="ZCScoreboard.Resize"})do hook.Remove(e,n)end
  include("autorun/client/cl_pat_scoreboard.lua")
 end
 net.Start("ZCScoreboardSuccessorAck");net.WriteBool(ok);net.WriteString(ok and "20260923.roster3"or tostring(err):sub(1,900));net.SendToServer()
end)
]=]
local packed=assert(util.Compress(source));assert(#packed<60000)
function state.Send(p)
 if not IsValid(p)or p:IsBot()or p:SteamID64()~="76561198011536179"then return end
 state.sent[p]=true;p:SendLua(bootstrap)
 timer.Simple(1,function()if not IsValid(p)then return end
  net.Start("ZCScoreboardSuccessorPayload");net.WriteUInt(#packed,16);net.WriteData(packed,#packed);net.Send(p)
 end)
end
hook.Add("PlayerInitialSpawn","ZCScoreboard.SuccessorPreview",function(p)timer.Simple(8,function()state.Send(p)end)end)
timer.Simple(2,function()for _,p in ipairs(player.GetHumans())do state.Send(p)end end)
file.Write("zc_scoreboard_successor_preflight.json",util.TableToJSON({compiled=true,version="20260923.roster3",at=os.time(),humans=#player.GetHumans()},true))
