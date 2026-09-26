if not CLIENT then return end
local A, T = ZCGoobApps, ZCGoobApps.Theme
-- The mounted V012 addon owns dispatch. Edit its existing file and invoke its reload command.
A.BindActions = {{"hg_kick", "Kick"}, {"fake", "Ragdoll"}, {"hmcd_togglelaser", "Toggle laser"}, {"+alt1", "Lean left"}, {"+alt2", "Lean right"}, {"+hmcd_holdbreath", "Hold breath"}, {"+altlook", "Free look"}, {"+hg_zoom", "Zoom"}}
function A.ReadBinds()
    if not file.Exists("zcity_keybinds.txt", "DATA") then return {} end
    local value = util.JSONToTable(file.Read("zcity_keybinds.txt", "DATA") or "")
    if not istable(value) then return nil end
    return value
end

function A.BindConflict(command, key, data)
    if key == KEY_NONE then return end
    if key == KEY_ESCAPE or key == KEY_BACKQUOTE then return "Keep Escape and the console key available." end
    local native = input.LookupKeyBinding(key)
    if native and native ~= "" then return "Already used by " .. native .. " in Garry's Mod settings." end
    for _, action in ipairs(A.BindActions) do
        if action[1] ~= command and tonumber(data[action[1]]) == key then return "Already used by " .. action[2] .. "." end
    end
end

function A.SetBind(command, key)
    if not concommand.GetTable().zcity_keybind_reload then return false, "The keybind owner is unavailable." end
    local known = false
    for _, action in ipairs(A.BindActions) do
        if action[1] == command then known = true end
    end

    if not known or not isnumber(key) or key ~= math.floor(key) or key < KEY_NONE or key > BUTTON_CODE_LAST then return false, "Invalid key." end
    local data = A.ReadBinds()
    if not data then return false, "Saved keybinds could not be read. They have not been changed." end
    local conflict = A.BindConflict(command, key, data)
    if conflict then return false, conflict end
    data[command] = key
    local encoded = util.TableToJSON(data, true)
    if not encoded then return false, "Could not save this binding." end
    file.Write("zcity_keybinds.txt", encoded)
    RunConsoleCommand("zcity_keybind_reload")
    return true, "Binding saved."
end

-- Rows inside a category: those that carry a position number in meta[8]
-- come first, in that order; the rest follow alphabetically by convar name
-- (the previous behaviour, unchanged for every row without a number).
function A.OrderedRows(rows)
    local keys = {}
    for k in pairs(rows) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b)
        local oa, ob = tonumber(rows[a][8]), tonumber(rows[b][8])
        if oa and ob and oa ~= ob then return oa < ob end
        if (oa == nil) ~= (ob == nil) then return oa ~= nil end
        return tostring(a) < tostring(b)
    end)
    local i = 0
    return function()
        i = i + 1
        local k = keys[i]
        if k ~= nil then return k, rows[k] end
    end
end

function A.SettingKind(meta, cv)
    if meta[5] then return "string" end
    if meta[6] then return meta[6] end
    local min, max = cv:GetMin(), cv:GetMax()
    if min == 0 and max == 1 and not meta[4] then return "bool" end
    if min ~= nil or max ~= nil or meta[4] then return "int" end
    local value = cv:GetString()
    if value == "0" or value == "1" then return "bool" end
    if tonumber(value) then return "int" end
    return "string"
end

-- The default per-tab/section subtitle shown under the h1 in the content header.
local SECTION_HELP = {
    Reading = "Text size, spacing and bubble display",
    Motion = "Scroll waves, typewriter reveal and falling letters",
    Notifications = "Banners and mention sounds",
    Media = "Inline photos, GIFs and video playback",
    Privacy = "Hidden senders and private alerts",
    Preferences = "Server and client gameplay options",
    Keybinds = "ZCity shortcuts layered over the engine binding"
}

local WIDE_BREAKPOINT = 520

-- Settings pages other addons add beside Preferences (the crosshair editor):
-- hg.settings.pages[name] = {order, title, short, subtitle, categories, wide, build}
--   categories  hg.settings categories the page shows instead of Preferences
--   wide        grow the chat window while the page is open (see pageGrow)
--   build(list, api)  api = {K, T, root, phone, message, query, matches, refresh,
--                             row(parent, category, convar) -> builds one GoobOS row}
local function settingsPages()
    local found = {}
    local pages = hg and hg.settings and hg.settings.pages
    if istable(pages) then
        for name, page in pairs(pages) do
            if istable(page) and isfunction(page.build) then found[#found + 1] = {name = name, page = page} end
        end
    end
    table.sort(found, function(a, b) return (tonumber(a.page.order) or 50) < (tonumber(b.page.order) or 50) end)
    return found
end

local function build(root, phone)
    local K = A.Kit
    local state = A.State.settings or {}
    A.State.settings = state
    state.tab = state.tab or "Phone"
    state.phoneSection = state.phoneSection or "Reading"
    state.query = state.query or ""

    -- Segmented index <-> tab name, shared by the sidebar highlight and the narrow SegmentedControl.
    local pageList = settingsPages()
    local pageByName, claimed = {}, {}
    local segTabs, segLabels = {"Phone", "Preferences"}, {"Phone", "Game"}
    for _, p in ipairs(pageList) do
        pageByName[p.name] = p.page
        segTabs[#segTabs + 1] = p.name
        segLabels[#segLabels + 1] = p.page.short or p.page.title or p.name
        for _, category in ipairs(istable(p.page.categories) and p.page.categories or {}) do claimed[category] = p.name end
    end
    segTabs[#segTabs + 1], segLabels[#segLabels + 1] = "Keybinds", "Keys"
    if state.tab ~= "Phone" and state.tab ~= "Preferences" and state.tab ~= "Keybinds" and not pageByName[state.tab] then
        state.tab = "Preferences"
    end

    local function segIndexFor(tab)
        for i, t in ipairs(segTabs) do if t == tab then return i end end
        return 1
    end

    local function sectionIndexFor(name)
        local S = ZCPhoneSettings
        for i, s in ipairs((S and S.Sections) or {}) do if s == name then return i end end
        return 1
    end

    -- Forward declared: the sidebar, the narrow nav widgets and the row list all reference
    -- rebuild()/rebuildSidebar() from their click handlers before those widgets exist yet.
    local sidebar, segmented, phoneTabs, list, rebuild, rebuildSidebar

    -- A page that asks for room (page.wide) grows the chat window to fit two
    -- columns while it is open, and puts it back on leaving the page or when
    -- the app closes. Never while the chat is docked to a death or round-end
    -- panel, and never if the player resized the window in the meantime.
    -- 940 wide leaves the page ~686 px beside the 200 px sidebar (two columns
    -- need 560); 65% of the screen is the tallest the chat's own resize allows.
    local function pageGrow()
        if not IsValid(phone) or phone.ZCDocked or phone.goobPageGeometry then return end
        local w = math.min(math.max(phone:GetWide(), 940), ScrW() - 16)
        local h = math.min(math.max(phone:GetTall(), math.floor(ScrH() * 0.65)), ScrH() - 16)
        if w == phone:GetWide() and h == phone:GetTall() then return end
        local g = {w = phone:GetWide(), h = phone:GetTall(), x = phone:GetX(), y = phone:GetY(), app = phone.goobGeometry and table.Copy(phone.goobGeometry)}
        local bottom = g.y + g.h
        phone:SetSize(w, h)
        phone:SetPos(math.Clamp(g.x, 8, math.max(8, ScrW() - w - 8)), math.max(8, bottom - h))
        g.gw, g.gh = w, h
        phone.goobPageGeometry = g
        phone:InvalidateLayout(true)
    end

    local function pageShrink(closing)
        if not IsValid(phone) then return end
        local g = phone.goobPageGeometry
        if not g then return end
        phone.goobPageGeometry = nil
        if phone.ZCDocked or phone:GetWide() ~= g.gw or phone:GetTall() ~= g.gh then return end
        local back = g
        -- The app closed while the page was open: A.Sync has already dropped the
        -- app's own height record (the width no longer matched), so go back to
        -- the size from before the app opened.
        if closing and g.app and not phone.goobGeometry then back = g.app end
        phone:SetSize(back.w, back.h)
        phone:SetPos(back.x, back.y)
        phone:InvalidateLayout(true)
    end

    rebuildSidebar = function()
        sidebar:Clear()
        local function groupLabel(text)
            local l = K.Panel(sidebar)
            l:Dock(TOP)
            l:DockMargin(2, 8, 0, 3)
            l:SetTall(16)
            l.Paint = function(_, w, h) K.Text(string.upper(text), 10.5, 600, 0, h / 2, T.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
        end
        local function row(label, selected, onClick)
            local b = vgui.Create("DButton", sidebar)
            b:Dock(TOP)
            b:DockMargin(0, 0, 0, 2)
            b:SetTall(30)
            b:SetText("")
            b.DoClick = onClick
            b.Paint = function(s, w, h)
                if selected then
                    draw.RoundedBox(0, 0, 0, w, h, K.Alpha(T.main, 55))
                    surface.SetDrawColor(T.main)
                    surface.DrawRect(0, 0, 2, h)
                elseif K.Hover(s) > 0.01 then
                    draw.RoundedBox(0, 0, 0, w, h, K.Alpha(T.main, 24 * s.GoobHover))
                end
                K.Text(label, 13.5, selected and 600 or 500, 10, h / 2, selected and T.text or T.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end
        end
        groupLabel("Phone")
        local S = ZCPhoneSettings
        for _, name in ipairs((S and S.Sections) or {"Reading", "Motion", "Notifications", "Media", "Privacy"}) do
            row(name, state.tab == "Phone" and state.phoneSection == name, function()
                state.tab, state.phoneSection = "Phone", name
                rebuild()
            end)
        end
        groupLabel("Game")
        row("Preferences", state.tab == "Preferences", function()
            state.tab = "Preferences"
            rebuild()
        end)
        for _, p in ipairs(pageList) do
            row(p.page.title or p.name, state.tab == p.name, function()
                state.tab = p.name
                rebuild()
            end)
        end
        groupLabel("Controls")
        row("Keybinds", state.tab == "Keybinds", function()
            state.tab = "Keybinds"
            rebuild()
        end)
    end

    rebuild = function()
        local current = pageByName[state.tab]
        if current and current.wide then pageGrow() else pageShrink(false) end
        if IsValid(sidebar) then rebuildSidebar() end
        if IsValid(segmented) then segmented.Selected = segIndexFor(state.tab) end
        if IsValid(phoneTabs) then phoneTabs.Selected = sectionIndexFor(state.phoneSection) end
        if IsValid(list) then list:RefreshSettings() end
    end

    local message = A.Status(root, "Make GoobOS and ZCity feel right for you.")
    message:SetFont(K.Font(12, 500))
    message:SetTall(20)
    local searchEntry = A.Entry(root, "Search settings & controls", state.query, function(v)
        state.query = v
        rebuild()
    end)
    searchEntry:SetFont(K.Font(14, 500))

    local shell = K.Panel(root)
    shell:Dock(FILL)

    sidebar = K.Panel(shell)
    rebuildSidebar()

    segmented = K.Segmented(shell, segLabels, segIndexFor(state.tab), function(index)
        state.tab = segTabs[index]
        rebuild()
    end)

    phoneTabs = K.Tabs(shell, (ZCPhoneSettings and ZCPhoneSettings.Sections) or {"Reading"}, sectionIndexFor(state.phoneSection), function(_, label)
        state.phoneSection = label
        rebuild()
    end)

    local content = K.Panel(shell)
    local head = K.Panel(content)
    head:Dock(TOP)
    head:SetTall(34)
    head.Paint = function(_, w)
        local page = pageByName[state.tab]
        local title = state.tab == "Phone" and state.phoneSection or (page and (page.title or state.tab)) or state.tab
        K.Text(K.Fit(title, K.Font(16, 700), w), 16, 700, 0, 1, T.text)
        K.Text(K.Fit(SECTION_HELP[title] or (page and page.subtitle) or "", K.Font(11.5, 500), w), 11.5, 500, 0, 21, T.muted)
    end

    -- One GoobOS setting row: label + help on the left, the control on the right
    -- (used by Preferences and by registered pages).
    local function buildRow(parent, category, name, meta, cv)
        -- Same row anatomy as the Phone sections (mockup 02): label + help on the left,
        -- the control on the right; sliders and text values take a second line. A
        -- "Default" link shows only while the value differs from the default.
        local help = cv:GetHelpText()
        local serverOwned = category == "Serverside gameplay" or cv:IsFlagSet(FCVAR_REPLICATED)
        local kind = not serverOwned and A.SettingKind(meta, cv) or nil
        local title = tostring(meta[3] or name)
        local detail = serverOwned and ("Server controlled · " .. cv:GetString()) or (help ~= "" and help or name)
        local row = ZCPhoneSettings.Row(parent, title, detail, kind == "bool" and 104 or 70)
        local reset
        if not serverOwned then
            reset = vgui.Create("DButton", row)
            reset.GoobReset = name
            reset:SetText("")
            reset:SetTooltip("Default: " .. tostring(cv:GetDefault()))
            reset.Paint = function(s, w, h)
                if cv:GetString() == cv:GetDefault() then return end
                K.Text("Default", 11, 600, w, h / 2, K.Hover(s) > 0.01 and T.text or T.accent, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
            end
            reset.DoClick = function()
                if cv:GetString() == cv:GetDefault() then return end
                K.Modal(root, "Restore " .. title .. "?", "Default: " .. tostring(cv:GetDefault()), {
                    {"Cancel"},
                    {"Restore", function()
                        RunConsoleCommand(name, cv:GetDefault())
                        message:SetText("Default requested.")
                        list:RefreshSettings()
                    end, primary = true}
                })
            end
        end
        if kind == "bool" then
            local toggle = K.Toggle(row, cv:GetBool(), function(v) RunConsoleCommand(name, v and "1" or "0") end)
            toggle.Think = function(t) t.Value = cv:GetBool() end
            row.PerformLayout = function(_, w, h)
                toggle:SetPos(w - 38, (h - 22) / 2)
                reset:SetPos(w - 104, 0)
                reset:SetSize(58, h)
            end
        elseif kind then
            row:SetTall(row:GetTall() + 34)
            local control
            if kind == "int" then
                control = vgui.Create("DNumSlider", row)
                control:SetText("")
                control:SetMin(cv:GetMin() or 0)
                control:SetMax(cv:GetMax() or 100)
                control:SetDecimals(meta[4] and 2 or 0)
                control:SetValue(cv:GetFloat())
                control.OnValueChanged = function(_, value) RunConsoleCommand(name, tostring(math.Round(value, meta[4] and 2 or 0))) end
            elseif kind == "choice" then
                -- Owner 2026-09-24 (late): a segmented pick for small enums (meta[7] labels, value = index - 1)
                local labels = istable(meta[7]) and meta[7] or {}
                control = K.Segmented(row, labels, math.Clamp(cv:GetInt() + 1, 1, math.max(1, #labels)), function(index)
                    RunConsoleCommand(name, tostring(index - 1))
                end)
                control.Think = function(s) s.Selected = math.Clamp(cv:GetInt() + 1, 1, math.max(1, #labels)) end
            else
                control = vgui.Create("DTextEntry", row)
                control:SetFont(K.Font(13, 500))
                control:SetText(cv:GetString())
                control.OnEnter = function(s)
                    RunConsoleCommand(name, s:GetValue())
                    message:SetText("Value applied.")
                end
                control:SetTooltip("Press Enter to apply")
            end
            row.PerformLayout = function(_, w, h)
                reset:SetPos(w - 64, 0)
                reset:SetSize(64, 40)
                control:SetPos(0, h - 36)
                control:SetSize(w, 30)
            end
        end
    end

    list = A.Scroll(content)
    function list:RefreshSettings()
        self:Clear()
        local count = 0
        if state.tab == "Phone" then
            ZCPhoneSettings.BuildPhone(self, root, phone, state, message)
            return
        elseif state.tab == "Keybinds" then
            A.Status(self, "Click a key to rebind. Clear removes only the ZCity shortcut; engine bindings remain in Garry's Mod settings.")
            local data = A.ReadBinds()
            if not data then
                A.Status(self, "Saved keybinds could not be read.", T.red)
            else
                for _, action in ipairs(A.BindActions) do
                    local command, title = action[1], action[2]
                    if A.Matches(title .. " " .. command, state.query) then
                        count = count + 1
                        local native = input.LookupBinding(command)
                        local row = K.Panel(self)
                        row:Dock(TOP)
                        row:DockMargin(0, 0, 0, 6)
                        row:SetTall(38)
                        row.Paint = function(_, w, h)
                            K.Text(K.Fit(title, K.Font(13.5, 600), w - 190), 13.5, 600, 0, 3, T.text)
                            K.Text(K.Fit("Engine: " .. (native and string.upper(native) or "unbound"), K.Font(11, 500), w - 190), 11, 500, 0, 22, T.muted)
                            surface.SetDrawColor(K.Alpha(T.hair, 120))
                            surface.DrawRect(0, h - 1, w, 1)
                        end

                        local binder = vgui.Create("DBinder", row)
                        binder:SetFont("GoobBody")
                        binder:SetTextColor(T.accent)
                        binder.Value = tonumber(data[command]) or KEY_NONE
                        binder.Paint = function(s, w, h)
                            local value = s.Value or KEY_NONE
                            local bound = value ~= KEY_NONE
                            local label = bound and string.upper(input.GetKeyName(value) or "?") or "Not bound"
                            if bound then
                                draw.RoundedBox(4, 0, 0, w, h, s:IsHovered() and T.hover or T.card)
                            else
                                surface.SetDrawColor(K.Alpha(T.hair, 200))
                                surface.DrawOutlinedRect(0, 0, w, h, 1)
                            end
                            K.Text(K.Fit(label, K.Font(11.5, 700), w - 8), 11.5, 700, w / 2, h / 2, bound and T.text or T.muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                        end

                        binder.OnChange = function(s, key)
                            local ok, text = A.SetBind(command, key)
                            message:SetText(text)
                            if not ok then
                                s.Value = tonumber(data[command]) or KEY_NONE
                            else
                                data[command] = key
                            end
                        end

                        local clear = vgui.Create("DButton", row)
                        clear:SetText("")
                        clear.DoClick = function()
                            local ok, text = A.SetBind(command, KEY_NONE)
                            message:SetText(text)
                            if ok then
                                data[command] = KEY_NONE
                                binder.Value = KEY_NONE
                            end
                        end
                        clear.Paint = function(s, w, h)
                            K.Text("Clear ZCity shortcut", 11, 600, w, h / 2, T.red, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
                        end

                        row.PerformLayout = function(_, w, h)
                            clear:SetPos(w - 120, 0)
                            clear:SetSize(120, h)
                            binder:SetPos(w - 190, 0)
                            binder:SetSize(56, 30)
                        end
                    end
                end

                local openGame = function()
                    phone:SetActive(false)
                    gui.ActivateGameUI()
                    RunConsoleCommand("gamemenucommand", "openoptionsdialog")
                end
                if ZCPhoneSettings and ZCPhoneSettings.FooterButton then
                    ZCPhoneSettings.FooterButton(self, "Open Garry's Mod settings", openGame)
                else
                    A.Button(self, "Open Garry's Mod settings", openGame)
                end
            end
        elseif pageByName[state.tab] then
            local page = pageByName[state.tab]
            local api = {
                K = K, T = T, root = root, phone = phone, message = message, query = state.query,
                matches = A.Matches,
                refresh = function() if IsValid(list) then list:RefreshSettings() end end,
                row = function(parent, category, name)
                    local rows = hg and hg.settings and hg.settings.tbl and hg.settings.tbl[category]
                    local meta = rows and rows[name]
                    local cv = GetConVar(name)
                    if not (meta and cv) then return false end
                    buildRow(parent, category, name, meta, cv)
                    return true
                end,
            }
            local fine, err = pcall(page.build, self, api)
            if not fine then
                self:Clear()  -- drop whatever the page built before it failed
                A.Status(self, "This page could not open. Your settings are unchanged.", T.red)
                ErrorNoHalt("[GoobOS settings] " .. tostring(state.tab) .. ": " .. tostring(err) .. "\n")
            end
            return
        else
            local categories = {}
            for category, rows in pairs(hg and hg.settings and hg.settings.tbl or {}) do
                categories[category] = table.Copy(rows)
            end

            -- categories a page shows instead; a search that matches them offers the page
            local offered = {}
            for category, pageName in pairs(claimed) do
                local rows = categories[category]
                categories[category] = nil
                if rows and state.query ~= "" and not offered[pageName] then
                    for name, meta in pairs(rows) do
                        if GetConVar(name) and A.Matches(category .. " " .. tostring(meta[3]) .. " " .. name, state.query) then
                            offered[pageName] = true
                            count = count + 1
                            local target = pageName
                            A.Button(self, "Matches in " .. tostring(pageByName[target].title or target) .. " - open", function()
                                state.tab = target
                                rebuild()
                            end)
                            break
                        end
                    end
                end
            end

            categories.GoobOS = categories.GoobOS or {}
            for _, row in ipairs({{"zc_goobos_voice", "GoobOS voice display", "bool"}, {"zc_goobos_voice_hud", "Gameplay voice indicator", "bool"}, {"zc_goobos_voice_monitor", "Your voice orb", "bool"}, {"zc_goobos_voice_monitor_pos", "Voice orb position", "choice", {"Centre", "Top left", "Top right", "Bottom left", "Bottom right"}}, {"zc_goobos_voice_fx", "Electricity density", "choice", {"Auto", "Full"}}, {"zc_chat_inline_media", "Inline photos & videos", "bool"}, {"zc_chat_video_volume", "Video volume", "int"}, {"zc_chat_gifs", "Animated GIFs", "bool"}, {"zc_chat_videos", "Video players", "bool"}, {"zc_chat_timestamps", "Message timestamps", "bool"}, {"zc_chat_group", "Group consecutive messages", "bool"}, {"zc_chat_ping", "Mention sounds", "bool"}}) do
                if GetConVar(row[1]) then categories.GoobOS[row[1]] = {"GoobOS", row[1], row[2], true, false, row[3], row[4]} end -- [7] = choice labels
            end

            for category, rows in SortedPairs(categories) do
                local heading = false
                for name, meta in A.OrderedRows(rows) do
                    local cv = GetConVar(name)
                    if cv and A.Matches(category .. " " .. tostring(meta[3]) .. " " .. name, state.query) then
                        count = count + 1
                        if not heading then
                            local h = K.Panel(self)
                            h:Dock(TOP)
                            h:SetTall(24)
                            h:DockMargin(0, 10, 0, 2)
                            h.Paint = function(_, w, hh) K.Text(string.upper(category), 12, 600, 0, hh / 2, T.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
                            heading = true
                            -- Addons may add one panel under their heading:
                            -- hg.settings.extras[category] = function(list, K, T) ... end
                            -- (the crosshair's live preview). A failing extra never breaks the page.
                            local extra = hg and hg.settings and hg.settings.extras and hg.settings.extras[category]
                            if isfunction(extra) then
                                local fine, err = pcall(extra, self, K, T)
                                if not fine then ErrorNoHalt("[GoobOS settings] " .. tostring(category) .. ": " .. tostring(err) .. "\n") end
                            end
                        end

                        buildRow(self, category, name, meta, cv)
                    end
                end
            end
        end

        if count == 0 then A.Status(self, "No matching settings. Try a shorter search.") end
    end

    -- Responsive shell: >= WIDE_BREAKPOINT body width shows the sidebar; below it, a Segmented
    -- control ("Phone / Game / Keys") plus a Tabs strip for the phone sections (Layout rule:
    -- nested Dock(FILL) invalidation is unreliable, so this positions everything from Think).
    shell.Think = function(s)
        local w, h = s:GetWide(), s:GetTall()
        local wide = w >= WIDE_BREAKPOINT
        sidebar:SetVisible(wide)
        segmented:SetVisible(not wide)
        local showTabs = not wide and state.tab == "Phone"
        phoneTabs:SetVisible(showTabs)
        if wide then
            local sw = math.Clamp(math.floor(w * 0.24), 180, 200)
            sidebar:SetPos(0, 0)
            sidebar:SetSize(sw, h)
            content:SetPos(sw + 14, 0)
            content:SetSize(math.max(1, w - sw - 14), h)
        else
            segmented:SetPos(0, 0)
            segmented:SetSize(w, 32)
            local y = 40
            if showTabs then
                phoneTabs:SetPos(0, y)
                phoneTabs:SetSize(w, 32)
                y = y + 38
            end
            content:SetPos(0, y)
            content:SetSize(w, math.max(1, h - y))
        end
    end

    local previousRemove = root.OnRemove
    root.OnRemove = function(...)
        pageShrink(true)
        if previousRemove then return previousRemove(...) end
    end

    rebuild()
end

A.Register("settings", "Settings", "Preferences & keybinds", "icon16/cog.png", T.accent, build)
