if not CLIENT then return end
local A, T = ZCGoobApps, ZCGoobApps.Theme
function A.Duration(seconds)
    seconds = math.max(0, tonumber(seconds) or 0)
    return math.floor(seconds / 3600) .. "h " .. math.floor(seconds % 3600 / 60) .. "m"
end

function A.AchievementProgress(def, record)
    local value = tonumber(record and record.value) or tonumber(def.start_value) or 0
    local target = tonumber(def.needed_value) or 0
    return value, target, target > 0 and math.Clamp(value / target, 0, 1) or 0, target > 0 and value >= target
end

-- Completion ring (mockups/03_progress.html .pg-ring): GMod has no conic-gradient/texture ring, so it
-- is drawn as concentric line segments. Unit-circle points are cached once at file scope (kit.lua's
-- own K.Glyph "o" ring uses the same technique) — never rebuilt per frame.
local RING_SEGMENTS = 32
local ringUnit
local function ringPoints()
    if not ringUnit then
        ringUnit = {}
        for i = 0, RING_SEGMENTS - 1 do
            local a = (i / RING_SEGMENTS) * math.pi * 2
            ringUnit[i + 1] = {math.sin(a), -math.cos(a)}
        end
    end
    return ringUnit
end

local function drawRing(cx, cy, radius, thickness, fraction, litColor, trackColor)
    local pts = ringPoints()
    local n = #pts
    local lit = math.floor(math.Clamp(fraction, 0, 1) * n + 0.5)
    for band = 0, thickness - 1 do
        local r = radius - band
        for i = 1, n do
            local p, q = pts[i], pts[(i % n) + 1]
            surface.SetDrawColor(i <= lit and litColor or trackColor)
            surface.DrawLine(cx + p[1] * r, cy + p[2] * r, cx + q[1] * r, cy + q[2] * r)
        end
    end
end

-- Legacy build: the pre-kit list/button UI, verbatim, used only when kit.lua has not loaded on this
-- client (A.Kit missing). Keeps every behaviour of the live page as a fallback.
local function legacyBuild(root)
    local owner = hg and hg.achievements
    local state = A.State.progress or {
        query = "",
        filter = "All"
    }

    A.State.progress = state
    local time = A.Label(root, "Your time in the city", "GoobTitle", T.green)
    local session = A.Status(root, "Waiting for playtime…")
    local summary = A.Status(root, "Loading achievements…")
    local list
    local function rebuild()
        if IsValid(list) then list:RefreshProgress() end
    end

    A.Entry(root, "Search achievements", state.query, function(v)
        state.query = v
        rebuild()
    end)

    A.Button(root, "Showing: " .. state.filter, function(s)
        state.filter = state.filter == "All" and "In progress" or state.filter == "In progress" and "Completed" or "All"
        s:SetText("Showing: " .. state.filter)
        rebuild()
    end)

    list = A.Scroll(root)
    function list:RefreshProgress()
        self:Clear()
        if not owner then
            A.Status(self, "Achievements are not available yet.")
            return
        end

        local data = owner.achievements_data or {}
        local localData = owner.GetLocalAchievements and owner.GetLocalAchievements() or {}
        local rows = A.SortedRows(data.created_achevements, function(v) return v.name or v.key end)
        local complete, count = 0, 0
        for _, row in ipairs(rows) do
            local def = row.data
            local value, target, fraction, done = A.AchievementProgress(def, localData[def.key])
            if done then complete = complete + 1 end
            if A.Matches((def.name or "") .. " " .. (def.description or ""), state.query) and (state.filter == "All" or state.filter == "Completed" and done or state.filter == "In progress" and not done) then
                count = count + 1
                local card = A.Card(self)
                A.Label(card, (done and "✓  " or "") .. (def.name or def.key), "GoobBody", done and T.green or T.text)
                A.Status(card, def.description or "")
                A.Status(card, done and "Completed" or tostring(value) .. " / " .. tostring(target), done and T.green or T.muted)
                local bar = vgui.Create("DPanel", card)
                bar:Dock(TOP)
                bar:SetTall(5)
                bar.Paint = function(_, w, h)
                    draw.RoundedBox(2, 0, 0, w, h, T.line)
                    if fraction > 0 then draw.RoundedBox(2, 0, 0, w * fraction, h, done and T.green or T.accent) end
                end
            end
        end

        summary:SetText(#rows > 0 and complete .. " of " .. #rows .. " achievements completed" or "No achievement data received yet. Use Refresh to request it.")
        if count == 0 then A.Status(self, #rows > 0 and "No achievements match this view." or "Your achievements will appear here when the server responds.") end
        root.defs = data.created_achevements
        root.records = localData
    end

    local function request()
        if owner and owner.LoadAchievements then owner.LoadAchievements() end
    end

    local refresh = A.Button(root, "Refresh achievements", request)
    refresh:Dock(BOTTOM)
    request()
    list:RefreshProgress()
    root.Think = function(s)
        if (s.nextRefresh or 0) > RealTime() then return end
        s.nextRefresh = RealTime() + 1
        local p = LocalPlayer()
        if not IsValid(p) then return end
        local total = p:GetNWInt("ZCPlaytimeTotal", -1)
        time:SetText(total >= 0 and A.Duration(total) .. " played" or "Playtime unavailable")
        local current = p:GetNWInt("ZCPlaytimeSession", -1)
        session:SetText(current >= 0 and "This session · " .. A.Duration(current) .. "  /  Updated by the server" or "Waiting for the playtime tracker.")
        local data = owner and owner.achievements_data
        local records = owner and owner.GetLocalAchievements and owner.GetLocalAchievements()
        if data and (data.created_achevements ~= s.defs or records ~= s.records) then list:RefreshProgress() end
    end
end

-- Kit build (mockups/03_progress.html): header card with two tabular metrics + a completion ring,
-- a search entry + segmented filter, and achievement cards in a self-sizing 2/1 column grid.
-- Data sources, poll cadence and A.State.progress fields are unchanged from the live page.
local function build(root)
    local K = A.Kit
    if not K then return legacyBuild(root) end
    local owner = hg and hg.achievements
    local state = A.State.progress or {
        query = "",
        filter = "All"
    }
    A.State.progress = state

    local FILTERS = {"All", "In progress", "Completed"}
    local filterIndex = 1
    for i, label in ipairs(FILTERS) do
        if label == state.filter then filterIndex = i end
    end

    local rebuild -- forward-declared: the search entry and filter control below both trigger it

    -- Header: lifetime + session metrics (GoobMetric size, 30/600) and the completion ring. Also
    -- carries the "Refresh achievements" capability the live page docks bottom (progress.lua.orig:83-85)
    -- as a small corner button, since the 1 s poll already covers what a manual refresh used to do
    -- for playtime — this only re-requests achievement data from the server.
    local header = K.Panel(root)
    header:Dock(TOP)
    header:SetTall(72)
    header:DockMargin(0, 0, 0, 8)
    header.Lifetime, header.Session = "--", "--"
    header.Complete, header.Total = 0, 0
    header.RingLabel = "0/0"
    local refreshBtn -- the ring itself is the refresh control (tap to re-request achievement data)
    header.Paint = function(s, w, h)
        K.Card(0, 0, w, h, T.cardGlass, K.Alpha(T.edge, 180))
        local ringSize = 56
        local ringX = w - 14 - ringSize
        local col1X = 14
        -- 30 px metrics as in the mockup; the smallest phone steps down to 22 px so "123h 45m" fits.
        local metric = w >= 440 and 30 or 22
        local col2X = math.min(math.floor(w * 0.42), ringX - 90)
        K.Text("LIFETIME", 11, 600, col1X, 12, T.muted)
        K.Text(K.Fit(s.Lifetime, K.Font(metric, 600), (col2X > col1X and col2X or ringX) - col1X - 10), metric, 600, col1X, 26, T.text)
        if col2X > col1X + 60 then
            surface.SetDrawColor(T.hair)
            surface.DrawRect(col2X - 8, 10, 1, h - 20)
            K.Text("THIS SESSION", 11, 600, col2X, 12, T.muted)
            K.Text(K.Fit(s.Session, K.Font(metric, 600), ringX - col2X - 20), metric, 600, col2X, 26, T.text)
        end
        local cx, cy = ringX + ringSize / 2, h / 2
        local fraction = s.Total > 0 and s.Complete / s.Total or 0
        local hover = IsValid(refreshBtn) and K.Hover(refreshBtn) or 0
        drawRing(cx, cy, ringSize / 2, 5, fraction, T.green, K.Alpha(T.white, 22 + 40 * hover))
        K.Text(s.RingLabel, 12, 700, cx, cy, T.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    refreshBtn = vgui.Create("DButton", header)
    refreshBtn:SetText("")
    refreshBtn:SetCursor("hand")
    refreshBtn:SetTooltip("Refresh achievements")
    refreshBtn.Paint = function() end
    header.PerformLayout = function(_, w, h)
        refreshBtn:SetPos(w - 14 - 56, math.floor((h - 56) / 2))
        refreshBtn:SetSize(56, 56)
    end

    -- Search + filter row. A.Entry is already card-styled (T.card fill, T.main focus outline).
    local searchEntry = A.Entry(root, "Search achievements", state.query, function(v)
        state.query = v
        if rebuild then rebuild() end
    end)
    searchEntry:SetFont(K.Font(14, 500))

    local seg = K.Segmented(root, FILTERS, filterIndex, function(_, label)
        state.filter = label
        if rebuild then rebuild() end
    end)
    seg:Dock(TOP)
    seg:DockMargin(0, 0, 0, 8)

    -- Achievement list: a self-sizing grid (2 columns from ~520 px wide, 1 below) inside a scroll
    -- panel, same as the app body stacking to 1 column under the 360 px breakpoint at the smallest
    -- phone (tokens.md #4). minTile 256 + 8 px gap makes the 2-column crossover land at 520 px.
    local listArea = K.Panel(root)
    listArea:Dock(FILL)
    local scroll = A.Scroll(listArea)
    local grid = K.Grid(scroll, 256, 92, 8, 8, 2)
    grid:Dock(TOP)

    local function buildCard(parent)
        local card = K.Panel(parent)
        card.Paint = function(s, w, h)
            K.Card(0, 0, w, h, T.cardGlass, K.Alpha(T.edge, 150))
            local e = s.Entry
            if not e then return end
            K.Plate(10, 10, 36, e.done and "check" or "bars")
            local nameX = 56
            if e.done then
                draw.RoundedBox(7, nameX, 11, 14, 14, T.green)
                K.Glyph("check", nameX + 7, 18, 9, T.ink)
                nameX = nameX + 20
            end
            K.Text(K.Fit(e.name, K.Font(13, 600), w - nameX - 8), 13, 600, nameX, 9, T.text)
            if e.done then
                K.Text("Completed", 11, 500, 56, h - 18, T.green)
            else
                K.Text(e.label, 11, 500, w - 10, h - 18, T.muted, TEXT_ALIGN_RIGHT)
            end
        end
        local desc = vgui.Create("DLabel", card)
        desc:SetFont(K.Font(11, 500))
        desc:SetTextColor(T.muted)
        desc:SetWrap(true)
        card.Desc = desc
        card.Bar = K.Bar(card, 0, T.main)
        card.PerformLayout = function(s, w, h)
            s.Desc:SetPos(56, 30)
            s.Desc:SetSize(math.max(1, w - 66), 24)
            if s.Entry and not s.Entry.done then
                s.Bar:SetVisible(true)
                s.Bar:SetPos(56, h - 22)
                s.Bar:SetSize(math.max(1, w - 56 - 66), 6)
            else
                s.Bar:SetVisible(false)
            end
        end
        return card
    end

    local function fillCard(card, e)
        card.Entry = e
        card.Desc:SetText(e.description)
        if not e.done then card.Bar:SetFraction(e.fraction) end
        card:InvalidateLayout()
    end

    local function showEmpty(title, body)
        if IsValid(listArea.Empty) then listArea.Empty:Remove() end
        scroll:SetVisible(false)
        listArea.Empty = K.EmptyState(listArea, "bars", title, body)
    end

    rebuild = function()
        if IsValid(listArea.Empty) then
            listArea.Empty:Remove()
            listArea.Empty = nil
        end
        if not owner then
            showEmpty("Achievements unavailable", "Achievements are not available yet.")
            return
        end

        local data = owner.achievements_data or {}
        local localData = owner.GetLocalAchievements and owner.GetLocalAchievements() or {}
        local rows = A.SortedRows(data.created_achevements, function(v) return v.name or v.key end)
        local complete, matches = 0, {}
        for _, row in ipairs(rows) do
            local def = row.data
            local value, target, fraction, done = A.AchievementProgress(def, localData[def.key])
            if done then complete = complete + 1 end
            if A.Matches((def.name or "") .. " " .. (def.description or ""), state.query)
                and (state.filter == "All" or (state.filter == "Completed") == done) then
                matches[#matches + 1] = {
                    name = def.name or def.key,
                    description = def.description or "",
                    value = value,
                    target = target,
                    fraction = fraction,
                    done = done,
                    label = tostring(value) .. " / " .. tostring(target)
                }
            end
        end
        header.Complete, header.Total = complete, #rows
        header.RingLabel = complete .. "/" .. #rows
        root.defs, root.records = data.created_achevements, localData

        if #matches == 0 then
            if #rows == 0 then
                showEmpty("No achievements yet", "Your achievements will appear here when the server responds.")
            elseif state.query ~= "" then
                showEmpty("No achievements match your search", "Try a different search term.")
            elseif state.filter == "Completed" then
                showEmpty("No completed achievements yet", "Try the \"All\" filter to see what's in progress.")
            elseif state.filter == "In progress" then
                showEmpty("Nothing in progress", "Try the \"All\" filter to see what's in progress.")
            else
                showEmpty("No achievements match this view", "Try a different search term.")
            end
            return
        end

        scroll:SetVisible(true)
        local children = grid:GetChildren()
        for i = 1, math.max(#matches, #children) do
            local card = children[i]
            if i <= #matches then
                if not IsValid(card) then card = buildCard(grid) end
                fillCard(card, matches[i])
            elseif IsValid(card) then
                card:Remove()
            end
        end
    end

    local function request()
        if owner and owner.LoadAchievements then owner.LoadAchievements() end
    end
    refreshBtn.DoClick = request

    request()
    rebuild()
    root.Think = function(s)
        if (s.nextRefresh or 0) > RealTime() then return end
        s.nextRefresh = RealTime() + 1
        local p = LocalPlayer()
        if not IsValid(p) then return end
        local total = p:GetNWInt("ZCPlaytimeTotal", -1)
        header.Lifetime = total >= 0 and A.Duration(total) or "--"
        local current = p:GetNWInt("ZCPlaytimeSession", -1)
        header.Session = current >= 0 and A.Duration(current) or "--"
        local data = owner and owner.achievements_data
        local records = owner and owner.GetLocalAchievements and owner.GetLocalAchievements()
        if data and (data.created_achevements ~= s.defs or records ~= s.records) then rebuild() end
    end
end

A.Register("progress", "Progress", "Playtime & achievements", "icon16/award_star_gold_1.png", T.green, build)
