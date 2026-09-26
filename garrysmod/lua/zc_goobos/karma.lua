-- GoobOS Karma app: your lives, what was logged about each one, and whether it counted (owner, 2026-09-26:
-- "Transparent karma ledger, per-life, per-player, logging incidents along a timeline"). Opened from the home screen
-- or with !karma. Data: zc_killcam/sv_timeline.lua over net "zckc_timeline" - only ever the asking player's own lives,
-- with anything that would reveal a role held back while that round is still running.
--
-- Colour language (the death panel's timeline uses the same): red counted against you, grey is a flag that only
-- counts if a fight follows (or has no effect), green is helping or a good kill, gold is a kill that did not count.
if not CLIENT then return end
local A = ZCGoobApps
if not A or not A.Register then return end
local T = A.Theme

local S = A.State.karma or {data = nil, asked = 0, waiting = false}
A.State.karma = S

-- Same gate as the server (zc_killcam_timeline 0 off / 1 tester / 2 everyone), so the tile only shows for those who
-- can use it. The server checks again: this only decides what the phone draws.
local function allowed()
    local mode = GetConVar("zc_killcam_timeline")
    local m = mode and mode:GetInt() or 0
    if m >= 2 then return true end
    local me, tester = LocalPlayer(), GetConVar("zc_killcam_timeline_tester")
    return m == 1 and IsValid(me) and tester ~= nil and me:SteamID64() == string.Trim(tester:GetString())
end

local function addTile()
    if not allowed() then return end
    A.HomeGlyphs = A.HomeGlyphs or {}
    A.HomeGlyphs.karma = A.HomeGlyphs.karma or "pulse"
    if istable(A.HomeOrder) and not table.HasValue(A.HomeOrder, "karma") then table.insert(A.HomeOrder, "karma") end
end
hook.Add("InitPostEntity", "ZCGoobKarma.Tile", addTile)
addTile()

local function ask()
    if S.waiting and RealTime() - S.asked < 3 then return end
    S.waiting, S.asked = true, RealTime()
    net.Start("zckc_timeline")
    net.SendToServer()
end

net.Receive("zckc_timeline", function()
    local n = net.ReadUInt(16)
    local raw = n > 0 and net.ReadData(n) or ""
    local json = raw ~= "" and util.Decompress(raw) or nil
    local t = json and util.JSONToTable(json) or nil
    S.data, S.waiting = istable(t) and t or {allowed = false}, false
    if S.rebuild then S.rebuild() end
end)

local function clock(seconds)
    seconds = math.max(0, math.floor(tonumber(seconds) or 0))
    return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end
local function color(kind)
    if kind == "bad" or kind == "taken" or kind == "death" then return T.red end
    if kind == "heal" or kind == "dealt" or kind == "good" then return T.green end
    if kind == "kill" then return T.gold end
    return T.muted
end
local ENDED = {died = "Died", survived = "Survived the round", left = "Left", alive = "This life, so far"}

-- One line: time, a colour tick, what happened, and on the right whether it counted. Full text on hover.
local function row(parent, K, e)
    local r = K.Panel(parent)
    r:Dock(TOP)
    r:SetTall(20)
    r:SetMouseInputEnabled(true)
    r:SetTooltip(tostring(e.text or "") .. (e.tag and ("\n" .. e.tag) or ""))
    local c = color(e.kind)
    r.Paint = function(_, w, h)
        draw.RoundedBox(1, 12, 6, 3, 8, c)
        K.Text(clock(e.t), 11, 600, 22, h / 2, T.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        local tagW = e.tag and math.min(210, math.floor(w * 0.38)) or 0
        K.Text(K.Fit(tostring(e.text or ""), K.Font(12, 600), w - 70 - tagW - 16), 12, 600, 62, h / 2, T.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        if e.tag then K.Text(K.Fit(e.tag, K.Font(11, 500), tagW), 11, 500, w - 12, h / 2, K.Alpha(c, 230), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER) end
    end
end

local function card(parent, K, tall)
    local c = K.Panel(parent)
    c:Dock(TOP)
    c:DockMargin(0, 0, 8, 10)
    c:DockPadding(0, 0, 0, 8)
    c:SetTall(tall)
    return c
end

local function lifeCard(parent, K, life)
    local events = istable(life.events) and life.events or {}
    local c = card(parent, K, 50 + math.max(#events, 1) * 20 + 8)
    local k0, k1 = tonumber(life.karma0), tonumber(life.karma1)
    local karma = k0 and (k1 and string.format("Karma %d -> %d", k0, k1) or string.format("Karma %d at spawn", k0)) or nil
    local head = (ENDED[life.ended] or "Life") .. (life.span and ("  ·  " .. clock(life.span) .. " alive") or "")
    local sub = {}
    if life.at then sub[#sub + 1] = os.date("%b %d, %H:%M", life.at) end
    if life.map then sub[#sub + 1] = life.map end
    if life.mode then sub[#sub + 1] = life.mode end
    if life.held then sub[#sub + 1] = "verdicts shown when the round ends" end
    local subline = table.concat(sub, "  ·  ")
    c.Paint = function(_, w, h)
        K.Card(0, 0, w, h, T.cardGlass, K.Alpha(T.edge, 180))
        K.Text(head, 14, 700, 12, 10, T.text)
        if karma then
            local down = k1 and k0 and k1 < k0
            K.Text(karma, 12, 700, w - 12, 12, down and T.red or T.muted, TEXT_ALIGN_RIGHT)
        end
        K.Text(K.Fit(subline, K.Font(11, 500), w - 24), 11, 500, 12, 29, T.muted)
    end
    local list = K.Panel(c)
    list:Dock(FILL)
    list:DockMargin(0, 46, 0, 0)
    if #events == 0 then
        row(list, K, {t = 0, kind = "other", text = "Nothing was logged this life.", tag = "clean"})
    else
        for _, e in ipairs(events) do row(list, K, e) end
    end
end

-- The player's own row of the staff ledger. Nothing staff can see about your conduct is hidden from you.
local function ledgerCard(parent, K, L)
    local c = card(parent, K, 96)
    local rate = tonumber(L.rate)
    local line1 = rate and string.format("Recent rate: %.2f counted acts per round", rate)
        or string.format("Recent rate: not enough rounds yet (%d of %d)", tonumber(L.rounds) or 0, tonumber(L.need) or 0)
    local over = rate and L.floor and rate >= L.floor
    local line2 = string.format("%d unprovoked kills  ·  %d ambushes  ·  %d baits  ·  %d loot thefts   (each of the last three counts %.1f)",
        tonumber(L.unprovoked) or 0, tonumber(L.ambush) or 0, tonumber(L.bait) or 0, tonumber(L.loot) or 0, tonumber(L.conduct) or 0.5)
    local line3 = string.format("Not counted: %d kills in self-defence or provoked  ·  %d forgiven by the victim  ·  %d traitors killed",
        tonumber(L.contested) or 0, tonumber(L.forgiven) or 0, tonumber(L.traitors) or 0)
    local line4 = L.floor and string.format("Staff take a look at %.2f per round. Clean rounds bring the rate down; older ones fade.", L.floor) or nil
    c.Paint = function(_, w, h)
        K.Card(0, 0, w, h, T.cardGlass, K.Alpha(T.edge, 180))
        K.Text("YOUR RECORD", 10, 700, 12, 10, T.muted)
        if L.karma then K.Text(string.format("Karma %d", tonumber(L.karma) or 0), 12, 700, w - 12, 10, T.text, TEXT_ALIGN_RIGHT) end
        K.Text(line1, 14, 700, 12, 28, over and T.red or T.text)
        K.Text(K.Fit(line2, K.Font(11, 500), w - 24), 11, 500, 12, 50, T.muted)
        K.Text(K.Fit(line3, K.Font(11, 500), w - 24), 11, 500, 12, 66, T.green)
        if line4 then K.Text(K.Fit(line4, K.Font(10, 500), w - 24), 10, 500, 12, 81, T.muted) end
    end
end

local function introCard(parent, K)
    local c = card(parent, K, 62)
    c.Paint = function(_, w, h)
        K.Card(0, 0, w, h, T.cardGlass, K.Alpha(T.edge, 180))
        K.Text(K.Fit("Everything logged about each of your lives, and whether it counted.", K.Font(12, 600), w - 24), 12, 600, 12, 10, T.text)
        K.Text(K.Fit("Grey is a flag: it only counts if a fight follows. Red counted against you. Green is helping.", K.Font(11, 500), w - 24), 11, 500, 12, 28, T.muted)
        K.Text(K.Fit("Shooting back, or stopping someone attacking, never counts against you.", K.Font(11, 500), w - 24), 11, 500, 12, 43, T.muted)
    end
end

local function render(body)
    local K = A.Kit
    if not K then
        A.Label(body, "The Karma app needs the GoobOS kit, which has not loaded on this client.")
        return
    end
    if not allowed() or (S.data and S.data.allowed == false) then
        K.EmptyState(body, "pulse", "Karma timeline", "Not open on this server yet.")
        return
    end
    if not S.data then
        K.EmptyState(body, "pulse", "Karma timeline", "Loading your lives...")
        return
    end
    local scroll = A.Scroll(body)
    local top = K.Panel(scroll)
    top:Dock(TOP)
    top:SetTall(34)
    top:DockMargin(0, 0, 8, 8)
    local refresh = vgui.Create("DButton", top)
    refresh:Dock(RIGHT)
    refresh:SetWide(96)
    refresh:SetText("")
    refresh.DoClick = function() ask() end
    refresh.Paint = function(s, w, h)
        draw.RoundedBox(4, 0, 0, w, h, T.card)
        if K.Hover(s) > 0.01 then draw.RoundedBox(4, 0, 0, w, h, K.Alpha(T.text, 12 * s.GoobHover)) end
        K.Text(S.waiting and "..." or "Refresh", 12, 600, w / 2, h / 2, T.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    top.Paint = function(_, _, h) K.Text("Karma", 18, 700, 2, h / 2, T.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
    introCard(scroll, K)
    if istable(S.data.ledger) then ledgerCard(scroll, K, S.data.ledger) end
    if istable(S.data.current) then lifeCard(scroll, K, S.data.current) end
    local lives = istable(S.data.lives) and S.data.lives or {}
    for _, life in ipairs(lives) do lifeCard(scroll, K, life) end
    if #lives == 0 and not S.data.current then
        local empty = card(scroll, K, 40)
        empty.Paint = function(_, w, h)
            K.Card(0, 0, w, h, T.cardGlass, K.Alpha(T.edge, 180))
            K.Text("No lives recorded yet. They appear here after you die or a round ends.", 12, 500, 12, h / 2, T.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
    end
end

local function build(body)
    S.body = body
    S.rebuild = function()
        if not IsValid(S.body) then return end
        S.body:Clear()
        render(S.body)
    end
    S.rebuild()
    ask()
end

A.Register("karma", "Karma", "Your lives: what was logged and whether it counted", "icon16/chart_line.png", T.main, build)
