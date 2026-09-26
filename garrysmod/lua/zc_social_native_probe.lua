util.AddNetworkString("ZCSocialNativeProbe")
ZCSocialNativeProof={map=game.GetMap(),clients={}}
local proof=ZCSocialNativeProof
net.Receive("ZCSocialNativeProbe",function(len,p)
 if len>2048 or not IsValid(p) then return end
 local build,media,features=net.ReadString(),net.ReadString(),net.ReadBool()
 proof.clients[tostring(p:UserID())]={build=build,media=media,features=features}
 file.Write("zc_chat_social_stage/native_proof.json",util.TableToJSON(proof,true))
end)
for _,p in ipairs(player.GetHumans()) do p:SendLua([=[
local m=ZCChatMedia local c=hg and hg.chat
net.Start("ZCSocialNativeProbe")
net.WriteString(tostring(ZCChatBuild));net.WriteString(tostring(m and m.Version))
net.WriteBool(m and isfunction(m.CreatePicker) and isfunction(m.UpdateRowActions) and IsValid(c) and IsValid(c.ZCEmoteButton) or false)
net.SendToServer()
]=]) end
