util.AddNetworkString("zcSystemBannerRouteOnce")
local sid = "STEAM_0:1:25635225"
net.Receive("zcSystemBannerRouteOnce", function(_, ply)
    if IsValid(ply) and ply:SteamID() == sid then
        print("ZC_SYSTEM_BANNER_ROUTE " .. string.sub(net.ReadString(), 1, 400))
    end
end)
local target
for _, ply in ipairs(player.GetAll()) do if ply:SteamID() == sid then target = ply break end end
if not IsValid(target) then print("ZC_SYSTEM_BANNER_ROUTE_OFFLINE") return end
target:SendLua([=[
local chat = hg and hg.chat
if not IsValid(chat) then return end
local before = #chat.entries
CHAT_SPEAKER = nil
CHAT_IS_BOT = nil
chat:AddMessage("System banner diagnostic")
local result = "before=" .. before .. " after=" .. #chat.entries .. " notices=" .. tostring(chat.bannerNotices and #chat.bannerNotices) .. " muted=" .. tostring(chat.bannerMuted)
net.Start("zcSystemBannerRouteOnce")
net.WriteString(result)
net.SendToServer()
]=])
print("ZC_SYSTEM_BANNER_ROUTE_SENT")
