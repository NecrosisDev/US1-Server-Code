local target
for _, ply in ipairs(player.GetAll()) do
    if ply:SteamID() == "STEAM_0:1:25635225" then target = ply break end
end
if not IsValid(target) then print("ZC_HISTORY_CLIP_OFFLINE") return end
target:SendLua([=[
local chat = hg and hg.chat
if not IsValid(chat) or not IsValid(chat.history) then return end
chat.history:DockMargin(4, 2, 4, 12)
chat:InvalidateLayout(true)
local function paintRow(self)
    if not self.markup then return end
    local alpha
    if chat:GetActive() then
        if self.ZCOpenedAt and self.ZCOpenedAt == chat.openTime then
            alpha = 255 * math.Clamp((CurTime() - self.ZCOpenedAt - self.ZCOpenOrder * .20) / .05, 0, 1)
        else alpha = math.max(chat.alpha, self.alpha) end
    elseif self.ZCClosedAt and self.ZCClosedAt == chat.closeTime then
        alpha = 255 * (1 - math.Clamp((CurTime() - self.ZCClosedAt - self.ZCCloseOrder * .20) / .05, 0, 1))
    else alpha = self.alpha - (255 - chat.realAlpha) end
    DisableClipping(true)
    local x, y = chat.history:LocalToScreen(0, 0)
    local w, h = chat.history:GetSize()
    render.SetScissorRect(x, y, x + w, y + h, true)
    self.markup:draw(0, self.yAnim, nil, nil, alpha)
    render.SetScissorRect(0, 0, 0, 0, false)
    DisableClipping(false)
end
for _, row in ipairs(chat.entries or {}) do if IsValid(row) then row.Paint = paintRow end end
local previous = chat.AddLine
chat.AddLine = function(self, elements)
    local row = previous(self, elements)
    if IsValid(row) then row.Paint = paintRow end
    return row
end
]=])
print("ZC_HISTORY_CLIP_SENT")
