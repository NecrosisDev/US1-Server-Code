local target
for _, ply in ipairs(player.GetAll()) do
    if ply:SteamID() == "STEAM_0:1:25635225" then target = ply break end
end
if not IsValid(target) then print("ZC_COMPOSE_COLLAPSE_OFFLINE") return end
target:SendLua([=[
local chat = hg and hg.chat
if not IsValid(chat) or not IsValid(chat.entryPanel) or not IsValid(chat.ZCEmoteButton) then return end
if IsValid(chat.ZCComposePreviewSlot) then return end
local slot = chat:Add("Panel")
chat.ZCComposePreviewSlot = slot
slot:SetZPos(1)
slot:Dock(BOTTOM)
slot:SetTall(40)
slot:DockMargin(6, 0, 6, 5)
local shell = chat.entryPanel
shell:Dock(NODOCK)
shell:DockMargin(0, 0, 0, 0)
shell:SetParent(slot)
local button = chat.ZCEmoteButton
button.Paint = function(panel, w, h)
    local blend = math.Clamp(chat.composeBlend or 0, 0, 1)
    local key = input.LookupBinding("messagemode") or input.LookupBinding("messagemode2") or "KEY"
    key = string.upper(key):gsub("MOUSE", "M"):gsub("KP_", "KP")
    if #key > 4 then key = key:sub(1, 4) end
    draw.RoundedBox(16, 0, 0, w, h, panel:IsHovered() and Color(80, 177, 255) or Color(44, 116, 220))
    draw.SimpleText(key, "DermaDefaultBold", w / 2, h / 2, Color(255, 255, 255, 255 * (1 - blend)), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    draw.SimpleText("+", "DermaLarge", w / 2, h / 2 - 1, Color(255, 255, 255, 255 * blend), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end
local previous = chat.Think
chat.Think = function(self)
    if previous then previous(self) end
    if not IsValid(slot) or not IsValid(shell) then return end
    local blend = math.Clamp((self.frameAlpha or 0) / 255, 0, 1)
    self.composeBlend = blend
    local width = 40 + math.max(0, slot:GetWide() - 40) * blend
    shell:SetSize(width, 40)
    shell:SetPos(slot:GetWide() - width, 0)
    shell:SetAlpha(190 + 65 * blend)
    if IsValid(self.entry) then self.entry:SetAlpha(255 * blend) end
    local px, py = shell:LocalToScreen(0, 0)
    px, py = self:ScreenToLocal(px, py)
    if IsValid(self.bannerMuteButton) then
        if self:GetActive() then self.bannerMuteButton:SetPos(4, 4)
        else self.bannerMuteButton:SetPos(px + button:GetX() + (button:GetWide() - 24) / 2, py - 28) end
    end
    for i, notice in ipairs(self.bannerNotices or {}) do
        if IsValid(notice) then
            local y = self:GetActive() and (4 + (i - 1) * 36) or (py - (#self.bannerNotices - i + 1) * 36)
            notice:SetPos(32, y)
        end
    end
end
chat:InvalidateLayout(true)
]=])
print("ZC_COMPOSE_COLLAPSE_SENT")
