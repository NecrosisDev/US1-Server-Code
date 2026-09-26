local target
for _, ply in ipairs(player.GetAll()) do
    if ply:SteamID() == "STEAM_0:1:25635225" then target = ply break end
end
if not IsValid(target) then print("ZC_CHAT_TYPE_AVATAR_OFFLINE") return end
target:SendLua([=[
local chat = hg and hg.chat
if not IsValid(chat) then return end
local function enhance(row, elements)
    local speaker = IsValid(CHAT_SPEAKER) and CHAT_SPEAKER or nil
    if not speaker then
        for _, value in ipairs(elements) do
            if type(value) == "Player" and IsValid(value) then speaker = value break end
        end
    end
    if speaker then
        row.ZCLeftInset = 20
        row.ZCAvatar = row:Add("AvatarImage")
        row.ZCAvatar:SetPos(0, 0)
        row.ZCAvatar:SetSize(16, 16)
        row.ZCAvatar:SetPlayer(speaker, 16)
        row.ZCAvatar:SetMouseInputEnabled(false)
    end
    row.ZCTypewriterStart = CurTime()
    local function buildMarkup(self, width)
        self.markup = hg.markup.Parse(self.text, math.max(1, width - (self.ZCLeftInset or 0)))
        local count = 0
        for _, block in ipairs(self.markup.blocks) do
            if block.text then
                block.ZCRevealBefore = count
                count = count + string.utf8len(block.text)
            end
        end
        self.ZCTypewriterRate = math.max(45, count / 1.5)
        self.markup.onDrawText = function(text, font, x, y, color, alignX, alignY, alpha, block)
            local shown = math.floor((CurTime() - self.ZCTypewriterStart) * self.ZCTypewriterRate)
            local available = shown - block.ZCRevealBefore
            if available <= 0 then return end
            if available < string.utf8len(text) then text = string.utf8sub(text, 1, available) end
            alpha = alpha or 255
            surface.SetTextPos(x + 1, y + 1)
            surface.SetTextColor(0, 0, 0, alpha)
            surface.SetFont(font)
            surface.DrawText(text)
            surface.SetTextPos(x, y)
            surface.SetTextColor(color.r, color.g, color.b, alpha)
            surface.SetFont(font)
            surface.DrawText(text)
        end
    end
    row.BuildMarkup = buildMarkup
    row:BuildMarkup(row:GetWide())
    row:SetTall(row.markup:GetHeight())
    ZCChatMedia.Layout(row)
    row.PerformLayout = function(self, width, height)
        self:BuildMarkup(width)
        self:SetTall(self.markup:GetHeight())
        ZCChatMedia.Layout(self)
    end
    row.Paint = function(self, width, height)
        if not self.markup then return end
        local newAlpha
        if chat:GetActive() then
            if self.ZCOpenedAt and self.ZCOpenedAt == chat.openTime then
                local elapsed = CurTime() - self.ZCOpenedAt
                newAlpha = 255 * math.Clamp((elapsed - self.ZCOpenOrder * 0.20) / 0.05, 0, 1)
            else
                newAlpha = math.max(chat.alpha, self.alpha)
            end
        elseif self.ZCClosedAt and self.ZCClosedAt == chat.closeTime then
            local elapsed = CurTime() - self.ZCClosedAt
            local start = self.ZCCloseOrder * 0.20
            newAlpha = 255 * (1 - math.Clamp((elapsed - start) / 0.05, 0, 1))
        else
            newAlpha = self.alpha - (255 - chat.realAlpha)
        end
        DisableClipping(true)
        local x, y = chat:GetPos()
        local wide, tall = chat:GetSize()
        render.SetScissorRect(x, y, x + wide, y + tall, true)
        self.markup:draw(self.ZCLeftInset or 0, self.yAnim, nil, nil, newAlpha)
        render.SetScissorRect(0, 0, 0, 0, false)
        DisableClipping(false)
        if IsValid(self.ZCAvatar) then self.ZCAvatar:SetAlpha(math.Clamp(newAlpha, 0, 255)) end
    end
end
local oldAddLine = chat.AddLine
chat.AddLine = function(self, elements)
    local row = oldAddLine(self, elements)
    if IsValid(row) then enhance(row, elements) end
    return row
end
]=])
print("ZC_CHAT_TYPE_AVATAR_SENT")
