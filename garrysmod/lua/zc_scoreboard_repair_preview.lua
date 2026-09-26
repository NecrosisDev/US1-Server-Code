if not SERVER then return end
local own=assert(file.Read("zc_scoreboard_self_candidate.txt","DATA"));assert(util.SHA256(own)=="f06020d89b828a5f8e32f14996fff21d029bb586f24b53eb53c10c2291425c73");local ownfn=CompileString(own,"ZCScoreboardSelfPreview",false);assert(isfunction(ownfn));ownfn()
local source=assert(file.Read("zc_scoreboard_karma_candidate.txt","DATA"))
assert(util.SHA256(source)=="e05b364e24f9fef4766a4c0cb6e0d96afe8371760e02e62c4c6baea0656071f4")
assert(util.SHA256(file.Read("autorun/client/cl_pat_scoreboard.lua","LUA") or "")=="5185a1ee7a8d34834d2858d450feed3c94ecf105efe195278c83db32a60e97cf")
assert(isfunction(CompileString(source,"ZCScoreboardRepair",false)))
util.AddNetworkString("ZCScoreboardRepairPayload");util.AddNetworkString("ZCScoreboardRepairAck")
local state={sent={},ack={}};ZCScoreboardRepair=state
net.Receive("ZCScoreboardRepairAck",function(bits,p)
 if bits>4096 or not state.sent[p]then return end
 state.ack[p:SteamID64()]={ok=net.ReadBool(),detail=net.ReadString(),userid=p:UserID()}
 file.Write("zc_scoreboard_repair_ack.json",util.TableToJSON(state.ack,true))
end)
local bootstrap=[=[
net.Receive("ZCScoreboardRepairPayload",function()
 local length=net.ReadUInt(16);local source=util.Decompress(net.ReadData(length))
 local ok,err=pcall(function()
  assert(isstring(source) and util.SHA256(source)=="e05b364e24f9fef4766a4c0cb6e0d96afe8371760e02e62c4c6baea0656071f4","scoreboard checksum")
  local f=CompileString(source,"ZCScoreboardRepair",false);assert(isfunction(f),tostring(f));f()
  assert(PATSB.KarmaDisplayVersion=="20260923.karma2")
 end)
 net.Start("ZCScoreboardRepairAck");net.WriteBool(ok);net.WriteString(ok and "20260923.karma2" or tostring(err):sub(1,400));net.SendToServer()
end)
]=]
local packed=assert(util.Compress(source));assert(#packed<60000)
function state.Send(p)
 if not IsValid(p) or p:IsBot()then return end
 state.sent[p]=true;p:SendLua(bootstrap)
 timer.Simple(1,function()
  if not IsValid(p)then return end
  net.Start("ZCScoreboardRepairPayload");net.WriteUInt(#packed,16);net.WriteData(packed,#packed);net.Send(p)
 end)
end
for _,p in ipairs(player.GetHumans())do if p:SteamID64()=="76561198011536179"then state.Send(p)end end
