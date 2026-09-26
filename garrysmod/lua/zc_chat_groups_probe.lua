local G=ZCChatGroups
local store=G.DecodeStore(file.Read("zc_chat_media/groups.json","DATA"))
local result={version=G.Version,groups=table.Count(G.groups),storedGroups=store and table.Count(store) or 0,membershipMatches=store~=nil}
if store then
 for id,g in pairs(G.groups)do
  local saved=store[id]
  if not saved or saved.owner~=g.owner or saved.name~=g.name or table.Count(saved.members)~=table.Count(g.members)then result.membershipMatches=false
  else for steam in pairs(g.members)do if not saved.members[steam]then result.membershipMatches=false end end end
 end
end
for _,p in ipairs(player.GetHumans())do if p:SteamID64()=="76561198011536179"then result.ownerPeekPermission=G.CanPeek(p);result.ownerSpectator=G.Spectator(p)end end
result.restoreCompiled=isfunction(CompileString(assert(file.Read("autorun/server/zc_chat_groups_preview_restore.lua","LUA")),"GroupRestoreCheck",false))
result.oldPreviewGuardCompiled=isfunction(CompileString(assert(file.Read("zc_chat_pm_preview.lua","LUA")),"GroupOldPreviewGuardCheck",false))
file.Write("zc_chat_groups_runtime.json",util.TableToJSON(result,true))
util.AddNetworkString("ZCGroupUIProbe")
net.Receive("ZCGroupUIProbe",function(bits,p)
 if bits>12000 or p:SteamID64()~="76561198011536179"then return end
 local result=util.JSONToTable(net.ReadString());if istable(result)then file.Write("zc_chat_groups_ui_probe.json",util.TableToJSON(result,true))end
end)
local client=[=[
 local c=hg and hg.chat;local G=ZCChatGroupUI
 local r={valid=IsValid(c),build=ZCChatBuild,groupsVersion=G and G.Version}
 if IsValid(c)then
  r.groupsButton=IsValid(c.ZCGroupsButton);r.input=IsValid(c.entry);r.directory=IsValid(c.ZCDirectory);r.active=c:GetActive();r.groupThread=G and G.IsGroup(c.ZCThreadKey) or false
  local meta=G and G.meta[c.ZCThreadKey];r.readOnly=meta and meta.peek or false;r.threadCount=table.Count(c.ZCThreads or {});r.staff=G and G.staff or false
 end
 net.Start("ZCGroupUIProbe");net.WriteString(util.TableToJSON(r));net.SendToServer()
]=]
for _,p in ipairs(player.GetHumans())do if p:SteamID64()=="76561198011536179"then p:SendLua(client)end end
