local target
for _, ply in ipairs(player.GetAll()) do
    if ply:SteamID() == "STEAM_0:1:25635225" then target = ply break end
end
if not IsValid(target) then print("ZC_BUBBLE_AVATAR_OFFLINE") return end
target:SendLua([=[
local chat = hg and hg.chat
if not IsValid(chat) then return end
local previous = chat.AddLine
chat.AddLine = function(self, elements)
    local row = previous(self, elements)
    if not IsValid(row) then return row end
    local speaker = IsValid(CHAT_SPEAKER) and CHAT_SPEAKER or nil
    if not speaker then
        for _, value in ipairs(elements) do
            if type(value) == "Player" and IsValid(value) then speaker = value break end
        end
    end
    if not speaker then return row end
    row.ZCBubble = true
    row.ZCOwn = speaker == LocalPlayer()
    row.ZCBot = speaker:IsBot()
    row.ZCLeftInset = 36
    if not IsValid(row.ZCAvatar) then
        row.ZCAvatar = row:Add("AvatarImage")
        row.ZCAvatar:SetMouseInputEnabled(false)
    end
    row.ZCAvatar:SetSize(28, 28)
    row.ZCAvatar:SetPlayer(speaker, 28)
    row.BuildMarkup = function(self, width)
        local bubbleMax = math.min(width * 0.72, 560)
        self.markup = hg.markup.Parse(self.text, math.max(1, bubbleMax - 48))
        self.ZCBubbleWidth = math.min(bubbleMax, self.markup:GetWidth() + 48)
        self.ZCBubbleX = self.ZCOwn and math.max(0, width - self.ZCBubbleWidth - 4) or 0
        self.ZCTextX = self.ZCBubbleX + 40
        self.ZCBubbleBodyHeight = math.max(36, self.markup:GetHeight() + 8)
        self.ZCBaseHeight = self.ZCBubbleBodyHeight
        self.ZCAvatar:SetPos(self.ZCBubbleX + 4, 4)
        local count = 0
        for _, block in ipairs(self.markup.blocks) do
            if block.text then block.ZCRevealBefore = count; count = count + string.utf8len(block.text) end
        end
        self.ZCTypewriterRate = math.max(45, count / 1.5)
        self.markup.onDrawText = function(text, font, x, y, color, alignX, alignY, alpha, block)
            local shown = math.floor((CurTime() - (self.ZCTypewriterStart or 0)) * self.ZCTypewriterRate)
            local available = shown - block.ZCRevealBefore
            if available <= 0 then return end
            if available < string.utf8len(text) then text = string.utf8sub(text, 1, available) end
            alpha = alpha or 255
            surface.SetFont(font); surface.SetTextPos(x + 1, y + 1); surface.SetTextColor(0, 0, 0, alpha); surface.DrawText(text)
            surface.SetTextPos(x, y); surface.SetTextColor(color.r, color.g, color.b, alpha); surface.DrawText(text)
        end
    end
    row.PerformLayout = function(self, width)
        self:BuildMarkup(width)
        self:SetTall(self.ZCBaseHeight)
        ZCChatMedia.Layout(self)
    end
    row.Paint = function(self)
        local alpha
        if chat:GetActive() then
            if self.ZCOpenedAt == chat.openTime then
                alpha = 255 * math.Clamp((CurTime() - self.ZCOpenedAt - self.ZCOpenOrder * .20) / .05, 0, 1)
            else alpha = math.max(chat.alpha, self.alpha) end
        elseif self.ZCClosedAt == chat.closeTime then
            alpha = 255 * (1 - math.Clamp((CurTime() - self.ZCClosedAt - self.ZCCloseOrder * .20) / .05, 0, 1))
        else alpha = self.alpha - (255 - chat.realAlpha) end
        DisableClipping(true)
        local x, y = chat:GetPos(); local w, h = chat:GetSize()
        render.SetScissorRect(x, y, x + w, y + h, true)
        local shade = self.ZCOwn and Color(44, 116, 220, math.Clamp(alpha * .9, 0, 255))
            or (self.ZCBot and Color(76, 61, 109, math.Clamp(alpha * .9, 0, 255))
            or Color(46, 50, 59, math.Clamp(alpha * .9, 0, 255)))
        draw.RoundedBox(10, self.ZCBubbleX, 0, self.ZCBubbleWidth, self.ZCBubbleBodyHeight, shade)
        self.markup:draw(self.ZCTextX, self.yAnim + 4, nil, nil, alpha)
        render.SetScissorRect(0, 0, 0, 0, false)
        DisableClipping(false)
        self.ZCAvatar:SetAlpha(math.Clamp(alpha, 0, 255))
    end
    row:BuildMarkup(row:GetWide())
    row:SetTall(row.ZCBaseHeight)
    ZCChatMedia.Layout(row)
    row:InvalidateParent(true)
    return row
end
]=])
print("ZC_BUBBLE_AVATAR_SENT")
