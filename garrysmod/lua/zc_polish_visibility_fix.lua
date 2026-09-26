for _, ply in ipairs(player.GetHumans()) do
    if ply:SteamID() == "STEAM_0:1:25635225" then
        ply:SendLua([=[
local c=hg and hg.chat
if IsValid(c) and IsValid(c.mediaVisibilityButton) and not c.ZCMediaVisibilityFix then
 c.ZCMediaVisibilityFix=true
 local think=c.Think
 c.Think=function(self)
  think(self)
  if IsValid(self.mediaVisibilityButton) then self.mediaVisibilityButton:SetVisible(self:GetActive() and self.phonePage=="chat") end
 end
 c.mediaVisibilityButton:SetVisible(c:GetActive() and c.phonePage=="chat")
end
]=])
    end
end
