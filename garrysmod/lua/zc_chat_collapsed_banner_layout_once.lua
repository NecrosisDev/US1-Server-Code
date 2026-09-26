local target
for _, ply in ipairs(player.GetAll()) do
    if ply:SteamID() == "STEAM_0:1:25635225" then target = ply break end
end
if not IsValid(target) then print("ZC_COLLAPSED_BANNER_OFFLINE") return end
target:SendLua([=[
local chat = hg and hg.chat
if not IsValid(chat) or not IsValid(chat.bannerMuteButton) then return end
local previous = chat.Think
chat.Think = function(self)
    if previous then previous(self) end
    if not IsValid(self.entryPanel) or not IsValid(self.bannerMuteButton) then return end
    if self:GetActive() then
        self.bannerMuteButton:SetPos(4, 4)
    else
        local plus = self.ZCEmoteButton
        local x = IsValid(plus) and (self.entryPanel:GetX() + plus:GetX() + (plus:GetWide() - 24) / 2)
            or (self:GetWide() - 38)
        self.bannerMuteButton:SetPos(x, self.entryPanel:GetY() - 28)
    end
    for i, notice in ipairs(self.bannerNotices or {}) do
        if IsValid(notice) then
            notice:SetSize(math.max(120, self:GetWide() - 64), 32)
            local y = self:GetActive() and (4 + (i - 1) * 36)
                or (self.entryPanel:GetY() - (#self.bannerNotices - i + 1) * 36)
            notice:SetPos(32, y)
        end
    end
end
]=])
print("ZC_COLLAPSED_BANNER_SENT")
