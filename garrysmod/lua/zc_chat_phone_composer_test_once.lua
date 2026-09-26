local target
for _, ply in ipairs(player.GetAll()) do
    if ply:SteamID() == "STEAM_0:1:25635225" then target = ply break end
end
if not IsValid(target) then print("ZC_PHONE_COMPOSER_OFFLINE") return end
target:SendLua([=[
local chat = hg and hg.chat
if not IsValid(chat) or not IsValid(chat.entryPanel) or not IsValid(chat.entry) then return end
local shell = chat.entryPanel
shell:SetTall(40)
shell:DockMargin(6, 0, 6, 5)
shell.Paint = function(panel, w, h)
    local focused = IsValid(chat.entry) and chat.entry:HasFocus()
    draw.RoundedBox(18, 0, 0, w, h, focused and Color(67, 165, 255) or Color(67, 74, 86, 230))
    draw.RoundedBox(17, 1, 1, w - 2, h - 2, Color(26, 29, 35, 245))
end
chat.entry:DockMargin(12, 5, 4, 5)
chat.entry:SetPlaceholderText("Message")
chat.entry.Paint = function(self, w, h)
    self:DrawTextEntryText(color_white, Color(67, 165, 255), color_white)
end
local button = chat.ZCEmoteButton
if IsValid(button) then
    button:SetWide(32)
    button:DockMargin(0, 4, 4, 4)
    button:SetText("")
    button.Paint = function(panel, w, h)
        draw.RoundedBox(16, 0, 0, w, h, panel:IsHovered() and Color(80, 177, 255) or Color(44, 116, 220))
        draw.SimpleText("+", "DermaLarge", w / 2, h / 2 - 1, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
end
shell:InvalidateLayout(true)
]=])
print("ZC_PHONE_COMPOSER_SENT")
