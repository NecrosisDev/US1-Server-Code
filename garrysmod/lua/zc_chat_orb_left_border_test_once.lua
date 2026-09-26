local target
for _, ply in ipairs(player.GetAll()) do
    if ply:SteamID() == "STEAM_0:1:25635225" then target = ply break end
end
if not IsValid(target) then print("ZC_ORB_LEFT_OFFLINE") return end
target:SendLua([=[
local chat = hg and hg.chat
if not IsValid(chat) or not IsValid(chat.ZCComposePreviewSlot) or not IsValid(chat.ZCKeyOrbPreview) then return end
local slot = chat.ZCComposePreviewSlot
local orb = chat.ZCKeyOrbPreview
local shell = chat.entryPanel
local previous = chat.Think
chat.Think = function(self)
    if previous then previous(self) end
    if not IsValid(slot) or not IsValid(orb) or not IsValid(shell) then return end
    local blend = math.Clamp((self.frameAlpha or 0) / 255, 0, 1)
    local width = math.max(1, (slot:GetWide() - 84) * blend)
    shell:SetSize(width, 40)
    shell:SetPos(slot:GetWide() - width, 0)
    orb:SetPos(40 * blend, 0)
    local x, y = orb:LocalToScreen(0, 0)
    x, y = self:ScreenToLocal(x, y)
    if IsValid(self.bannerMuteButton) and not self:GetActive() then
        self.bannerMuteButton:SetPos(x + 8, y - 28)
    end
end
]=])
print("ZC_ORB_LEFT_SENT")
