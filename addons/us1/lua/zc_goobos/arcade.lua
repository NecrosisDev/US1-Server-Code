if not CLIENT then return end
local A, T = ZCGoobApps, ZCGoobApps.Theme
local C = A.State.arcade or {tab = "blackjack", stake = 10, flags = {}}
A.State.arcade = C
local function ready() return util.NetworkStringToID("GoobOS.Arcade.Request") ~= 0 end
function A.ArcadeCanAct()
    return not C.pending and not C.timeout and C.data ~= nil and C.data.ready ~= false
end
function A.ArcadeCanFund(stake)
    return A.ArcadeCanAct() and C.data.enabled and C.data.balance >= stake and C.data.wagerLeft >= stake
end
-- Ignore ticking durations, but retain revisions: a new turn must replace its controls.
local function sameView(a, b)
    if type(a) ~= type(b) then return false end
    if not istable(a) then return a == b end
    for k, v in pairs(a) do if k ~= "remaining" and not sameView(v, b[k]) then return false end end
    for k in pairs(b) do if k ~= "remaining" and a[k] == nil then return false end end
    return true
end
local function view(data)
    if not data then return nil end
    local selected = {scope = data.scope, ready = data.ready}
    if C.tab == "blackjack" or C.tab == "mines" then selected.game = data.game; selected.challenges = data.challengesLeft
    elseif C.tab == "match" then selected.market = data.market; selected.bet = data.bet; selected.notice = data.specdmNotice
    elseif C.tab == "duels" then selected.duels = data.duels
    elseif C.tab == "ledger" then selected.ledger = data.ledger
    else selected.history = data.history end
    return selected
end
function A.ArcadeRequest(op, value, option, marketID)
    if C.pending or not ready() or (op ~= 0 and not A.ArcadeCanAct()) then return false end
    C.pending, C.sent = true, RealTime()
    net.Start("GoobOS.Arcade.Request")
    net.WriteUInt(op, 3)
    net.WriteUInt(C.data and C.data.revision or 0, 32)
    net.WriteUInt(math.min(value or 0, 127), 7)
    net.WriteUInt(option or 0, 3)
    net.WriteString(marketID or (C.data and C.data.market and C.data.market.id) or "")
    net.WriteUInt(value or 0, 32) -- 2026-09-26 custom bets: full stake
    net.SendToServer()
    return true
end
net.Receive("GoobOS.Arcade.State", function()
    local raw = net.ReadString()
    if #raw > 32000 then return end
    local data = util.JSONToTable(raw, false, true)
    if not istable(data) then return end
    C.pending, C.timeout, C.error = false, false, data.error
    if data.revision then
        C.dirty = C.dirty or not sameView(view(C.data), view(data))
        if C.data and C.data.scope ~= data.scope then
            C.ledger = {}; C.flags = {}; C.tab = "match"
            C.resetScroll = true
            if IsValid(C.root) and IsValid(C.root.GoobConfirm) then C.root.GoobConfirm:Remove() end
        end
        C.data = data; C.updated = RealTime()
        if data.game and data.game.kind == "mines" and C.mineID ~= data.game.id then C.flags = {}; C.mineID = data.game.id end
    end
end)
local K = A.Kit
-- 2026-09-25 overhaul: one screen per tab, pinned wallet + stake, cards/tiles/boards drawn as objects,
-- results eased in place, errors as a self-dismissing one-line notice. Lines above are the unchanged
-- state/net/revision block. Animation start times live in C.born so a state rebuild never replays them.
C.born, C.bornCount = C.born or {}, C.bornCount or 0
if not isnumber(C.stake) or C.stake < 1 or C.stake > 1000000 or C.stake ~= math.floor(C.stake) then C.stake = 10 end
C.flags = C.flags or {}

local PAPER = Color(238, 235, 235)
local RED_SUIT = Color(166, 55, 75)
local BLACK_SUIT = Color(29, 26, 26)
local BACK_INNER = Color(110, 0, 0)
local BACK_LINE = Color(128, 12, 12)
local TILE_OPEN = Color(22, 19, 19, 235)
local MINE_BG = Color(194, 58, 61, 72)
local MINE_RED = Color(255, 106, 106)
local SLOT_LINE = Color(255, 255, 255, 22)
local RANKS = {"A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"}
local STAKES = {10, 20, 50, 100, 250, 500, 1000, 5000}
local STAKE_TABS = {blackjack = true, match = true, duels = true}
local ISOLATED_TABS = {match = true, ledger = true, history = true}
local TABS = {{"blackjack", "Blackjack"}, {"mines", "Mines"}, {"match", "Match"}, {"duels", "Duels"}, {"ledger", "Ledger"}, {"history", "History"}}
local BJ_WORDS = {["You win"] = "Win", ["Dealer wins"] = "Lose", Push = "Push", Bust = "Bust", ["Blackjack!"] = "Blackjack", ["Dealer blackjack"] = "Dealer 21"}
local DUEL_TITLES = {"Rock-Paper-Scissors", "Tic-Tac-Toe"}
local DUEL_SHORT = {"RPS", "Tic-Tac-Toe"} -- used only where the full name would be clipped
local DUEL_GLYPHS = {"arcade.rock", "arcade.grid"}
local RPS = {{"Rock", "arcade.rock"}, {"Paper", "arcade.paper"}, {"Scissors", "arcade.scissors"}}
local LEFT, CENTER, RIGHT = TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, TEXT_ALIGN_RIGHT
local ui = {}

-- Arcade line glyphs, added to the shared table under an "arcade." prefix (the kit's own pattern for
-- app-local glyphs; kit.lua is not edited). Assigned every load so an edit lands on autorefresh.
local G = K.Glyphs
G["arcade.rock"] = {{"c", 4, 14.5, 5.5, 9, 10, 5.5, 16, 5.5, 20, 9.5, 20.5, 15, 17, 19.5, 9, 19.5}, {"l", 11, 8.5, 13, 12, 11.5, 15.5}}
G["arcade.paper"] = {{"r", 5.5, 3, 13, 18}, {"l", 8.5, 8, 15.5, 8}, {"l", 8.5, 11.5, 15.5, 11.5}, {"l", 8.5, 15, 13, 15}}
G["arcade.scissors"] = {{"o", 7, 17, 3}, {"o", 17, 17, 3}, {"l", 9, 14.8, 17, 3.5}, {"l", 15, 14.8, 7, 3.5}}
G["arcade.grid"] = {{"l", 9, 4, 9, 20}, {"l", 15, 4, 15, 20}, {"l", 4, 9, 20, 9}, {"l", 4, 15, 20, 15}}
G["arcade.minus"] = {{"l", 6, 12, 18, 12}}
G["arcade.plus"] = {{"l", 6, 12, 18, 12}, {"l", 12, 6, 12, 18}}

-- Small helpers ---------------------------------------------------------------------------------

-- First time a key is seen it gets a start time (now + delay); later rebuilds reuse it.
local function bornAt(key, delay)
    local t = C.born[key]
    if t then return t end
    if C.bornCount > 600 then C.born, C.bornCount = {}, 0 end
    t = RealTime() + (K.Reduced() and math.min(delay or 0, 0) or (delay or 0))
    C.born[key], C.bornCount = t, C.bornCount + 1
    return t
end

local function textW(text, size, weight)
    surface.SetFont(K.Font(size, weight))
    return (surface.GetTextSize(text))
end

local function signed(n)
    n = math.floor((tonumber(n) or 0) + 0.5)
    return n > 0 and "+" .. n or tostring(n)
end

local function capital(text)
    return (string.gsub(tostring(text or ""), "^%l", string.upper))
end

local function deltaColor(n) return n > 0 and T.green or n < 0 and T.red or T.muted end

local function clock(s)
    s = math.max(0, math.ceil(s))
    return string.format("%d:%02d", math.floor(s / 60), s % 60)
end

local function act(op, value, option, marketID)
    C.lastOp = op
    return A.ArcadeRequest(op, value, option, marketID)
end

local function duelAct(op, d, value, kind)
    if not A.ArcadeDuelRequest then return false end
    C.lastOp = "duel"
    return A.ArcadeDuelRequest(op, d, value, kind)
end

-- A reply to a user action dims controls at once; a background poll only if it is slow.
local function looksBusy()
    return C.pending and (C.lastOp ~= 0 or RealTime() - (C.sent or 0) > 0.4)
end

-- Painted enable state: during a fast background poll a control keeps the look it had before the poll,
-- so nothing flickers every 5 s. Clicks still go through the real predicate (and A.ArcadeRequest refuses
-- while a reply is pending).
local function paintedOn(panel, enabled)
    if not enabled then return true end
    if C.pending and not looksBusy() and panel.GoobLastOn ~= nil then return panel.GoobLastOn end
    panel.GoobLastOn = enabled() and true or false
    return panel.GoobLastOn
end

local function canAct() return A.ArcadeCanAct() end
local function fundEnabled() return A.ArcadeCanFund(C.stake) end

-- Button label for a stake-funded action: the verb, or the one reason it cannot run.
local function fundLabel(verb, stake)
    local data = C.data
    if not data or data.ready == false then return verb end
    if not data.enabled then return "Paused" end
    if (data.balance or 0) < stake then return "Low balance" end
    return verb
end

local function disc(cx, cy, r, color)
    r = math.max(1, math.floor(r))
    draw.RoundedBox(r, math.floor(cx - r), math.floor(cy - r), r * 2, r * 2, color)
end

local poly3 = {{x = 0, y = 0}, {x = 0, y = 0}, {x = 0, y = 0}}
local poly4 = {{x = 0, y = 0}, {x = 0, y = 0}, {x = 0, y = 0}, {x = 0, y = 0}}
-- Filled polygons, vertices clockwise on screen (y down).
local function tri(color, x1, y1, x2, y2, x3, y3)
    poly3[1].x, poly3[1].y, poly3[2].x, poly3[2].y, poly3[3].x, poly3[3].y = x1, y1, x2, y2, x3, y3
    draw.NoTexture()
    surface.SetDrawColor(color)
    surface.DrawPoly(poly3)
end

-- Filled suit shapes: 1 spade, 2 heart, 3 club, 4 diamond; s = box size centred on (cx, cy).
local function suit(kind, cx, cy, s, color)
    if kind == 4 then
        poly4[1].x, poly4[1].y, poly4[2].x, poly4[2].y = cx, cy - s * 0.48, cx + s * 0.36, cy
        poly4[3].x, poly4[3].y, poly4[4].x, poly4[4].y = cx, cy + s * 0.48, cx - s * 0.36, cy
        draw.NoTexture()
        surface.SetDrawColor(color)
        surface.DrawPoly(poly4)
    elseif kind == 2 then
        local r = s * 0.26
        disc(cx - r * 0.92, cy - s * 0.12, r, color)
        disc(cx + r * 0.92, cy - s * 0.12, r, color)
        tri(color, cx - r * 1.9, cy - s * 0.06, cx + r * 1.9, cy - s * 0.06, cx, cy + s * 0.44)
    elseif kind == 1 then
        local r = s * 0.25
        disc(cx - r * 0.92, cy + s * 0.06, r, color)
        disc(cx + r * 0.92, cy + s * 0.06, r, color)
        tri(color, cx, cy - s * 0.46, cx + r * 1.9, cy, cx - r * 1.9, cy)
        tri(color, cx, cy + s * 0.06, cx + s * 0.14, cy + s * 0.46, cx - s * 0.14, cy + s * 0.46)
    else
        local r = s * 0.2
        disc(cx, cy - s * 0.2, r, color)
        disc(cx - s * 0.22, cy + s * 0.06, r, color)
        disc(cx + s * 0.22, cy + s * 0.06, r, color)
        disc(cx, cy + s * 0.02, r * 0.8, color)
        tri(color, cx, cy + s * 0.06, cx + s * 0.14, cy + s * 0.46, cx - s * 0.14, cy + s * 0.46)
    end
end

local function cardFace(x, y, w, h, card, detail)
    draw.RoundedBox(4, x, y, w, h, PAPER)
    if not detail then return end
    local kind = math.floor((card - 1) / 13) + 1
    local ink = (kind == 2 or kind == 4) and RED_SUIT or BLACK_SUIT
    local fs = w >= 56 and 17 or (w >= 42 and 15 or 12)
    K.Text(RANKS[(card - 1) % 13 + 1], fs, 700, x + 5, y + 3, ink)
    suit(kind, x + 5 + fs * 0.34, y + 7 + fs * 1.2, fs * 0.72, ink)
    suit(kind, x + w * 0.58, y + h * 0.6, math.min(w, h) * 0.46, ink)
end

local function cardBack(x, y, w, h)
    draw.RoundedBox(4, x, y, w, h, T.main)
    if w < 10 then return end
    local ix, iy, iw, ih = x + 3, y + 3, w - 6, h - 6
    draw.RoundedBox(3, ix, iy, iw, ih, BACK_INNER)
    surface.SetDrawColor(BACK_LINE)
    local o = -ih
    while o < iw do
        surface.DrawLine(ix + math.max(o, 0), iy + math.max(0, -o), ix + math.min(o + ih, iw), iy + ih - math.max(0, o + ih - iw))
        o = o + 8
    end
end

local function mineIcon(cx, cy, r)
    surface.SetDrawColor(MINE_RED)
    surface.DrawRect(math.floor(cx - r * 1.55), math.floor(cy - 1), math.floor(r * 3.1), 2)
    surface.DrawRect(math.floor(cx - 1), math.floor(cy - r * 1.55), 2, math.floor(r * 3.1))
    disc(cx, cy, r, MINE_RED)
end

local function thick(x1, y1, x2, y2)
    surface.DrawLine(x1, y1, x2, y2)
    surface.DrawLine(x1 + 1, y1, x2 + 1, y2)
    surface.DrawLine(x1, y1 + 1, x2, y2 + 1)
    surface.DrawLine(x1 + 1, y1 + 1, x2 + 1, y2 + 1)
end

-- Tic-tac-toe marks drawn in over p (0..1).
local function markX(cx, cy, r, p, color)
    surface.SetDrawColor(color)
    local a = math.Clamp(p * 2, 0, 1)
    if a > 0 then thick(cx - r, cy - r, cx - r + 2 * r * a, cy - r + 2 * r * a) end
    local b = math.Clamp(p * 2 - 1, 0, 1)
    if b > 0 then thick(cx + r, cy - r, cx + r - 2 * r * b, cy - r + 2 * r * b) end
end

local function markO(cx, cy, r, p, color)
    surface.SetDrawColor(color)
    local steps = math.floor(32 * math.Clamp(p, 0, 1))
    for i = 0, steps - 1 do
        local a0, a1 = (i / 32 - 0.25) * math.pi * 2, ((i + 1) / 32 - 0.25) * math.pi * 2
        thick(cx + math.cos(a0) * r, cy + math.sin(a0) * r, cx + math.cos(a1) * r, cy + math.sin(a1) * r)
    end
end

-- Widgets ---------------------------------------------------------------------------------------

-- kind: "primary" (red fill), "secondary" (card fill), "quiet" (text only), "danger" (quiet, red text).
-- label/badge may be functions (re-read every frame). selected() draws the gold "on" state.
-- UI cohesion (2026-09-26): painted by the shared K.Button. paintedOn keeps the last on/off state while a request is
-- pending (no flicker); the click still checks the live enabled().
local function button(parent, label, kind, enabled, click, badge, selected)
    local b
    b = K.Button(parent, {label = label, kind = kind, sub = badge, selected = selected, dock = false, size = 15,
        enabled = enabled and function() return paintedOn(b, enabled) end})
    b.DoClick = function(s)
        if enabled and not enabled() then return end
        s.Flash = RealTime()
        click(s)
    end
    return b
end

-- Side-by-side layout for a row of buttons: items = {{panel, weight}, ...}.
local function row(panel, items, gap)
    panel.PerformLayout = function(_, w, h)
        local total = 0
        for _, it in ipairs(items) do total = total + it[2] end
        local x, room = 0, w - (gap or 8) * (#items - 1)
        for i, it in ipairs(items) do
            local bw = i == #items and w - x or math.floor(room * it[2] / total)
            it[1]:SetPos(x, 0)
            it[1]:SetSize(bw, h)
            x = x + bw + (gap or 8)
        end
    end
end

-- A tab body: stage (fills) + optional action bar pinned to the bottom.
local function frame(host, withBar)
    local bar
    if withBar then
        bar = K.Panel(host)
        bar:Dock(BOTTOM)
        bar:SetTall(40)
        bar:DockMargin(0, 8, 0, 0)
    end
    local stage = K.Panel(host)
    stage:Dock(FILL)
    return stage, bar
end

local function caption(parent, text, right)
    local c = K.Panel(parent)
    c:Dock(TOP)
    c:SetTall(18)
    c:DockMargin(0, 0, 0, 4)
    c.Paint = function(_, w, h)
        K.Text(text, 11, 700, 0, h / 2, T.muted, LEFT, CENTER)
        local r = isfunction(right) and right() or right
        if r then K.Text(r, 11, 600, w, h / 2, T.muted, RIGHT, CENTER) end
    end
    return c
end

-- Confirm sheet: keeps root.GoobConfirm pointed at the open shade, because the net.Receive handler
-- above force-closes it on a scope change.
local function confirm(root, title, detail, accept, danger)
    if IsValid(root.GoobConfirm) then root.GoobConfirm:Remove() end
    local _, shade = K.Modal(root, title, detail, {
        {danger or "Confirm", accept, primary = not danger, danger = danger ~= nil},
        {"Cancel"}
    })
    root.GoobConfirm = shade
end

-- Polled duel clocks: deadline re-anchors on each new snapshot without rebuilding the board.
local function remaining(initial)
    local snapshot, deadline = initial, (C.updated or RealTime()) + (initial.remaining or 0)
    return function()
        local duels = C.data and C.data.duels
        local current = duels and duels.current
        if not current or current.id ~= initial.id then
            current = nil
            for _, offer in ipairs(duels and duels.lobby or {}) do
                if offer.id == initial.id then current = offer; break end
            end
        end
        if current and current ~= snapshot then snapshot = current; deadline = (C.updated or RealTime()) + (current.remaining or 0) end
        return math.max(0, deadline - RealTime())
    end
end

local function timerBar(x, y, w, fraction, urgent)
    draw.RoundedBox(2, x, y, w, 3, K.Alpha(T.ink, 235))
    if fraction > 0 then draw.RoundedBox(2, x, y, math.max(3, math.floor(w * math.Clamp(fraction, 0, 1))), 3, urgent and T.red or T.main) end
end

local function empty(host, glyph, title, body, actionLabel, action)
    K.EmptyState(host, glyph, title, body, actionLabel, action) -- the kit fits body to width in Paint
end

-- Blackjack --------------------------------------------------------------------------------------

local function blackjackTab(host, root, data)
    local g = data.game
    local hand = g and g.kind == "blackjack" and g or nil
    local busyOther = g and not hand and not g.done
    local stage, bar = frame(host, true)
    local rows, last = {{}, {}}, RealTime()
    local key = hand and ("bj" .. tostring(hand.expires or 0) .. ":" .. tostring(hand.stake or 0)) or nil
    if hand then
        local queue = 0
        local function add(r, i, card)
            local k = key .. ":" .. r .. ":" .. i .. ":" .. card
            local fresh = C.born[k] == nil
            local flip = r == 1 and i == 2 and card ~= 0 and C.born[key .. ":1:2:0"] ~= nil
            local at = bornAt(k, fresh and queue * 0.13 or 0)
            if fresh then queue = queue + 1 end
            rows[r][i] = {card = card, at = at, flip = flip}
            last = math.max(last, at + 0.28)
        end
        local p, d = hand.player or {}, hand.dealer or {}
        for i = 1, 2 do
            if p[i] then add(2, i, p[i]) end
            if d[i] then add(1, i, d[i]) end
        end
        for i = 3, #p do add(2, i, p[i]) end
        for i = 3, #d do add(1, i, d[i]) end
    end
    local resultAt = hand and hand.done and bornAt(key .. ":res", math.max(0, last - RealTime())) or nil

    local function drawRow(list, top, w, cw, ch)
        local n = #list
        if n == 0 then
            local x0 = math.floor((w - cw * 2 - 8) / 2)
            surface.SetDrawColor(SLOT_LINE)
            surface.DrawOutlinedRect(x0, top, cw, ch, 1)
            surface.DrawOutlinedRect(x0 + cw + 8, top, cw, ch, 1)
            return
        end
        local step = n > 1 and math.min(cw + 8, (w - 20 - cw) / (n - 1)) or 0
        local x0 = math.floor((w - (step * (n - 1) + cw)) / 2)
        local now = RealTime()
        for i, c in ipairs(list) do
            local tx = math.floor(x0 + (i - 1) * step)
            if c.flip then
                local p = K.Progress(c.at, 0.28)
                if p >= 1 then
                    cardFace(tx, top, cw, ch, c.card, true)
                else
                    local sc = math.abs(1 - 2 * p)
                    local sw = math.max(2, math.floor(cw * sc))
                    local sx = tx + math.floor((cw - sw) / 2)
                    if p < 0.5 then cardBack(sx, top, sw, ch) else cardFace(sx, top, sw, ch, c.card, sc > 0.6) end
                end
            elseif now >= c.at or K.Reduced() then
                local p = K.EaseOut(K.Progress(c.at, 0.28))
                local x, y = Lerp(p, w - 10 - cw, tx), Lerp(p, 10, top)
                if c.card == 0 then cardBack(x, y, cw, ch) else cardFace(x, y, cw, ch, c.card, true) end
            end
        end
    end

    local function totalChip(x, y, value, color)
        local label = tostring(value)
        local cw = textW(label, 13, 700) + 14
        draw.RoundedBox(4, x - cw, y, cw, 18, K.Alpha(T.ink, 200))
        K.Text(label, 13, 700, x - cw / 2, y + 9, color, CENTER, CENTER)
    end

    stage.Paint = function(_, w, h)
        K.Card(0, 0, w, h, T.cardGlass)
        local band = 30
        local ch = math.floor(math.Clamp((h - 94) / 2, 40, 112))
        local cw = math.floor(ch * 0.7)
        local dy = 28
        local by = dy + ch + 4
        local py = by + band + 2
        local ly = py + ch + 4
        K.Text("DEALER", 11, 700, 10, 9, T.muted)
        K.Text("YOU", 11, 700, 10, ly + 1, T.muted)
        drawRow(rows[1], dy, w, cw, ch)
        drawRow(rows[2], py, w, cw, ch)
        if hand then
            local total = tonumber(hand.total) or 0
            totalChip(w - 10, ly, total, total > 21 and T.red or total == 21 and T.green or T.gold)
            if hand.dealerTotal and resultAt and RealTime() >= resultAt then totalChip(w - 10, 6, hand.dealerTotal, T.text) end
        end
        local mid = by + band / 2
        if resultAt and RealTime() >= resultAt then
            local p = K.EaseOut(K.Progress(resultAt, 0.24))
            local word = BJ_WORDS[hand.result] or tostring(hand.result or "")
            local delta = (tonumber(hand.payout) or 0) - (tonumber(hand.stake) or 0)
            local color = deltaColor(delta)
            local ww, dw = textW(word, 17, 700), textW(signed(delta), 17, 700)
            local pw = ww + dw + 34
            local px, py2 = math.floor((w - pw) / 2), math.floor(mid - 13 + (1 - p) * 6)
            draw.RoundedBox(4, px, py2, pw, 26, K.Alpha(color, 200 * p))
            draw.RoundedBox(4, px + 1, py2 + 1, pw - 2, 24, K.Alpha(T.glassHi, 250 * p))
            K.Text(word, 17, 700, px + 12, py2 + 13, K.Alpha(T.text, 255 * p), LEFT, CENTER)
            K.Text(signed(delta), 17, 700, px + pw - 12, py2 + 13, K.Alpha(color, 255 * p), RIGHT, CENTER)
        else
            K.Text(K.Fit("BLACKJACK PAYS 3:2  ·  DEALER STANDS ON 17", K.Font(10, 700), w - 20), 10, 700, w / 2, mid, K.Alpha(T.muted, 80), CENTER, CENTER)
        end
    end

    if hand and not hand.done then
        local hit = button(bar, "Hit", "primary", canAct, function() act(2) end)
        local stand = button(bar, "Stand", "secondary", canAct, function() act(3) end)
        row(bar, {{hit, 1}, {stand, 1}})
    elseif busyOther then
        local go = button(bar, "Finish Mines", "secondary", nil, function() ui.switch("mines") end)
        row(bar, {{go, 1}})
    else
        local deal = button(bar, function() return fundLabel("Deal", C.stake) end, "primary", fundEnabled,
            function() act(1, C.stake) end, function() return C.stake .. " ZP" end)
        row(bar, {{deal, 1}})
    end
end

-- Mines ------------------------------------------------------------------------------------------

local function heat(v) return v == 1 and T.green or v == 2 and T.gold or T.red end

local function minesTab(host, root, data)
    local g = data.game
    local field = g and g.kind == "mines" and g or nil
    local busyOther = g and not field and not g.done
    local stage, bar = frame(host, true)
    local id = field and tostring(field.id) or "idle"
    local press = C.press and C.press.id == id and C.press.cell or nil
    local timing, last = {}, RealTime()
    if field then
        local ox, oy = press and (press - 1) % 6, press and math.floor((press - 1) / 6)
        for i = 1, 36 do
            local v = field.shown[i]
            if v and v ~= -1 then
                local k = "m" .. id .. ":" .. i .. ":" .. v
                local delay = -1
                if C.born[k] == nil and press then
                    local dist = math.max(math.abs((i - 1) % 6 - ox), math.abs(math.floor((i - 1) / 6) - oy))
                    delay = v == 9 and (i == press and 0 or 0.2 + dist * 0.04) or dist * 0.035
                end
                timing[i] = bornAt(k, delay)
                last = math.max(last, timing[i] + 0.2)
            end
        end
    end
    local resultAt = field and field.done and bornAt("m" .. id .. ":res", math.max(0, last - RealTime())) or nil
    local won = field and field.done and (tonumber(field.payout) or 0) > 0
    local lost = false
    if field and field.done and not won then
        for i = 1, 36 do if field.shown[i] == 9 then lost = true; break end end
    end

    local head = K.Panel(stage)
    head:Dock(TOP)
    head:SetTall(24)
    head:DockMargin(0, 0, 0, 6)
    head.Paint = function(_, w, h)
        local left = tonumber(data.challengesLeft) or 0
        if field and not field.done then
            local cleared = tostring(field.cleared or 0)
            K.Text(cleared, 18, 700, 0, h / 2, T.text, LEFT, CENTER)
            K.Text("/ 30", 13, 600, textW(cleared, 18, 700) + 5, h / 2 + 1, T.muted, LEFT, CENTER)
            local flags = 0
            for i in pairs(C.flags) do if C.flags[i] and field.shown[i] == -1 then flags = flags + 1 end end
            local text = flags .. " / 6"
            K.Text(text, 13, 600, w, h / 2, flags > 0 and T.gold or T.muted, RIGHT, CENTER)
            K.Glyph("flag", w - textW(text, 13, 600) - 12, h / 2, 14, flags > 0 and T.gold or T.muted)
        else
            local lt = left .. " left"
            K.Text(lt, 13, 600, w, h / 2, left > 0 and T.muted or T.red, RIGHT, CENTER)
            if field and resultAt and RealTime() >= resultAt then
                local p = K.EaseOut(K.Progress(resultAt, 0.24))
                local word = won and "Cleared" or lost and "Mine" or "Ended"
                local color = won and T.green or lost and T.red or T.muted
                K.Text(word, 18, 700, 0, h / 2 + (1 - p) * 5, K.Alpha(color, 255 * p), LEFT, CENTER)
                if won then K.Text(signed(field.payout), 18, 700, textW(word, 18, 700) + 10, h / 2 + (1 - p) * 5, K.Alpha(T.gold, 255 * p), LEFT, CENTER) end
            elseif not field then
                K.Text("Prize", 13, 600, 0, h / 2, T.muted, LEFT, CENTER)
                K.Text("5 ZP", 15, 700, textW("Prize", 13, 600) + 6, h / 2, T.gold, LEFT, CENTER)
            end
        end
    end

    local grid = K.Panel(stage)
    grid:Dock(FILL)
    local cells = {}
    local function live() return field and not field.done end
    local function click(i, flag)
        if not live() or field.shown[i] ~= -1 then return end
        if flag or C.flagMode then C.flags[i] = not C.flags[i] or nil; return end
        if C.flags[i] then return end
        if act(5, i) then C.press = {id = id, cell = i} end
    end
    for i = 1, 36 do
        local b = vgui.Create("DButton", grid)
        b:SetText("")
        cells[i] = b
        b.DoClick = function() click(i, false) end
        b.DoRightClick = function() click(i, true) end
        b.Paint = function(s, w, h)
            local v = field and field.shown[i] or -1
            local at, sc = timing[i], 1
            if v ~= -1 and at then
                if RealTime() < at and not K.Reduced() then v = -1
                else
                    local p = K.Progress(at, 0.2)
                    if p < 1 then sc = math.abs(1 - 2 * p); if p < 0.5 then v = -1 end end
                end
            end
            local sw = math.max(2, math.floor((w - 2) * sc))
            local sx = 1 + math.floor((w - 2 - sw) / 2)
            if v == -1 then
                local pressed = C.pending and press == i
                local hover = live() and K.Hover(s) or 0
                draw.RoundedBox(3, sx, 1, sw, h - 2, pressed and TILE_OPEN or T.card)
                if hover > 0.01 and not pressed then draw.RoundedBox(3, sx, 1, sw, h - 2, K.Alpha(T.main, 70 * hover)) end
                if not field then draw.RoundedBox(3, sx, 1, sw, h - 2, K.Alpha(T.ink, 90)) end
                surface.SetDrawColor(K.Alpha(T.white, 14))
                surface.DrawRect(sx + 3, 2, math.max(0, sw - 6), 1)
                if field and C.flags[i] and sc > 0.5 then K.Glyph("flag", w / 2, h / 2, math.floor(h * 0.42), T.gold) end
            else
                local mine = v == 9
                draw.RoundedBox(3, sx, 1, sw, h - 2, mine and (press == i and T.main or MINE_BG) or TILE_OPEN)
                if sc > 0.55 then
                    if mine then mineIcon(w / 2, h / 2, h * 0.16)
                    elseif v > 0 then K.Text(tostring(v), h >= 40 and 18 or 15, 700, w / 2, h / 2, heat(v), CENTER, CENTER) end
                end
            end
        end
    end
    grid.PerformLayout = function(s, w, h)
        local size = math.max(12, math.floor(math.min(w, h) / 6))
        local left, top = math.floor((w - size * 6) / 2), math.floor((h - size * 6) / 2)
        s.Box = {left, top, size * 6}
        for i, b in ipairs(cells) do
            b:SetPos(left + (i - 1) % 6 * size, top + math.floor((i - 1) / 6) * size)
            b:SetSize(size, size)
        end
    end
    grid.Paint = function(s)
        local box = s.Box
        if not box or not resultAt or RealTime() < resultAt or not (won or lost) then return end
        local p = K.EaseOut(K.Progress(resultAt, 0.3))
        draw.RoundedBox(5, box[1] - 3, box[2] - 3, box[3] + 6, box[3] + 6, K.Alpha(won and T.green or T.main, 150 * p))
    end

    if live() then
        local flag = button(bar, "Flag", "secondary", nil, function() C.flagMode = not C.flagMode end, nil, function() return C.flagMode end)
        local stop = button(bar, "End", "quiet", canAct, function()
            confirm(root, "End this game?", "No points are charged. It still uses one of today's games.", function() act(6) end, "End")
        end)
        row(bar, {{flag, 1}, {stop, 1}})
    elseif busyOther then
        local go = button(bar, "Finish hand", "secondary", nil, function() ui.switch("blackjack") end)
        row(bar, {{go, 1}})
    else
        local start = button(bar, function() return (tonumber(data.challengesLeft) or 0) > 0 and "New game" or "None left" end, "primary",
            function() return A.ArcadeCanAct() and C.data.enabled and (tonumber(C.data.challengesLeft) or 0) > 0 end,
            function() C.flagMode = false; act(4) end, "Free")
        row(bar, {{start, 1}})
    end
end

-- Match market -----------------------------------------------------------------------------------

local function matchTab(host, root, data)
    local m = data.market or {}
    local bet = data.bet
    local stage = K.Panel(host)
    stage:Dock(FILL)
    local head = K.Panel(stage)
    head:Dock(TOP)
    head:SetTall(28)
    head:DockMargin(0, 0, 0, 2)
    local closes = (C.updated or RealTime()) + (tonumber(m.remaining) or 0)
    head.Paint = function(_, w, h)
        local chip, color
        if m.options then
            chip, color = m.open and "OPEN" or "LOCKED", m.open and T.green or T.muted
            if m.open and m.remaining and closes > RealTime() then chip = "OPEN  " .. clock(closes - RealTime()) end
        end
        local cw = chip and textW(chip, 11, 700) + 16 or 0
        K.Text(K.Fit(m.title or "Match", K.Font(18, 700), w - cw - 10), 18, 700, 0, h / 2, T.text, LEFT, CENTER)
        if chip then
            draw.RoundedBox(4, w - cw, h / 2 - 10, cw, 20, K.Alpha(color, 45))
            K.Text(chip, 11, 700, w - cw / 2, h / 2, color, CENTER, CENTER)
        end
    end
    if m.notice then
        local n = K.Panel(stage)
        n:Dock(TOP)
        n:SetTall(16)
        n:DockMargin(0, 0, 0, 4)
        n.Paint = function(_, w, h) K.Text(K.Fit(m.notice, K.Font(12, 500), w), 12, 500, 0, h / 2, T.muted, LEFT, CENTER) end
    end
    if m.options then
        local pool = K.Panel(stage)
        pool:Dock(TOP)
        pool:SetTall(22)
        pool:DockMargin(0, 2, 0, 6)
        pool.Paint = function(_, w, h)
            K.Text("Pool", 13, 600, 0, h / 2, T.muted, LEFT, CENTER)
            K.Text((m.total or 0) .. " ZP", 15, 700, textW("Pool", 13, 600) + 6, h / 2, T.gold, LEFT, CENTER)
            K.Text("No fee · stakes split by share", 11, 500, w, h / 2, K.Alpha(T.muted, 170), RIGHT, CENTER)
        end
    end
    if bet and not (m.options and bet.round == m.id) then
        -- A ticket on an earlier round (awaiting settlement) keeps its own card.
        local ticket = K.Panel(stage)
        ticket:Dock(TOP)
        ticket:SetTall(40)
        ticket:DockMargin(0, 0, 0, 8)
        ticket.Paint = function(_, w, h)
            K.Card(0, 0, w, h, T.cardGlass, T.gold)
            K.Text("TICKET", 11, 700, 12, h / 2, T.gold, LEFT, CENTER)
            K.Text(K.Fit(tostring(bet.label or bet.mode or ""), K.Font(14, 600), w - 150), 14, 600, 66, h / 2, T.text, LEFT, CENTER)
            K.Text((bet.stake or 0) .. " ZP", 14, 700, w - 12, h / 2, T.gold, RIGHT, CENTER)
        end
    end
    if not m.options then
        empty(stage, "bars", m.reason and "Closed" or "Match", m.reason)
        return
    end
    local list = A.Scroll(stage)
    host.Scroll = list
    for index, option in ipairs(m.options) do
        local mine = bet and bet.round == m.id and (bet.choice == option.id or bet.label == option.name)
        local canBack = m.open and not bet
        local card = K.Panel(list)
        card:Dock(TOP)
        card:SetTall(54)
        card:DockMargin(0, 0, 0, 8)
        card.Share = 0
        local function amount() return tonumber((m.pools or {})[option.id]) or 0 end
        local function returns() return math.floor(C.stake * ((m.total or 0) + C.stake) / (amount() + C.stake)) end
        card.Paint = function(s, w, h)
            K.Card(0, 0, w, h, T.cardGlass, mine and T.gold or nil)
            local room = w - (canBack and 120 or (mine and 110 or 24))
            K.Text(K.Fit(option.name, K.Font(15, 600), room), 15, 600, 12, 8, T.text)
            local total = tonumber(m.total) or 0
            s.Share = K.Spring(s.Share, total > 0 and amount() / total or 0, 9)
            draw.RoundedBox(2, 12, 30, room, 4, K.Alpha(T.ink, 235))
            if s.Share > 0.005 then draw.RoundedBox(2, 12, 30, math.max(4, math.floor(room * s.Share)), 4, mine and T.gold or T.main) end
            local a = amount() .. " ZP"
            K.Text(a, 11, 600, 12, 44, T.muted, LEFT, CENTER)
            if canBack then K.Text("pays " .. returns(), 11, 700, 12 + textW(a, 11, 600) + 10, 44, T.gold, LEFT, CENTER) end
            if mine then
                K.Text("TICKET", 11, 700, w - 12, 18, T.gold, RIGHT, CENTER)
                K.Text((bet.stake or 0) .. " ZP", 15, 700, w - 12, 36, T.gold, RIGHT, CENTER)
            end
        end
        if canBack then
            local back = button(card, function() return fundLabel("Back", C.stake) end, "primary", fundEnabled, function()
                local stake = C.stake
                local marketID = C.data and C.data.market and C.data.market.id
                confirm(root, "Back " .. option.name .. " · " .. stake .. " ZP?", "Returns about " .. returns() .. " ZP if it wins; this changes until betting locks. One ticket per round, no cancellation.",
                    function() act(7, stake, index, marketID) end)
            end)
            card.PerformLayout = function(_, w, h) back:SetPos(w - 104, (h - 32) / 2); back:SetSize(94, 32) end
        end
    end
end

-- Duels ------------------------------------------------------------------------------------------

local function duelWaiting(host, root, d)
    local stage, bar = frame(host, true)
    local left = remaining(d)
    stage.Paint = function(_, w, h)
        K.Card(0, 0, w, h, T.cardGlass)
        local cy = math.floor(h / 2 - 44)
        K.Glyph(DUEL_GLYPHS[d.kind] or "arcade.grid", w / 2, cy, 34, T.gold)
        K.Text(K.Fit(DUEL_TITLES[d.kind] or "Duel", K.Font(16, 700), w - 24), 16, 700, w / 2, cy + 26, T.text, CENTER)
        local s = left()
        K.Text(s > 0 and "Waiting" or "Expired", 13, 600, w / 2, cy + 48, T.muted, CENTER)
        local bw = math.min(220, w - 40)
        timerBar(math.floor((w - bw) / 2), cy + 72, bw, s / 120, false)
        K.Text(clock(s) .. "  ·  " .. (d.stake or 0) .. " ZP held", 12, 600, w / 2, cy + 84, T.muted, CENTER)
    end
    local cancel = button(bar, "Cancel", "secondary", canAct, function() duelAct(3, d) end, "Refund")
    row(bar, {{cancel, 1}})
end

local function duelPlaying(host, root, d)
    local stage, bar = frame(host, true)
    local left = remaining(d)
    local me = d.slot or 1
    local them = 3 - me
    local players = d.players or {}
    local theirName = players[them] and players[them].name or "Opponent"
    local head = K.Panel(stage)
    head:Dock(TOP)
    head:SetTall(50)
    head:DockMargin(0, 0, 0, 8)
    head.Paint = function(_, w, h)
        K.Card(0, 0, w, h, T.cardGlass)
        local s = left()
        local center
        if d.kind == 1 then
            local score = d.score or {0, 0}
            center = (score[me] or 0) .. " : " .. (score[them] or 0)
            K.Text(center, 22, 700, w / 2, 20, T.text, CENTER, CENTER)
            K.Text(d.locked and "Locked" or ("Round " .. (d.round or 1)), 11, 600, w / 2, 38, d.locked and T.green or T.muted, CENTER, CENTER)
        else
            local mine = d.turn == d.slot
            K.Text(mine and "Your turn" or "Their turn", 15, 700, w / 2, 20, mine and T.gold or T.muted, CENTER, CENTER)
            K.Text(clock(s), 11, 600, w / 2, 38, s <= 10 and T.red or T.muted, CENTER, CENTER)
        end
        local side = math.floor(w / 2 - 70)
        K.Text("You", 13, 700, 12, 20, T.gold, LEFT, CENTER)
        K.Text(K.Fit(theirName, K.Font(13, 700), side - 12), 13, 700, w - 12, 20, T.red, RIGHT, CENTER)
        if d.kind == 2 then
            K.Text(me == 1 and "X" or "O", 11, 700, 12, 36, T.muted, LEFT, CENTER)
            K.Text(me == 1 and "O" or "X", 11, 700, w - 12, 36, T.muted, RIGHT, CENTER)
        end
        timerBar(8, h - 5, w - 16, s / 90, s <= 10)
    end
    local body = K.Panel(stage)
    body:Dock(FILL)
    if d.kind == 1 then
        local key = "rps" .. tostring(d.id) .. ":" .. tostring(d.round)
        local lastAt = d.last and bornAt(key, 0) or nil
        local reveal = K.Panel(body)
        reveal:Dock(TOP)
        reveal:SetTall(d.last and 44 or 0)
        reveal:DockMargin(0, 0, 0, d.last and 8 or 0)
        reveal.Paint = function(_, w, h)
            if not d.last then return end
            local p = K.EaseOut(K.Progress(lastAt, 0.25))
            local winner = d.last[3]
            local word = winner == 0 and "Draw" or winner == me and "Won" or "Lost"
            local color = winner == 0 and T.muted or winner == me and T.green or T.red
            local mv, tv = RPS[d.last[me]], RPS[d.last[them]]
            local off = (1 - p) * 30
            K.Text(word, 14, 700, w / 2, h / 2, K.Alpha(color, 255 * p), CENTER, CENTER)
            if mv then K.Glyph(mv[2], w / 2 - 64 - off, h / 2, 28, K.Alpha(winner == me and T.green or T.text, 255 * p)) end
            if tv then K.Glyph(tv[2], w / 2 + 64 + off, h / 2, 28, K.Alpha(winner == them and T.red or T.text, 255 * p)) end
        end
        local picks = K.Panel(body)
        picks:Dock(FILL)
        local tiles = {}
        for i, choice in ipairs(RPS) do
            local b = vgui.Create("DButton", picks)
            b:SetText("")
            tiles[i] = b
            local function enabled() return not d.locked and A.ArcadeCanAct() and left() > 0 end
            b.DoClick = function(s)
                if not enabled() then return end
                s.Flash = RealTime()
                if duelAct(4, d, i) then C.rpsPick = {id = d.id, round = d.round, value = i} end
            end
            b.Paint = function(s, w, h)
                local picked = d.locked and C.rpsPick and C.rpsPick.id == d.id and C.rpsPick.round == d.round and C.rpsPick.value == i
                local on = paintedOn(s, enabled)
                local hover = on and K.Hover(s) or 0
                K.Card(0, 0, w, h, T.cardGlass, picked and T.gold or nil)
                if hover > 0.01 then draw.RoundedBox(4, 0, 0, w, h, K.Alpha(T.main, 60 * hover)) end
                local flash = s.Flash and 1 - K.Progress(s.Flash, 0.2) or 0
                if flash > 0 then draw.RoundedBox(4, 0, 0, w, h, K.Alpha(T.white, 40 * flash)) end
                local color = picked and T.gold or on and T.text or K.Alpha(T.muted, 140)
                local g = math.floor(math.min(w, h) * 0.4)
                K.Glyph(choice[2], w / 2, h / 2 - 8, g, color)
                K.Text(choice[1], 13, 600, w / 2, h / 2 + g / 2 + 4, color, CENTER)
            end
        end
        picks.PerformLayout = function(_, w, h)
            local size = math.floor(math.min((w - 16) / 3, h))
            local x0 = math.floor((w - size * 3 - 16) / 2)
            for i, b in ipairs(tiles) do
                b:SetPos(x0 + (i - 1) * (size + 8), math.floor((h - size) / 2))
                b:SetSize(size, size)
            end
        end
    else
        local known = C.born["ttt" .. tostring(d.id)] ~= nil
        bornAt("ttt" .. tostring(d.id), 0)
        local cells = {}
        for i = 1, 9 do
            local b = vgui.Create("DButton", body)
            b:SetText("")
            cells[i] = b
            local mark = (d.board or {})[i] or 0
            local at = mark ~= 0 and bornAt("ttt" .. tostring(d.id) .. ":" .. i .. ":" .. mark, known and 0 or -1) or nil
            local function open() return mark == 0 and d.turn == d.slot and A.ArcadeCanAct() and left() > 0 end
            b.DoClick = function(s)
                if not open() then return end
                s.Flash = RealTime()
                duelAct(4, d, i)
            end
            b.Paint = function(s, w, h)
                local hover = open() and K.Hover(s) or 0
                draw.RoundedBox(4, 2, 2, w - 4, h - 4, T.card)
                if hover > 0.01 then draw.RoundedBox(4, 2, 2, w - 4, h - 4, K.Alpha(T.main, 70 * hover)) end
                local flash = s.Flash and 1 - K.Progress(s.Flash, 0.2) or 0
                if flash > 0 then draw.RoundedBox(4, 2, 2, w - 4, h - 4, K.Alpha(T.white, 40 * flash)) end
                if mark ~= 0 then
                    local p = K.EaseOut(K.Progress(at, 0.26))
                    local color = mark == d.slot and T.gold or T.red
                    local r = math.floor(math.min(w, h) * 0.26)
                    if mark == 1 then markX(w / 2, h / 2, r, p, color) else markO(w / 2, h / 2, r, p, color) end
                end
            end
        end
        body.PerformLayout = function(_, w, h)
            local size = math.floor(math.min(w, h) / 3)
            local x0, y0 = math.floor((w - size * 3) / 2), math.floor((h - size * 3) / 2)
            for i, b in ipairs(cells) do
                b:SetPos(x0 + (i - 1) % 3 * size, y0 + math.floor((i - 1) / 3) * size)
                b:SetSize(size, size)
            end
        end
    end
    local concede = button(bar, "Concede", "danger", canAct, function()
        confirm(root, "Concede " .. (d.stake or 0) .. " ZP?", theirName .. " receives the pot. The result is public.", function() duelAct(5, d) end, "Concede")
    end)
    row(bar, {{concede, 1}})
end

local function duelLobby(host, root, duels)
    local stage = K.Panel(host)
    stage:Dock(FILL)
    local r = duels.recent
    if r then
        local at = bornAt("recent" .. tostring(r.id or r.time or ""), 0)
        local strip = K.Panel(stage)
        strip:Dock(TOP)
        strip:SetTall(34)
        strip:DockMargin(0, 0, 0, 8)
        strip.Paint = function(_, w, h)
            local p = K.EaseOut(K.Progress(at, 0.25))
            local delta = tonumber(r.delta) or 0
            K.Card(0, 0, w, h, T.cardGlass, K.Alpha(deltaColor(delta), 160 * p))
            K.Text("LAST", 11, 700, 12, h / 2, T.muted, LEFT, CENTER)
            K.Text(K.Fit(capital(r.game), K.Font(13, 600), w - 130), 13, 600, 50, h / 2, T.text, LEFT, CENTER)
            K.Text(signed(delta), 16, 700, w - 12, h / 2, K.Alpha(deltaColor(delta), 255 * p), RIGHT, CENTER)
        end
    end
    local offers = K.Panel(stage)
    offers:Dock(TOP)
    offers:SetTall(62)
    offers:DockMargin(0, 0, 0, 10)
    local items = {}
    for kind, name in ipairs(DUEL_TITLES) do
        local b = vgui.Create("DButton", offers)
        b:SetText("")
        items[#items + 1] = {b, 1}
        b.DoClick = function(s)
            if not fundEnabled() then return end
            s.Flash = RealTime()
            duelAct(1, nil, C.stake, kind)
        end
        b.Paint = function(s, w, h)
            local on = paintedOn(s, fundEnabled)
            local hover = on and K.Hover(s) or 0
            K.Card(0, 0, w, h, T.cardGlass)
            draw.RoundedBox(2, 0, 0, 3, h, on and T.main or K.Alpha(T.main, 80))
            if hover > 0.01 then draw.RoundedBox(4, 0, 0, w, h, K.Alpha(T.main, 60 * hover)) end
            local flash = s.Flash and 1 - K.Progress(s.Flash, 0.2) or 0
            if flash > 0 then draw.RoundedBox(4, 0, 0, w, h, K.Alpha(T.white, 40 * flash)) end
            K.Glyph(DUEL_GLYPHS[kind], 28, h / 2, 26, on and T.gold or T.muted)
            local label = textW(name, 14, 600) <= w - 60 and name or DUEL_SHORT[kind]
            K.Text(K.Fit(label, K.Font(14, 600), w - 60), 14, 600, 52, h / 2 - 9, on and T.text or T.muted, LEFT, CENTER)
            K.Text(fundLabel("Offer", C.stake) .. (fundLabel("Offer", C.stake) == "Offer" and " " .. C.stake .. " ZP" or ""), 12, 600, 52, h / 2 + 10, on and T.gold or T.muted, LEFT, CENTER)
        end
    end
    row(offers, items)
    local lobby = duels.lobby or {}
    caption(stage, "OPEN DUELS", #lobby > 0 and tostring(#lobby) or nil)
    if #lobby == 0 then
        local none = K.Panel(stage)
        none:Dock(TOP)
        none:SetTall(40)
        none.Paint = function(_, w, h) K.Text("None open", 13, 500, w / 2, h / 2, T.muted, CENTER, CENTER) end
        return
    end
    local list = A.Scroll(stage)
    host.Scroll = list
    for _, offer in ipairs(lobby) do
        local left = remaining(offer)
        local card = K.Panel(list)
        card:Dock(TOP)
        card:SetTall(50)
        card:DockMargin(0, 0, 0, 8)
        local name = offer.players and offer.players[1] and offer.players[1].name or "Player"
        card.Paint = function(_, w, h)
            K.Card(0, 0, w, h, T.cardGlass)
            K.Glyph(DUEL_GLYPHS[offer.kind] or "arcade.grid", 22, h / 2 - 1, 20, T.gold)
            K.Text(K.Fit(name, K.Font(14, 600), w - 160), 14, 600, 42, h / 2 - 8, T.text, LEFT, CENTER)
            K.Text(K.Fit((DUEL_TITLES[offer.kind] or "Duel") .. "  ·  " .. (offer.stake or 0) .. " ZP", K.Font(11, 600), w - 160), 11, 600, 42, h / 2 + 9, T.muted, LEFT, CENTER)
            timerBar(8, h - 5, w - 16, left() / 120, left() <= 10)
        end
        local accept = button(card, function() return fundLabel("Accept", offer.stake or 0) end, "primary", function()
            return A.ArcadeCanAct() and A.ArcadeCanFund(offer.stake or 0) and left() > 0
        end, function()
            confirm(root, "Accept · " .. (offer.stake or 0) .. " ZP?", (DUEL_TITLES[offer.kind] or "Duel") .. " against " .. name .. ". Winner receives " .. (offer.stake or 0) * 2 .. " ZP. No cancellation; 90-second turns.",
                function() duelAct(2, offer, offer.stake) end)
        end)
        card.PerformLayout = function(_, w, h) accept:SetPos(w - 108, (h - 30) / 2 - 2); accept:SetSize(98, 30) end
    end
end

local function duelsTab(host, root, data)
    local duels = data.duels
    if not duels or not A.ArcadeDuelRequest then empty(host, "arcade.grid", "Unavailable"); return end
    local d = duels.current
    if d and d.status == "waiting" then duelWaiting(host, root, d)
    elseif d then duelPlaying(host, root, d)
    else duelLobby(host, root, duels) end
end

-- Ledger / History -------------------------------------------------------------------------------

local function ledgerTab(host, root, data)
    local rows = data.ledger or C.ledger or {}
    if #rows == 0 then empty(host, "bars", "No results"); return end
    local list = A.Scroll(host)
    host.Scroll = list
    for _, entry in ipairs(rows) do
        local players = entry.players or {}
        local card = K.Panel(list)
        card:Dock(TOP)
        card:SetTall(30 + #players * 20)
        card:DockMargin(0, 0, 0, 6)
        local when = os.date("%H:%M", tonumber(entry.time) or 0)
        card.Paint = function(_, w, h)
            K.Card(0, 0, w, h, T.cardGlass)
            local tw = textW(when, 11, 600)
            K.Text(K.Fit(capital(entry.game) .. "  ·  " .. tostring(entry.result or ""), K.Font(12, 600), w - tw - 34), 12, 600, 10, 14, T.muted, LEFT, CENTER)
            K.Text(when, 11, 600, w - 10, 14, K.Alpha(T.muted, 170), RIGHT, CENTER)
            local y = 36
            for _, p in ipairs(players) do
                local delta = tonumber(p.delta) or 0
                K.Text(K.Fit(tostring(p.name or ""), K.Font(14, 600), w - 100), 14, 600, 10, y, T.text, LEFT, CENTER)
                K.Text(signed(delta), 14, 700, w - 10, y, deltaColor(delta), RIGHT, CENTER)
                y = y + 20
            end
        end
    end
end

local function historyTab(host, root, data)
    local rows = data.history or {}
    if #rows == 0 then empty(host, "bars", "No games yet"); return end
    local total = 0
    for _, entry in ipairs(rows) do total = total + (tonumber(entry.delta) or 0) end
    local sum = K.Panel(host)
    sum:Dock(TOP)
    sum:SetTall(40)
    sum:DockMargin(0, 0, 0, 8)
    sum.Paint = function(_, w, h)
        K.Card(0, 0, w, h, T.cardGlass)
        K.Text("NET", 11, 700, 12, h / 2, T.muted, LEFT, CENTER)
        K.Text(signed(total) .. " ZP", 18, 700, 44, h / 2, deltaColor(total), LEFT, CENTER)
        K.Text("Last " .. #rows, 12, 600, w - 12, h / 2, T.muted, RIGHT, CENTER)
    end
    local list = A.Scroll(host)
    host.Scroll = list
    for _, entry in ipairs(rows) do
        local card = K.Panel(list)
        card:Dock(TOP)
        card:SetTall(44)
        card:DockMargin(0, 0, 0, 6)
        local delta = tonumber(entry.delta) or 0
        local sub = tostring(entry.result or "") .. "  ·  " .. os.date("%b %d %H:%M", tonumber(entry.time) or 0)
        card.Paint = function(_, w, h)
            K.Card(0, 0, w, h, T.cardGlass)
            draw.RoundedBox(2, 0, 6, 3, h - 12, deltaColor(delta))
            K.Text(K.Fit(capital(entry.game), K.Font(14, 600), w - 100), 14, 600, 12, 14, T.text, LEFT, CENTER)
            K.Text(K.Fit(sub, K.Font(11, 500), w - 100), 11, 500, 12, 31, T.muted, LEFT, CENTER)
            K.Text(signed(delta), 16, 700, w - 12, h / 2, deltaColor(delta), RIGHT, CENTER)
        end
    end
end

-- Compat for one release: the old arcade_social.lua exported these entry points.
A.BuildArcadeDuels = function(parent, root, data) return duelsTab(parent, root, data) end
A.BuildArcadeLedger = function(parent, data) return ledgerTab(parent, nil, data) end

local BUILDERS = {blackjack = blackjackTab, mines = minesTab, match = matchTab, duels = duelsTab, ledger = ledgerTab, history = historyTab}

-- App shell --------------------------------------------------------------------------------------

local function tabAllowed(key)
    local data = C.data
    return not (data and data.scope and data.scope ~= "main") or ISOLATED_TABS[key] == true
end

local function build(root, phone)
    C.root = root
    local host, rebuild

    -- Wallet (left) · stake stepper + refresh (right). Same place on every tab.
    local top = K.Panel(root)
    top:Dock(TOP)
    top:SetTall(32)
    top:DockMargin(0, 0, 0, 6)
    top.Paint = function(s, w, h)
        local data = C.data
        if not data or data.ready == false then
            K.Text("-- ZP", 20, 700, 0, h / 2, T.muted, LEFT, CENTER)
            return
        end
        local balance = tonumber(data.balance) or 0
        if s.Last and s.Last ~= balance then s.Delta, s.DeltaAt = balance - s.Last, RealTime() end
        s.Last = balance
        s.Shown = s.Shown and K.Spring(s.Shown, balance, 9) or balance
        local stakeTab = STAKE_TABS[C.tab]
        local short = stakeTab and balance < C.stake
        local text = tostring(math.floor(s.Shown + 0.5))
        K.Text(text, 20, 700, 0, h / 2, short and T.red or T.gold, LEFT, CENTER)
        local x = textW(text, 20, 700) + 4
        K.Text("ZP", 12, 700, x, h / 2 + 2, T.muted, LEFT, CENTER)
        x = x + textW("ZP", 12, 700) + 10
        local room = w - 170 - x
        local age = s.DeltaAt and RealTime() - s.DeltaAt or 99
        if age < 1.6 and s.Delta ~= 0 then
            -- A balance change shows as +N / -N where the budget sits, then hands the spot back.
            local a = math.Clamp(age / 0.12, 0, 1) * (1 - math.Clamp((age - 1.1) / 0.5, 0, 1))
            K.Text(signed(s.Delta), 15, 700, x + (1 - K.EaseOut(math.Clamp(age / 0.25, 0, 1))) * 8, h / 2, K.Alpha(deltaColor(s.Delta), 255 * a), LEFT, CENTER)
        elseif room > 40 then
            local budget = tonumber(data.wagerLeft) or 0
            local line = "" -- 2026-09-26 owner: no daily wager limit, so no budget line
            K.Text(K.Fit(line, K.Font(12, 500), room), 12, 500, x, h / 2 + 1, stakeTab and budget < C.stake and T.red or K.Alpha(T.muted, 190), LEFT, CENTER)
        end
    end

    local stepper = K.Panel(top)
    stepper.Paint = function(_, w, h)
        local on = STAKE_TABS[C.tab]
        draw.RoundedBox(4, 0, 0, w, h, K.Alpha(T.ink, 150))
        local data = C.data
        local short = on and data and data.ready ~= false and ((tonumber(data.balance) or 0) < C.stake or (tonumber(data.wagerLeft) or 0) < C.stake)
        K.Text(C.stake .. " ZP", 14, 700, w / 2, h / 2, not on and K.Alpha(T.muted, 120) or short and T.red or T.gold, CENTER, CENTER)
    end
    local function stepButton(dir)
        local b = vgui.Create("DButton", stepper)
        b:SetText("")
        local function index()
            -- next preset above (dir 1) or below (dir -1) the current, possibly custom, stake
            if dir > 0 then for _, v in ipairs(STAKES) do if v > C.stake then return v end end
            else for i = #STAKES, 1, -1 do if STAKES[i] < C.stake then return STAKES[i] end end end
        end
        local function can() return STAKE_TABS[C.tab] and index() ~= nil end
        b.DoClick = function(s)
            if not can() then return end
            s.Flash = RealTime()
            C.stake = index()
        end
        b.Paint = function(s, w, h)
            local on = can()
            local hover = on and K.Hover(s) or 0
            if hover > 0.01 then draw.RoundedBox(4, 0, 0, w, h, K.Alpha(T.main, 70 * hover)) end
            local flash = s.Flash and 1 - K.Progress(s.Flash, 0.2) or 0
            if flash > 0 then draw.RoundedBox(4, 0, 0, w, h, K.Alpha(T.white, 40 * flash)) end
            K.Glyph(dir < 0 and "arcade.minus" or "arcade.plus", w / 2, h / 2, 14, on and T.text or K.Alpha(T.muted, 90))
        end
        return b
    end
    local minus, plus = stepButton(-1), stepButton(1)
    stepper:SetTooltip("Click to type a custom stake")
    stepper.OnMousePressed = function()
        if not STAKE_TABS[C.tab] then return end
        Derma_StringRequest("Custom stake", "ZPoints to stake (1 - 1,000,000)", tostring(C.stake), function(text)
            local n = math.floor(tonumber(text) or 0)
            if n >= 1 and n <= 1000000 then C.stake = n end
        end)
    end
    stepper.PerformLayout = function(_, w, h)
        minus:SetPos(0, 0); minus:SetSize(30, h)
        plus:SetPos(w - 30, 0); plus:SetSize(30, h)
    end

    local refresh = vgui.Create("DButton", top)
    refresh:SetText("")
    refresh.DoClick = function(s)
        if C.pending then return end
        s.Flash = RealTime()
        C.lastOp = "refresh"
        A.ArcadeRequest(0)
    end
    refresh.Paint = function(s, w, h)
        local on = not C.pending
        draw.RoundedBox(4, 0, 0, w, h, T.card)
        local hover = K.Hover(s)
        if on and hover > 0.01 then draw.RoundedBox(4, 0, 0, w, h, K.Alpha(T.white, 14 * hover)) end
        local flash = s.Flash and 1 - K.Progress(s.Flash, 0.25) or 0
        if flash > 0 then draw.RoundedBox(4, 0, 0, w, h, K.Alpha(T.white, 40 * flash)) end
        K.Glyph("refresh", w / 2, h / 2, 15, C.timeout and T.red or on and T.muted or T.line)
    end
    top.PerformLayout = function(_, w, h)
        refresh:SetPos(w - 30, (h - 30) / 2); refresh:SetSize(30, 30)
        stepper:SetPos(w - 30 - 8 - 120, (h - 30) / 2); stepper:SetSize(120, 30)
    end

    -- Tabs: each as wide as its label plus an equal share of the spare room, so all six fit the
    -- smallest phone (344 px body) unclipped; the underline glides to the selection.
    local tabs = K.Panel(root)
    tabs:Dock(TOP)
    tabs:SetTall(30)
    tabs:DockMargin(0, 0, 0, 8)
    tabs:SetMouseInputEnabled(true)
    local tabButtons = {}
    for i, spec in ipairs(TABS) do
        local b = vgui.Create("DButton", tabs)
        b:SetText("")
        tabButtons[i] = b
        b.DoClick = function() ui.switch(spec[1]) end
        b.Paint = function(s, w, h)
            local allowed = tabAllowed(spec[1])
            local on = C.tab == spec[1]
            local hover = allowed and K.Hover(s) or 0
            local font = K.Font(tabs.FontSize or 13, on and 600 or 500)
            local color = on and T.text or allowed and K.Alpha(T.muted, 190 + 65 * hover) or K.Alpha(T.muted, 70)
            draw.SimpleText(K.Fit(spec[2], font, w - 4), font, w / 2, h / 2 - 1, color, CENTER, CENTER)
        end
    end
    tabs.PerformLayout = function(s, w, h)
        local size, widths, spare = 14, {}, 0
        for _, try in ipairs({14, 13}) do
            size, spare = try, w
            for i, spec in ipairs(TABS) do
                widths[i] = textW(spec[2], try, 600) + 4
                spare = spare - widths[i]
            end
            if spare >= #TABS * 12 then break end
        end
        s.FontSize = size
        local x, extra = 0, math.max(0, spare) / #TABS
        for i, b in ipairs(tabButtons) do
            local bw = i == #tabButtons and w - math.floor(x) or math.floor(widths[i] + extra)
            b:SetPos(math.floor(x), 0)
            b:SetSize(bw, h)
            x = x + widths[i] + extra
        end
    end
    tabs.Paint = function(s, w, h)
        surface.SetDrawColor(T.hair)
        surface.DrawRect(0, h - 1, w, 1)
        local target
        for i, spec in ipairs(TABS) do if spec[1] == C.tab then target = tabButtons[i] end end
        if target then
            local tx, tw = target:GetX() + target:GetWide() * 0.18, target:GetWide() * 0.64
            s.UnderX = s.UnderX and K.Spring(s.UnderX, tx, 18) or tx
            s.UnderW = s.UnderW and K.Spring(s.UnderW, tw, 18) or tw
            surface.SetDrawColor(T.accent)
            surface.DrawRect(math.floor(s.UnderX), h - 2, math.floor(s.UnderW), 2)
        end
        if looksBusy() then
            local t = (RealTime() * 0.9) % 1
            surface.SetDrawColor(K.Alpha(T.accent, 200))
            surface.DrawRect(math.floor((t * 1.3 - 0.3) * w), h - 1, math.floor(w * 0.3), 1)
        end
    end

    host = K.Panel(root)
    host:Dock(FILL)

    -- One-line notice for errors and timeouts: slides in over the top of the tab body and leaves on its own.
    local notice = K.Panel(root)
    notice:SetZPos(850)
    notice:SetMouseInputEnabled(false)
    notice.Think = function(s)
        local w, y = root:GetWide(), host:GetY()
        if s:GetWide() ~= w or s:GetY() ~= y then s:SetPos(0, y); s:SetSize(w, 30) end
    end
    notice.Paint = function(_, w, h)
        local t = C.toast
        if not t then return end
        local age = RealTime() - t.at
        if age > 3.4 then return end
        local a = math.Clamp(age / 0.15, 0, 1) * math.Clamp((3.4 - age) / 0.4, 0, 1)
        local y = math.floor((1 - K.EaseOut(math.Clamp(age / 0.2, 0, 1))) * -6)
        draw.RoundedBox(4, 0, y, w, h, K.Alpha(T.glassHi, 245 * a))
        draw.RoundedBox(2, 0, y, 3, h, K.Alpha(T.red, 255 * a))
        K.Text(K.Fit(t.text, K.Font(13, 600), w - 24), 13, 600, 12, y + h / 2, K.Alpha(T.text, 255 * a), LEFT, CENTER)
    end

    rebuild = function(resetScroll)
        if not IsValid(host) then return end
        local keep = 0
        if not resetScroll and IsValid(host.Scroll) then keep = host.Scroll:GetVBar():GetScroll() end
        host:Clear()
        host.Scroll = nil
        local data = C.data
        if not ready() then empty(host, "dice", "Unavailable"); return end
        if not data then empty(host, "dice", C.error and "Not loaded" or "Loading", C.error); return end
        if data.ready == false then
            empty(host, "dice", "Not ready", data.market and data.market.reason, "Refresh", function()
                C.lastOp = "refresh"
                A.ArcadeRequest(0)
            end)
            return
        end
        if not tabAllowed(C.tab) then C.tab = "match" end
        local builder = BUILDERS[C.tab] or historyTab
        builder(host, root, data)
        if keep > 0 and IsValid(host.Scroll) then
            host:InvalidateLayout(true)
            host.Scroll:InvalidateLayout(true)
            host.Scroll:GetVBar():SetScroll(keep)
        end
    end

    ui.switch = function(key)
        if not tabAllowed(key) then return end
        if C.tab ~= key then
            C.tab = key
            rebuild(true)
        end
    end

    local nextPoll = RealTime() + 5
    local wasPending = C.pending
    root.Think = function()
        if C.pending and RealTime() - C.sent > 8 then
            C.pending = false; C.timeout = true; C.error = "No reply from the server. Retrying."
            -- Recover on our own with backoff: a state refresh replaces the stale revision, then actions
            -- re-enable. Retries wait 8 s, 16 s, then every 32 s; any reply resets the ladder.
            if not C.retryDelay then C.toast = {text = C.error, at = RealTime()} end
            C.retryDelay = math.min(32, C.retryDelay and C.retryDelay * 2 or 8)
            C.retryAt = RealTime() + C.retryDelay
        elseif C.timeout and not C.pending and RealTime() >= (C.retryAt or 0) then
            C.lastOp = 0
            A.ArcadeRequest(0)
        elseif wasPending and not C.pending then
            if C.error and (C.lastOp ~= 0 or C.error ~= C.toastError) then C.toast = {text = C.error, at = RealTime()} end
            C.toastError = C.error
        end
        wasPending = C.pending
        if not C.timeout then C.retryDelay = nil end
        if C.dirty then
            C.dirty = false
            local reset = C.resetScroll
            C.resetScroll = false
            rebuild(reset)
        end
        if phone:GetActive() and phone.phonePage == "arcade" and RealTime() > nextPoll and RealTime() - (C.sent or 0) >= 5 and not C.pending and not C.timeout then
            nextPoll = RealTime() + 5
            C.lastOp = 0
            A.ArcadeRequest(0)
        end
    end
    rebuild(true)
    C.lastOp = 0
    A.ArcadeRequest(0)
end
A.Register("arcade", "Arcade", "Blackjack, mines, bets and duels", "icon16/controller.png", T.gold, build)
