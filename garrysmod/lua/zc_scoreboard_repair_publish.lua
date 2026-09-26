local state=assert(ZCScoreboardRepair)
state.public=true
net.Receive("ZCScoreboardRepairAck",function(bits,p)
 if bits>4096 or not state.sent[p]then return end
 local ok,detail=net.ReadBool(),net.ReadString()
 state.ack[p:SteamID64()]={ok=ok,detail=detail,userid=p:UserID()}
 if not ok then state.halted=true end
 file.Write("zc_scoreboard_repair_ack.json",util.TableToJSON(state.ack,true))
end)
for i,p in ipairs(player.GetHumans())do timer.Simple((i-1)*1.25,function()
 if not state.halted and IsValid(p)then state.Send(p)end
end)end
