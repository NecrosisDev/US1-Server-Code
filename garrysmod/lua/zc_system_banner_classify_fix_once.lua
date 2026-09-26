local target
for _, ply in ipairs(player.GetAll()) do
    if ply:SteamID() == "STEAM_0:1:25635225" then target = ply break end
end
if not IsValid(target) then print("ZC_BANNER_CLASSIFY_OFFLINE") return end
target:SendLua([=[
local chat = hg and hg.chat
if not IsValid(chat) or not chat.ShowSystemBanner then return end
local previous = chat.AddLine
chat.AddLine = function(self, elements)
    if not (IsValid(CHAT_SPEAKER) and CHAT_SPEAKER:IsPlayer()) and not CHAT_IS_BOT then
        self:ShowSystemBanner(elements)
        return
    end
    return previous(self, elements)
end
]=])
print("ZC_BANNER_CLASSIFY_SENT")
