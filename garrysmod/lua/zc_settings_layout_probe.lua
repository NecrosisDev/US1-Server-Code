util.AddNetworkString("ZCSettingsLayoutProbe")
net.Receive("ZCSettingsLayoutProbe",function(bits,p)
 if bits>50000 or p:SteamID64()~="76561198011536179" then return end
 local r=util.JSONToTable(net.ReadString());if not istable(r)then return end
 file.Write("zc_settings_layout_probe.json",util.TableToJSON(r,true))
end)
local client=[=[
local c=hg and hg.chat
local r={build=ZCChatBuild,page=IsValid(c) and c.phonePage,panels={}}
local function walk(p,depth)
 if not IsValid(p) or depth>4 or #r.panels>70 then return end
 local x,y=p:GetPos();local row={class=p:GetClassName(),x=x,y=y,w=p:GetWide(),h=p:GetTall(),visible=p:IsVisible(),children=#p:GetChildren(),depth=depth}
 if p.GetCanvas and IsValid(p:GetCanvas())then
  row.canvasH=p:GetCanvas():GetTall();row.canvasChildren=#p:GetCanvas():GetChildren()
  local info=debug.getinfo(p.Rebuild,'S');row.rebuild=info and info.short_src;row.rebuildLine=info and info.linedefined
 end
 r.panels[#r.panels+1]=row
 for _,ch in ipairs(p:GetChildren())do walk(ch,depth+1)end
end
if IsValid(c)then walk(c.appHost,0)end
net.Start("ZCSettingsLayoutProbe");net.WriteString(util.TableToJSON(r));net.SendToServer()
]=]
local online=false
for _,p in ipairs(player.GetHumans())do if p:SteamID64()=="76561198011536179"then online=true;p:SendLua(client)end end
file.Write("zc_settings_probe_online.json",util.TableToJSON({sir=online,humans=#player.GetHumans()}))
