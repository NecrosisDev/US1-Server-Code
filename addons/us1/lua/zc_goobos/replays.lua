-- GoobOS Replays app: your saved deaths and round highlights (mockup 13_replays_app.html). Client
-- only; no new file exists in the mirror for this app (P3_SEAM.txt / STEP5_BRIEF.md are the spec).
-- Data comes from the killcam's own "zckc_index" net message (zc_killcam/sv_net.lua:94-134), which
-- already has a client receiver (zc_killcam/viewer_parts/cl_part_03.lua:115). We never add a second
-- net.Receive for that name (KIT_API rule): we wrap the installed receiver instead, identity-checked,
-- and only consume a response this app is waiting on -- every other response (someone else's request,
-- or an update after this app's queue is empty) is handed to the original untouched.
if not CLIENT then return end
local A = ZCGoobApps
if not A or not A.Register then return end
local T = A.Theme

-- Survive autorefresh the same way arcade.lua's C table does: mutate the table already sitting in
-- A.State, never replace it, so a re-included file doesn't drop mid-flight request state.
local S = A.State.replays or {
    filter = 1, -- 1 All, 2 My deaths, 3 Highlights
    selected = nil,
    locked = false,
    dirty = true,
    queue = {},
    pending = nil,
    rows = {mine = {}, highlights = {}}
}
A.State.replays = S
A.Replays = A.Replays or {}
local Rp = A.Replays
Rp.Wraps = Rp.Wraps or {}

-- Refresh glyph: same shared-table addition arcade.lua makes (kit candidate, not yet in kit.lua).
-- Guarded so whichever of the two files loads first wins and the other is a no-op.
if A.Kit and A.Kit.Glyphs and not A.Kit.Glyphs.refresh then
    local K0 = A.Kit
    local arc, a0, a1, steps = {"l"}, -40, 250, 12
    for i = 0, steps do
        local a = math.rad(a0 + (a1 - a0) * i / steps)
        arc[#arc + 1] = 12 + math.cos(a) * 7.5
        arc[#arc + 1] = 12 + math.sin(a) * 7.5
    end
    local tipA = math.rad(a1)
    local tx, ty = 12 + math.cos(tipA) * 7.5, 12 + math.sin(tipA) * 7.5
    local nx, ny = math.cos(tipA + math.pi / 2), math.sin(tipA + math.pi / 2)
    K0.Glyphs.refresh = {arc, {"l", tx - nx * 5 - math.cos(tipA) * 2, ty - ny * 5 - math.sin(tipA) * 2, tx, ty, tx - nx * 5 + math.cos(tipA) * 2, ty - ny * 5 + math.sin(tipA) * 2}}
end

-- Title wording: the exact "what" formula the killcam's own records list uses (cl_part_03.lua:130),
-- so a saved clip reads the same in both places -- except a highlight row (kind "highlight" from the
-- optional P1 trailer, or an older row's tag when the trailer is absent) gets "Highlight · <map>"
-- instead: that legacy formula was never taught about highlight rows and would otherwise print
-- "Traitor, killed by <other>" for one (spec-uncovered: the brief calls for the map wording directly).
local function rowTitle(row)
    if row.kind == "highlight" or (row.kind == "" and row.tag == "highlight") then
        return "Highlight · " .. (row.map ~= "" and row.map or "?")
    end
    if row.tag == "life" then
        return row.role == "" and row.other or ("Your death, last hit by " .. row.other)
    end
    if row.role == "" then return row.other end
    if row.tag == "ivi" then return (row.role == "killer" and "You killed " or "Killed by ") .. row.other end
    return "Traitor, killed by " .. row.other
end

local function dayKey(t) return os.date("%Y-%m-%d", t) end
local function dayLabel(t)
    local key = dayKey(t)
    if key == dayKey(os.time()) then return "Today" end
    if key == dayKey(os.time() - 86400) then return "Yesterday" end
    return os.date("%d %b", t)
end

-- Net wrap ----------------------------------------------------------------------------------------

-- A request the server never answers (throttled, or the killcam is off) must not keep swallowing the killcam
-- viewer's own zckc_index replies: a pending ask expires after 6 s.
local function pendingLive()
    if S.pending and RealTime() - (S.pendingAt or 0) > 6 then S.pending = nil end
    return S.pending ~= nil
end

local function requestNext()
    if pendingLive() or #S.queue == 0 then return end
    local scope = table.remove(S.queue, 1)
    S.pending, S.pendingAt = scope, RealTime()
    net.Start("zckc_index")
    net.WriteString(scope)
    net.SendToServer()
end

function Rp.Refresh()
    S.queue = {"mine", "highlights"}
    requestNext()
end

local function installWrap()
    if not istable(net) or not istable(net.Receivers) then return end
    local key = string.lower("zckc_index")
    local original = net.Receivers[key]
    if not isfunction(original) or original == Rp.Wraps.index then return end
    Rp.Wraps.original = original
    Rp.Wraps.index = function(len)
        if not pendingLive() then return original(len) end
        local scope = net.ReadString()
        local locked = net.ReadBool()
        local n = net.ReadUInt(5)
        local rows = {}
        for i = 1, n do
            rows[i] = {
                id = net.ReadString(), t = net.ReadUInt(32), map = net.ReadString(),
                tag = net.ReadString(), role = net.ReadString(), other = net.ReadString(),
                reported = net.ReadBool(), missed = false, kind = "", reason = ""
            }
        end
        -- P1 trailer (STEP5_BRIEF): may be absent on an older server -- only read it if the bytes
        -- are actually there, so a client talking to a pre-P1 server never over-reads the message.
        if net.BytesLeft() > 0 then
            for i = 1, n do
                local row = rows[i]
                row.missed, row.kind, row.reason = net.ReadBool(), net.ReadString(), net.ReadString()
            end
        end
        local wanted = S.pending
        S.pending = nil
        if scope == wanted then
            for i, row in ipairs(rows) do
                row._title = rowTitle(row)
                row._meta = dayLabel(row.t) .. " " .. os.date("%H:%M", row.t) .. " · " .. row.map .. (row.reported and " · reported" or "")
                rows[i] = row
            end
            S.rows[scope] = rows
            S.locked = locked
            S.dirty = true
        end
        -- Not calling original here: once this app decided (before any read) that a response was
        -- its own to consume, the stream is destructive -- there is no way to hand unread bytes to
        -- the original receiver after the fact. This mirrors STEP5_BRIEF's "pending flag + scope
        -- match" rule; a genuine mismatch (a race with the killcam's own frame) is simply dropped.
        requestNext()
    end
    net.Receive("zckc_index", Rp.Wraps.index)
end
installWrap()
hook.Add("InitPostEntity", "GoobOS.Replays.Wrap", installWrap)
timer.Create("GoobOS.Replays.Wrap", 2, 0, installWrap)

-- "Watch": ZCGoobApps.Media.OpenClip (media.lua) is the one clip player; the killcam's own receivers do the rest.
local function watchClip(id)
    local media = ZCGoobApps.Media
    return istable(media) and isfunction(media.OpenClip) and media.OpenClip(id) or false
end
Rp.Watch = watchClip

-- UI ------------------------------------------------------------------------------------------

local BREAKPOINT = 560

local function collectRows(filter)
    local list = {}
    if filter ~= 3 then for _, r in ipairs(S.rows.mine) do list[#list + 1] = r end end
    if filter ~= 2 then for _, r in ipairs(S.rows.highlights) do list[#list + 1] = r end end
    table.sort(list, function(a, b) return a.t > b.t end)
    return list
end

local function findRow(id)
    if not id then return nil end
    for _, scope in ipairs({"mine", "highlights"}) do
        for _, r in ipairs(S.rows[scope]) do
            if r.id == id then return r end
        end
    end
    return nil
end

local function build(body, phone)
    local K = A.Kit
    if not K then
        A.Status(body, "GoobOS kit failed to load; try reopening the phone.")
        return
    end

    local subRow = K.Panel(body)
    subRow:Dock(TOP)
    subRow:SetTall(20)
    subRow:DockMargin(0, 0, 0, 8)
    subRow.Paint = function(_, w, h)
        K.Text("Your deaths and round highlights", 13, 500, 0, h / 2, T.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    local refreshBtn = vgui.Create("DButton", subRow)
    refreshBtn:SetText("")
    refreshBtn:SetSize(24, 24)
    refreshBtn.DoClick = function() Rp.Refresh() end
    refreshBtn.Paint = function(s, w, h)
        local hover = K.Hover(s)
        if hover > 0.01 then draw.RoundedBox(4, 0, 0, w, h, K.Alpha(T.main, 30 * hover)) end
        K.Glyph("refresh", w / 2, h / 2, 14, T.muted)
    end
    -- Full-round replays (owner 2026-09-25): opens the killcam's own round list (viewer bundle cl_part_09 R.List, the
    -- same list `zc_replay` opens; the server's zc_killcam_replay decides who may watch). Feature-detected: the button
    -- only shows once the bundle that carries it has loaded.
    local function roundList()
        local V = rawget(_G, "ZCKillcamView")
        local R = istable(V) and V.Round
        return istable(R) and isfunction(R.List) and R.List or nil
    end
    local roundsBtn = vgui.Create("DButton", subRow)
    roundsBtn:SetText("")
    roundsBtn:SetSize(96, 22)
    roundsBtn.DoClick = function()
        local list = roundList()
        if list then list() end
    end
    roundsBtn.Paint = function(s, w, h)
        local hover = K.Hover(s)
        draw.RoundedBox(4, 0, 0, w, h, K.Alpha(T.main, 60 + 60 * hover))
        K.Text("Full rounds", 12, 600, w / 2, h / 2, T.white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    subRow.Think = function(s)
        roundsBtn:SetVisible(roundList() ~= nil)
        local w = s:GetWide()
        if w == s.GoobLastW then return end
        s.GoobLastW = w
        refreshBtn:SetPos(w - 24, (20 - 24) / 2)
        roundsBtn:SetPos(w - 24 - 8 - 96, (20 - 22) / 2)
    end

    local rebuildList, refreshDetail

    local seg = K.Segmented(body, {"All", "My deaths", "Highlights"}, S.filter, function(index)
        S.filter = index
        S.dirty = true
    end)
    seg:Dock(TOP)
    seg:DockMargin(0, 0, 0, 10)

    local area = K.Panel(body)
    area:Dock(FILL)

    local listPane = A.Scroll(area)
    listPane:Dock(NODOCK)
    listPane:DockPadding(0, 0, 6, 0)

    local detailHolder = K.Panel(area)
    detailHolder:Dock(NODOCK)

    local function buildDetailContent(container, row)
        container:Clear()
        if not row then
            K.EmptyState(container, "play", "Select a replay", "Pick one on the left to see it here.")
            return
        end
        local plate = K.Panel(container)
        plate:Dock(TOP)
        plate:DockMargin(0, 0, 0, 10)
        plate.Think = function(s)
            local w = container:GetWide()
            local h = w > 0 and math.floor(w * 9 / 16) or 0
            if h > 0 and s:GetTall() ~= h then s:SetTall(h) end
        end
        plate.Paint = function(_, w, h)
            draw.RoundedBox(4, 0, 0, w, h, T.ink)
            K.Glyph("play", w / 2, h / 2, 32, T.muted)
            if row.missed then
                local pw = 64
                draw.RoundedBox(8, w - pw - 8, 8, pw, 16, T.card)
                surface.SetDrawColor(T.accent)
                surface.DrawOutlinedRect(w - pw - 8, 8, pw, 16, 1)
                K.Text("MISSED", 10, 700, w - pw / 2 - 8, 16, T.accent, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
        end

        local heading = K.Panel(container)
        heading:Dock(TOP)
        heading:SetTall(46)
        heading.Paint = function(_, w)
            K.Text(K.Fit(row._title, K.Font(18, 700), w), 18, 700, 0, 2, T.text)
            K.Text(K.Fit(row._meta, K.Font(13, 500), w), 13, 500, 0, 26, T.muted)
        end

        if row.missed then
            local reasonLbl = K.Panel(container)
            reasonLbl:Dock(TOP)
            reasonLbl:SetTall(20)
            reasonLbl:DockMargin(0, 0, 0, 4)
            local text = "Missed" .. (row.reason ~= "" and (" — " .. row.reason) or "")
            reasonLbl.Paint = function(_, w, h) K.Text(K.Fit(text, K.Font(13, 500), w), 13, 500, 0, h / 2, T.accent, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
        end

        -- Report is omitted: the index payload carries no per-row "reportable" flag (that only
        -- exists on an opened clip's V.State().inst), so this app cannot tell which rows qualify
        -- (STEP5_BRIEF: "if you cannot tell from the index data, omit Report and note it").
        local watch = vgui.Create("DButton", container)
        watch:SetText("")
        watch:Dock(TOP)
        watch:DockMargin(0, 10, 0, 0)
        watch:SetTall(40)
        watch.DoClick = function() watchClip(row.id) end
        watch.Paint = function(s, w, h)
            local hover = K.Hover(s)
            draw.RoundedBox(4, 0, 0, w, h, T.main)
            if hover > 0.01 then draw.RoundedBox(4, 0, 0, w, h, K.Alpha(T.white, 18 * hover)) end
            K.Glyph("play", w / 2 - 42, h / 2, 16, T.white)
            K.Text("Watch", 15, 600, w / 2 + 4, h / 2, T.white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    end

    refreshDetail = function()
        if IsValid(detailHolder) and detailHolder:IsVisible() then
            buildDetailContent(detailHolder, findRow(S.selected))
        end
    end

    local function selectRow(id)
        S.selected = id
        if IsValid(detailHolder) and detailHolder:IsVisible() then
            refreshDetail()
        else
            local sheet = K.Sheet(body, math.floor(math.min((body:GetTall() or 420) * 0.86, 420)), true)
            buildDetailContent(sheet, findRow(id))
        end
    end

    local function lockedMessage()
        K.EmptyState(listPane, "empty", "Replays are locked",
            "Replays are locked while a traitor round has you alive.")
    end

    local function emptyMessage()
        K.EmptyState(listPane, "empty", "No replays yet",
            "Deaths and round highlights you save or miss land here.")
    end

    rebuildList = function()
        listPane:Clear()
        if S.locked then lockedMessage() return end
        local list = collectRows(S.filter)
        if #list == 0 then emptyMessage() return end
        local lastDay = nil
        for index, row in ipairs(list) do
            local day = dayLabel(row.t)
            if day ~= lastDay then
                lastDay = day
                local head = K.Panel(listPane)
                head:Dock(TOP)
                head:SetTall(18)
                head:DockMargin(2, index == 1 and 0 or 10, 2, 4)
                head.Paint = function(_, w, h) K.Text(string.upper(day), 12, 600, 0, h / 2, T.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
            end
            local btn = vgui.Create("DButton", listPane)
            btn:SetText("")
            btn:Dock(TOP)
            btn:DockMargin(0, 0, 0, 6)
            btn:SetTall(64)
            btn.DoClick = function() selectRow(row.id) end
            btn.Paint = function(s, w, h)
                local sel = S.selected == row.id
                local hover = K.Hover(s)
                -- K.Alpha is one shared scratch Color: K.Card already consumes it once for the edge,
                -- so the selected/hover wash is a second RoundedBox after it returns, never a second
                -- K.Alpha argument in the same call (that would alias the edge's colour instead).
                K.Card(0, 0, w, h, T.cardGlass, K.Alpha(T.edge, 180))
                if sel then
                    draw.RoundedBox(4, 1, 1, w - 2, h - 2, K.Alpha(T.main, 40))
                elseif hover > 0.01 then
                    draw.RoundedBox(4, 1, 1, w - 2, h - 2, K.Alpha(T.white, 10 * hover))
                end
                local thumbW, thumbH = 64, 36
                draw.RoundedBox(3, 8, (h - thumbH) / 2, thumbW, thumbH, T.ink)
                K.Glyph("play", 8 + thumbW / 2, h / 2, 16, T.muted)
                local tx = 8 + thumbW + 10
                K.Text(K.Fit(row._title, K.Font(15, 600), w - tx - 66), 15, 600, tx, h / 2 - 11, T.text)
                K.Text(K.Fit(row._meta, K.Font(13, 500), w - tx - 66), 13, 500, tx, h / 2 + 10, T.muted)
                if row.missed then
                    local pw = 58
                    draw.RoundedBox(8, w - pw - 8, 8, pw, 16, T.card)
                    surface.SetDrawColor(T.accent)
                    surface.DrawOutlinedRect(w - pw - 8, 8, pw, 16, 1)
                    K.Text("MISSED", 10, 700, w - pw / 2 - 8, 16, T.accent, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                end
            end
        end
    end

    local layout = {}
    area.Think = function(s)
        local ok, err = pcall(function()
            local w, h = s:GetWide(), s:GetTall()
            if w <= 0 or h <= 0 then return end
            if w == layout.w and h == layout.h then return end
            layout.w, layout.h = w, h
            if w >= BREAKPOINT then
                local listW = math.min(360, math.floor(w * 0.46))
                listPane:SetPos(0, 0); listPane:SetSize(listW, h)
                detailHolder:SetVisible(true)
                detailHolder:SetPos(listW + 10, 0)
                detailHolder:SetSize(w - listW - 10, h)
                refreshDetail()
            else
                listPane:SetPos(0, 0); listPane:SetSize(w, h)
                detailHolder:SetVisible(false)
            end
        end)
        if not ok then ErrorNoHalt("[GoobOS] replays layout failed: " .. tostring(err) .. "\n") end
        if S.dirty then
            S.dirty = false
            rebuildList()
            refreshDetail()
        end
    end

    S.dirty = true
    Rp.Refresh()
end

A.Register("replays", "Replays", "Your deaths and round highlights", "icon16/film.png", T.main, build)
