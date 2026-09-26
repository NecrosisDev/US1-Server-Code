util.AddNetworkString("ZCChatPMUIProbe")
net.Receive("ZCChatPMUIProbe",function(bits,ply)
 if bits>24000 or ply:SteamID64()~="76561198011536179" then return end
 local result=util.JSONToTable(net.ReadString())
 if not istable(result) then return end
 file.Write("zc_chat_pm_ui_probe.json",util.TableToJSON(result,true))
end)
local client=[=[
 local c=hg and hg.chat
 local r={valid=IsValid(c),build=ZCChatBuild,media=ZCChatMedia and ZCChatMedia.Version,threads=ZCChatThreads and ZCChatThreads.Version}
 if IsValid(c) then
  r.active=c:GetActive();r.width=c:GetWide();r.height=c:GetTall();r.tabstrip=IsValid(c.ZCTabStrip);r.players=IsValid(c.ZCPlayers);r.compose=IsValid(c.ZCNewMessage)
  r.directory=IsValid(c.ZCDirectory);r.selected=c.ZCThreadKey=="main" and "main" or "private";r.threadCount=table.Count(c.ZCThreads or {});r.rowCount=#(c.entries or {})
  if r.tabstrip then r.tabX,r.tabY=c.ZCTabStrip:GetPos();r.tabWidth,r.tabHeight=c.ZCTabStrip:GetSize() end
  r.inputValid=IsValid(c.entry);r.replyID=c.ZCReplyID~=nil
 end
 net.Start("ZCChatPMUIProbe");net.WriteString(util.TableToJSON(r));net.SendToServer()
]=]
for _,p in ipairs(player.GetHumans()) do if p:SteamID64()=="76561198011536179" then p:SendLua(client) end end
local r={}
for _,path in ipairs({"zc_chat_pm_preview.lua","autorun/server/zc_chat_pm_preview_restore.lua","zc_chat_conversation_preview.lua"}) do
 local f=CompileString(assert(file.Read(path,"LUA")),"PMPersistenceCheck/"..path,false);r[path]=isfunction(f) and "compiled" or tostring(f)
end
file.Write("zc_chat_pm_persistence_check.json",util.TableToJSON(r,true))
