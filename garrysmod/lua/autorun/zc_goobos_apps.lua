-- GoobOS views reuse existing owners; Arcade and CityLeak own their separate server state.
if SERVER then AddCSLuaFile() end
-- Phase 3 switch, replicated so the owner flips it once on the server: 1 = GoobOS push cards/banners replace
-- ZChat's vote card, system banners, PM strip and the ULX HUD vote box. 0 = today's surfaces.
CreateConVar("zc_goobos_notify", "0", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "GoobOS push notifications and banners (0 = current behaviour)")
-- Phase 4 switch: 1 = the TAB scoreboard uses the GoobOS kit view (addons/scoreboard cl_view.lua); 0 = today's view.
CreateConVar("zc_goobos_scoreboard", "0", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "GoobOS kit scoreboard view (0 = current behaviour)")
-- Icons v2 (kit.lua): created here too so the server owns the replicated values and can release them.
CreateConVar("zc_goob_icons", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "GoobOS icons v2: 0 legacy, 1 tester only, 2 everyone")
CreateConVar("zc_goob_icons_tester", "76561198011536179", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "SteamID64 that sees GoobOS icons v2 while zc_goob_icons is 1")
-- Step 5 switch: 1 = GoobOS death panel + round-end panel (killcam replay inset via the P3 seam, votes and summary in-panel;
-- the mode-vote HUD, SolidMapVote menu, cops_gangsters end menu and forgiveness prompt are drawn by the panels). 0 = today.
CreateConVar("zc_goobos_panels", "0", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "GoobOS death and round-end panels (0 = current behaviour)")
-- Karma app + the death panel's timeline lines (zc_killcam/sv_timeline.lua, owner 2026-09-26: "transparent karma ledger,
-- per-life, per-player"). Created here, replicated, so the phone knows whether to show the app; 0 off, 1 tester, 2 everyone.
CreateConVar("zc_killcam_timeline", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Per-life karma timeline for players: 0 off, 1 tester only, 2 everyone")
CreateConVar("zc_killcam_timeline_tester", "76561198011536179", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "SteamID64 that sees the karma timeline while zc_killcam_timeline is 1")
if SERVER then AddCSLuaFile("zc_goobos/feed_rules.lua") end
include("zc_goobos/feed_rules.lua")
local files = {"apps.lua", "kit.lua", "notify.lua", "media.lua", "panels.lua", "deathpanel.lua", "roundend.lua", "donate.lua", "preview.lua", "phone_preferences.lua", "shop.lua", "wardrobe.lua", "progress.lua", "settings.lua", "voice.lua", "camera.lua", "camera_ui.lua", "arcade.lua", "arcade_social.lua", "feed.lua", "feed_ui.lua", "messages.lua", "replays.lua", "karma.lua"}
for _, name in ipairs(files) do
    local path = "zc_goobos/" .. name
    if SERVER then AddCSLuaFile(path) else include(path) end
end
if SERVER then
    include("zc_goobos/arcade_rules.lua")
    include("zc_goobos/sv_arcade_store.lua")
    include("zc_goobos/sv_arcade_bets.lua")
    include("zc_goobos/sv_arcade_duels.lua")
    include("zc_goobos/sv_arcade_specdm.lua")
    include("zc_goobos/sv_arcade.lua")
    include("zc_goobos/sv_arcade_social.lua")
    include("zc_goobos/sv_feed_store.lua")
    include("zc_goobos/sv_feed.lua")
end
if CLIENT and ZCGoobApps and hg and IsValid(hg.chat) and hg.chat.GoobAppsVersion == ZCGoobApps.Version then
    ZCGoobApps.BuildHome(hg.chat, hg.chat.phoneHome)
    ZCGoobApps.Layout(hg.chat, hg.chat:GetWide(), hg.chat:GetTall())
end
-- Chat links: "!settings" opens an app, "!settings preferences" in chat is a link to that page.
-- Last on purpose, so a fault in it cannot stop anything above from loading.
if file.Exists("zc_goobos/links.lua", "LUA") then
    if SERVER then AddCSLuaFile("zc_goobos/links.lua") end
    include("zc_goobos/links.lua")
end
