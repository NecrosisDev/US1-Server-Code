util.AddNetworkString("ZCPolishUIProbe")
net.Receive("ZCPolishUIProbe", function(length, ply)
    if length > 8192 or ply:SteamID() ~= "STEAM_0:1:25635225" then return end
    print("ZC_POLISH_UI_STATE", net.ReadString():sub(1, 1000))
end)
for _, ply in ipairs(player.GetHumans()) do
    if ply:SteamID() == "STEAM_0:1:25635225" then
        ply:SendLua([=[
local c=hg and hg.chat
local function probe()
 local r={build=ZCChatBuild,media=ZCChatMedia and ZCChatMedia.Version,active=IsValid(c) and c:GetActive(),page=IsValid(c) and c.phonePage}
 if IsValid(c) then
  r.width,r.height=c:GetSize()
  for _,k in ipairs({"phoneBar","mediaVisibilityButton","bannerMuteButton"}) do
   local p=c[k] local v={valid=IsValid(p)} r[k]=v
   if IsValid(p) then v.visible=p:IsVisible() v.x,v.y=p:GetPos() v.w,v.h=p:GetSize() v.alpha=p:GetAlpha() end
  end
 end
 net.Start("ZCPolishUIProbe") net.WriteString(util.TableToJSON(r)) net.SendToServer()
end
probe()
timer.Create("ZCPolishUIProbeOpen",0.5,40,function()
 if IsValid(c) and c:GetActive() and c.phonePage=="chat" then timer.Remove("ZCPolishUIProbeOpen") probe() end
end)
]=])
    end
end
