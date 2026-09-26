local target
for _, ply in ipairs(player.GetAll()) do
    if ply:SteamID() == "STEAM_0:1:25635225" then target = ply break end
end
if not IsValid(target) then print("ZC_SYSTEM_BANNER_OFFLINE") return end
target:SendLua([=[
local chat = hg and hg.chat
if not IsValid(chat) then return end
chat.bannerMuted = cookie.GetNumber("zchat_mute_banners", 0) == 1
chat.bannerNotices = chat.bannerNotices or {}
if not IsValid(chat.bannerMuteButton) then
    local button = chat:Add("DButton")
    chat.bannerMuteButton = button
    button:SetPos(4, 4); button:SetSize(24, 24); button:SetText("")
    button:SetTooltip("Mute system banners")
    button.Paint = function(_, w, h)
        local alpha = chat:GetActive() and 220 or 80
        draw.RoundedBox(6, 0, 0, w, h, Color(38, 45, 56, alpha))
        draw.SimpleText("!", "DermaDefaultBold", w / 2, h / 2, Color(220, 229, 240, alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        if chat.bannerMuted then
            surface.SetDrawColor(255, 105, 105, alpha); surface.DrawLine(5, 19, 19, 5)
        end
    end
    button.DoClick = function()
        chat.bannerMuted = not chat.bannerMuted
        cookie.Set("zchat_mute_banners", chat.bannerMuted and "1" or "0")
        button:SetTooltip(chat.bannerMuted and "Unmute system banners" or "Mute system banners")
        if chat.bannerMuted then
            for _, notice in ipairs(chat.bannerNotices) do if IsValid(notice) then notice:Remove() end end
            chat.bannerNotices = {}
        end
    end
end
chat.ShowSystemBanner = function(self, elements)
    if self.bannerMuted then return end
    local parts = {}
    for _, value in ipairs(elements) do
        if isstring(value) or isnumber(value) then parts[#parts + 1] = tostring(value) end
    end
    local message = string.Trim(table.concat(parts))
    if message == "" then return end
    while #self.bannerNotices >= 3 do
        local old = table.remove(self.bannerNotices, 1)
        if IsValid(old) then old:Remove() end
    end
    local banner = self:Add("DPanel")
    self.bannerNotices[#self.bannerNotices + 1] = banner
    banner:SetMouseInputEnabled(false)
    banner:SetSize(math.max(120, self:GetWide() - 64), 32)
    banner:SetPos(32, 4 + (#self.bannerNotices - 1) * 36)
    banner:MoveToFront(); self.bannerMuteButton:MoveToFront()
    local started = CurTime()
    banner.Paint = function(panel, w, h)
        local elapsed = CurTime() - started
        local alpha = 255 * math.min(math.Clamp(elapsed / .18, 0, 1), math.Clamp((3.5 - elapsed) / .25, 0, 1))
        draw.RoundedBox(8, 0, 0, w, h, Color(35, 43, 54, alpha * .96))
        draw.SimpleText(string.sub(message, 1, 180), "DermaDefaultBold", 12, h / 2, Color(235, 241, 250, alpha), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    banner.Think = function(panel)
        panel:SetSize(math.max(120, self:GetWide() - 64), 32)
        if CurTime() - started < 3.5 then return end
        panel:Remove()
        for i, notice in ipairs(self.bannerNotices) do if notice == panel then table.remove(self.bannerNotices, i) break end end
        for i, notice in ipairs(self.bannerNotices) do if IsValid(notice) then notice:SetY(4 + (i - 1) * 36) end end
    end
end
local previous = chat.AddLine
chat.AddLine = function(self, elements)
    local speaker = IsValid(CHAT_SPEAKER) and CHAT_SPEAKER or nil
    if not speaker then
        for _, value in ipairs(elements) do
            if type(value) == "Player" and IsValid(value) then speaker = value break end
        end
    end
    if not speaker and not CHAT_IS_BOT then self:ShowSystemBanner(elements); return end
    return previous(self, elements)
end
chat:AddMessage("System banner preview")
]=])
print("ZC_SYSTEM_BANNER_SENT")
