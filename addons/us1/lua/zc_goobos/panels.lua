-- GoobOS fullscreen panels coordinator (step 5): the death panel and the round-end panel both draw the killcam
-- replay inset through the killcam's P3 seam (work/loader/killcam_revitalize/P3_SEAM.txt). The seam accepts ONE
-- owner (ZCKillcamView.SetUIOwner), so every panel claims through here and the owner answers "on screen" when any
-- claimed panel says so. The killcam only hands drawing over while its client convar zc_killcam_ui is 1.
--
-- zc_killcam_ui is a per-player archived client convar (default 0, owned by lua/zc_killcam). So the owner can flip
-- the panels server-wide, when zc_goobos_panels (replicated, created in lua/autorun/zc_goobos_apps.lua) is 1 this
-- file sets zc_killcam_ui 1 on clients that never touched it, and puts it back to 0 when the server switch goes
-- back to 0. A player who set zc_killcam_ui themselves is never overridden (cookie "zc_goob_kcui" = "auto" marks
-- only the values this file wrote).
if not CLIENT then return end
local A = ZCGoobApps
if not A then return end
local P = A.Panels or {}
A.Panels = P
P.Version = "20260925.panels4"
P.Claims = P.Claims or {}

-- Owner canvas note (2026-09-25): "leave room for the voice chat column on the right border, on ALL killcam/highlight
-- screens". The voice speaker plates hug the right screen edge (voice.lua:319 ORB_MAX_W = 176, :1185 EDGE = 8), so both
-- full-screen panels keep that strip clear. A.Voice.Gutter, when the voice module publishes one, wins over the constant.
function P.RightGutter()
    local V = A.Voice
    local g = istable(V) and tonumber(V.Gutter) or nil
    return math.max(0, g or (176 + 16))
end

-- Clean weapon display name (owner canvas note: "[clean weapon display name]"): the SWEP's PrintName when this client
-- knows the class, else the class without its prefix and underscores ("weapon_m4a1" -> "m4a1").
function P.WeaponName(class)
    if not isstring(class) or class == "" then return "unknown weapon" end
    local W = rawget(_G, "weapons")
    local stored = istable(W) and isfunction(W.GetStored) and W.GetStored(class) or nil
    local name = istable(stored) and stored.PrintName or nil
    if isstring(name) and name ~= "" then
        local L = rawget(_G, "language")
        if string.sub(name, 1, 1) == "#" and istable(L) and isfunction(L.GetPhrase) then name = L.GetPhrase(string.sub(name, 2)) end
        return name
    end
    return (string.gsub(string.gsub(class, "^[a-z0-9]+_", ""), "_", " "))
end

-- Player actions shared by the panels' rosters (owner canvas note 2026-09-25: "left clicking to access cityleak profile,
-- steam profile, mute, and private message"). `ply` may be NULL (left the server): only the profiles work then.
local function voiceKey(ply)
    if ply:IsBot() then return "bot_" .. tostring(ply:EntIndex()) end
    return ply:SteamID() or ""
end
-- Mirrors zc_scoreboard cl_services.lua saveMuteInfo + applyVoiceState (hg.playerInfo[key] = {muted, volume} persisted
-- to zcity_muted.txt) so the scoreboard's slider and the join loader agree with a mute set from here.
function P.MutePlayer(ply, muted)
    if not IsValid(ply) or not isfunction(ply.SetMuted) then return false end
    muted = muted and true or false
    ply:SetMuted(muted)
    local hgT = rawget(_G, "hg")
    if istable(hgT) then
        hgT.playerInfo = hgT.playerInfo or {}
        local key = voiceKey(ply)
        local prev = hgT.playerInfo[key]
        local volume = istable(prev) and tonumber(prev[2]) or 1
        hgT.playerInfo[key] = {muted, volume}
        if isfunction(ply.SetVoiceVolumeScale) then ply:SetVoiceVolumeScale(muted and 0 or volume) end
        local json = util.TableToJSON(hgT.playerInfo)
        local F = rawget(_G, "file")
        if json and istable(F) and isfunction(F.Write) then F.Write("zcity_muted.txt", json) end
    end
    return true
end
-- CityLeak is the "feed" app (apps.lua A.Register("feed")); its client state (feed.lua F.Client) drives the view the app
-- renders when it opens, so the profile view is armed first and the app launched second.
function P.OpenCityLeak(sid)
    local F = rawget(_G, "ZCGoobFeed")
    local C = istable(F) and F.Client or nil
    if istable(C) then C.view, C.author, C.before, C.feedItems = "profile", sid, nil, {} end
    return isfunction(A.Launch) and A.Launch("feed") == true
end
-- A private message thread in ZChat (zc_chat_media/threads.lua T.Open(chat, sid64, name)).
function P.OpenPM(ply)
    local Th = rawget(_G, "ZCChatThreads")
    local hgT = rawget(_G, "hg")
    local chat = istable(hgT) and hgT.chat or nil
    if not (istable(Th) and isfunction(Th.Open) and IsValid(chat) and IsValid(ply)) then return false end
    Th.Open(chat, ply:SteamID64(), ply:Nick())
    return true
end
function P.PlayerMenu(sid, ply)
    local DM = rawget(_G, "DermaMenu")
    if not isfunction(DM) then return false end
    local menu = DM()
    local me = LocalPlayer()
    if sid then
        menu:AddOption("CityLeak profile", function() P.OpenCityLeak(sid) end)
        menu:AddOption("Steam profile", function() gui.OpenURL("https://steamcommunity.com/profiles/" .. sid) end)
    end
    if IsValid(ply) and ply ~= me then
        local muted = isfunction(ply.IsMuted) and ply:IsMuted() == true
        menu:AddOption(muted and "Unmute voice" or "Mute voice", function() P.MutePlayer(ply, not muted) end)
        menu:AddOption("Private message", function() P.OpenPM(ply) end)
    end
    menu:Open()
    return true
end

local switchCache = {}
local function switchOn(name)
    local cv = switchCache[name]
    if cv == nil then
        cv = GetConVar(name)
        if cv ~= nil then switchCache[name] = cv end
    end
    return cv ~= nil and cv:GetBool()
end
function P.Enabled() return switchOn("zc_goobos_panels") and A.Kit ~= nil end

-- fn() -> true while that panel covers the screen and draws the replay itself.
function P.Claim(name, fn)
    P.Claims[name] = fn
    P.Install()
end

-- postround_20260925: a claim may answer "side" - the panel draws the replay in a small card and the player's own
-- view, HUD and input stay theirs (the killcam must not blank or replace the world, see cl_part_06 V.UISide).
-- Any claim answering true (covers the screen) wins over "side".
local function owner()
    if not P.Enabled() then return false end
    local side = false
    for _, fn in pairs(P.Claims) do
        local ok, on = pcall(fn)
        if ok and on == true then return true end
        if ok and on == "side" then side = true end
    end
    return side and "side" or false
end
P.Owner = owner

function P.Install()
    local V = ZCKillcamView
    if istable(V) and isfunction(V.SetUIOwner) and V.GoobOwner ~= owner then
        V.SetUIOwner(owner)
        V.GoobOwner = owner
    end
end

-- The replay seam, nil-safe. Returns the V.State() table or nil.
function P.Replay()
    local V = ZCKillcamView
    if not istable(V) or not isfunction(V.State) then return nil end
    local ok, state = pcall(V.State)
    return ok and istable(state) and state or nil
end

function P.UIActive()
    local V = ZCKillcamView
    return istable(V) and isfunction(V.UIActive) and V.UIActive() == true
end

-- Draw the replay into a panel-local rect; returns true when a frame was drawn.
function P.RenderInset(panel, x, y, w, h)
    local V = ZCKillcamView
    if not istable(V) or not isfunction(V.RenderInset) or not IsValid(panel) then return false end
    local sx, sy = panel:LocalToScreen(x, y)
    local ok, drawn = pcall(V.RenderInset, sx, sy, w, h)
    return ok and drawn == true
end

-- Wrapper for V.Play / V.Next / V.Skip / V.Save / V.Report; returns false when unavailable.
function P.Call(name, ...)
    local V = ZCKillcamView
    if not istable(V) or not isfunction(V[name]) then return false end
    local ok, acted = pcall(V[name], ...)
    return ok and acted
end

-- Polish pass 2026-09-24: shared input + layout helpers, so the two panels agree on them.
-- Typing guard (the killcam bundle uses the same three checks): a letter typed into chat, the console or the game
-- menu must never step, skip, save, report or vote.
function P.Typing()
    if gui.IsConsoleVisible() or gui.IsGameUIVisible() then return true end
    local focus = vgui.GetKeyboardFocus()
    return IsValid(focus) and isfunction(focus.IsEditing) and focus:IsEditing() == true
end

-- Layout unit: 1 at 1920x1080, scaled by the smaller screen axis and clamped so 720p stays readable and 4K does not
-- balloon. Every panel size, font and gap in the panels is authored in these units.
function P.Unit()
    local u = math.min(ScrW() / 1920, ScrH() / 1080)
    return math.Clamp(u, 0.62, 1.5)
end

-- Edge-triggered key state per panel: `keys` is the panel's own table, so two panels polling the same key never
-- steal each other's edges. Returns true on the frame the key goes down.
-- postround_20260925 (owner: "voice chat input takes precedence"): the key bound to +voicerecord is never a panel
-- hotkey. Found with input.LookupKeyBinding over the button codes (the engine's own lookup, see
-- lua/vgui/dadjustablemodelpanel.lua), re-read every 2 s so a rebind is picked up.
local boundVoiceKey, boundVoiceKeyAt = nil, -math.huge
function P.IsVoiceBind(bind) return isstring(bind) and string.find(bind, "voicerecord", 1, true) ~= nil end
function P.VoiceKey()
    local now = RealTime()
    if now - boundVoiceKeyAt < 2 then return boundVoiceKey end
    boundVoiceKeyAt, boundVoiceKey = now, nil
    local last = rawget(_G, "BUTTON_CODE_LAST") or 171
    for code = 1, last do
        local ok, bind = pcall(input.LookupKeyBinding, code)
        if ok and P.IsVoiceBind(bind) then boundVoiceKey = code break end
    end
    return boundVoiceKey
end
function P.Edge(keys, code)
    if code == P.VoiceKey() then keys[code] = input.IsKeyDown(code) return false end
    local down = input.IsKeyDown(code)
    local was = keys[code]
    keys[code] = down
    return down and not was
end
-- Keep tracking while typing so a key held through the chat closing does not fire on release.
function P.Track(keys, codes)
    for _, code in ipairs(codes) do keys[code] = input.IsKeyDown(code) end
end
function P.Release(keys)
    for code in pairs(keys) do keys[code] = nil end
end

local function syncKillcamUI()
    P.Install()
    local cv = GetConVar("zc_killcam_ui")
    if not cv then return end
    local mark = cookie.GetString("zc_goob_kcui", "")
    if P.Enabled() then
        if not cv:GetBool() and mark == "" then
            RunConsoleCommand("zc_killcam_ui", "1")
            cookie.Set("zc_goob_kcui", "auto")
        end
    elseif mark == "auto" then
        if cv:GetBool() then RunConsoleCommand("zc_killcam_ui", "0") end
        cookie.Delete("zc_goob_kcui")
    end
end
timer.Create("GoobOS.Panels.Sync", 1, 0, syncKillcamUI)
hook.Add("InitPostEntity", "GoobOS.Panels.Sync", syncKillcamUI)

-- Chat dock (owner 2026-09-24: "chat gets a dedicated space within the killcam/highlight panels"). A panel that is up
-- reserves a screen rectangle for the chat frame: it publishes the rect every frame it is visible (P.ChatDock), the
-- frame (addons/zcity .. zchat/derma/cl_zchat.lua PANEL:Think) moves into it and draws on top of the panel while the
-- rect is fresh, and a rect nobody has refreshed for 0.3 s is dropped - so a panel that vanishes without saying so
-- still hands the chat back to its corner. The chat frame's own minimums (384 x 180 px) are the callers' to respect.
function P.ChatDock(x, y, w, h)
    if x == nil then ZCChatDock = nil return end
    local d = ZCChatDock
    if not istable(d) then d = {} ZCChatDock = d end
    d.x, d.y, d.w, d.h, d.at = math.floor(x), math.floor(y), math.floor(w), math.floor(h), RealTime()
end
timer.Create("GoobOS.Panels.ChatDock", 0.25, 0, function()
    local d = ZCChatDock
    if istable(d) and RealTime() - (d.at or 0) > 0.3 then ZCChatDock = nil end
end)

-- Number keys for in-panel votes and actions: P.SetKeys(name, fn) where fn(n) returns true when it used slot n.
-- Only slot binds are taken, and only while a handler says it used the press (e.g. a vote card is up).
P.KeyHandlers = P.KeyHandlers or {}
function P.SetKeys(name, fn) P.KeyHandlers[name] = fn end
hook.Add("PlayerBindPress", "GoobOS.Panels.Keys", function(_, bind, pressed)
    if not pressed then return end
    local n = tonumber(string.match(bind or "", "^slot(%d+)$"))
    if not n then return end
    for _, fn in pairs(P.KeyHandlers) do
        local ok, handled = pcall(fn, n)
        if ok and handled == true then return true end
    end
end)
