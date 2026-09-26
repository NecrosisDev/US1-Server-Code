local target
for _, ply in ipairs(player.GetAll()) do
    if ply:SteamID() == "STEAM_0:1:25635225" then target = ply break end
end
if not IsValid(target) then print("ZC_WRAPPED_BANNER_OFFLINE") return end
target:SendLua([=[
local chat = hg and hg.chat
if not IsValid(chat) or not IsValid(chat.ZCKeyOrbPreview) then return end
local function wrap(message, maxWidth)
    surface.SetFont("DermaDefaultBold")
    local lines, current = {}, ""
    for word in tostring(message):gsub("[\r\n]", " "):gmatch("%S+") do
        local nextLine = current == "" and word or current .. " " .. word
        if current ~= "" and surface.GetTextSize(nextLine) > maxWidth then
            lines[#lines + 1] = current; current = word
        else current = nextLine end
    end
    if current ~= "" then lines[#lines + 1] = current end
    if #lines == 0 then lines[1] = "" end
    while #lines > 4 do table.remove(lines) end
    return lines
end
chat.ShowSystemBanner = function(self, elements)
    if self.bannerMuted then return end
    local parts = {}
    for _, value in ipairs(elements) do
        if isstring(value) or isnumber(value) then parts[#parts + 1] = tostring(value) end
        if type(value) == "Player" and IsValid(value) then parts[#parts + 1] = value:Nick() end
    end
    local message = string.Trim(table.concat(parts))
    if message == "" then return end
    while #self.bannerNotices >= 3 do
        local old = table.remove(self.bannerNotices, 1)
        if IsValid(old) then old:Remove() end
    end
    local card = self:Add("DPanel")
    self.bannerNotices[#self.bannerNotices + 1] = card
    card:SetMouseInputEnabled(false)
    local width = math.max(120, self:GetWide() - 64)
    card.ZCLines = wrap(message, width - 24)
    card:SetSize(width, math.max(32, #card.ZCLines * 16 + 14))
    card:MoveToFront(); self.bannerMuteButton:MoveToFront()
    local started = CurTime()
    card.Paint = function(panel, w, h)
        local elapsed = CurTime() - started
        local alpha = 255 * math.min(math.Clamp(elapsed / .18, 0, 1), math.Clamp((6 - elapsed) / .25, 0, 1))
        draw.RoundedBox(8, 0, 0, w, h, Color(35, 43, 54, alpha * .96))
        for i, line in ipairs(panel.ZCLines) do
            draw.SimpleText(line, "DermaDefaultBold", 12, 7 + (i - 1) * 16, Color(235, 241, 250, alpha), TEXT_ALIGN_LEFT)
        end
    end
    card.Think = function(panel)
        if CurTime() - started < 6 then return end
        panel:Remove()
        for i, notice in ipairs(self.bannerNotices) do if notice == panel then table.remove(self.bannerNotices, i) break end end
    end
end
local previous = chat.Think
chat.Think = function(self)
    if previous then previous(self) end
    local orb = self.ZCKeyOrbPreview
    if not IsValid(orb) then return end
    local _, bottom = orb:LocalToScreen(0, 0)
    _, bottom = self:ScreenToLocal(0, bottom)
    bottom = bottom - 4
    local top = 4
    for i, notice in ipairs(self.bannerNotices or {}) do
        if IsValid(notice) and self:GetActive() then
            notice:SetPos(32, top); top = top + notice:GetTall() + 4
        end
    end
    if not self:GetActive() then
        for i = #(self.bannerNotices or {}), 1, -1 do
            local notice = self.bannerNotices[i]
            if IsValid(notice) then bottom = bottom - notice:GetTall(); notice:SetPos(32, bottom); bottom = bottom - 4 end
        end
    end
end
chat:AddMessage("Server notice: This is a longer system notification preview to confirm that text wraps onto another line above the collapsed chat input without overlapping the key orb or mute control.")
]=])
print("ZC_WRAPPED_BANNER_SENT")
