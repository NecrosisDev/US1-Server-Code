-- ULX Log Panel - client GUI
-- Two tabs: Command Log (filter/group/paginate the 7-day ulx_cmdlog) and
-- Punishments (permanent punish_history lookup). Admin+ (server enforces).
-- Open: console "ulx_logs_open", chat "!logs", or the GoobOS Staff app ("ulx_logs" is the server-side
-- opener behind !logs: it checks access, then runs ulx_logs_open). Export writes a text file to
-- YOUR local garrysmod/data/.
if not CLIENT then return end

local PANEL_W, PANEL_H = 0.72, 0.78  -- fractions of screen

local colBG      = Color(28, 28, 32, 245)
local colHeader  = Color(18, 18, 22, 255)
local colAccent  = Color(200, 60, 60)
local colRow     = Color(40, 40, 46)
local colRowAlt  = Color(34, 34, 40)
local colDenied  = Color(120, 40, 40)
local colText    = Color(230, 230, 230)
local colDim     = Color(150, 150, 150)

surface.CreateFont("ULXLog_Text", { font = "Bahnschrift", size = 15, weight = 500 })
surface.CreateFont("ULXLog_Head", { font = "Bahnschrift", size = 18, weight = 800 })

local frame
local state = {
    tab = "log", page = 0, days = 7,
    rank = "", result = "", group = "", search = "", dir = "",
    lastRows = {},
}

-- ---------------------------------------------------------------------
-- data plumbing
-- ---------------------------------------------------------------------
local function Request()
    net.Start("ULXLogPanel_Query")
        net.WriteString(util.TableToJSON({
            tab = state.tab, page = state.page, days = state.days,
            rank = state.rank, result = state.result,
            group = state.group ~= "" and state.group or nil,
            search = state.search,
            dir = state.dir,
            teamkill = state.teamkill or nil,
        }))
    net.SendToServer()
end

local Rebuild -- fwd decl

net.Receive("ULXLogPanel_Data", function()
    local len = net.ReadUInt(32)
    local data = util.Decompress(net.ReadData(len))
    if not data then return end
    local ok, result = pcall(util.JSONToTable, data)
    if not ok or not istable(result) then return end

    state.lastResult = result
    state.lastRows = result.rows or {}
    if IsValid(frame) and Rebuild then Rebuild(result) end
end)

-- ---------------------------------------------------------------------
-- helpers
-- ---------------------------------------------------------------------
local function FmtDur(mins)
    mins = tonumber(mins) or 0
    if mins <= 0 then return "perma" end
    if mins < 60 then return mins .. "m" end
    if mins < 1440 then return math.Round(mins / 60, 1) .. "h" end
    return math.Round(mins / 1440, 1) .. "d"
end

local function DarkButton(parent, label, w)
    local b = vgui.Create("DButton", parent)
    b:SetText(label)
    b:SetFont("ULXLog_Text")
    b:SetTextColor(colText)
    if w then b:SetWide(w) end
    b.Paint = function(self, bw, bh)
        surface.SetDrawColor(self:IsHovered() and colAccent or colRow)
        surface.DrawRect(0, 0, bw, bh)
    end
    return b
end

local function StyleLine(line, color)
    for _, lbl in pairs(line.Columns or {}) do
        lbl:SetTextColor(color)
        lbl:SetFont("ULXLog_Text")
    end
end

local function StyleHeaders(lv)
    for _, col in pairs(lv.Columns or {}) do
        if IsValid(col.Header) then
            col.Header:SetTextColor(colText)
            col.Header.Paint = function(self, w, h)
                surface.SetDrawColor(colHeader)
                surface.DrawRect(0, 0, w, h)
            end
        end
    end
end

local function Export()
    local rows = state.lastRows
    if not rows or #rows == 0 then chat.AddText("Nothing to export.") return end

    local out = { "ULX Log Panel export - " .. os.date("%Y-%m-%d %H:%M:%S") }
    for _, r in ipairs(rows) do
        if state.tab == "punish" then
            out[#out + 1] = string.format("%s | %s (%s) | %s %s | by %s [%s] | %s",
                os.date("%Y-%m-%d %H:%M", tonumber(r.ts)), r.name or "?", r.sid,
                r.ptype, FmtDur(r.duration), r.staff_name or "?", r.staff_rank or "?",
                r.reason or "-")
        elseif r.g then
            out[#out + 1] = string.format("%-30s %6s total  %s denied", r.g, r.c, r.denied or 0)
        else
            out[#out + 1] = string.format("%s | %-10s | %s (%s) | %s -> %s | %s | %s%s",
                os.date("%Y-%m-%d %H:%M:%S", tonumber(r.ts)), r.rank, r.name, r.sid,
                r.cmd, r.target or "-", r.args or "-", r.result,
                tonumber(r.selftarget) == 1 and " [SELF]" or "")
        end
    end
    file.Write("ulxlog_panel_export.txt", table.concat(out, "\n"))
    chat.AddText(Color(120, 220, 120), "[Logs] Exported " .. #rows .. " rows to data/ulxlog_panel_export.txt (your PC)")
end

-- ---------------------------------------------------------------------
-- the panel
-- ---------------------------------------------------------------------
local function Open()
    if IsValid(frame) then frame:Remove() end

    frame = vgui.Create("DFrame")
    frame:SetSize(ScrW() * PANEL_W, ScrH() * PANEL_H)
    frame:Center()
    frame:SetTitle("")
    frame:MakePopup()
    frame:ShowCloseButton(true)
    frame.Paint = function(self, w, h)
        surface.SetDrawColor(colBG) surface.DrawRect(0, 0, w, h)
        surface.SetDrawColor(colHeader) surface.DrawRect(0, 0, w, 30)
        surface.SetDrawColor(colAccent) surface.DrawOutlinedRect(0, 0, w, h, 2)
        draw.SimpleText("Staff Logs", "ULXLog_Head", 10, 15, colText, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    -- ===== tab bar =====
    local tabs = vgui.Create("DPanel", frame)
    tabs:Dock(TOP) tabs:SetTall(30) tabs:DockMargin(4, 4, 4, 0)
    tabs.Paint = nil

    local btnLog = DarkButton(tabs, "Command Log", 130)
    btnLog:Dock(LEFT) btnLog:DockMargin(0, 0, 4, 0)
    local btnPun = DarkButton(tabs, "Punishments", 130)
    btnPun:Dock(LEFT) btnPun:DockMargin(0, 0, 4, 0)
    local btnDmg = DarkButton(tabs, "Damage", 130)
    btnDmg:Dock(LEFT) btnDmg:DockMargin(0, 0, 4, 0)
    local btnWD = DarkButton(tabs, "Watchdog", 130)
    btnWD:Dock(LEFT)

    -- ===== filter bar =====
    local filters = vgui.Create("DPanel", frame)
    filters:Dock(TOP) filters:SetTall(30) filters:DockMargin(4, 4, 4, 0)
    filters.Paint = nil

    local search = vgui.Create("DTextEntry", filters)
    search:Dock(LEFT) search:SetWide(220) search:DockMargin(0, 2, 6, 2)
    search:SetPlaceholderText("search name / steamid / command / text")
    search.OnEnter = function(self)
        state.search = self:GetValue()
        state.page = 0
        Request()
    end

    local function Combo(label, choices, key, wide)
        local c = vgui.Create("DComboBox", filters)
        c:Dock(LEFT) c:SetWide(wide or 110) c:DockMargin(0, 2, 6, 2)
        c:SetValue(label)
        for _, ch in ipairs(choices) do c:AddChoice(ch[1], ch[2]) end
        c.OnSelect = function(_, _, _, val)
            state[key] = val
            state.page = 0
            Request()
        end
        return c
    end

    local comboRank = Combo("rank: all", {
        {"all ranks", ""}, {"user", "user"}, {"operator", "operator"},
        {"admin", "admin"}, {"superadmin", "superadmin"}, {"console", "console"},
    }, "rank")

    local comboResult = Combo("result: all", {
        {"all results", ""}, {"executed", "executed"}, {"denied", "denied"},
    }, "result")

    local comboGroup = Combo("group: none", {
        {"no grouping", ""}, {"by rank", "rank"}, {"by person", "person"},
        {"by command", "cmd"}, {"by target", "target"},
        {"by result", "result"}, {"by hour", "hour"},
    }, "group", 120)

    local comboDays = Combo("last 7d", {
        {"last 1d", 1}, {"last 3d", 3}, {"last 7d", 7},
    }, "days", 80)

    local comboDir = Combo("dir: both", {
        {"both directions", ""}, {"damage BY them", "dealt"}, {"damage TO them", "taken"},
    }, "dir", 140)

    local btnTK = DarkButton(filters, "TK only: off", 100)
    btnTK:Dock(LEFT) btnTK:DockMargin(0, 2, 6, 2)
    btnTK.DoClick = function(self)
        state.teamkill = not state.teamkill
        self:SetText(state.teamkill and "TK only: ON" or "TK only: off")
        state.page = 0
        Request()
    end

    local btnExport = DarkButton(filters, "Export", 70)
    btnExport:Dock(RIGHT) btnExport:DockMargin(6, 2, 0, 2)
    btnExport.DoClick = Export

    -- ===== list =====
    local list = vgui.Create("DListView", frame)
    list:Dock(FILL) list:DockMargin(4, 4, 4, 0)
    list:SetMultiSelect(true)
    list:SetDataHeight(20)
    list.Paint = function(self, w, h)
        surface.SetDrawColor(colRowAlt) surface.DrawRect(0, 0, w, h)
    end

    -- ===== footer / pagination =====
    local footer = vgui.Create("DPanel", frame)
    footer:Dock(BOTTOM) footer:SetTall(28) footer:DockMargin(4, 4, 4, 4)
    footer.Paint = nil

    local btnPrev = DarkButton(footer, "< Prev", 70)
    btnPrev:Dock(LEFT)
    local btnNext = DarkButton(footer, "Next >", 70)
    btnNext:Dock(LEFT) btnNext:DockMargin(6, 0, 0, 0)

    local pageLbl = vgui.Create("DLabel", footer)
    pageLbl:Dock(LEFT) pageLbl:SetWide(200) pageLbl:DockMargin(10, 0, 0, 0)
    pageLbl:SetFont("ULXLog_Text") pageLbl:SetTextColor(colDim)
    pageLbl:SetText("")

    local btnDelete
    if LocalPlayer():IsSuperAdmin() then
        btnDelete = DarkButton(footer, "Delete Selected", 120)
        btnDelete:Dock(LEFT) btnDelete:DockMargin(14, 0, 0, 0)
        btnDelete.DoClick = function()
            if state.tab == "log" and state.group ~= "" then
                chat.AddText(Color(255, 120, 120), "[Logs] Can't delete grouped rows - switch grouping to none.")
                return
            end
            local ids = {}
            for _, line in ipairs(list:GetSelected() or {}) do
                if line.dbID then ids[#ids + 1] = line.dbID end
            end
            if #ids == 0 then
                chat.AddText(Color(255, 120, 120), "[Logs] Select rows to delete first.")
                return
            end

            Derma_Query(
                "Permanently delete " .. #ids .. " log entr" .. (#ids == 1 and "y" or "ies") ..
                "?\nThis is audited and cannot be undone.",
                "Confirm Deletion",
                "Delete", function()
                    net.Start("ULXLogPanel_Delete")
                        net.WriteString(state.tab)
                        net.WriteUInt(math.min(#ids, 100), 8)
                        for i = 1, math.min(#ids, 100) do
                            net.WriteUInt(ids[i], 32)
                        end
                    net.SendToServer()
                    timer.Simple(0.3, Request)
                end,
                "Cancel", function() end)
        end
    end

    local note = vgui.Create("DLabel", footer)
    note:Dock(RIGHT) note:SetWide(360)
    note:SetFont("ULXLog_Text") note:SetTextColor(colDim)
    note:SetText("ULX commands only - lua_run/console cvars not captured")

    btnPrev.DoClick = function()
        if state.page > 0 then state.page = state.page - 1 Request() end
    end
    btnNext.DoClick = function()
        if state.lastResult and state.lastResult.more then
            state.page = state.page + 1 Request()
        end
    end

    -- ===== tab switching =====
    local function SetTab(tab)
        state.tab = tab
        state.page = 0
        state.group = ""
        state.dir = ""
        state.teamkill = false
        btnTK:SetText("TK only: off")
        comboDir:SetValue("dir: both")
        comboGroup:SetValue("group: none")

        local isLog, isDmg, isWD = tab == "log", tab == "damage", tab == "watchdog"
        comboGroup:SetVisible(isLog)
        comboRank:SetVisible(isLog)
        comboResult:SetVisible(isLog)
        comboDays:SetVisible(isLog or isDmg or isWD)
        comboDir:SetVisible(isDmg)
        btnTK:SetVisible(isDmg)
        filters:InvalidateLayout()

        search:SetPlaceholderText(
            tab == "punish" and "steamid or name - who are you checking?"
            or isDmg and "player name or steamid - blank = recent events"
            or isWD and "search player / steamid / module (aim, spin, speed...)"
            or "search name / steamid / command / text")
        Request()
    end
    btnLog.DoClick = function() SetTab("log") end
    btnPun.DoClick = function() SetTab("punish") end
    btnDmg.DoClick = function() SetTab("damage") end
    btnWD.DoClick = function() SetTab("watchdog") end

    -- ===== rebuild on data =====
    Rebuild = function(result)
        list:Clear()
        for _, col in ipairs(list.Columns or {}) do col:Remove() end
        list.Columns = {}

        if result.mode == "group" then
            list:AddColumn("Group"):SetFixedWidth(300)
            list:AddColumn("Count"):SetFixedWidth(90)
            list:AddColumn("Denied"):SetFixedWidth(90)
            for _, r in ipairs(result.rows) do
                StyleLine(list:AddLine(tostring(r.g or "?"), r.c or 0, r.denied or 0), colText)
            end
            StyleHeaders(list)
            pageLbl:SetText(#result.rows .. " groups")

        elseif result.mode == "punish" then
            list:AddColumn("Date"):SetFixedWidth(110)
            list:AddColumn("Player"):SetFixedWidth(150)
            list:AddColumn("SteamID"):SetFixedWidth(160)
            list:AddColumn("Type"):SetFixedWidth(60)
            list:AddColumn("Length"):SetFixedWidth(60)
            list:AddColumn("Staff"):SetFixedWidth(130)
            list:AddColumn("Reason")
            for _, r in ipairs(result.rows) do
                local ac = r.source and string.match(tostring(r.source), "|wd:(%w+)")
                local reason = (r.reason and r.reason ~= "NULL") and r.reason or ""
                if ac then reason = "[AC:" .. ac .. "] " .. reason end
                local line = list:AddLine(
                    os.date("%m-%d %H:%M", tonumber(r.ts)),
                    r.name or "?", r.sid, r.ptype, FmtDur(r.duration),
                    (r.staff_name or "?") .. ((r.staff_rank and r.staff_rank ~= "NULL") and (" [" .. r.staff_rank .. "]") or ""),
                    reason)
                StyleLine(line, ac and Color(235, 170, 90) or colText)
                line.dbID = tonumber(r.id)
            end
            StyleHeaders(list)
            -- summary in the page label
            local parts = {}
            for ptype, n in SortedPairs(result.summary or {}) do
                parts[#parts + 1] = n .. " " .. ptype
            end
            pageLbl:SetText(#result.rows == 0 and "no history / enter a search"
                or table.concat(parts, ", "))

        elseif result.mode == "damage" then
            list:AddColumn("Time"):SetFixedWidth(95)
            list:AddColumn("Rnd"):SetFixedWidth(40)
            list:AddColumn("Mode"):SetFixedWidth(60)
            list:AddColumn("Attacker"):SetFixedWidth(160)
            list:AddColumn("Victim"):SetFixedWidth(160)
            list:AddColumn("Weapon"):SetFixedWidth(150)
            list:AddColumn("Dmg"):SetFixedWidth(55)
            list:AddColumn("Hits"):SetFixedWidth(45)
            list:AddColumn("Type"):SetFixedWidth(55)

            local focus = result.summary and result.summary.sid

            for _, r in ipairs(result.rows) do
                local aLabel = (r.a_char and r.a_char ~= "NULL" and r.a_char ~= "") and (r.a_char .. " / " .. r.a_name) or r.a_name
                local vLabel = (r.v_char and r.v_char ~= "NULL" and r.v_char ~= "") and (r.v_char .. " / " .. r.v_name) or r.v_name

                local line = list:AddLine(
                    os.date("%m-%d %H:%M", tonumber(r.ts)),
                    r.round or "?", r.mode or "?",
                    aLabel, vLabel, r.weapon or "?",
                    r.etype == "kill" and "KILL" or math.Round(tonumber(r.dmg) or 0),
                    r.hits or 1,
                    (tonumber(r.teamkill) == 1 and "TK " or "") .. r.etype)

                local col = colText
                if r.etype == "kill" then
                    col = Color(255, 150, 90)
                elseif tonumber(r.teamkill) == 1 then
                    col = Color(255, 120, 120)
                elseif focus and r.v_sid == focus then
                    col = Color(140, 190, 255)  -- damage TO the searched player
                end
                StyleLine(line, col)
                line.dmgRow = r
                line.dbID = tonumber(r.id)
            end
            StyleHeaders(list)

            if result.summary then
                local s = result.summary
                pageLbl:SetWide(430)
                pageLbl:SetText(string.format("dealt %d (%d kills, %d TKs) | taken %d (%d deaths) | pg %d%s",
                    s.dealt, s.kills, s.tks, s.taken, s.deaths,
                    result.page + 1, result.more and "+" or ""))
            else
                pageLbl:SetText("recent events - page " .. (result.page + 1) ..
                    (result.more and " (more)" or " (end)"))
            end

        elseif result.mode == "watchdog" then
            list:AddColumn("Time"):SetFixedWidth(110)
            list:AddColumn("Player"):SetFixedWidth(150)
            list:AddColumn("SteamID"):SetFixedWidth(160)
            list:AddColumn("Module"):SetFixedWidth(90)
            list:AddColumn("Detail")
            for _, r in ipairs(result.rows) do
                local line = list:AddLine(
                    os.date("%m-%d %H:%M:%S", tonumber(r.ts)),
                    r.name or "?", r.sid, r.module, r.summary or "")
                StyleLine(line, Color(235, 170, 90))
                line.dbID = tonumber(r.id)
                line.wdRow = r
            end
            StyleHeaders(list)
            local parts = {}
            for m, n in SortedPairs(result.summary or {}) do parts[#parts + 1] = n .. " " .. m end
            pageLbl:SetText((#result.rows == 0 and "no detections" or table.concat(parts, ", "))
                .. "  -  page " .. (result.page + 1) .. (result.more and " (more)" or " (end)"))

        else -- rows
            list:AddColumn("Time"):SetFixedWidth(110)
            list:AddColumn("Rank"):SetFixedWidth(80)
            list:AddColumn("Who"):SetFixedWidth(140)
            list:AddColumn("Command"):SetFixedWidth(110)
            list:AddColumn("Target"):SetFixedWidth(130)
            list:AddColumn("Args")
            list:AddColumn("Result"):SetFixedWidth(70)
            for _, r in ipairs(result.rows) do
                local line = list:AddLine(
                    os.date("%m-%d %H:%M:%S", tonumber(r.ts)),
                    r.rank, r.name, r.cmd,
                    (r.target or "-") .. (tonumber(r.selftarget) == 1 and " [SELF]" or ""),
                    r.args or "", r.result)
                StyleLine(line, r.result == "denied" and Color(255, 120, 120) or colText)
                line.dbID = tonumber(r.id)
            end
            StyleHeaders(list)
            pageLbl:SetText("page " .. (result.page + 1) ..
                (result.more and " (more available)" or " (end)"))
        end
    end

    -- double-click a log row -> jump to that person's punishment history
    list.DoDoubleClick = function(_, _, line)
        if not line then return end

        if state.tab == "damage" and line.dmgRow then
            local sid = line.dmgRow.a_sid
            search:SetValue(sid)
            state.search = sid
            SetTab("punish")
            return
        end

        if state.tab == "watchdog" and line.wdRow then
            local sid = line.wdRow.sid
            search:SetValue(sid)
            state.search = sid
            SetTab("punish")
            return
        end

        if state.tab ~= "log" then return end
        local rows = state.lastRows
        local sid = line:GetColumnText(3)
        -- prefer target's sid if the row had one
        for _, r in ipairs(rows) do
            if r.name == line:GetColumnText(3) and r.target_sid and r.target_sid ~= "NULL" then
                sid = r.target_sid
                break
            end
        end
        search:SetValue(sid)
        state.search = sid
        SetTab("punish")
    end

    SetTab("log")
end

concommand.Add("ulx_logs_open", Open, nil, "Open the ULX log panel: the 7-day command log and the punishment history (staff; the server checks access on every query). Chat: !logs")
