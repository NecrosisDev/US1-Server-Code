if not CLIENT then return end
PATSB = PATSB or {}
PATSB.Settings = PATSB.Settings or {}
-- Close only this addon's existing voice popup on refresh.
if IsValid(PATSB.VoiceFrame) then PATSB.VoiceFrame:Remove() end

local function colorData(r, g, b, a)
    return {
        r = r,
        g = g,
        b = b,
        a = a or 255
    }
end

PATSB.ThemeDefaults = PATSB.ThemeDefaults or {
    white = colorData(245, 245, 245, 255),
    text = colorData(220, 220, 220, 255),
    muted = colorData(160, 160, 160, 255),
    accent = colorData(190, 20, 20, 220),
    accent_soft = colorData(255, 45, 45, 120),
    bg = colorData(8, 8, 8, 220),
    bg2 = colorData(18, 18, 18, 235),
    bg3 = colorData(28, 28, 28, 220),
    spec = colorData(180, 180, 180, 255),
    team_t = colorData(190, 55, 55, 255),
    team_ct = colorData(70, 150, 220, 255)
}

local THEME_KEYS = {
    "accent",
    "accent_soft",
    "bg",
    "bg2",
    "bg3",
    "white",
    "text",
    "muted",
    "spec",
    "team_t",
    "team_ct"
}

local THEME_LABELS = {
    accent = "Accent",
    accent_soft = "Accent Soft",
    bg = "Background",
    bg2 = "Panel Background",
    bg3 = "Panel Accent Background",
    white = "Primary Text",
    text = "Secondary Text",
    muted = "Muted Text",
    spec = "Spectator",
    team_t = "Team T",
    team_ct = "Team CT"
}

PATSB.Defaults = {
    refresh_interval = 1,
    enable_ulx_menu = true,
    enable_profile_button = true,
    show_spectators = true,
    show_karma = true,
    show_session = true,
    show_playtime = true,
    show_tickrate = true,
    show_ulx_ranks = true,
    show_voice_buttons = true,
    show_bottom_mute_buttons = true,
    show_team_button = true,
    blur_strength = 5,
    frame_width = 1600,
    frame_height = 920,
    sidebar_width_min = 300,
    sidebar_width_max = 420,
    sidebar_width_frac = 0.24,
    command_1_enabled = true,
    command_1_text = "Store",
    command_1_say = "!store",
    command_2_enabled = true,
    command_2_text = "Guide",
    command_2_say = "!motd",
    font_title = "Bahnschrift",
    font_body = "Bahnschrift",
    ui_scale_mul = 1,
    theme = table.Copy(PATSB.ThemeDefaults)
}

for k, v in pairs(PATSB.Defaults) do
    if PATSB.Settings[k] == nil then
        PATSB.Settings[k] = istable(v) and table.Copy(v) or v
    end
end

local scoreBoardMenu
hg = hg or {}
hg.playerInfo = hg.playerInfo or {}
zb = zb or {}

local COL_WHITE
local COL_TEXT
local COL_MUTED
local COL_RED
local COL_RED_SOFT
local COL_BG
local COL_BG2
local COL_BG3
local COL_SPEC
local COL_T
local COL_CT

local BASE_W, BASE_H = 1920, 1080
local _lastScrW, _lastScrH = 0, 0

local FONT_TITLE = "PATSB_Title"
local FONT_HEADER = "PATSB_Header"
local FONT_MED = "PATSB_Med"
local FONT_SMALL = "PATSB_Small"

local function themeColorData(entry, fallback)
    local defaults = istable(fallback) and fallback or { r = 255, g = 255, b = 255, a = 255 }
    local value = istable(entry) and entry or {}

    return Color(
        math.Clamp(tonumber(value.r) or defaults.r or 255, 0, 255),
        math.Clamp(tonumber(value.g) or defaults.g or 255, 0, 255),
        math.Clamp(tonumber(value.b) or defaults.b or 255, 0, 255),
        math.Clamp(tonumber(value.a) or defaults.a or 255, 0, 255)
    )
end

local function ensureThemeTable(settings)
    settings.theme = istable(settings.theme) and settings.theme or {}

    for key, defaults in pairs(PATSB.ThemeDefaults) do
        settings.theme[key] = istable(settings.theme[key]) and settings.theme[key] or table.Copy(defaults)
    end
end

local function applyThemeColors()
    ensureThemeTable(PATSB.Settings)

    local theme = PATSB.Settings.theme
    COL_WHITE = themeColorData(theme.white, PATSB.ThemeDefaults.white)
    COL_TEXT = themeColorData(theme.text, PATSB.ThemeDefaults.text)
    COL_MUTED = themeColorData(theme.muted, PATSB.ThemeDefaults.muted)
    COL_RED = themeColorData(theme.accent, PATSB.ThemeDefaults.accent)
    COL_RED_SOFT = themeColorData(theme.accent_soft, PATSB.ThemeDefaults.accent_soft)
    COL_BG = themeColorData(theme.bg, PATSB.ThemeDefaults.bg)
    COL_BG2 = themeColorData(theme.bg2, PATSB.ThemeDefaults.bg2)
    COL_BG3 = themeColorData(theme.bg3, PATSB.ThemeDefaults.bg3)
    COL_SPEC = themeColorData(theme.spec, PATSB.ThemeDefaults.spec)
    COL_T = themeColorData(theme.team_t, PATSB.ThemeDefaults.team_t)
    COL_CT = themeColorData(theme.team_ct, PATSB.ThemeDefaults.team_ct)
end

applyThemeColors()

local function sbBool(name, fallback)
    local v = PATSB.Settings[name]
    if v == nil then return fallback end
    return v and true or false
end

local function sbInt(name, fallback)
    local v = tonumber(PATSB.Settings[name])
    if v == nil then return fallback end
    return math.floor(v)
end

local function sbFloat(name, fallback)
    local v = tonumber(PATSB.Settings[name])
    if v == nil then return fallback end
    return v
end

local function sbString(name, fallback)
    local v = PATSB.Settings[name]
    if v == nil or v == "" then return fallback end
    return tostring(v)
end

local function UIScale()
    return math.min(ScrW() / BASE_W, ScrH() / BASE_H) * sbFloat("ui_scale_mul", 1)
end

local function ui(v)
    return math.max(1, math.floor(v * UIScale()))
end

local function rebuildFonts(force)
    if not force and _lastScrW == ScrW() and _lastScrH == ScrH() then return end
    _lastScrW, _lastScrH = ScrW(), ScrH()

    local titleFont = sbString("font_title", "Tahoma")
    local bodyFont = sbString("font_body", "Tahoma")

    surface.CreateFont(FONT_TITLE, {
        font = titleFont,
        size = ui(28),
        weight = 900,
        extended = true
    })

    surface.CreateFont(FONT_HEADER, {
        font = bodyFont,
        size = ui(20),
        weight = 800,
        extended = true
    })

    surface.CreateFont(FONT_MED, {
        font = bodyFont,
        size = ui(18),
        weight = 700,
        extended = true
    })

    surface.CreateFont(FONT_SMALL, {
        font = bodyFont,
        size = ui(14),
        weight = 600,
        extended = true
    })
end

rebuildFonts(true)

hook.Add("OnScreenSizeChanged", "PATSB_RebuildFonts", function()
    rebuildFonts(true)
end)

local function drawOutlinedRect(x, y, w, h, col, thick)
    surface.SetDrawColor(col)
    surface.DrawOutlinedRect(x, y, w, h, thick or 1)
end

local function blurPanel(panel, a)
    local blur = sbInt("blur_strength", 5)

    if hg and hg.DrawBlur then
        hg.DrawBlur(panel, blur, 1, a or 120)
    else
        surface.SetDrawColor(0, 0, 0, a or 120)
        surface.DrawRect(0, 0, panel:GetWide(), panel:GetTall())
    end
end

local function getTeamAccent(ply)
    if not IsValid(ply) then return COL_SPEC end
    if TEAM_SPECTATOR and ply:Team() == TEAM_SPECTATOR then return COL_SPEC end
    return ply:Team() == 1 and COL_CT or COL_T
end

-- Public representation only. Hidden-round settlement remains server-owned.
local function getKarma(ply)
    if not IsValid(ply) or not isfunction(ply.GetNetVar) then return nil end
    local value
    if ply == LocalPlayer() then
        local own = ZCScoreboardSelfView and ZCScoreboardSelfView.Get()
        value = own and own.karma
    else value = ply:GetNetVar("Karma") end
    if not isnumber(value) or value ~= value or math.abs(value) == math.huge then return nil end
    return math.floor(value)
end
PATSB.GetDisplayedKarma = getKarma
PATSB.KarmaDisplayVersion = "20260923.karma2"

local function prettifyUserGroup(group)
    group = tostring(group or "user")
    if group == "" then
        return "User"
    end

    group = string.gsub(group, "_", " ")
    group = string.Trim(group)

    return string.upper(string.sub(group, 1, 1)) .. string.sub(group, 2)
end

local function getUserGroupText(ply)
    if not IsValid(ply) then return "User" end

    if AS and AS.GetUserGroup then
        return prettifyUserGroup(AS:GetUserGroup(ply))
    end

    if ply.GetUserGroup then
        return prettifyUserGroup(ply:GetUserGroup())
    end

    return "User"
end

local function formatSessionTime(seconds)
    seconds = math.max(0, math.floor(seconds or 0))

    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)

    if hours > 0 then
        return string.format("%02ih %02im", hours, minutes)
    end

    return string.format("%02im", minutes)
end

local function getSessionTimeText(ply)
    if not IsValid(ply) then
        return "00m"
    end

    if not ply.TimeConnected then
        return "00m"
    end

    return formatSessionTime(tonumber(ply:TimeConnected()) or 0)
end

local function getPlaytimeSeconds(ply)
    if not IsValid(ply) then
        return nil
    end

    local zcStoreTotal = tonumber(ply:GetNWInt("ZCStore_TotalPlaytime", -1))
    if zcStoreTotal and zcStoreTotal >= 0 then
        local zcSyncUnix = math.max(0, tonumber(ply:GetNWInt("ZCStore_PlaytimeSyncUnix", os.time())) or os.time())
        return zcStoreTotal + math.max(0, os.time() - zcSyncUnix)
    end

    local baseTotal = tonumber(ply:GetNWInt("PATSB_TotalPlayBase", -1))
    if baseTotal and baseTotal >= 0 then
        return baseTotal + math.max(0, os.time() - math.max(0, ply:GetNWInt("PATSB_JoinUnix", os.time())))
    end

    if ply.GetUTimeTotalTime then
        local total = tonumber(ply:GetUTimeTotalTime())
        local session = ply.GetUTimeSessionTime and tonumber(ply:GetUTimeSessionTime()) or 0
        if total and total >= 0 then
            return total + math.max(session or 0, 0)
        end
    end

    local nwKeys = {
        "UTimeTotalTime",
        "UTime_TotalTime",
        "PlayTime",
        "TimePlayed",
        "TotalPlayTime"
    }

    for _, key in ipairs(nwKeys) do
        local value = tonumber(ply:GetNWInt(key, -1))
        if value and value >= 0 then
            return value
        end
    end

    return nil
end

local function getPlaytimeText(ply)
    local seconds = getPlaytimeSeconds(ply)
    if not seconds or seconds <= 0 then
        return nil
    end

    return formatSessionTime(seconds)
end

local function getRoundStateText()
    if zb.ROUND_STATE == 0 then return "Waiting" end
    if zb.ROUND_STATE == 1 then return "Live" end
    if zb.ROUND_STATE == 2 then return "Post-Round" end
    if zb.ROUND_STATE == 3 then return "Ending" end
    return "Unknown"
end

local function getTimeText()
    -- fear rounds: no clock, just the truth
    if zb.CROUND == "fear" or zb.CROUND == "fear_soe" then
        return "POLICE WON'T SAVE YOU."
    end

    -- homicide rounds show the police clock instead (bridge-fed;
    -- wildwest and no-police types never set it)
    local policeETA = GetGlobalFloat("HMCD_PoliceETA", 0)
    if policeETA > 0 then
        if GetGlobalBool("HMCD_PoliceHere", false) then
            return "POLICE ON SCENE"
        end
        local left = math.max(policeETA - CurTime(), 0)
        return "POLICE: " .. string.FormattedTime(left, "%02i:%02i")
    end

    local startTime = zb.ROUND_START or CurTime()
    local roundTime = zb.ROUND_TIME or 0
    local left = math.max(startTime + roundTime - CurTime(), 0)
    return string.FormattedTime(left, "%02i:%02i")
end

local function getVoiceKey(ply)
    if not IsValid(ply) then return "" end

    if ply:IsBot() then
        return "bot_" .. tostring(ply:EntIndex())
    end

    return ply:SteamID() or ""
end

local function volumeFor(ply)
    local key = getVoiceKey(ply)
    if key == "" then return 1 end

    local info = hg.playerInfo and hg.playerInfo[key]
    if istable(info) then
        return tonumber(info[2]) or 1
    end

    return 1
end

local function isStoredMuted(ply)
    local key = getVoiceKey(ply)
    if key == "" then return false end

    local info = hg.playerInfo and hg.playerInfo[key]
    if istable(info) then
        return info[1] and true or false
    end

    return false
end

local function saveMuteInfo(ply, muted, volume)
    if not IsValid(ply) then return end

    local key = getVoiceKey(ply)
    if key == "" then return end

    hg.playerInfo = hg.playerInfo or {}
    hg.playerInfo[key] = {muted and true or false, volume or volumeFor(ply)}

    local json = util.TableToJSON(hg.playerInfo)
    if json then
        file.Write("zcity_muted.txt", json)
    end
end

local function applyVoiceState(ply)
    if not IsValid(ply) then return end

    if hg.muteall then
        ply:SetVoiceVolumeScale(0)
        return
    end

    if hg.mutespect and not ply:Alive() then
        ply:SetVoiceVolumeScale(0)
        return
    end

    if isStoredMuted(ply) then
        ply:SetVoiceVolumeScale(0)
        return
    end

    ply:SetVoiceVolumeScale(volumeFor(ply))
end

-- Uses the same per-player preferences as ZCity's existing voice renderer.
local VOICE_SAVE_TIMER = "PATSB_VoiceVolumeSave"

local function canAdjustVoice(ply)
    return IsValid(ply) and ply ~= LocalPlayer()
end

local function openVoiceControls(ply)
    if not canAdjustVoice(ply) or not IsValid(scoreBoardMenu) then return end
    if IsValid(PATSB.VoiceFrame) then PATSB.VoiceFrame:Remove() end
    local key = getVoiceKey(ply)
    if key == "" then return end
    PATSB.VoiceSequence = (PATSB.VoiceSequence or 0) + 1
    local saveTimer = VOICE_SAVE_TIMER .. "_" .. PATSB.VoiceSequence

    -- Parent to the scoreboard, not a player card: list refreshes rebuild cards.
    local frame = vgui.Create("DFrame", scoreBoardMenu)
    PATSB.VoiceFrame = frame
    frame:SetSize(math.min(ui(420), scoreBoardMenu:GetWide() - ui(24)), ui(174))
    frame:Center()
    frame:SetTitle("Voice - " .. (ply:Name() or "Unknown"))
    frame:SetDraggable(false)
    frame:SetSizable(false)
    frame:SetDeleteOnClose(true)
    frame:SetKeyboardInputEnabled(false)
    frame:MoveToFront()
    frame.Paint = function(self, w, h)
        surface.SetDrawColor(COL_BG2)
        surface.DrawRect(0, 0, w, h)
        drawOutlinedRect(0, 0, w, h, COL_RED, ui(2))
    end

    local slider = vgui.Create("DNumSlider", frame)
    slider:SetPos(ui(12), ui(38))
    slider:SetSize(frame:GetWide() - ui(24), ui(36))
    slider:SetText("Volume (%)")
    slider:SetMinMax(0, 100)
    slider:SetDecimals(0)
    local initial = (isStoredMuted(ply) or ply:IsMuted()) and 0 or volumeFor(ply) * 100
    if initial ~= initial or initial == math.huge or initial == -math.huge then initial = 100 end
    slider:SetValue(math.Clamp(initial, 0, 100))
    -- Keep Tab release available to the scoreboard instead of a number editor.
    slider.TextArea:SetMouseInputEnabled(false)
    slider.TextArea:SetKeyboardInputEnabled(false)

    local hint = vgui.Create("DLabel", frame)
    hint:SetPos(ui(12), ui(78))
    hint:SetSize(frame:GetWide() - ui(24), ui(42))
    hint:SetFont(FONT_SMALL)
    hint:SetTextColor(COL_TEXT)
    hint:SetWrap(true)
    hint:SetText("Only changes what you hear. 0% mutes this player.")

    local dirty = false
    local function flush()
        timer.Remove(saveTimer)
        if not dirty then return end
        local json = util.TableToJSON(hg.playerInfo)
        if json then file.Write("zcity_muted.txt", json); dirty = false end
    end
    frame.OnRemove = function()
        flush()
        if PATSB.VoiceFrame == frame then PATSB.VoiceFrame = nil end
    end
    local originalThink = frame.Think
    frame.Think = function(self)
        if originalThink then originalThink(self) end
        if not canAdjustVoice(ply) or getVoiceKey(ply) ~= key then frame:Remove() end
    end
    slider.OnValueChanged = function(_, value)
        if not canAdjustVoice(ply) or getVoiceKey(ply) ~= key then frame:Remove(); return end
        value = tonumber(value)
        if not value or value ~= value or value == math.huge or value == -math.huge then return end
        local volume = math.Clamp(math.Round(value), 0, 100) / 100
        local muted = volume == 0
        if not istable(hg.playerInfo) then hg.playerInfo = {} end
        local previous = hg.playerInfo[key]
        if istable(previous) and previous[1] == muted and previous[2] == volume and ply:IsMuted() == muted then return end
        hg.playerInfo[key] = {muted, volume}
        -- The existing join loader restores both engine mute and saved gain.
        ply:SetMuted(muted)
        applyVoiceState(ply)
        dirty = true
        timer.Create(saveTimer, 0.25, 1, flush)
    end

    local reset = vgui.Create("DButton", frame)
    reset:SetPos(ui(12), ui(128))
    reset:SetSize(ui(128), ui(28))
    reset:SetText("Reset to 100%")
    reset.DoClick = function() slider:SetValue(100) end

    local close = vgui.Create("DButton", frame)
    close:SetPos(frame:GetWide() - ui(92), ui(128))
    close:SetSize(ui(80), ui(28))
    close:SetText("Done")
    close.DoClick = function() frame:Close() end
    if ZCScoreboard and ZCScoreboard.Skin then ZCScoreboard.Skin.VoicePopup(frame,ply,slider,hint,reset,close) end
end

local function createVoiceButton(parent, ply)
    if not canAdjustVoice(ply) or not sbBool("show_voice_buttons", true) then return end
    local button = vgui.Create("DButton", parent)
    button:SetSize(ui(72), ui(28))
    button:SetText("")
    button:SetTooltip("Adjust how loudly you hear " .. (ply:Name() or "Unknown"))
    button.DoClick = function() openVoiceControls(ply) end
    button.Paint = function(self, w, h)
        surface.SetDrawColor(0, 0, 0, 160)
        surface.DrawRect(0, 0, w, h)
        local muted = isStoredMuted(ply) or volumeFor(ply) <= 0
        drawOutlinedRect(0, 0, w, h, muted and Color(107,0,0) or Color(0,97,5), 1)
        draw.SimpleText("Voice", FONT_SMALL, w / 2, h / 2, COL_WHITE, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    return button
end

local function runULXCommand(cmd)
    LocalPlayer():ConCommand(cmd)
end

local function hasZCityKarmaULX()
    return istable(ZCITY_ULX_KARMA)
        and ZCITY_ULX_KARMA.Loaded
        and istable(ZCITY_ULX_KARMA.Commands)
        and ZCITY_ULX_KARMA.Commands.setkarma
        and ZCITY_ULX_KARMA.Commands.addkarma
        and ZCITY_ULX_KARMA.Commands.removekarma
end

local function hasZCityStoreULX()
    return istable(ZCITY_ULX_STORE)
        and ZCITY_ULX_STORE.Loaded
        and istable(ZCITY_ULX_STORE.Commands)
        and ZCITY_ULX_STORE.Commands.settokens
        and ZCITY_ULX_STORE.Commands.addtokens
        and ZCITY_ULX_STORE.Commands.removetokens
end

local ZC_BOT_ID64_BASE = "76561197960265728"

-- accountID = id64 - base; valid bot ids (E1 sv_persona.lua) share the same
-- high digits as the base, so subtract only the low 10 digits (safely inside
-- double precision) instead of tonumber()-ing the full 17-digit id64 string.
local function zcBotIDDiff(id64)
    local low = 10
    local prefixA = string.sub(id64, 1, -low - 1)
    local prefixB = string.sub(ZC_BOT_ID64_BASE, 1, -low - 1)
    if prefixA ~= prefixB then return nil end
    local a = tonumber(string.sub(id64, -low))
    local b = tonumber(string.sub(ZC_BOT_ID64_BASE, -low))
    if not a or not b then return nil end
    local diff = a - b
    if diff < 0 then return nil end
    return diff
end

local function botSteamID64(ply)
    if ply:IsBot() then
        local id64 = ply:GetNWString("zcSteamID64", "")
        if id64 ~= "" then return id64 end
    end
    return ply:SteamID64()
end

local function botSteamID(ply)
    if ply:IsBot() then
        local id64 = ply:GetNWString("zcSteamID64", "")
        if id64 ~= "" then
            local diff = zcBotIDDiff(id64)
            if diff then
                local Y = diff % 2
                local Z = math.floor(diff / 2)
                return "STEAM_0:" .. Y .. ":" .. Z
            end
        end
    end
    return ply:SteamID()
end

local function addStaffULXSubmenu(menu, ply)
    if not sbBool("enable_ulx_menu", true) then return end
    if not IsValid(LocalPlayer()) or not LocalPlayer():IsAdmin() then return end
    if not IsValid(ply) then return end

    local nick = string.gsub(ply:Nick() or "unknown", "\"", "")
    local sid = botSteamID(ply) or ""
    local sid64 = botSteamID64(ply) or ""

    local staffMenu = menu:AddSubMenu("Staff / ULX")

    local tpMenu = staffMenu:AddSubMenu("Teleport")
    tpMenu:AddOption("Bring", function() runULXCommand('ulx bring "' .. nick .. '"') end)
    tpMenu:AddOption("Goto", function() runULXCommand('ulx goto "' .. nick .. '"') end)
    tpMenu:AddOption("Return", function() runULXCommand('ulx return "' .. nick .. '"') end)

    local modMenu = staffMenu:AddSubMenu("Moderation")
    modMenu:AddOption("Freeze", function() runULXCommand('ulx freeze "' .. nick .. '"') end)
    modMenu:AddOption("Unfreeze", function() runULXCommand('ulx unfreeze "' .. nick .. '"') end)
    modMenu:AddOption("Jail", function() runULXCommand('ulx jail "' .. nick .. '"') end)
    modMenu:AddOption("Unjail", function() runULXCommand('ulx unjail "' .. nick .. '"') end)
    modMenu:AddOption("Spectate", function() runULXCommand('ulx spectate "' .. nick .. '"') end)
    modMenu:AddSpacer()
    modMenu:AddOption("Slay", function()
        Derma_Query(
            "Slay " .. nick .. "?",
            "Confirm Slay",
            "Yes", function() runULXCommand('ulx slay "' .. nick .. '"') end,
            "No"
        )
    end)
    modMenu:AddOption("Kick", function()
        Derma_StringRequest(
            "Kick Player",
            "Enter kick reason for " .. nick,
            "",
            function(reason)
                reason = reason ~= "" and reason or "No reason"
                runULXCommand('ulx kick "' .. nick .. '" "' .. string.gsub(reason, '"', "'") .. '"')
            end,
            function() end,
            "Kick",
            "Cancel"
        )
    end)
    modMenu:AddOption("Ban (60m)", function()
        Derma_StringRequest(
            "Ban Player",
            "Enter ban reason for " .. nick,
            "",
            function(reason)
                reason = reason ~= "" and reason or "No reason"
                runULXCommand('ulx ban "' .. nick .. '" 60 "' .. string.gsub(reason, '"', "'") .. '"')
            end,
            function() end,
            "Ban",
            "Cancel"
        )
    end)

    if hasZCityKarmaULX() or hasZCityStoreULX() then
        local zcity = staffMenu:AddSubMenu("Z-City")

        if hasZCityKarmaULX() then
            zcity:AddOption("Set Karma", function()
                Derma_StringRequest(
                    "Set Karma",
                    "Enter karma value for " .. nick,
                    getKarma(ply) ~= nil and tostring(getKarma(ply)) or "",
                    function(value)
                        value = tonumber(value)
                        if not value then return end
                        value = math.max(0, math.floor(value))
                        runULXCommand('ulx setkarma "' .. nick .. '" ' .. value)
                    end,
                    function() end,
                    "Set",
                    "Cancel"
                )
            end)

            zcity:AddOption("Add Karma", function()
                Derma_StringRequest(
                    "Add Karma",
                    "Enter amount to add for " .. nick,
                    "10",
                    function(value)
                        value = tonumber(value)
                        if not value then return end
                        value = math.max(0, math.floor(value))
                        runULXCommand('ulx addkarma "' .. nick .. '" ' .. value)
                    end,
                    function() end,
                    "Add",
                    "Cancel"
                )
            end)

            zcity:AddOption("Remove Karma", function()
                Derma_StringRequest(
                    "Remove Karma",
                    "Enter amount to remove from " .. nick,
                    "10",
                    function(value)
                        value = tonumber(value)
                        if not value then return end
                        value = math.max(0, math.floor(value))
                        runULXCommand('ulx removekarma "' .. nick .. '" ' .. value)
                    end,
                    function() end,
                    "Remove",
                    "Cancel"
                )
            end)

            zcity:AddOption("Set Spectator", function()
                Derma_Query(
                    "Move " .. nick .. " to spectators?",
                    "Set Spectator",
                    "Yes", function() runULXCommand('ulx setspectator "' .. nick .. '"') end,
                    "No"
                )
            end)
        end

        if hasZCityStoreULX() then
            if hasZCityKarmaULX() then
                zcity:AddSpacer()
            end

            local setTokensCommand = tostring(ZCITY_ULX_STORE.Commands.settokens or "zbstoretokens")
            local addTokensCommand = tostring(ZCITY_ULX_STORE.Commands.addtokens or "zbstoreaddtokens")
            local removeTokensCommand = tostring(ZCITY_ULX_STORE.Commands.removetokens or "zbstoreremovetokens")

            zcity:AddOption("Set Tokens", function()
                Derma_StringRequest(
                    "Set Tokens",
                    "Enter token total for " .. nick,
                    tostring(ply:GetNWInt("ZCStore_Tokens", 0)),
                    function(value)
                        value = tonumber(value)
                        if not value then return end
                        value = math.max(0, math.floor(value))
                        runULXCommand('ulx ' .. setTokensCommand .. ' "' .. nick .. '" ' .. value)
                    end,
                    function() end,
                    "Set",
                    "Cancel"
                )
            end)

            zcity:AddOption("Add Tokens", function()
                Derma_StringRequest(
                    "Add Tokens",
                    "Enter token amount to add for " .. nick,
                    "10",
                    function(value)
                        value = tonumber(value)
                        if not value then return end
                        value = math.max(0, math.floor(value))
                        runULXCommand('ulx ' .. addTokensCommand .. ' "' .. nick .. '" ' .. value)
                    end,
                    function() end,
                    "Add",
                    "Cancel"
                )
            end)

            zcity:AddOption("Remove Tokens", function()
                Derma_StringRequest(
                    "Remove Tokens",
                    "Enter token amount to remove from " .. nick,
                    "10",
                    function(value)
                        value = tonumber(value)
                        if not value then return end
                        value = math.max(0, math.floor(value))
                        runULXCommand('ulx ' .. removeTokensCommand .. ' "' .. nick .. '" ' .. value)
                    end,
                    function() end,
                    "Remove",
                    "Cancel"
                )
            end)
        end
    end

    local utilMenu = staffMenu:AddSubMenu("Utility")
    utilMenu:AddOption("Copy SteamID", function() SetClipboardText(sid) end)
    utilMenu:AddOption("Copy SteamID64", function() SetClipboardText(sid64) end)

    if sbBool("enable_profile_button", true) then
        utilMenu:AddOption("Open Steam Profile", function()
            gui.OpenURL("https://steamcommunity.com/profiles/" .. sid64)
        end)
    end
end

local function createCommandButton(parent, text, x, y, w, h, sayText)
    local btn = vgui.Create("DButton", parent)
    btn:SetPos(x, y)
    btn:SetSize(w, h)
    btn:SetText("")
    btn.DoClick = function()
        RunConsoleCommand("say", sayText)
    end
    btn.Paint = function(self, pw, ph)
        surface.SetDrawColor(0, 0, 0, 180)
        surface.DrawRect(0, 0, pw, ph)
        drawOutlinedRect(0, 0, pw, ph, COL_RED, ui(2))
        draw.SimpleText(text, FONT_MED, pw * 0.5, ph * 0.5, COL_WHITE, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    return btn
end

local function createMiniButton(parent, text, x, y, w, h, fn)
    local btn = vgui.Create("DButton", parent)
    btn:SetPos(x, y)
    btn:SetSize(w, h)
    btn:SetText("")
    btn.DoClick = fn
    btn.Paint = function(self, pw, ph)
        surface.SetDrawColor(0, 0, 0, 160)
        surface.DrawRect(0, 0, pw, ph)
        drawOutlinedRect(0, 0, pw, ph, COL_RED, ui(2))
        draw.SimpleText(text, FONT_SMALL, pw * 0.5, ph * 0.5, COL_WHITE, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    return btn
end

local function makeScrollBarPretty(panel)
    local bar = panel:GetVBar()

    function bar:Paint() end
    function bar.btnUp:Paint(w, h)
        surface.SetDrawColor(0, 0, 0, 150)
        surface.DrawRect(0, 0, w, h)
        drawOutlinedRect(0, 0, w, h, COL_RED, 1)
    end
    function bar.btnDown:Paint(w, h)
        surface.SetDrawColor(0, 0, 0, 150)
        surface.DrawRect(0, 0, w, h)
        drawOutlinedRect(0, 0, w, h, COL_RED, 1)
    end
    function bar.btnGrip:Paint(w, h)
        surface.SetDrawColor(40, 40, 40, 220)
        surface.DrawRect(0, 0, w, h)
        drawOutlinedRect(0, 0, w, h, COL_RED, 1)
    end

    bar:SetWide(ui(10))
end

-- Bots draw a generated placeholder here instead of an empty AvatarImage, so
-- they read as real players on the scoreboard. Style, palette and geometry
-- come from the bot's NAME through a small local hash (never a random roll),
-- so the same name always draws the same avatar across rounds and
-- reconnects. Everything expensive (the hash walk, per-style parameters, any
-- polygon vertices) is computed once per name into BOT_AVATAR_CACHE; Paint
-- only reads that cache and issues draw calls.
local BOT_AVATAR_STYLE_COUNT = 12
local BOT_AVATAR_HUES = { 0, 30, 60, 90, 120, 150, 180, 210, 240, 270, 300, 330 }
local BOT_AVATAR_CACHE = {}
local BOT_AVATAR_CACHE_MAX = 96
local BOT_AVATAR_FALLBACK_COLOR = Color(96, 98, 108, 255)
local BOT_AVATAR_HEX_CENTERS = { { 0.30, 0.34 }, { 0.70, 0.34 }, { 0.50, 0.70 } }

-- djb2-style string hash, computed once per name -- never inside Paint.
local function botAvatarHash(name)
    local hash = 5381
    for i = 1, #name do
        hash = (hash * 33 + string.byte(name, i)) % 2147483647
    end
    if hash == 0 then hash = 104729 end
    return hash
end

-- Park-Miller multiplicative LCG (mod the Mersenne prime 2^31-1). Lua numbers
-- are doubles, exact only up to 2^53; 16807 is small enough that
-- seed * 16807 never leaves that exact range, unlike glibc-style constants.
local function botAvatarNextSeed(seed)
    return (seed * 16807) % 2147483647
end

local function botAvatarNextInt(seed, maxExclusive)
    seed = botAvatarNextSeed(seed)
    return seed, seed % maxExclusive
end

local function botAvatarUsesSilhouette(name)
    local hash = 176389
    for i = 1, #name do
        hash = (hash * 131 + string.byte(name, i)) % 2147483647
    end
    return (hash % 10) < 3 -- ~30%
end

local function botAvatarInitials(name)
    local letters = string.match(name, "^%a%a?")
    if not letters or letters == "" then
        letters = string.sub(name, 1, 1)
    end
    if letters == "" then letters = "?" end
    return string.upper(letters)
end

local function botAvatarPalette(hue)
    return {
        bg = HSVToColor(hue, 0.42, 0.30),
        primary = HSVToColor(hue, 0.70, 0.82),
        secondary = HSVToColor((hue + 36) % 360, 0.60, 0.76),
        accent = HSVToColor((hue + 200) % 360, 0.55, 0.88)
    }
end

local function botAvatarCircle(cx, cy, radius, segments)
    local points = {}
    for i = 1, segments do
        local angle = (i / segments) * math.pi * 2
        points[i] = { x = cx + math.cos(angle) * radius, y = cy + math.sin(angle) * radius }
    end
    return points
end

-- Lazily bakes w/h-dependent geometry once per record, and again only if the
-- avatar box is ever resized (a UI-scale change) -- never on every Paint.
local function botAvatarEnsureGeo(record, w, h, builder)
    if record.geo and record.geoW == w and record.geoH == h then return end
    record.geo = builder(record, w, h)
    record.geoW = w
    record.geoH = h
end

local function botAvatarParamsIdenticon(record, seed)
    local grid = {}
    for row = 0, 4 do
        for col = 0, 2 do
            local onRoll
            seed, onRoll = botAvatarNextInt(seed, 2)
            local on = onRoll == 1
            grid[row * 5 + col + 1] = on
            grid[row * 5 + (4 - col) + 1] = on
        end
    end
    record.grid = grid
end

local function botAvatarParamsRings(record, seed)
    local countRoll
    seed, countRoll = botAvatarNextInt(seed, 2)
    record.ringCount = 3 + countRoll
    local cyc = { record.palette.primary, record.palette.secondary, record.palette.accent }
    local colors = {}
    for i = 1, record.ringCount do
        colors[i] = cyc[((i - 1) % 3) + 1]
    end
    record.ringColors = colors
end

local function botAvatarParamsStripes(record, seed)
    local countRoll
    seed, countRoll = botAvatarNextInt(seed, 3)
    record.stripeCount = 4 + countRoll
    record.stripeColors = { record.palette.primary, record.palette.secondary }
end

local function botAvatarParamsFacets(record, seed)
    local rx, ry
    seed, rx = botAvatarNextInt(seed, 41)
    seed, ry = botAvatarNextInt(seed, 41)
    record.facetPointX = 0.30 + rx / 100
    record.facetPointY = 0.30 + ry / 100
    record.facetColors = {
        record.palette.primary, record.palette.secondary,
        record.palette.accent, record.palette.secondary
    }
end

local function botAvatarParamsPixelFace(record, seed)
    local gapRoll, sizeRoll, mouthRoll, openRoll, widthRoll
    seed, gapRoll = botAvatarNextInt(seed, 11)
    seed, sizeRoll = botAvatarNextInt(seed, 9)
    seed, mouthRoll = botAvatarNextInt(seed, 11)
    seed, openRoll = botAvatarNextInt(seed, 2)
    seed, widthRoll = botAvatarNextInt(seed, 21)
    record.eyeGapFrac = 0.16 + gapRoll / 100
    record.eyeSizeFrac = 0.12 + sizeRoll / 100
    record.mouthOpen = openRoll == 1
    record.mouthYFrac = 0.62 + mouthRoll / 200
    record.mouthWFrac = 0.30 + widthRoll / 100
end

local function botAvatarParamsCircuit(record, seed)
    local dirs = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
    local points = { { 0.5, 0.5 } }
    local gx, gy = 2, 2
    for _ = 1, 5 do
        local dirRoll
        seed, dirRoll = botAvatarNextInt(seed, 4)
        local dir = dirs[dirRoll + 1]
        gx = math.Clamp(gx + dir[1], 0, 4)
        gy = math.Clamp(gy + dir[2], 0, 4)
        points[#points + 1] = { gx / 4, gy / 4 }
    end
    record.tracePoints = points
end

local function botAvatarParamsStarburst(record, seed)
    local countRoll
    seed, countRoll = botAvatarNextInt(seed, 4)
    local rayCount = 7 + countRoll
    local dirs = {}
    for i = 1, rayCount do
        local jitterRoll
        seed, jitterRoll = botAvatarNextInt(seed, 21)
        local angle = (i / rayCount) * math.pi * 2 + math.rad(jitterRoll - 10)
        dirs[i] = { math.cos(angle), math.sin(angle) }
    end
    record.rayDirs = dirs
end

local function botAvatarParamsHex(record, seed)
    local cyc = { record.palette.primary, record.palette.secondary, record.palette.accent }
    local colors = {}
    for i = 1, #BOT_AVATAR_HEX_CENTERS do
        local pick
        seed, pick = botAvatarNextInt(seed, 3)
        colors[i] = cyc[pick + 1]
    end
    record.hexColors = colors
end

local function botAvatarParamsChevrons(record, seed)
    local countRoll
    seed, countRoll = botAvatarNextInt(seed, 3)
    record.chevronRows = 3 + countRoll
end

local function botAvatarParamsDots(record, seed)
    local countRoll
    seed, countRoll = botAvatarNextInt(seed, 3)
    local count = 6 + countRoll
    local dots = {}
    for i = 1, count do
        local gx, gy
        seed, gx = botAvatarNextInt(seed, 5)
        seed, gy = botAvatarNextInt(seed, 5)
        dots[i] = { (gx + 0.5) / 5, (gy + 0.5) / 5 }
    end
    record.dots = dots
end

local BOT_AVATAR_PARAM_BUILDERS = {
    [2] = botAvatarParamsIdenticon,
    [3] = botAvatarParamsRings,
    [4] = botAvatarParamsStripes,
    [5] = botAvatarParamsFacets,
    [6] = botAvatarParamsPixelFace,
    [7] = botAvatarParamsCircuit,
    [8] = botAvatarParamsStarburst,
    [9] = botAvatarParamsHex,
    [10] = botAvatarParamsChevrons,
    [11] = botAvatarParamsDots
}

local function buildBotAvatarRingsGeo(record, w, h)
    local cx, cy = w * 0.5, h * 0.5
    local maxRadius = math.min(w, h) * 0.46
    local rings = {}
    for i = 1, record.ringCount do
        rings[i] = botAvatarCircle(cx, cy, maxRadius * (i / record.ringCount), 14)
    end
    return rings
end

local function buildBotAvatarStripesGeo(record, w, h)
    local count = record.stripeCount
    local bandWidth = (w + h) / count
    local bands = {}
    for i = 0, count - 1 do
        local x = i * bandWidth - h
        bands[i + 1] = {
            { x = x, y = h },
            { x = x + h, y = 0 },
            { x = x + h + bandWidth, y = 0 },
            { x = x + bandWidth, y = h }
        }
    end
    return bands
end

local function buildBotAvatarFacetsGeo(record, w, h)
    local px, py = w * record.facetPointX, h * record.facetPointY
    local corners = { { x = 0, y = 0 }, { x = w, y = 0 }, { x = w, y = h }, { x = 0, y = h } }
    local tris = {}
    for i = 1, 4 do
        tris[i] = { { x = px, y = py }, corners[i], corners[(i % 4) + 1] }
    end
    return tris
end

local function buildBotAvatarHexGeo(record, w, h)
    local radius = math.min(w, h) * 0.30
    local hexes = {}
    for i = 1, #BOT_AVATAR_HEX_CENTERS do
        local c = BOT_AVATAR_HEX_CENTERS[i]
        hexes[i] = botAvatarCircle(c[1] * w, c[2] * h, radius, 6)
    end
    return hexes
end

local function buildBotAvatarBauhausGeo(record, w, h)
    return {
        circle = botAvatarCircle(w * 0.72, h * 0.28, math.min(w, h) * 0.20, 12),
        triangle = { { x = 0, y = h }, { x = w * 0.5, y = h * 0.5 }, { x = 0, y = h * 0.5 } }
    }
end

local function paintBotAvatarMonogram(record, w, h)
    surface.SetDrawColor(record.palette.bg)
    surface.DrawRect(0, 0, w, h)
    surface.SetDrawColor(record.palette.primary)
    surface.DrawRect(w * 0.14, h * 0.14, w * 0.72, h * 0.72)
    draw.SimpleText(record.initials, FONT_MED, w * 0.5, h * 0.5, record.palette.accent, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

local function paintBotAvatarIdenticon(record, w, h)
    surface.SetDrawColor(record.palette.bg)
    surface.DrawRect(0, 0, w, h)
    surface.SetDrawColor(record.palette.primary)
    local cellW, cellH = w / 5, h / 5
    local grid = record.grid
    for row = 0, 4 do
        local rowBase = row * 5
        for col = 0, 4 do
            if grid[rowBase + col + 1] then
                surface.DrawRect(col * cellW, row * cellH, cellW, cellH)
            end
        end
    end
end

local function paintBotAvatarRings(record, w, h)
    botAvatarEnsureGeo(record, w, h, buildBotAvatarRingsGeo)
    surface.SetDrawColor(record.palette.bg)
    surface.DrawRect(0, 0, w, h)
    draw.NoTexture()
    local rings = record.geo
    local colors = record.ringColors
    for i = #rings, 1, -1 do
        surface.SetDrawColor(colors[i])
        surface.DrawPoly(rings[i])
    end
end

local function paintBotAvatarStripes(record, w, h)
    botAvatarEnsureGeo(record, w, h, buildBotAvatarStripesGeo)
    surface.SetDrawColor(record.palette.bg)
    surface.DrawRect(0, 0, w, h)
    draw.NoTexture()
    local bands = record.geo
    local colors = record.stripeColors
    for i = 1, #bands do
        surface.SetDrawColor(colors[(i % 2) + 1])
        surface.DrawPoly(bands[i])
    end
end

local function paintBotAvatarFacets(record, w, h)
    botAvatarEnsureGeo(record, w, h, buildBotAvatarFacetsGeo)
    surface.SetDrawColor(record.palette.bg)
    surface.DrawRect(0, 0, w, h)
    draw.NoTexture()
    local tris = record.geo
    local colors = record.facetColors
    for i = 1, #tris do
        surface.SetDrawColor(colors[i])
        surface.DrawPoly(tris[i])
    end
end

local function paintBotAvatarPixelFace(record, w, h)
    surface.SetDrawColor(record.palette.bg)
    surface.DrawRect(0, 0, w, h)
    surface.SetDrawColor(record.palette.primary)
    local eyeSize = w * record.eyeSizeFrac
    local eyeY = h * 0.30
    surface.DrawRect(w * (0.5 - record.eyeGapFrac) - eyeSize * 0.5, eyeY, eyeSize, eyeSize)
    surface.DrawRect(w * (0.5 + record.eyeGapFrac) - eyeSize * 0.5, eyeY, eyeSize, eyeSize)
    surface.SetDrawColor(record.palette.accent)
    local mouthW = w * record.mouthWFrac
    local mouthH = record.mouthOpen and (h * 0.14) or (h * 0.05)
    surface.DrawRect(w * 0.5 - mouthW * 0.5, h * record.mouthYFrac, mouthW, mouthH)
end

local function paintBotAvatarCircuit(record, w, h)
    surface.SetDrawColor(record.palette.bg)
    surface.DrawRect(0, 0, w, h)
    surface.SetDrawColor(record.palette.primary)
    local points = record.tracePoints
    for i = 1, #points - 1 do
        local a, b = points[i], points[i + 1]
        surface.DrawLine(a[1] * w, a[2] * h, b[1] * w, b[2] * h)
    end
    surface.SetDrawColor(record.palette.accent)
    local nodeSize = w * 0.09
    for i = 1, #points do
        local p = points[i]
        surface.DrawRect(p[1] * w - nodeSize * 0.5, p[2] * h - nodeSize * 0.5, nodeSize, nodeSize)
    end
end

local function paintBotAvatarStarburst(record, w, h)
    surface.SetDrawColor(record.palette.bg)
    surface.DrawRect(0, 0, w, h)
    surface.SetDrawColor(record.palette.primary)
    local cx, cy = w * 0.5, h * 0.5
    local radius = math.min(w, h) * 0.44
    local dirs = record.rayDirs
    for i = 1, #dirs do
        local d = dirs[i]
        surface.DrawLine(cx, cy, cx + d[1] * radius, cy + d[2] * radius)
    end
    surface.SetDrawColor(record.palette.accent)
    local coreSize = w * 0.22
    surface.DrawRect(cx - coreSize * 0.5, cy - coreSize * 0.5, coreSize, coreSize)
end

local function paintBotAvatarHex(record, w, h)
    botAvatarEnsureGeo(record, w, h, buildBotAvatarHexGeo)
    surface.SetDrawColor(record.palette.bg)
    surface.DrawRect(0, 0, w, h)
    draw.NoTexture()
    local hexes = record.geo
    local colors = record.hexColors
    for i = 1, #hexes do
        surface.SetDrawColor(colors[i])
        surface.DrawPoly(hexes[i])
    end
end

local function paintBotAvatarChevrons(record, w, h)
    surface.SetDrawColor(record.palette.bg)
    surface.DrawRect(0, 0, w, h)
    local rows = record.chevronRows
    local rowH = h / rows
    local thickness = math.max(2, math.floor(h * 0.045))
    for i = 0, rows - 1 do
        local y0, yBase = i * rowH, i * rowH + rowH
        surface.SetDrawColor((i % 2 == 0) and record.palette.primary or record.palette.secondary)
        for t = 0, thickness - 1 do
            surface.DrawLine(0, yBase - t, w * 0.5, y0 + t)
            surface.DrawLine(w * 0.5, y0 + t, w, yBase - t)
        end
    end
end

local function paintBotAvatarDots(record, w, h)
    surface.SetDrawColor(record.palette.bg)
    surface.DrawRect(0, 0, w, h)
    local dots = record.dots
    surface.SetDrawColor(record.palette.secondary)
    for i = 1, #dots - 1 do
        local a, b = dots[i], dots[i + 1]
        surface.DrawLine(a[1] * w, a[2] * h, b[1] * w, b[2] * h)
    end
    surface.SetDrawColor(record.palette.accent)
    local dotSize = w * 0.10
    for i = 1, #dots do
        local d = dots[i]
        surface.DrawRect(d[1] * w - dotSize * 0.5, d[2] * h - dotSize * 0.5, dotSize, dotSize)
    end
end

local function paintBotAvatarBauhaus(record, w, h)
    botAvatarEnsureGeo(record, w, h, buildBotAvatarBauhausGeo)
    surface.SetDrawColor(record.palette.bg)
    surface.DrawRect(0, 0, w, h)
    surface.SetDrawColor(record.palette.primary)
    surface.DrawRect(0, 0, w * 0.5, h * 0.5)
    surface.SetDrawColor(record.palette.accent)
    surface.DrawRect(w * 0.5, h * 0.5, w * 0.5, h * 0.5)
    draw.NoTexture()
    surface.SetDrawColor(record.palette.secondary)
    surface.DrawPoly(record.geo.circle)
    surface.SetDrawColor(record.palette.accent)
    surface.DrawPoly(record.geo.triangle)
end

-- Index-aligned with BOT_AVATAR_HUES; exactly 12 entries (tests/test_scoreboard_avatars.py pins this).
local BOT_AVATAR_PAINTERS = {
    paintBotAvatarMonogram, paintBotAvatarIdenticon, paintBotAvatarRings,
    paintBotAvatarStripes, paintBotAvatarFacets, paintBotAvatarPixelFace,
    paintBotAvatarCircuit, paintBotAvatarStarburst, paintBotAvatarHex,
    paintBotAvatarChevrons, paintBotAvatarDots, paintBotAvatarBauhaus
}

local function botAvatarRecordFor(name)
    if not name or name == "" then return nil end

    local cached = BOT_AVATAR_CACHE[name]
    if cached then return cached end

    if table.Count(BOT_AVATAR_CACHE) >= BOT_AVATAR_CACHE_MAX then
        table.Empty(BOT_AVATAR_CACHE)
    end

    local seed = botAvatarHash(name)
    local styleRoll
    seed, styleRoll = botAvatarNextInt(seed, BOT_AVATAR_STYLE_COUNT)
    local style = styleRoll + 1

    local hueJitter
    seed, hueJitter = botAvatarNextInt(seed, 41)
    local hue = (BOT_AVATAR_HUES[style] + hueJitter - 20 + 360) % 360

    local record = {
        style = style,
        palette = botAvatarPalette(hue),
        initials = botAvatarInitials(name),
        silhouette = botAvatarUsesSilhouette(name)
    }

    local paramBuilder = BOT_AVATAR_PARAM_BUILDERS[style]
    if paramBuilder then paramBuilder(record, seed) end

    BOT_AVATAR_CACHE[name] = record
    return record
end

-- ~30% of bot names (hash-selected, see botAvatarUsesSilhouette) draw the
-- same default silhouette AvatarImage shows for a human with no avatar set,
-- so not every bot reads as procedurally-generated. Falls back to the
-- procedural painter if the material is missing/erroring.
local BOT_AVATAR_DEFAULT_MATERIAL
local BOT_AVATAR_DEFAULT_MATERIAL_CHECKED = false

local function botAvatarDefaultMaterial()
    if not BOT_AVATAR_DEFAULT_MATERIAL_CHECKED then
        BOT_AVATAR_DEFAULT_MATERIAL_CHECKED = true
        local ok, mat = pcall(Material, "vgui/avatar_default")
        if ok and mat and not mat:IsError() then
            BOT_AVATAR_DEFAULT_MATERIAL = mat
        end
    end
    return BOT_AVATAR_DEFAULT_MATERIAL
end

local function paintBotAvatarSilhouette(w, h)
    local mat = botAvatarDefaultMaterial()
    if not mat then return false end
    surface.SetDrawColor(255, 255, 255, 255)
    surface.SetMaterial(mat)
    surface.DrawTexturedRect(0, 0, w, h)
    return true
end

-- The one entry point the player-card Paint hook calls for a bot slot.
local function paintBotAvatar(w, h, name)
    local record = botAvatarRecordFor(name)
    if not record then
        surface.SetDrawColor(BOT_AVATAR_FALLBACK_COLOR)
        surface.DrawRect(0, 0, w, h)
        return
    end
    if record.silhouette and paintBotAvatarSilhouette(w, h) then return end
    BOT_AVATAR_PAINTERS[record.style](record, w, h)
end

local settingsFrame

local function openScoreboardSettingsMenu(initialSettings)
    if not IsValid(LocalPlayer()) or not LocalPlayer():IsAdmin() then return end

    if IsValid(settingsFrame) then
        settingsFrame:Remove()
        settingsFrame = nil
    end

    rebuildFonts(true)

    local staged = table.Copy(istable(initialSettings) and initialSettings or PATSB.Settings)
    ensureThemeTable(staged)

    local frameClass = vgui.GetControlTable("ZFrame") and "ZFrame" or "DFrame"
    settingsFrame = vgui.Create(frameClass)
    local fr = settingsFrame

    fr:SetSize(math.min(ui(1180), ScrW() * 0.84), math.min(ui(900), ScrH() * 0.9))
    fr:Center()
    fr:MakePopup()
    fr:SetKeyboardInputEnabled(true)

    if fr.SetTitle then fr:SetTitle("") end
    if fr.ShowCloseButton then fr:ShowCloseButton(false) end

    fr.Paint = function(self, w, h)
        blurPanel(self, 100)
        surface.SetDrawColor(COL_BG)
        surface.DrawRect(0, 0, w, h)
        drawOutlinedRect(0, 0, w, h, COL_RED, ui(2))
    end

    local titleBar = fr:Add("DPanel")
    titleBar:Dock(TOP)
    titleBar:SetTall(ui(56))
    titleBar.Paint = function(self, w, h)
        surface.SetDrawColor(COL_BG2)
        surface.DrawRect(0, 0, w, h)
        drawOutlinedRect(0, 0, w, h, COL_RED_SOFT, 1)
        draw.SimpleText("Scoreboard Admin", FONT_TITLE, ui(14), ui(6), COL_WHITE, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        draw.SimpleText("Admin changes apply to everyone.", FONT_SMALL, ui(16), ui(32), COL_MUTED, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    end

    local function styleTitleButton(button, label)
        button:SetText("")
        button.Paint = function(self, w, h)
            surface.SetDrawColor(0, 0, 0, 180)
            surface.DrawRect(0, 0, w, h)
            drawOutlinedRect(0, 0, w, h, self:IsHovered() and COL_RED or COL_RED_SOFT, ui(2))
            draw.SimpleText(label, FONT_SMALL, w * 0.5, h * 0.5, COL_WHITE, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    end

    local closeButton = titleBar:Add("DButton")
    closeButton:Dock(RIGHT)
    closeButton:DockMargin(0, ui(10), ui(10), ui(10))
    closeButton:SetWide(ui(36))
    styleTitleButton(closeButton, "X")
    closeButton.DoClick = function()
        fr:Remove()
    end

    local saveButton = titleBar:Add("DButton")
    saveButton:Dock(RIGHT)
    saveButton:DockMargin(0, ui(10), ui(10), ui(10))
    saveButton:SetWide(ui(132))
    styleTitleButton(saveButton, "Save Settings")
    saveButton.DoClick = function()
        net.Start("PATSB_SaveSettings")
        net.WriteString(util.TableToJSON(staged, false) or "{}")
        net.SendToServer()
        fr:Remove()
    end

    local resetButton = titleBar:Add("DButton")
    resetButton:Dock(RIGHT)
    resetButton:DockMargin(0, ui(10), ui(10), ui(10))
    resetButton:SetWide(ui(120))
    styleTitleButton(resetButton, "Reset Defaults")
    resetButton.DoClick = function()
        fr:Remove()
        openScoreboardSettingsMenu(table.Copy(PATSB.Defaults))
    end

    local sheet = fr:Add("DPropertySheet")
    sheet:Dock(FILL)
    sheet:DockMargin(ui(10), ui(10), ui(10), ui(10))
    sheet.Paint = function(self, w, h)
        surface.SetDrawColor(0, 0, 0, 85)
        surface.DrawRect(0, 0, w, h)
        drawOutlinedRect(0, 0, w, h, COL_RED_SOFT, 1)
    end
    if IsValid(sheet.tabScroller) then
        sheet.tabScroller:SetTall(ui(42))
        sheet.tabScroller:SetOverlap(0)
    end

    local function styleSheetTab(tab, label)
        tab:SetText(label)
        if tab.SetContentAlignment then
            tab:SetContentAlignment(5)
        end
        if tab.SetTextColor then
            tab:SetTextColor(Color(0, 0, 0, 0))
        end
        if tab.DockMargin then
            tab:DockMargin(0, 0, ui(6), 0)
        end
        tab.ApplySchemeSettings = function(self)
            self:SetTextInset(ui(14), ui(4))
            surface.SetFont(FONT_MED)
            local textWidth = select(1, surface.GetTextSize(label))
            self:SetSize(math.max(ui(160), textWidth + ui(56)), ui(36))
            DLabel.ApplySchemeSettings(self)
            self:SetTextStyleColor(Color(0, 0, 0, 0))
        end
        tab.PerformLayout = function(self)
            self:ApplySchemeSettings()
            if IsValid(self.Image) then
                self.Image:SetPos(ui(7), ui(3))
            end
        end
        tab.Paint = function(self, w, h)
            local active = sheet:GetActiveTab() == self
            surface.SetDrawColor(0, 0, 0, active and 220 or 160)
            surface.DrawRect(0, 0, w, h)
            drawOutlinedRect(0, 0, w, h, active and COL_RED or COL_RED_SOFT, 1)
            draw.SimpleText(label, FONT_MED, w * 0.5, h * 0.5, active and COL_WHITE or COL_MUTED, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    end

    local function createTab(label)
        local panel = vgui.Create("DScrollPanel", sheet)
        makeScrollBarPretty(panel)
        if IsValid(panel:GetCanvas()) then
            panel:GetCanvas():DockPadding(ui(12), ui(12), ui(12), ui(12))
        end

        local tabData = sheet:AddSheet(label, panel)
        styleSheetTab(tabData.Tab, label)

        return panel
    end

    local function styleTextEntry(entry)
        entry:SetFont(FONT_MED)
        entry:SetTextColor(COL_WHITE)
        entry:SetHighlightColor(COL_RED)
        entry.Paint = function(self, w, h)
            surface.SetDrawColor(COL_BG3)
            surface.DrawRect(0, 0, w, h)
            drawOutlinedRect(0, 0, w, h, self:HasFocus() and COL_RED or COL_RED_SOFT, 1)
            self:DrawTextEntryText(COL_WHITE, COL_RED, COL_WHITE)
        end
    end

    local function styleCombo(combo)
        combo:SetFont(FONT_MED)
        combo:SetTextColor(COL_WHITE)
        combo.Paint = function(self, w, h)
            surface.SetDrawColor(COL_BG3)
            surface.DrawRect(0, 0, w, h)
            drawOutlinedRect(0, 0, w, h, self:IsMenuOpen() and COL_RED or COL_RED_SOFT, 1)
            draw.SimpleText(self:GetValue() or "", FONT_MED, ui(10), h * 0.5, COL_WHITE, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end

        if IsValid(combo.DropButton) then
            combo.DropButton:SetText("")
            combo.DropButton.Paint = function(self, w, h)
                draw.SimpleText("v", FONT_SMALL, w * 0.5, h * 0.5, COL_WHITE, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
        end
    end

    local function stagedThemeColor(key)
        return themeColorData(staged.theme and staged.theme[key], PATSB.ThemeDefaults[key])
    end

    local function addSectionHeader(parent, title, subtitle)
        local header = parent:Add("DPanel")
        header:Dock(TOP)
        header:DockMargin(0, 0, 0, ui(10))
        header:SetTall(subtitle and ui(52) or ui(30))
        header.Paint = nil

        local titleLabel = header:Add("DLabel")
        titleLabel:Dock(TOP)
        titleLabel:SetTall(ui(24))
        titleLabel:SetFont(FONT_HEADER)
        titleLabel:SetText(title)
        titleLabel:SetTextColor(COL_WHITE)
        titleLabel:SetContentAlignment(4)

        if subtitle then
            local subtitleLabel = header:Add("DLabel")
            subtitleLabel:Dock(TOP)
            subtitleLabel:SetTall(ui(18))
            subtitleLabel:SetFont(FONT_SMALL)
            subtitleLabel:SetText(subtitle)
            subtitleLabel:SetTextColor(COL_MUTED)
            subtitleLabel:SetContentAlignment(4)
        end
    end

    local function addFieldBlock(parent, labelText, opts)
        opts = opts or {}

        local block = parent:Add("DPanel")
        block:Dock(TOP)
        block:DockMargin(0, 0, 0, ui(10))
        block:SetTall(opts.height or ui(58))
        block.Paint = function(self, w, h)
            surface.SetDrawColor(COL_BG2)
            surface.DrawRect(0, 0, w, h)
            drawOutlinedRect(0, 0, w, h, COL_RED_SOFT, 1)
        end

        local label = block:Add("DLabel")
        label:Dock(TOP)
        label:DockMargin(ui(10), ui(8), ui(10), ui(4))
        label:SetTall(ui(16))
        label:SetFont(FONT_SMALL)
        label:SetText(labelText)
        label:SetTextColor(COL_WHITE)
        label:SetContentAlignment(4)

        return block, label
    end

    local function addTextEntry(parent, labelText, key, opts)
        opts = opts or {}
        local block = addFieldBlock(parent, labelText, { height = opts.multiline and ui(104) or ui(58) })
        local entry = block:Add("DTextEntry")
        entry:Dock(FILL)
        entry:DockMargin(ui(10), 0, ui(10), ui(8))
        entry:SetText(tostring(staged[key] or ""))
        entry:SetUpdateOnType(true)
        entry:SetMultiline(opts.multiline == true)
        if opts.numeric then
            entry:SetNumeric(true)
        end
        styleTextEntry(entry)
        entry.OnValueChange = function(self, val)
            staged[key] = val
        end

        return entry
    end

    local function addCheck(parent, labelText, key)
        local block = parent:Add("DPanel")
        block:Dock(TOP)
        block:DockMargin(0, 0, 0, ui(10))
        block:SetTall(ui(38))
        block.Paint = function(self, w, h)
            surface.SetDrawColor(COL_BG2)
            surface.DrawRect(0, 0, w, h)
            drawOutlinedRect(0, 0, w, h, COL_RED_SOFT, 1)
        end

        local label = block:Add("DLabel")
        label:Dock(FILL)
        label:DockMargin(ui(10), 0, ui(10), 0)
        label:SetFont(FONT_MED)
        label:SetText(labelText)
        label:SetTextColor(COL_WHITE)
        label:SetContentAlignment(4)

        local checkbox = block:Add("DCheckBox")
        checkbox:Dock(RIGHT)
        checkbox:DockMargin(0, ui(8), ui(10), ui(8))
        checkbox:SetWide(ui(22))
        checkbox:SetChecked(staged[key] and true or false)
        checkbox.Paint = function(self, w, h)
            surface.SetDrawColor(COL_BG3)
            surface.DrawRect(0, 0, w, h)
            drawOutlinedRect(0, 0, w, h, self:GetChecked() and COL_RED or COL_RED_SOFT, 1)
            if self:GetChecked() then
                surface.SetDrawColor(COL_RED)
                surface.DrawRect(ui(4), ui(4), w - ui(8), h - ui(8))
            end
        end
        checkbox.OnChange = function(_, val)
            staged[key] = val and true or false
        end
    end

    local function addCombo(parent, labelText, key, choices)
        local block = addFieldBlock(parent, labelText)
        local combo = block:Add("DComboBox")
        combo:Dock(FILL)
        combo:DockMargin(ui(10), 0, ui(10), ui(8))
        for _, choice in ipairs(choices or {}) do
            combo:AddChoice(choice)
        end
        combo:SetValue(tostring(staged[key] or choices[1] or ""))
        styleCombo(combo)
        combo.OnSelect = function(_, _, value)
            staged[key] = value
        end

        return combo
    end

    local generalPanel = createTab("General")
    addSectionHeader(generalPanel, "Core", "High-level behavior and font setup.")
    addTextEntry(generalPanel, "Refresh interval (0.25 - 5)", "refresh_interval", { numeric = true })
    addTextEntry(generalPanel, "Blur strength (0 - 10)", "blur_strength", { numeric = true })
    addTextEntry(generalPanel, "UI scale multiplier (0.75 - 1.50)", "ui_scale_mul", { numeric = true })
    addSectionHeader(generalPanel, "Fonts", "These rebuild after save when the server syncs settings back.")
    addTextEntry(generalPanel, "Title font", "font_title")
    addTextEntry(generalPanel, "Body font", "font_body")

    local layoutPanel = createTab("Layout")
    addSectionHeader(layoutPanel, "Window Size", "Scoreboard frame bounds for all clients.")
    addTextEntry(layoutPanel, "Frame width (1000 - 1800)", "frame_width", { numeric = true })
    addTextEntry(layoutPanel, "Frame height (700 - 1100)", "frame_height", { numeric = true })
    addSectionHeader(layoutPanel, "Sidebar", "Left-side summary panel sizing.")
    addTextEntry(layoutPanel, "Sidebar min width (220 - 500)", "sidebar_width_min", { numeric = true })
    addTextEntry(layoutPanel, "Sidebar max width (260 - 600)", "sidebar_width_max", { numeric = true })
    addTextEntry(layoutPanel, "Sidebar width fraction (0.15 - 0.40)", "sidebar_width_frac", { numeric = true })

    local featuresPanel = createTab("Features")
    addSectionHeader(featuresPanel, "Visibility", "Toggle what players can see and interact with.")
    addCheck(featuresPanel, "Enable ULX menu", "enable_ulx_menu")
    addCheck(featuresPanel, "Enable Steam profile button", "enable_profile_button")
    addCheck(featuresPanel, "Show spectators", "show_spectators")
    addCheck(featuresPanel, "Show karma", "show_karma")
    addCheck(featuresPanel, "Show session time", "show_session")
    addCheck(featuresPanel, "Show total playtime", "show_playtime")
    addCheck(featuresPanel, "Show tickrate", "show_tickrate")
    addCheck(featuresPanel, "Show ULX ranks", "show_ulx_ranks")
    addCheck(featuresPanel, "Show per-player voice buttons", "show_voice_buttons")
    addCheck(featuresPanel, "Show mute buttons", "show_bottom_mute_buttons")
    addCheck(featuresPanel, "Show spectate/join button", "show_team_button")

    local commandsPanel = createTab("Commands")
    addSectionHeader(commandsPanel, "Bottom Bar Buttons", "Configure the two custom command buttons on the scoreboard.")
    addCheck(commandsPanel, "Enable command button 1", "command_1_enabled")
    addTextEntry(commandsPanel, "Command 1 text", "command_1_text")
    addTextEntry(commandsPanel, "Command 1 say", "command_1_say")
    addCheck(commandsPanel, "Enable command button 2", "command_2_enabled")
    addTextEntry(commandsPanel, "Command 2 text", "command_2_text")
    addTextEntry(commandsPanel, "Command 2 say", "command_2_say")

    local themePanel = vgui.Create("DPanel", sheet)
    themePanel:Dock(FILL)
    themePanel.Paint = nil
    local themeTab = sheet:AddSheet("Theme", themePanel)
    styleSheetTab(themeTab.Tab, "Theme")

    local themeList = themePanel:Add("DScrollPanel")
    themeList:Dock(LEFT)
    themeList:SetWide(ui(220))
    themeList:DockMargin(0, 0, ui(10), 0)
    makeScrollBarPretty(themeList)

    local themeRight = themePanel:Add("DPanel")
    themeRight:Dock(FILL)
    themeRight.Paint = nil

    local themePreview = themeRight:Add("DPanel")
    themePreview:Dock(TOP)
    themePreview:SetTall(ui(180))
    themePreview:DockMargin(0, 0, 0, ui(10))
    themePreview.Paint = function(self, w, h)
        local bg = stagedThemeColor("bg")
        local bg2 = stagedThemeColor("bg2")
        local bg3 = stagedThemeColor("bg3")
        local accent = stagedThemeColor("accent")
        local accentSoft = stagedThemeColor("accent_soft")
        local white = stagedThemeColor("white")
        local muted = stagedThemeColor("muted")
        local teamT = stagedThemeColor("team_t")

        surface.SetDrawColor(bg)
        surface.DrawRect(0, 0, w, h)
        drawOutlinedRect(0, 0, w, h, accent, ui(2))

        surface.SetDrawColor(bg2)
        surface.DrawRect(ui(12), ui(12), w - ui(24), ui(44))
        drawOutlinedRect(ui(12), ui(12), w - ui(24), ui(44), accentSoft, 1)
        draw.SimpleText(GetHostName() or "ZBattle", FONT_HEADER, w * 0.5, ui(24), white, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)

        surface.SetDrawColor(bg2)
        surface.DrawRect(ui(12), ui(68), w - ui(24), ui(88))
        surface.SetDrawColor(bg3)
        surface.DrawRect(ui(12), ui(112), w - ui(24), ui(44))
        surface.SetDrawColor(teamT)
        surface.DrawRect(ui(12), ui(68), ui(6), ui(88))
        drawOutlinedRect(ui(12), ui(68), w - ui(24), ui(88), accentSoft, 1)

        draw.SimpleText("Sample Player", FONT_MED, ui(32), ui(78), white, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        draw.SimpleText("Admin", FONT_SMALL, ui(32), ui(100), muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        draw.SimpleText("Karma", FONT_SMALL, w - ui(170), ui(78), muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        draw.SimpleText("100", FONT_MED, w - ui(170), ui(100), white, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    end

    local themeMixer = themeRight:Add("DColorMixer")
    themeMixer:Dock(FILL)
    themeMixer:SetPalette(true)
    themeMixer:SetAlphaBar(true)
    themeMixer:SetWangs(true)

    local selectedThemeKey = THEME_KEYS[1]
    local selectedThemeButtons = {}

    local function syncThemeMixer()
        themeMixer:SetColor(stagedThemeColor(selectedThemeKey))
    end

    local function refreshThemeButtons()
        for key, button in pairs(selectedThemeButtons) do
            if IsValid(button) then
                button:InvalidateLayout(true)
            end
        end
        themePreview:InvalidateLayout(true)
    end

    for _, key in ipairs(THEME_KEYS) do
        local button = themeList:Add("DButton")
        selectedThemeButtons[key] = button
        button:Dock(TOP)
        button:SetTall(ui(34))
        button:DockMargin(0, 0, 0, ui(6))
        button:SetText("")
        button.Paint = function(self, w, h)
            local colorValue = stagedThemeColor(key)
            surface.SetDrawColor(25, 25, 25, 220)
            surface.DrawRect(0, 0, w, h)
            drawOutlinedRect(0, 0, w, h, key == selectedThemeKey and stagedThemeColor("accent") or stagedThemeColor("accent_soft"), 1)
            surface.SetDrawColor(colorValue)
            surface.DrawRect(ui(8), ui(8), ui(18), h - ui(16))
            draw.SimpleText(THEME_LABELS[key] or key, FONT_SMALL, ui(34), h * 0.5, stagedThemeColor("white"), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
        button.DoClick = function()
            selectedThemeKey = key
            syncThemeMixer()
            refreshThemeButtons()
        end
    end

    themeMixer.ValueChanged = function(_, value)
        if not selectedThemeKey then return end

        staged.theme[selectedThemeKey] = {
            r = math.floor(value.r or 255),
            g = math.floor(value.g or 255),
            b = math.floor(value.b or 255),
            a = math.floor(value.a or 255)
        }

        refreshThemeButtons()
    end

    syncThemeMixer()
end


local S=ZCScoreboard
S.Services={Bool=sbBool,Int=sbInt,Float=sbFloat,String=sbString,Scale=ui,
 Karma=getKarma,Rank=getUserGroupText,Session=getSessionTimeText,Playtime=getPlaytimeText,
 PlaySeconds=getPlaytimeSeconds,RoundState=getRoundStateText,Clock=getTimeText,
 Voice=openVoiceControls,VoiceAllowed=canAdjustVoice,ApplyVoice=applyVoiceState,
 Volume=volumeFor,Muted=isStoredMuted,Staff=addStaffULXSubmenu,
 Blur=blurPanel,BotAvatar=paintBotAvatar,Settings=openScoreboardSettingsMenu,
 SteamID64 = botSteamID64, SteamID = botSteamID,
 SetFrame=function(frame)scoreBoardMenu=frame end,
 Fonts=function()rebuildFonts(true)end,
 CloseAuxiliary=function()if IsValid(settingsFrame)then settingsFrame:Remove()end;if IsValid(PATSB.VoiceFrame)then PATSB.VoiceFrame:Remove()end end,
 Colors=function()return {bg=COL_BG,card=COL_BG2,hover=COL_BG3,text=COL_WHITE,muted=COL_MUTED,accent=COL_RED}end}
net.Receive("PATSB_SendSettings",function()
 local data=util.JSONToTable(net.ReadString());if not istable(data)then return end
 PATSB.Settings=table.Copy(PATSB.Defaults)
 for k,v in pairs(data)do if PATSB.Defaults[k]~=nil then PATSB.Settings[k]=v end end
 ensureThemeTable(PATSB.Settings);applyThemeColors();rebuildFonts(true)
 if S.Rebuild then S.Rebuild()end
end)
