util.AddNetworkString("zcSystemBannerProbeOnce")
local sid = "STEAM_0:1:25635225"
net.Receive("zcSystemBannerProbeOnce", function(_, ply)
    if IsValid(ply) and ply:SteamID() == sid then
        print("ZC_SYSTEM_BANNER_PROBE " .. string.sub(net.ReadString(), 1, 500))
    end
end)
local target
for _, ply in ipairs(player.GetAll()) do if ply:SteamID() == sid then target = ply break end end
if not IsValid(target) then print("ZC_SYSTEM_BANNER_PROBE_OFFLINE") return end
target:SendLua([=[
local chat = hg and hg.chat
local parts = {}
parts[#parts + 1] = "chat=" .. tostring(IsValid(chat))
parts[#parts + 1] = "bannerfn=" .. tostring(IsValid(chat) and type(chat.ShowSystemBanner))
parts[#parts + 1] = "button=" .. tostring(IsValid(chat) and IsValid(chat.bannerMuteButton))
parts[#parts + 1] = "muted=" .. tostring(IsValid(chat) and chat.bannerMuted)
parts[#parts + 1] = "notices=" .. tostring(IsValid(chat) and chat.bannerNotices and #chat.bannerNotices)
parts[#parts + 1] = "rows=" .. tostring(IsValid(chat) and chat.entries and #chat.entries)
net.Start("zcSystemBannerProbeOnce")
net.WriteString(table.concat(parts, " | "))
net.SendToServer()
]=])
print("ZC_SYSTEM_BANNER_PROBE_SENT")
