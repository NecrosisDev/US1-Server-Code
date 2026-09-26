if CLIENT then return end

local hadPlaytimeCache = PATSB and istable(PATSB.PlaytimeData)

PATSB = PATSB or {}
PATSB.SettingsFile = "pat_scoreboard_shared.json"
PATSB.PlaytimeFile = "pat_scoreboard_playtime.json"

util.AddNetworkString("PATSB_RequestSettings")
util.AddNetworkString("PATSB_SendSettings")
util.AddNetworkString("PATSB_SaveSettings")

local function colorData(r, g, b, a)
    return {
        r = r,
        g = g,
        b = b,
        a = a or 255
    }
end

PATSB.ThemeDefaults = {
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

PATSB.Defaults = {
    refresh_interval = 1,
    enable_ulx_menu = true,
    enable_profile_button = true,
    show_spectators = true,
    show_karma = true,
    show_session = true,
    show_playtime = false,
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
    font_title = "Tahoma",
    font_body = "Tahoma",
    ui_scale_mul = 1,
    theme = table.Copy(PATSB.ThemeDefaults)
}

PATSB.Settings = table.Copy(PATSB.Defaults)
PATSB.PlaytimeData = PATSB.PlaytimeData or {}

local function sanitizeString(v, fallback, maxLen)
    v = tostring(v or fallback or "")
    v = string.Trim(v)
    if maxLen and #v > maxLen then
        v = string.sub(v, 1, maxLen)
    end
    if v == "" then
        return fallback or ""
    end
    return v
end

local function sanitizeBool(v, fallback)
    if isbool(v) then return v end
    if v == 1 or v == "1" or v == "true" then return true end
    if v == 0 or v == "0" or v == "false" then return false end
    return fallback and true or false
end

local function sanitizeNumber(v, fallback, minv, maxv, decimals)
    v = tonumber(v)
    if not v or v ~= v or math.abs(v) == math.huge then v = fallback or 0 end
    if minv then v = math.max(v, minv) end
    if maxv then v = math.min(v, maxv) end
    if decimals and decimals > 0 then
        v = math.Round(v, decimals)
    else
        v = math.Round(v)
    end
    return v
end

function PATSB:NormalizeSettings(incoming)
    local out = table.Copy(self.Defaults)
    incoming = istable(incoming) and incoming or {}

    out.refresh_interval = sanitizeNumber(incoming.refresh_interval, out.refresh_interval, 0.25, 5, 2)
    out.enable_ulx_menu = sanitizeBool(incoming.enable_ulx_menu, out.enable_ulx_menu)
    out.enable_profile_button = sanitizeBool(incoming.enable_profile_button, out.enable_profile_button)
    out.show_spectators = sanitizeBool(incoming.show_spectators, out.show_spectators)
    out.show_karma = sanitizeBool(incoming.show_karma, out.show_karma)
    out.show_session = sanitizeBool(incoming.show_session, out.show_session)
    out.show_playtime = sanitizeBool(incoming.show_playtime, out.show_playtime)
    out.show_tickrate = sanitizeBool(incoming.show_tickrate, out.show_tickrate)
    out.show_ulx_ranks = sanitizeBool(incoming.show_ulx_ranks, out.show_ulx_ranks)
    out.show_voice_buttons = sanitizeBool(incoming.show_voice_buttons, out.show_voice_buttons)
    out.show_bottom_mute_buttons = sanitizeBool(incoming.show_bottom_mute_buttons, out.show_bottom_mute_buttons)
    out.show_team_button = sanitizeBool(incoming.show_team_button, out.show_team_button)

    out.blur_strength = sanitizeNumber(incoming.blur_strength, out.blur_strength, 0, 10, 0)
    out.frame_width = sanitizeNumber(incoming.frame_width, out.frame_width, 1000, 1800, 0)
    out.frame_height = sanitizeNumber(incoming.frame_height, out.frame_height, 700, 1100, 0)
    out.sidebar_width_min = sanitizeNumber(incoming.sidebar_width_min, out.sidebar_width_min, 220, 500, 0)
    out.sidebar_width_max = sanitizeNumber(incoming.sidebar_width_max, out.sidebar_width_max, 260, 600, 0)
    out.sidebar_width_frac = sanitizeNumber(incoming.sidebar_width_frac, out.sidebar_width_frac, 0.15, 0.40, 2)

    if out.sidebar_width_min > out.sidebar_width_max then
        out.sidebar_width_min, out.sidebar_width_max = out.sidebar_width_max, out.sidebar_width_min
    end

    out.command_1_enabled = sanitizeBool(incoming.command_1_enabled, out.command_1_enabled)
    out.command_1_text = sanitizeString(incoming.command_1_text, out.command_1_text, 32)
    out.command_1_say = sanitizeString(incoming.command_1_say, out.command_1_say, 64)

    out.command_2_enabled = sanitizeBool(incoming.command_2_enabled, out.command_2_enabled)
    out.command_2_text = sanitizeString(incoming.command_2_text, out.command_2_text, 32)
    out.command_2_say = sanitizeString(incoming.command_2_say, out.command_2_say, 64)

    out.font_title = sanitizeString(incoming.font_title, out.font_title, 64)
    out.font_body = sanitizeString(incoming.font_body, out.font_body, 64)
    out.ui_scale_mul = sanitizeNumber(incoming.ui_scale_mul, out.ui_scale_mul, 0.75, 1.50, 2)

    local incomingTheme = istable(incoming.theme) and incoming.theme or {}
    out.theme = table.Copy(self.ThemeDefaults)
    for key, defaults in pairs(self.ThemeDefaults) do
        local value = istable(incomingTheme[key]) and incomingTheme[key] or {}
        out.theme[key] = {
            r = sanitizeNumber(value.r, defaults.r, 0, 255, 0),
            g = sanitizeNumber(value.g, defaults.g, 0, 255, 0),
            b = sanitizeNumber(value.b, defaults.b, 0, 255, 0),
            a = sanitizeNumber(value.a, defaults.a, 0, 255, 0)
        }
    end

    return out
end

function PATSB:LoadSettings()
    local raw = file.Read(self.SettingsFile, "DATA")
    if not raw or raw == "" then
        self.Settings = table.Copy(self.Defaults)
        return
    end

    local data = util.JSONToTable(raw)
    self.Settings = self:NormalizeSettings(data)
end

function PATSB:SaveSettings()
    file.Write(self.SettingsFile, util.TableToJSON(self.Settings, true))
end

function PATSB:LoadPlaytimeData()
    local raw = file.Read(self.PlaytimeFile, "DATA")
    if not raw or raw == "" then
        self.PlaytimeData = {}
        return
    end

    local data = util.JSONToTable(raw)
    self.PlaytimeData = istable(data) and data or {}
end

function PATSB:SavePlaytimeData()
    file.Write(self.PlaytimeFile, util.TableToJSON(self.PlaytimeData or {}, true))
end

function PATSB:BroadcastSettings(target)
    local json = util.TableToJSON(self.Settings, false) or "{}"

    net.Start("PATSB_SendSettings")
    net.WriteString(json)

    if IsValid(target) then
        net.Send(target)
    else
        net.Broadcast()
    end
end

PATSB:LoadSettings()
if not hadPlaytimeCache then PATSB:LoadPlaytimeData() end

net.Receive("PATSB_RequestSettings", function(bits, ply)
    if not IsValid(ply) then return end
    if bits > 32 or (ply.ZCSBNextRequest or 0) > CurTime() then return end
    ply.ZCSBNextRequest = CurTime() + 2
    PATSB:BroadcastSettings(ply)
end)

net.Receive("PATSB_SaveSettings", function(bits, ply)
    if not IsValid(ply) or not ply:IsAdmin() then return end

    if bits > 131072 or (ply.ZCSBNextSave or 0) > CurTime() then return end
    ply.ZCSBNextSave = CurTime() + 1
    local raw = net.ReadString()
    local incoming = util.JSONToTable(raw)
    if not istable(incoming) then return end

    PATSB.Settings = PATSB:NormalizeSettings(incoming)
    PATSB:SaveSettings()
    PATSB:BroadcastSettings()

    print("[PATSB] Settings updated by " .. ply:Nick())
end)
