-- GoobOS Staff app (UI cohesion U5, 2026-09-26): one staff-only app listing every admin tool, gated by ULX access.
-- The server (zc_goobos/sv_staff.lua, net "GoobOS.Staff.Rights") says which tools this player may use and the ULX right
-- each one needs. The app is registered only while that list is not empty, so a player without staff rights never sees
-- it. Every tile runs the tool's existing console or ULX command (shown on the tile, so the command stays learnable):
-- nothing is re-implemented here, and every tool still checks its right on the server.
if not CLIENT then return end
ZCGoobApps = ZCGoobApps or {}
local A = ZCGoobApps
if not A.Register then return end
local T = A.Theme

-- Survives autorefresh: the last rights list stays until the server sends a new one.
local St = A.Staff or {allowed = {}, known = false, shown = false}
A.Staff = St
St.NetName = "GoobOS.Staff.Rights"

function St.Has(id) return St.allowed[id] ~= nil end

-- Tile glyph: the kit has none for staff, so it is added the way donate.lua added "heart", only when missing.
local K0 = A.Kit
if K0 and K0.Glyphs and not K0.Glyphs.shield then
    K0.Glyphs.shield = {{"c", 12, 2.5, 19.5, 5.5, 19.5, 11.5, 18.2, 15.5, 15.5, 18.8, 12, 21.5, 8.5, 18.8, 5.8, 15.5, 4.5, 11.5, 4.5, 5.5}, {"l", 8.5, 12, 11, 14.5, 15.5, 9.5}}
end
if K0 and K0.IconsV2 and K0.IconsV2.Defs and not K0.IconsV2.Defs.shield then
    K0.IconsV2.Defs.shield = {{"L", {"pg", 12, 2.5, 19.5, 5.5, 19.5, 11.5, 18.2, 15.5, 15.5, 18.8, 12, 21.5, 8.5, 18.8, 5.8, 15.5, 4.5, 11.5, 4.5, 5.5}}, {"s", 8.5, 12, 11, 14.5, 15.5, 9.5}}
end

local function command(...)
    local args = {...}
    return function() RunConsoleCommand(unpack(args)) end
end

-- Tiles, in order. id = the server's tool id (sv_staff.lua S.Tools). run = the existing command; page = an in-app page.
-- public tools need no right (shown to anyone who has the app) and only while `available` says the command exists.
St.Tools = {
    {id = "guilt", title = "Guilt admin", body = "Guilt rules, punish presets and the guilt menu colours.", command = "!guiltadmin", glyph = "flag", run = command("ulx", "guiltadmin")},
    {id = "logs", title = "Command log", body = "Seven days of ULX commands and the punishment history.", command = "ulx_logs_open  ·  !logs", glyph = "news", run = command("ulx_logs_open")},
    {id = "restart", title = "Restart warning", body = "Schedule a maintenance restart with a reason, or cancel one.", command = "!restart  ·  !restartcancel", glyph = "refresh", page = "restart"},
    {id = "killzones", title = "Kill zones", body = "Mark, list and clear this map's kill zones.", command = "zkill_menu", glyph = "grid", run = command("zkill_menu")},
    {id = "pprops", title = "Persistent props", body = "Props that respawn on this map every round.", command = "!pprops", glyph = "diamond", run = command("ulx", "persistentpropsmenu")},
    {id = "watchdog", title = "Watchdog", body = "Live suspicion, dossiers and detection modules.", command = "wd", glyph = "pulse", run = command("wd")},
    {id = "traitor", title = "Traitor admin", body = "Roles, reinforcements, rotations, spawns and events.", command = "traitor_admin  ·  F8", glyph = "dice", run = command("traitor_admin")},
    {id = "playertools", title = "Player tools", body = "Crusher, super crusher, torso and your own context actions.", command = "zc_selfmenu", glyph = "shirt", page = "playertools"},
    {id = "spectate", title = "Spectate tools", body = "The Afterlife spectator panel.", command = "zc_observer", glyph = "ghost", public = true, run = command("zc_observer"),
        available = function() return concommand.GetTable().zc_observer ~= nil end}
}

function St.Request()
    if util.NetworkStringToID(St.NetName) == 0 then return end -- a server without sv_staff.lua
    local now = RealTime()
    if now < (St.NextAsk or 0) then return end
    St.NextAsk = now + 3
    net.Start(St.NetName)
    net.SendToServer()
end

-- The tiles this player may use right now.
function St.Rows()
    local rows = {}
    for _, tool in ipairs(St.Tools) do
        local right = St.allowed[tool.id]
        if (right or tool.public) and (not tool.available or tool.available()) then rows[#rows + 1] = {tool = tool, right = right} end
    end
    return rows
end

-- UI ------------------------------------------------------------------------------------------

local REASON_MAX = 140 -- restart_warning's R.CleanReason limit

local function closePhone(phone)
    if IsValid(phone) and phone.SetActive then phone:SetActive(false) end
end

-- One printable line for a console argument (quotes would end the argument early).
local function cleanReason(text)
    text = string.gsub(tostring(text or ""), "[%c\"]", " ")
    text = string.gsub(text, "%s+", " ")
    return string.match(text, "^%s*(.-)%s*$") or ""
end

-- Restart warning page: the existing ULX commands (`ulx restart <when> <reason>`, `ulx restart cancel`, status), which
-- check "ulx restart" and write the ULX log themselves.
local function restartPage(parent)
    local K = A.Kit
    local sheet, shade = K.Sheet(parent, math.min(parent:GetTall(), 318), true)
    local head = K.Panel(sheet)
    head:Dock(TOP)
    head:SetTall(42)
    head.Paint = function(_, w)
        K.Text("Restart warning", 18, 700, 0, 0, T.text)
        K.Text(K.Fit("Players see the countdown for the last 15 minutes.", K.Font(12, 500), w), 12, 500, 0, 23, T.muted)
    end
    local minutes = A.Entry(sheet, "Minutes from now (1 - 10080)", "")
    minutes:SetNumeric(true)
    local reason = A.Entry(sheet, "Reason players see (optional)", "")
    local function count()
        local n = tonumber(minutes:GetValue())
        if n and n == math.floor(n) and n >= 1 and n <= 10080 then return n end
    end
    local function reasonText()
        local text = cleanReason(reason:GetValue())
        return text, (utf8.len(text) or #text) <= REASON_MAX
    end
    K.Button(sheet, {
        kind = "primary",
        label = function()
            local _, fits = reasonText()
            if not fits then return "Reason is over " .. REASON_MAX .. " characters" end
            local n = count()
            return n and ("Schedule restart in " .. n .. " min") or "Schedule restart"
        end,
        enabled = function()
            local _, fits = reasonText()
            return count() ~= nil and fits
        end,
        click = function()
            local n, text = count(), reasonText()
            K.Modal(shade, "Restart the server in " .. n .. " min?", text ~= "" and text or "No reason given.", {
                {"Cancel"},
                {"Schedule", function()
                    if text ~= "" then RunConsoleCommand("ulx", "restart", n .. "m", text) else RunConsoleCommand("ulx", "restart", n .. "m") end
                    shade:Close()
                end, primary = true}
            })
        end
    })
    K.Button(sheet, {kind = "danger", label = "Cancel the pending restart", click = function()
        RunConsoleCommand("ulx", "restart", "cancel")
        shade:Close()
    end})
    K.Button(sheet, {kind = "quiet", label = "Show the schedule in chat", click = function() RunConsoleCommand("ulx", "restart") end})
end

-- Player tools page: the self menu's list (autorun/client/cl_zc_selfmenu.lua), whose relay the server gates with
-- "zc staff playertools".
local function playerToolsPage(parent)
    local K = A.Kit
    local sheet = K.Sheet(parent, math.floor(parent:GetTall() * 0.92), true)
    local head = K.Panel(sheet)
    head:Dock(TOP)
    head:SetTall(42)
    head.Paint = function(_, w)
        K.Text("Player tools", 18, 700, 0, 0, T.text)
        K.Text(K.Fit("On yourself. The server checks every action.", K.Font(12, 500), w), 12, 500, 0, 23, T.muted)
    end
    local UI = ZCSelfMenuUI
    if not (UI and UI.Build and UI.Build(sheet)) then
        K.EmptyState(sheet, "empty", "Player tools are unavailable", "The self menu did not load on this client.")
    end
end

local function build(body, phone)
    local K = A.Kit
    if not K then
        A.Status(body, "GoobOS kit failed to load; try reopening the phone.")
        return
    end
    St.Request()
    local S = K.Scaler(1)
    local rows = St.Rows()
    local list = K.List(body, {
        rowHeight = 72,
        gap = 8,
        count = function() return #rows end,
        build = function(row)
            local b = vgui.Create("DButton", row)
            b:SetText("")
            b:Dock(FILL)
            b.DoClick = function(s)
                local tool = s.Entry and s.Entry.tool
                if not tool then return end
                if tool.page == "restart" then
                    restartPage(body)
                elseif tool.page == "playertools" then
                    playerToolsPage(body)
                elseif tool.run then
                    tool.run()
                    closePhone(phone) -- each of these opens its own window
                end
            end
            b.Paint = function(s, w, h)
                local entry = s.Entry
                if not entry then return end
                local tool, hover = entry.tool, K.Hover(s)
                K.Card(0, 0, w, h, T.cardGlass, K.Alpha(T.edge, 180))
                if hover > 0.01 then draw.RoundedBox(4, 1, 1, w - 2, h - 2, K.Alpha(T.white, 10 * hover)) end
                draw.RoundedBox(4, 10, 12, 32, 32, T.main)
                K.Glyph(tool.glyph, 26, 28, 16, T.white)
                local x = 54
                local chip = entry.right and S.chip(entry.right, w - 10, 9, T.muted, nil, TEXT_ALIGN_RIGHT) + 8 or 0
                K.Text(K.Fit(tool.title, K.Font(15, 600), w - x - 10 - chip), 15, 600, x, 9, T.text)
                K.Text(K.Fit(tool.body, K.Font(13, 500), w - x - 10), 13, 500, x, 30, T.muted)
                K.Text(K.Fit(tool.command, K.Font(11, 600), w - x - 10), 11, 600, x, 51, K.Alpha(T.muted, 190))
            end
            row.Btn = b
        end,
        fill = function(row, index)
            local entry = rows[index]
            row.Btn.Entry = entry
            row.Btn:SetCursor(entry and "hand" or "arrow")
            row.Btn:SetTooltip(entry and entry.right and ("Needs the ULX right \"" .. entry.right .. "\"") or false)
        end
    })
    list:Dock(FILL)
    -- A new rights list (group change) re-reads the tiles in place.
    list.GoobSeen = St.Revision
    local think = list.Think
    list.Think = function(s)
        if s.GoobSeen ~= St.Revision then
            s.GoobSeen = St.Revision
            rows = St.Rows()
            s:Refresh()
        end
        think(s)
    end
end

-- Registration --------------------------------------------------------------------------------

local function rebuildHome(visible)
    local phone = hg and hg.chat
    if not IsValid(phone) or phone.GoobAppsVersion ~= A.Version or not phone.phoneHome then return end
    if not visible and phone.phonePage == "staff" and phone.SetPhonePage then phone:SetPhonePage("home") end
    A.BuildHome(phone, phone.phoneHome)
    A.Layout(phone, phone:GetWide(), phone:GetTall())
end

-- Register the app while the player has a staff right, unregister it otherwise; rebuild the launcher when that flips.
function St.Apply()
    local visible = next(St.allowed) ~= nil
    if visible then
        A.HomeGlyphs = A.HomeGlyphs or {}
        A.HomeGlyphs.staff = "shield"
        A.Register("staff", "Staff", "Admin tools for your rights", "icon16/shield.png", T.main, build)
    else
        A.Registry.staff = nil
    end
    if visible ~= St.shown then
        St.shown = visible
        rebuildHome(visible)
    end
end

net.Receive(St.NetName, function()
    local count = net.ReadUInt(5)
    local allowed = {}
    for _ = 1, count do
        local id, right = net.ReadString(), net.ReadString()
        if id ~= "" and right ~= "" then allowed[id] = right end
    end
    St.allowed, St.known = allowed, true
    St.Revision = (St.Revision or 0) + 1
    St.Apply()
end)

St.Apply() -- autorefresh keeps the last list; a fresh client starts hidden
if IsValid(LocalPlayer()) then St.Request() end
hook.Add("InitPostEntity", "US1.Staff.Request", St.Request)

concommand.Add("zc_staff", function()
    if A.Launch("staff") then return end
    St.Request()
    print(St.known and "[Staff] You have no staff tools on this server." or "[Staff] Checking your staff rights; try again in a moment.")
end, nil, "Open the GoobOS Staff app: every staff tool your ULX rights allow (same as 'goobos staff').")
