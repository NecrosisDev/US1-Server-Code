local target
for _, ply in ipairs(player.GetAll()) do if ply:SteamID()=="STEAM_0:1:25635225" then target=ply break end end
if not IsValid(target) then print("ZC_CHAT_PREVIEW_OFFLINE") return end
util.AddNetworkString("ZCChatPreview")
util.AddNetworkString("ZCChatPreviewAck")
net.Receive("ZCChatPreviewAck",function(_,ply)
 if ply:SteamID()~="STEAM_0:1:25635225" then return end
 ply.ZCChatPreviewApplied=true
 print("ZC_CHAT_PREVIEW_ACK "..ply:Nick())
end)
local bootstrap=[=[
ZCP={p={},n={}}
net.Receive("ZCChatPreview",function()
 local name=net.ReadString() local i=net.ReadUInt(12) local n=net.ReadUInt(12) local len=net.ReadUInt(16) local data=net.ReadData(len)
 local p=ZCP if not p then return end p.p[name]=p.p[name] or {} p.p[name][i]=data p.n[name]=n
 for _,v in ipairs({"client.lua","cl_zchat.lua","sh_chat.lua","cl_ulx_lib.lua"}) do if not p.n[v] then return end for j=1,p.n[v] do if not p.p[v][j] then return end end end
 local old=hg and hg.chat local saved=IsValid(old) and old.messageHistory or {} if IsValid(old) then old:Remove() end
 for _,v in ipairs({"client.lua","cl_zchat.lua","sh_chat.lua","cl_ulx_lib.lua"}) do local src=util.Decompress(table.concat(p.p[v])) local f=src and CompileString(src,"ZCP_"..v,false) if type(f)~="function" then ErrorNoHalt("ZCP compile "..v.." "..tostring(f).."\n") return end local ok,err=pcall(f) if not ok then ErrorNoHalt("ZCP run "..v.." "..tostring(err).."\n") return end end
 hg.chat=vgui.Create("zChatbox") if IsValid(hg.chat) then hg.chat.messageHistory=saved end
 print("ZC_CHAT_PREVIEW_APPLIED_20260922_2") ZCP=nil
 net.Start("ZCChatPreviewAck") net.SendToServer()
end)
]=]
target:SendLua(bootstrap)
timer.Simple(1,function()
 if not IsValid(target) then return end
 for _,name in ipairs({"client.lua","cl_zchat.lua","sh_chat.lua","cl_ulx_lib.lua"}) do
  local source=file.Read("zc_chat_preview/"..name,"LUA")
  if not source then print("ZC_CHAT_PREVIEW_MISSING "..name) return end
  local packed=util.Compress(source)
  local count=math.ceil(#packed/28000)
  for i=1,count do
   local chunk=packed:sub((i-1)*28000+1,i*28000)
   net.Start("ZCChatPreview") net.WriteString(name) net.WriteUInt(i,12) net.WriteUInt(count,12) net.WriteUInt(#chunk,16) net.WriteData(chunk,#chunk) net.Send(target)
  end
 end
 print("ZC_CHAT_PREVIEW_NET_SENT "..target:Nick())
end)

