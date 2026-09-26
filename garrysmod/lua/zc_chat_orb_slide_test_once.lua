local target
for _, ply in ipairs(player.GetAll()) do
    if ply:SteamID() == "STEAM_0:1:25635225" then target = ply break end
end
if not IsValid(target) then print("ZC_ORB_SLIDE_OFFLINE") return end
target:SendLua([=[
local chat = hg and hg.chat
if not IsValid(chat) or not IsValid(chat.ZCComposePreviewSlot) then return end
local slot = chat.ZCComposePreviewSlot
local shell = chat.entryPanel
local button = chat.ZCEmoteButton
local orb = slot:Add("DPanel")
chat.ZCKeyOrbPreview = orb
orb:SetSize(40, 40)
orb:SetMouseInputEnabled(false)
orb.Paint = function(_, w, h)
    local key = input.LookupBinding("messagemode") or input.LookupBinding("messagemode2") or "KEY"
    key = string.upper(key):gsub("MOUSE", "M"):gsub("KP_", "KP")
    if #key > 4 then key = key:sub(1, 4) end
    draw.RoundedBox(20, 0, 0, w, h, Color(44, 116, 220, 230))
    draw.SimpleText(key, "DermaDefaultBold", w / 2, h / 2, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end
button.Paint = function(panel, w, h)
    draw.RoundedBox(16, 0, 0, w, h, panel:IsHovered() and Color(80, 177, 255) or Color(44, 116, 220))
    draw.SimpleText("+", "DermaLarge", w / 2, h / 2 - 1, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end
local oldSetActive = chat.SetActive
chat.SetActive = function(self, active, ...)
    if active then shell:SetVisible(true) end
    return oldSetActive(self, active, ...)
end
local previous = chat.Think
chat.Think = function(self)
    if previous then previous(self) end
    if not IsValid(slot) or not IsValid(shell) or not IsValid(orb) then return end
    local blend = math.Clamp((self.frameAlpha or 0) / 255, 0, 1)
    self.composeBlend = blend
    local width = math.max(1, (slot:GetWide() - 44) * blend)
    shell:SetSize(width, 40)
    shell:SetPos(slot:GetWide() - width, 0)
    shell:SetAlpha(255 * blend)
    shell:SetVisible(blend > .01 or self:GetActive())
    if IsValid(self.entry) then self.entry:SetAlpha(255) end
    orb:SetPos(math.max(0, slot:GetWide() - 40) * (1 - blend), 0)
    local x, y = orb:LocalToScreen(0, 0)
    x, y = self:ScreenToLocal(x, y)
    if IsValid(self.bannerMuteButton) then
        if self:GetActive() then self.bannerMuteButton:SetPos(4, 4)
        else self.bannerMuteButton:SetPos(x + 8, y - 28) end
    end
end
]=])
print("ZC_ORB_SLIDE_SENT")
