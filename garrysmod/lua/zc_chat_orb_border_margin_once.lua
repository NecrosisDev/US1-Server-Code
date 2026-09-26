for _, ply in ipairs(player.GetAll()) do
    if ply:SteamID() == "STEAM_0:1:25635225" then
        ply:SendLua([=[
local chat = hg and hg.chat
if IsValid(chat) and IsValid(chat.ZCComposePreviewSlot) then
    chat.ZCComposePreviewSlot:DockMargin(0, 0, 6, 5)
    chat:InvalidateLayout(true)
end
]=])
        break
    end
end
print("ZC_ORB_BORDER_MARGIN_SENT")
