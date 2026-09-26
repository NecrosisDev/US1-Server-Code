-- GoobOS Replays app: your saved deaths, round highlights and shared clips (mockup 13_replays_app.html). Client
-- only; no new file exists in the mirror for this app (P3_SEAM.txt / STEP5_BRIEF.md are the spec).
-- Data comes from the killcam's own "zckc_index" net message (zc_killcam/sv_net.lua), which already has a client
-- receiver (zc_killcam/viewer_parts/cl_part_03.lua:115). We never add a second net.Receive for that name (KIT_API
-- rule): we wrap the installed receiver instead, identity-checked, and only consume a response this app is waiting
-- on -- every other response (someone else's request, or an update after this app's queue is empty) is handed to
-- the original untouched.
-- UI cohesion U2 (2026-09-26): a "Clips" filter (clips on live CityLeak posts - scope "shared" - and your saved
-- clips), paging past 31 rows ("Load more": an optional UInt(16) offset on the request, an optional trailer on the
-- reply that the viewer never reads), and Watch / Share / Report in the detail view. Other files read
-- A.State.replays.rows.highlights (roundend.lua): its shape - an array of rows with kind and tag - stays.
if not CLIENT then return end
local A = ZCGoobApps
if not A or not A.Register then return end
local T = A.Theme

-- Survive autorefresh the same way arcade.lua's C table does: mutate the table already sitting in
-- A.State, never replace it, so a re-included file doesn't drop mid-flight request state.
local S = A.State.replays or {
    filter = 1, -- 1 All, 2 My deaths, 3 Highlights, 4 Clips
    selected = nil,
    locked = false,
    dirty = true,
    queue = {},
    pending = nil,
    rows = {mine = {}, highlights = {}}
}
A.State.replays = S
S.rows.shared, S.rows.focus = S.rows.shared or {}, S.rows.focus or {}
S.more, S.next = S.more or {}, S.next or {} -- per scope: may there be more rows, and the offset to ask from
A.Replays = A.Replays or {}
local Rp = A.Replays
Rp.Wraps = Rp.Wraps or {}
local FILTERS = {"All", "My deaths", "Highlights", "Clips"}
local SCOPES = {{"mine", "highlights"}, {"mine"}, {"highlights"}, {"shared", "mine"}}

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
-- A shared row's `other` is "<poster>: <caption>" (sv_net.lua sharedRows): the caption is the title.
local function sharedParts(row)
    local name, caption = string.match(row.other or "", "^(.-): (.+)$")
    return name or row.other or "?", caption
end
local function rowTitle(row)
    if row.kind == "shared" then
        local name, caption = sharedParts(row)
        return caption or ("Clip shared by " .. name)
    end
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

local function decorate(row, scope)
    row.scope = scope
    row.shared = row.kind == "shared"
    -- a party may post it: your own records are yours; a highlight was shown to everyone; a shared row says so
    row.party = scope == "mine" or scope == "highlights" or row.mine == true
    row._title = rowTitle(row)
    local when = dayLabel(row.t) .. " " .. os.date("%H:%M", row.t)
    if row.shared then
        row._meta = "Shared by " .. (sharedParts(row)) .. " · " .. when .. (row.map ~= "" and (" · " .. row.map) or "")
    else
        row._meta = when .. " · " .. row.map .. (row.reported and " · reported" or "")
    end
    return row
end

-- Net wrap ----------------------------------------------------------------------------------------

-- A request the server never answers (throttled, or the killcam is off) must not keep swallowing the killcam
-- viewer's own zckc_index replies: a pending ask expires after 6 s.
local function pendingLive()
    if S.pending and RealTime() - (S.pendingAt or 0) > 6 then S.pending = nil end
    return S.pending ~= nil
end

-- The server answers one zckc_index a second per player (sv_net.lua throttled "index", 1) and drops the rest, so the
-- queue is paced: a request sent sooner would be dropped and stall the queue until its 6 s expiry.
local GAP = 1.1
local function requestNext()
    if pendingLive() or #S.queue == 0 then return end
    local wait = (S.sentAt or -100) + GAP - RealTime()
    if wait > 0 then
        timer.Create("GoobOS.Replays.Next", wait, 1, requestNext)
        return
    end
    local ask = table.remove(S.queue, 1)
    if not istable(ask) then ask = {scope = tostring(ask), offset = 0} end -- a queue left by the pre-U2 file (autorefresh)
    S.pending, S.pendingAt, S.sentAt = ask, RealTime(), RealTime()
    net.Start("zckc_index")
    net.WriteString(ask.scope)
    net.WriteUInt(math.Clamp(ask.offset or 0, 0, 65535), 16) -- U2 paging; a server that predates it reads only the scope
    net.SendToServer()
    -- an unanswered ask lapses in pendingLive(); this is what moves the queue on when that happens
    timer.Create("GoobOS.Replays.Expire", 6.1, 1, function() if not pendingLive() then requestNext() end end)
end
Rp.RequestNext = requestNext

local function shareOn()
    local sh = A.Share
    return istable(sh) and isfunction(sh.Enabled) and sh.Enabled() or false
end

function Rp.Refresh()
    if not S.focus then S.rows.focus = {} end -- a "Watch in Replays" row lives until the next plain visit
    S.queue = {{scope = "mine", offset = 0}, {scope = "highlights", offset = 0}}
    if shareOn() then S.queue[3] = {scope = "shared", offset = 0} else S.rows.shared, S.more.shared = {}, nil end
    requestNext()
end
-- "Load more" for the scopes behind a filter that said they have more.
function Rp.More(filter)
    for _, scope in ipairs(SCOPES[filter or S.filter] or {}) do
        if S.more[scope] then
            local queued = false
            for _, ask in ipairs(S.queue) do if ask.scope == scope then queued = true end end
            if not queued then S.queue[#S.queue + 1] = {scope = scope, offset = S.next[scope] or #S.rows[scope]} end
        end
    end
    requestNext()
end

-- Reads one zckc_index reply (the caller has decided it is ours). Returns scope, locked, rows, next offset, more.
function Rp.ReadIndex()
    local scope = net.ReadString()
    local locked = net.ReadBool()
    local n = net.ReadUInt(5)
    local rows = {}
    for i = 1, n do
        rows[i] = {
            id = net.ReadString(), t = net.ReadUInt(32), map = net.ReadString(),
            tag = net.ReadString(), role = net.ReadString(), other = net.ReadString(),
            reported = net.ReadBool(), missed = false, kind = "", reason = "", post = 0, mine = false
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
    -- U2 paging trailer, same rule: the next offset, whether there is more, then per row the post and "yours".
    local nextAt, more
    if net.BytesLeft() > 0 then
        nextAt, more = net.ReadUInt(16), net.ReadBool()
        for i = 1, n do
            local row = rows[i]
            row.post, row.mine = net.ReadUInt(32), net.ReadBool()
        end
    end
    return scope, locked, rows, nextAt, more
end

local function installWrap()
    if not istable(net) or not istable(net.Receivers) then return end
    local key = string.lower("zckc_index")
    local original = net.Receivers[key]
    if not isfunction(original) or original == Rp.Wraps.index then return end
    Rp.Wraps.original = original
    Rp.Wraps.index = function(len)
        if not pendingLive() then return original(len) end
        local scope, locked, rows, nextAt, more = Rp.ReadIndex()
        local wanted = S.pending
        S.pending = nil
        if istable(wanted) and scope == wanted.scope then
            for _, row in ipairs(rows) do decorate(row, scope) end
            local list = S.rows[scope] or {}
            if (wanted.offset or 0) > 0 then
                local seen = {}
                for _, row in ipairs(list) do seen[row.id] = true end
                for _, row in ipairs(rows) do if not seen[row.id] then list[#list + 1] = row end end
            else
                list = rows
            end
            S.rows[scope] = list
            S.next[scope] = nextAt or ((wanted.offset or 0) + #rows)
            S.more[scope] = more == true
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

-- Open Replays on one clip (CityLeak "Watch in Replays"): the Clips filter with that clip selected. `info` describes
-- it (name, body, created, post, mine) so it shows even before - or beyond the first page of - the shared list.
function Rp.Show(id, info)
    if not (isstring(id) and #id <= 24 and string.match(id, "^%d+_%d+$")) then return false end
    info = istable(info) and info or {}
    local caption = string.Trim(string.gsub(tostring(info.body or ""), "[%c]", " "))
    local row = {id = id, t = tonumber(info.created) or os.time(), map = "", tag = "shared", role = "",
        other = tostring(info.name or "?") .. (caption ~= "" and (": " .. caption) or ""), reported = false, missed = false,
        kind = "shared", reason = "", post = tonumber(info.post) or 0, mine = info.mine == true}
    S.rows.focus = {decorate(row, "focus")}
    S.filter, S.selected, S.focus, S.dirty = 4, id, id, true
    return A.Launch("replays") == true
end

-- UI ------------------------------------------------------------------------------------------

local BREAKPOINT = 560

local function collectRows(filter)
    local list, seen = {}, {}
    local function add(r) if not seen[r.id] then seen[r.id] = true list[#list + 1] = r end end
    if filter == 4 then
        for _, r in ipairs(S.rows.shared) do add(r) end
        for _, r in ipairs(S.rows.focus) do add(r) end
        for _, r in ipairs(S.rows.mine) do if not r.missed then add(r) end end -- your saved clips
    else
        if filter ~= 3 then for _, r in ipairs(S.rows.mine) do add(r) end end
        if filter ~= 2 then for _, r in ipairs(S.rows.highlights) do add(r) end end
    end
    table.sort(list, function(a, b) return a.t > b.t end)
    return list
end

local function findRow(id)
    if not id then return nil end
    for _, scope in ipairs({"mine", "highlights", "shared", "focus"}) do
        for _, r in ipairs(S.rows[scope] or {}) do
            if r.id == id then return r end
        end
    end
    return nil
end

-- One chip painter for every state pill in this app (the two MISSED copies were merged): the kit's small-caps chip.
local chipScaler
local function rowChips(row)
    local out = {}
    if row.missed then out[#out + 1] = {"MISSED", T.accent} end
    if row.reported then out[#out + 1] = {"REPORTED", T.gold} end
    if row.shared then out[#out + 1] = {"SHARED", T.green} end
    return out
end
-- Draws the row's chips right-aligned ending at x; returns the width they took.
local function paintChips(row, x, y)
    local K = A.Kit
    chipScaler = chipScaler or K.Scaler(1)
    local x0 = x
    for _, chip in ipairs(rowChips(row)) do
        x = x - chipScaler.chip(chip[1], x, y, chip[2], K.Alpha(T.chip or T.ink, 220), TEXT_ALIGN_RIGHT) - 4
    end
    return x0 - x
end

local function shareSpec(row)
    return {kind = "clip", clip = row.id, title = row._title, party = row.party, shared = row.shared}
end

local function build(body, phone)
    local K = A.Kit
    if not K then
        A.Status(body, "GoobOS kit failed to load; try reopening the phone.")
        return
    end

    local subRow = K.Panel(body)
    subRow:Dock(TOP)
    subRow:SetTall(24)
    subRow:DockMargin(0, 0, 0, 8)
    subRow.Paint = function(_, w, h)
        K.Text(K.Fit("Your deaths, highlights and shared clips", K.Font(13, 500), w - 150), 13, 500, 0, h / 2, T.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    local refreshBtn = vgui.Create("DButton", subRow)
    refreshBtn:SetText("")
    refreshBtn:SetSize(24, 24)
    refreshBtn:SetTooltip("Refresh")
    refreshBtn.DoClick = function() Rp.Refresh() end
    refreshBtn.Paint = function(s, w, h)
        local hover = K.Hover(s)
        if hover > 0.01 then draw.RoundedBox(T.radius.card, 0, 0, w, h, K.Alpha(T.main, 30 * hover)) end
        K.Glyph("refresh", w / 2, h / 2, 14, T.muted)
    end
    -- Full-round replays (owner 2026-09-25): opens the killcam's own round list (viewer bundle cl_part_09 R.List, the
    -- same list `zc_replay` opens; the server's zc_killcam_replay decides who may watch). U2: always shown, greyed
    -- with the reason until the bundle that carries it has loaded.
    local function roundList()
        local V = rawget(_G, "ZCKillcamView")
        local R = istable(V) and V.Round
        return istable(R) and isfunction(R.List) and R.List or nil
    end
    local roundsBtn = K.Button(subRow, {label = "Full rounds", size = 12, dock = false, enabled = function() return roundList() ~= nil end,
        click = function() local list = roundList() if list then list() end end})
    roundsBtn:SetSize(104, 24)
    subRow.Think = function(s)
        local reason = roundList() and "Every round you played, from its start" or "Round replays have not loaded yet. Try again in a moment."
        if roundsBtn.GoobTip ~= reason then roundsBtn.GoobTip = reason roundsBtn:SetTooltip(reason) end
        local w = s:GetWide()
        if w == s.GoobLastW then return end
        s.GoobLastW = w
        refreshBtn:SetPos(w - 24, 0)
        roundsBtn:SetPos(w - 24 - 8 - 104, 0)
    end

    local rebuildList, refreshDetail

    local seg = K.Segmented(body, FILTERS, S.filter, function(index)
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

    local function status(parent, text, color)
        local line = K.Panel(parent)
        line:Dock(TOP)
        line:SetTall(18)
        line:DockMargin(0, 0, 0, 6)
        line.Paint = function(_, w, h) K.Text(K.Fit(text, K.Font(12, 500), w), 12, 500, 0, h / 2, color or T.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
        return line
    end

    local function buildDetailContent(container, row)
        container:Clear()
        if not row then
            K.EmptyState(container, "play", "Select a replay", "Pick one on the left to see it here.")
            return
        end
        local scroll = A.Scroll(container)
        local plate = vgui.Create("DButton", scroll)
        plate:SetText("")
        plate:Dock(TOP)
        plate:DockMargin(0, 0, 0, 10)
        plate:SetTooltip("Watch")
        plate.DoClick = function() watchClip(row.id) end
        plate.Think = function(s)
            local w = container:GetWide() - 8
            local h = w > 0 and math.floor(w * 9 / 16) or 0
            if h > 0 and s:GetTall() ~= h then s:SetTall(h) end
        end
        plate.Paint = function(s, w, h)
            draw.RoundedBox(T.radius.card, 0, 0, w, h, T.ink)
            K.Glyph("play", w / 2, h / 2, 32, K.Hover(s) > 0.5 and T.text or T.muted)
            paintChips(row, w - 8, 8)
        end

        local heading = K.Panel(scroll)
        heading:Dock(TOP)
        heading:SetTall(46)
        heading.Paint = function(_, w)
            K.Text(K.Fit(row._title, K.Font(18, 700), w), 18, 700, 0, 2, T.text)
            K.Text(K.Fit(row._meta, K.Font(13, 500), w), 13, 500, 0, 26, T.muted)
        end

        if row.missed then status(scroll, "Missed" .. (row.reason ~= "" and (" · " .. row.reason) or ""), T.accent) end
        -- What the death screen promised ("Change this later in Replays › My deaths"): the index carries the report
        -- flag, so it is shown; the forgive decision is not in the index (it lives in the guilt system), so it is not.
        if row.reported then status(scroll, "You reported a hit in this replay to staff.", T.gold) end

        K.Button(scroll, {label = "Watch", kind = "primary", glyph = "play", click = function() watchClip(row.id) end})

        local sh = A.Share
        local spec = shareSpec(row)
        local canShare, whyNot = false, "Sharing is not loaded."
        if istable(sh) and isfunction(sh.Available) then canShare, whyNot = sh.Available(spec) end
        K.Button(scroll, {label = "Share", glyph = "chat",
            enabled = function() return istable(sh) and isfunction(sh.Open) and (sh.Available(spec)) end,
            click = function() sh.Open(spec) end})
        if not canShare then status(scroll, whyNot) end

        -- Report: the killcam's report dialog (cl_part_03 V.ReportDialog) needs the hit list of a death sequence,
        -- which the index does not carry - but the killcam records view that Watch opens lists every hit of a saved
        -- death with its own "Report this hit to staff" control. So Report opens that, for your own deaths only.
        if row.scope == "mine" and row.tag == "life" then
            K.Button(scroll, {label = "Report a hit", kind = "ghost", glyph = "flag", click = function() watchClip(row.id) end})
            status(scroll, "Opens the killcam records: pick the hit, then Report this hit to staff.")
        elseif row.scope == "mine" then
            status(scroll, "Report from the death screen or the killcam records.")
        end

        if (row.post or 0) > 0 then
            K.Button(scroll, {label = "Open the post in CityLeak", glyph = "chat", kind = "ghost", click = function()
                local F = rawget(_G, "ZCGoobFeed")
                local C = istable(F) and F.Client
                if istable(C) then C.view, C.postID, C.feedItems = "thread", row.post, {} end
                A.Launch("feed")
            end})
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
            local sheet = K.Sheet(body, math.floor(math.min((body:GetTall() or 420) * 0.9, 460)), true)
            buildDetailContent(sheet, findRow(id))
        end
    end

    local function lockedMessage()
        K.EmptyState(listPane, "empty", "Replays are locked",
            "Replays are locked while a traitor round has you alive.")
    end

    local function emptyMessage()
        if S.filter == 4 then
            K.EmptyState(listPane, "play", "No clips yet", "Share a death or a highlight and it lands here, with what others post.")
            return
        end
        K.EmptyState(listPane, "empty", "No replays yet",
            "Deaths and round highlights you save or miss land here.")
    end

    local function hasMore()
        for _, scope in ipairs(SCOPES[S.filter] or {}) do if S.more[scope] then return true end end
        return false
    end

    rebuildList = function()
        listPane:Clear()
        if S.locked then lockedMessage() return end
        local list = collectRows(S.filter)
        if #list == 0 and not hasMore() then emptyMessage() return end
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
                    draw.RoundedBox(T.radius.card, 1, 1, w - 2, h - 2, K.Alpha(T.main, 40))
                elseif hover > 0.01 then
                    draw.RoundedBox(T.radius.card, 1, 1, w - 2, h - 2, K.Alpha(T.white, 10 * hover))
                end
                local thumbW, thumbH = 64, 36
                draw.RoundedBox(T.radius.chip, 8, (h - thumbH) / 2, thumbW, thumbH, T.ink)
                K.Glyph("play", 8 + thumbW / 2, h / 2, 16, T.muted)
                local tx = 8 + thumbW + 10
                local chipsW = paintChips(row, w - 8, 6)
                K.Text(K.Fit(row._title, K.Font(15, 600), w - tx - 8 - chipsW), 15, 600, tx, h / 2 - 11, T.text)
                K.Text(K.Fit(row._meta, K.Font(13, 500), w - tx - 8), 13, 500, tx, h / 2 + 10, T.muted)
            end
        end
        if hasMore() then
            local more = K.Button(listPane, {label = "Load more", kind = "ghost", enabled = function() return not pendingLive() end,
                click = function() Rp.More(S.filter) end})
            more:DockMargin(0, 4, 0, 6)
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
            if IsValid(seg) and seg.Selected ~= S.filter then seg.Selected = S.filter end
            rebuildList()
            refreshDetail()
        end
        -- "Watch in Replays" (Rp.Show): open that clip's detail once the layout says whether it is a pane or a sheet.
        if S.focus and layout.w then
            local id = S.focus
            S.focus = nil
            selectRow(id)
        end
    end

    S.dirty = true
    Rp.Refresh()
end

A.Register("replays", "Replays", "Your deaths, highlights and shared clips", "icon16/film.png", T.main, build)
