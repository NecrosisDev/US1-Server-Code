util.AddNetworkString("ZCScoreboardLayoutAudit")
net.Receive("ZCScoreboardLayoutAudit",function(bits,p)
 if bits>16384 or p:SteamID64()~="76561198011536179"then return end
 local result=util.JSONToTable(net.ReadString());if not istable(result)then return end
 file.Write("zc_scoreboard_layout_audit.json",util.TableToJSON({at=os.time(),result=result},true))
end)
local code=[=[
local count=0
timer.Create("ZCScoreboard.LayoutAudit",.5,90,function()
 count=count+1
 local S=ZCScoreboard;local f=S and S.Frame
 if not IsValid(f)or not f:IsVisible()then return end
 local out={version=S.Version,screen={ScrW(),ScrH()},frame={f:GetWide(),f:GetTall()},list={f.List:GetWide(),f.List:GetTall()},rows=table.Count(f.Rows),samples={}}
 for p,row in pairs(f.Rows)do
  local x,y=row.Name:GetPos();local kx,ky=row.Stats[1].value:GetPos()
  out.samples[#out.samples+1]={w=row:GetWide(),h=row:GetTall(),nameRight=x+row.Name:GetWide(),karmaX=kx,overlap=x+row.Name:GetWide()>kx,voice=row.Voice:IsVisible()}
  if #out.samples>=3 then break end
 end
 net.Start("ZCScoreboardLayoutAudit");net.WriteString(util.TableToJSON(out));net.SendToServer()
 timer.Remove("ZCScoreboard.LayoutAudit")
end)
]=]
for _,p in ipairs(player.GetHumans())do if p:SteamID64()=="76561198011536179"then p:SendLua(code)end end
