-- GoobOS Death Panel (step 5, canvas revamp 2026-09-25): fullscreen "you died" recap. Claims the killcam's
-- P3 seam (work/loader/killcam_revitalize/P3_SEAM.txt) while ZCGoobApps.Panels.Enabled() and the local
-- player is dead mid death-replay. Loads after kit.lua and panels.lua.
--
-- Layout follows the owner's marked-up canvas (claude.ai/artifact/PdDUK2yBacj3PkEFd3SspA, Main + Inset_* boards):
-- a "versus" screen - YOU on the left, the replay inset in the middle, the KILLER on the right; under the inset an
-- ACTION TIMELINE of the life (hover for timestamps) and the head-to-head as mirrored bars; forgiveness lives in
-- the killer column; the chat docks bottom-left; the right border keeps a gutter for the voice column. The inset
-- draws its own three states (Loading replay / playing / KILLING BLOW verdict). Everything is in P.Unit() units.
if not CLIENT then return end
local A = ZCGoobApps
if not A or not A.Kit then return end
local P = A.Panels
if not P then return end
local K, T = A.Kit, A.Theme

local DP = A.DeathPanel or {}
A.DeathPanel = DP
DP.Version = "20260925.deathpanel8"
-- Autorefresh reinstalls this file while the old panel lives on with the old painters (LESSONS.md): tear it down so the
-- next open builds it from this file's code.
if IsValid(DP.root) then DP.root:Remove() end
DP.root, DP.Open = nil, false

-- Mirrors zc_killcam/cl_life.lua:16 (tag vocabulary) and :59 (the gamemode forgiveness window).
local TAGS = {ivi = "Innocent hit innocent", tvt = "Traitor hit traitor", ivt = "Innocent hit traitor", tvi = "Traitor hit innocent", other = "Not a traitor round"}
-- Roles each tag implies (attacker, victim), for the chips under the two names. Nothing else records roles.
local ROLES = {ivi = {"Innocent", "Innocent"}, tvt = {"Traitor", "Traitor"}, ivt = {"Innocent", "Traitor"}, tvi = {"Traitor", "Innocent"}}
local HITGROUPS = {[0] = "Unknown", [1] = "Head", [2] = "Chest", [3] = "Stomach", [4] = "Left arm", [5] = "Right arm", [6] = "Left leg", [7] = "Right leg"}
local VERDICTS = {[1] = "HEADSHOT", [2] = "CHEST SHOT", [3] = "GUT SHOT", [4] = "ARM SHOT", [5] = "ARM SHOT", [6] = "LEG SHOT", [7] = "LEG SHOT"}
local FORGIVE_WINDOW = 5
local END_CARD_SECONDS = 8 -- P3_SEAM: the end card leaves by itself after 8 s
local HOLD_SKIP = 0.6 -- canvas: "Hold space to skip all" - a Space held this long hands the screen back
-- Hoisted: no Color() allocation inside Paint (kit rule).
local INSET_BG = Color(20, 17, 17, 255)
local INSET_DIM = Color(12, 10, 10, 215)
local LETTERBOX = Color(0, 0, 0, 255)
local CHIP_BG = Color(10, 9, 9)
-- K.Alpha returns ONE shared scratch colour: a call needing two tinted colours at once gets real tables (review 2026-09-25).
local DOCK_FILL = Color(T.ink.r, T.ink.g, T.ink.b, 150)
local DOCK_EDGE = Color(T.edge.r, T.edge.g, T.edge.b, 120)
local KEY_N_CODE = rawget(_G, "KEY_N") or 24
-- 1-9 jump to that hit. Polled as raw keys like the rest: the killcam's own PlayerBindPress swallows every slot bind
-- during a life replay, and hook order decides whether a bind handler would ever see them (review 2026-09-26).
local HIT_KEYS = {}
for n = 1, 9 do HIT_KEYS[n] = KEY_1 + n - 1 end
local WAIT_KEYS = {KEY_SPACE, KEY_G, KEY_V, KEY_Q, KEY_F, KEY_N_CODE, unpack(HIT_KEYS)}
-- Footer vocabulary from the canvas: Space skips a hit, holding it skips them all, 1-9 jump, G report, Q spectate.
local KEY_HINTS = {{"Space", "Skip hit"}, {"Hold Space", "Skip all"}, {"1-9", "Jump to hit"}, {"G", "Report"}, {"Q", "Spectate"}}

local function clock(seconds)
    if not isnumber(seconds) then return nil end
    return string.FormattedTime(math.max(seconds, 0), "%02i:%02i")
end

local function weaponName(wep) return P.WeaponName(wep) end

local function findSteamID(tbl)
    if not istable(tbl) then return nil end
    local id = tbl.steamid64 or tbl.steamID64 or tbl.sid64 or tbl.SteamID64
    return isstring(id) and id or nil
end

local function num(v) return tonumber(v) or 0 end

-- Unit-scaled sizes, recomputed once per layout pass and read by every painter.
local U = 1
local function u(n) return math.floor(n * U + 0.5) end
local function font(size, weight) return K.Font(math.max(8, u(size)), weight) end
local function text(str, size, weight, x, y, color, ax, ay)
    return draw.SimpleText(str, font(size, weight), x, y, color or T.text, ax or TEXT_ALIGN_LEFT, ay or TEXT_ALIGN_TOP)
end
local function fit(str, size, weight, width) return K.Fit(str, font(size, weight), width) end
local function measure(str, size, weight)
    surface.SetFont(font(size, weight))
    return surface.GetTextSize(str)
end

-- Shared freeform button painter (arcade.lua/wardrobe.lua kitButton pattern, rebuilt locally per
-- KIT_API.md: no cross-file helper exists for non-docked buttons). `label` may be a string or a
-- function() -> string so footer buttons can show live state (Saved, Replay vs Next). `key` is the
-- keycap drawn at the left edge.
local function labelOf(s, label) return s.Label or (isfunction(label) and label() or label) end
local function kitButton(parent, label, kind, enabledFn, click, key)
    local b = vgui.Create("DButton", parent)
    b:SetText("")
    b.Key = key
    b.DoClick = function() if not enabledFn or enabledFn() then click() end end
    b.Paint = function(s, w, h)
        local on = not enabledFn or enabledFn()
        draw.RoundedBox(4, 0, 0, w, h, kind == "primary" and T.main or (kind == "ghost" and K.Alpha(T.ink, 90) or T.card))
        if kind == "ghost" then
            surface.SetDrawColor(T.line)
            surface.DrawOutlinedRect(0, 0, w, h, 1)
        end
        local hover = K.Hover(s)
        if on and hover > 0.01 then draw.RoundedBox(4, 0, 0, w, h, K.Alpha(T.white, (kind == "primary" and 20 or 14) * hover)) end
        -- s.Label overrides the creation-time label: the four forgive-card buttons share one
        -- kitButton() call site and get their real text assigned per-row in refreshFrame().
        local str = labelOf(s, label)
        local color = kind == "primary" and T.white or (kind == "danger" and T.red or T.text)
        local x = w / 2
        if s.Key then
            local kw = u(10) + #s.Key * u(7)
            draw.RoundedBox(3, u(8), h / 2 - u(9), kw, u(18), K.Alpha(T.ink, 200))
            text(s.Key, 10, 700, u(8) + kw / 2, h / 2, on and T.text or T.muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            x = u(8) + kw + (w - u(8) - kw) / 2
        end
        text(fit(str, 13, 600, w - u(16) - (s.Key and u(30) or 0)), 13, 600, x, h / 2, on and color or T.muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    -- Width from the label, so no button is ever a fixed 140 px at any scale.
    function b:Measure()
        local str = labelOf(self, label)
        surface.SetFont(font(13, 600))
        local tw = surface.GetTextSize(str)
        return tw + u(32) + (self.Key and (u(18) + #self.Key * u(7)) or 0)
    end
    return b
end

-- Initials avatar: used for the killer block when no SteamID is available anywhere on h2h/inst.
-- p.Letter is mutable so refreshFrame() can update it without recreating the panel.
local function miniAvatar(parent, letter)
    local p = K.Panel(parent)
    p.Letter = letter
    p.Paint = function(s, w, h)
        draw.RoundedBox(4, 0, 0, w, h, T.card)
        surface.SetDrawColor(T.main)
        surface.DrawOutlinedRect(0, 0, w, h, 2)
        text(s.Letter or "?", math.floor(w / U * 0.36), 700, w / 2, h / 2, T.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    return p
end

----------------------------------------------------------------------------------------------
-- Guilt / forgiveness: the ACTIVE prompt on the live server is ZCityGuiltReview
-- (zc_guilt_justice/client.lua, deployed over cl_guilt.lua by zc_guilt_review_activate.lua).
-- Its HUDPaint hook "ZCityGuiltReview_Prompt" draws "Press F to review this incident" and polls
-- KEY_F itself; its net "zc_guilt_review_v3" already has a receiver (client.lua's C.Show, which
-- pops a DFrame). We keep both nets and the F key, but move the DRAWING into our inline card and
-- take the case rows ourselves instead of letting the popup open, only while we're up.
----------------------------------------------------------------------------------------------
DP.WantGuilt = DP.WantGuilt or false
DP.GuiltRows = DP.GuiltRows or nil

function DP.ApplyGuiltRows(rows)
    DP.GuiltRows = istable(rows) and rows or {}
    -- Reconcile the optimistic "Forgiven / Reported" with what the server actually did (review 2026-09-26): it refuses
    -- silently (killer left, report cooldown, refund not saved, case locked) and then the card lied and could not retry.
    local sent = DP.GuiltSent
    if not sent then return end
    DP.GuiltSent = nil
    for _, row in ipairs(DP.GuiltRows) do
        if row.caseid == sent.caseid and row.steamid64 == sent.steamid64 then
            local done = (sent.action == "report" and row.reported == true) or (sent.action ~= "report" and row.decided and row.decision == sent.action)
            if not done and DP.GuiltDecided == sent.action then
                DP.GuiltDecided = nil
                DP.Note, DP.NoteUntil = "That didn't go through. Try again, or use the guilt menu", RealTime() + 5
            end
            return
        end
    end
end

function DP.MatchGuiltRow(killerName)
    if not isstring(killerName) or not istable(DP.GuiltRows) then return nil end
    for _, row in ipairs(DP.GuiltRows) do
        if row.name == killerName and not row.decided then return row end
    end
    return nil
end

local function installGuiltWrap()
    local hooks = hook.GetTable()
    local hp = hooks and hooks.HUDPaint
    local originalPrompt = hp and hp["ZCityGuiltReview_Prompt"]
    if isfunction(originalPrompt) and originalPrompt ~= DP.GuiltPromptWrap then
        DP.GuiltPromptOriginal = originalPrompt
        DP.GuiltPromptWrap = function(...)
            if DP.WantGuilt then return end
            return DP.GuiltPromptOriginal(...)
        end
        hook.Add("HUDPaint", "ZCityGuiltReview_Prompt", DP.GuiltPromptWrap)
    end
    local key = string.lower("zc_guilt_review_v3")
    local originalNet = net.Receivers[key]
    if isfunction(originalNet) and originalNet ~= DP.GuiltNetWrap then
        DP.GuiltNetOriginal = originalNet
        DP.GuiltNetWrap = function(len)
            -- GuiltQuietUntil: the reply to an action sent from this panel can land after the panel closed (respawn, Q,
            -- end card); it must not open the stock guilt popup over live play.
            if DP.WantGuilt or RealTime() < (DP.GuiltQuietUntil or 0) then
                local raw = net.ReadString()
                local ok, data = pcall(util.JSONToTable, raw, false, true)
                DP.ApplyGuiltRows(ok and data or {})
            else
                DP.GuiltNetOriginal(len)
            end
        end
        net.Receive("zc_guilt_review_v3", DP.GuiltNetWrap)
    end
end
hook.Add("InitPostEntity", "GoobOS.DeathPanel.GuiltWrap", installGuiltWrap)
timer.Create("GoobOS.DeathPanel.GuiltWrap", 2, 0, installGuiltWrap)

local function requestGuiltRows() RunConsoleCommand("zcity_guilt_menu") end

local function sendGuiltAction(row, action)
    net.Start("zc_guilt_action_v3")
    net.WriteUInt(row.caseid, 32)
    net.WriteString(row.steamid64)
    net.WriteString(action)
    net.SendToServer()
    DP.GuiltDecided = action
    DP.GuiltSent = {caseid = row.caseid, steamid64 = row.steamid64, action = action}
    DP.GuiltQuietUntil = RealTime() + 3
    timer.Simple(0.3, requestGuiltRows)
end

-- The killcam's one-line replies (saved / reported / refused) arrive through V.Note. The tactical viewer
-- (cl_part_03) already defines V.Note for its own frame, so it is chained, never replaced.
local function installNoteWrap()
    local V = ZCKillcamView
    if not istable(V) then return end
    local current = V.Note
    if current == DP.NoteWrap then return end
    DP.NoteOriginal = isfunction(current) and current or nil
    DP.NoteWrap = function(str)
        if isstring(str) then DP.Note, DP.NoteUntil = str, RealTime() + 4 end
        if DP.NoteOriginal then return DP.NoteOriginal(str) end
    end
    V.Note = DP.NoteWrap
end

----------------------------------------------------------------------------------------------
-- Derived facts shared by the header, the inset verdict and the cards.
----------------------------------------------------------------------------------------------
local function killerLabel() return DP.KillerName or "Someone" end

-- The fatal hit's hit group (penetration v2 organ name beats the engine hit group when the ledger carries one).
local function hitLabel()
    local how = DP.H2H and DP.H2H.how
    if how and isstring(how.organ) and how.organ ~= "" then return how.organ end
    if how and isnumber(how.hitgroup) then return HITGROUPS[how.hitgroup] or "Unknown" end
    return nil
end
local function verdictWord()
    local how = DP.H2H and DP.H2H.how
    if how and isstring(how.organ) and how.organ ~= "" then return string.upper(how.organ) end
    if how and isnumber(how.hitgroup) then return VERDICTS[how.hitgroup] or "KILLED" end
    return "KILLED"
end
-- Distance is an ADDITIVE field (h2h.how.dist / inst.dist, metres); nothing ships it yet, so it is only shown when present.
local function distanceLabel()
    local how = DP.H2H and DP.H2H.how
    local d = tonumber(how and how.dist) or tonumber(DP.Inst and DP.Inst.dist)
    return d and string.format("%dm", math.floor(d + 0.5)) or nil
end
-- The engagement: from the killer's first hit on you to your death (the earliest instance's `ago`).
local function engagementSeconds()
    local instances = DP.Seq and DP.Seq.instances
    if not istable(instances) or #instances == 0 then return nil end
    local most = 0
    for _, it in ipairs(instances) do most = math.max(most, num(it.ago)) end
    return most
end
local function withArticle(name)
    local first = string.lower(string.sub(name or "", 1, 1))
    return ((first == "a" or first == "e" or first == "i" or first == "o" or first == "u") and "an " or "a ") .. name
end

----------------------------------------------------------------------------------------------
-- Cards.
----------------------------------------------------------------------------------------------
local function cardHead(title, x, y, w, right, rightColor)
    text(title, 10, 700, x, y, T.muted)
    if right then text(right, 10, 700, x + w, y, rightColor or T.gold, TEXT_ALIGN_RIGHT) end
end

-- label above value, three or four to a row
local function cell(label, value, x, y, color, big)
    text(label, 9, 600, x, y, T.muted)
    text(value, big and 18 or 14, 700, x, y + u(12), color or T.text)
end

local function buildForgiveCard(parent)
    local card = K.Panel(parent)
    card.Bar = K.Bar(card, 1, T.gold)
    card.Buttons = {}
    for i = 1, 4 do card.Buttons[i] = kitButton(card, "", i == 1 and "primary" or (i <= 2 and "secondary" or "ghost"), nil, function() end) end
    card.Paint = function(_, w, h)
        K.Card(0, 0, w, h, T.cardGlass, K.Alpha(T.gold, 140))
        local row = DP.GuiltRow
        if DP.GuiltDecided then
            local msg = DP.GuiltDecided == "forgive" and "Forgiven" or DP.GuiltDecided == "respect" and "Respect given" or DP.GuiltDecided == "report" and "Reported to staff" or "Penalty kept"
            text(msg, 13, 700, u(12), h / 2, T.green, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            text("Review later in Replays", 11, 500, w - u(12), h / 2, T.muted, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
            return
        end
        if not row then return end
        draw.RoundedBox(3, u(12), u(10), u(18), u(18), K.Alpha(T.ink, 200))
        text("F", 11, 700, u(21), u(19), T.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        text(fit("Forgive " .. killerLabel() .. "?", 15, 700, w - u(80)), 15, 700, u(36), u(10), T.text)
        local left = math.max(0, FORGIVE_WINDOW - (RealTime() - (DP.OpenedAt or RealTime())))
        text(string.format("%.1f", left), 15, 800, w - u(12), u(10), T.gold, TEXT_ALIGN_RIGHT)
        local tag = DP.Inst and TAGS[DP.Inst.tag] or nil
        local penalty = (row.karma or 0) > 0 and string.format("%s's penalty: -%.0f karma unless forgiven", killerLabel(), row.karma) or nil
        local foot = tag and penalty and (tag .. "  ·  " .. penalty) or tag or penalty
        if foot then text(fit(foot, 10, 500, w - u(24)), 10, 500, u(12), h - u(18), T.muted) end
    end
    return card
end

local function buildHappenedCard(parent)
    local card = K.Panel(parent)
    card.Paint = function(_, w, h)
        K.Card(0, 0, w, h, T.cardGlass, K.Alpha(T.edge, 180))
        local inst, how = DP.Inst, DP.H2H and DP.H2H.how
        if not inst then return end
        cardHead("HOW IT HAPPENED", u(12), u(10), w - u(24))
        local colW = (w - u(24)) / 2
        local x, y = u(12), u(30)
        cell("WEAPON", fit(weaponName(how and how.weapon or inst.wep), 14, 700, colW - u(8)), x, y)
        cell("HIT", hitLabel() or ((inst.hits or 1) .. " hit" .. ((inst.hits or 1) == 1 and "" or "s")), x + colW, y, T.red)
        y = y + u(36)
        cell("DISTANCE", distanceLabel() or "—", x, y)
        local eng = engagementSeconds()
        cell("TIMING", eng and string.format("%.1fs engagement", eng) or string.format("%.1fs before death", num(inst.ago)), x + colW, y)
    end
    return card
end

-- "You dealt to X" (left column) and "X dealt to you" (right column): the trade totals from h2h.traded, with
-- the share of the exchange as a bar.
local function buildDealtCard(parent, mine)
    local card = K.Panel(parent)
    card.Paint = function(_, w, h)
        K.Card(0, 0, w, h, T.cardGlass, K.Alpha(T.edge, 180))
        local traded = DP.H2H and DP.H2H.traded
        local life = DP.H2H and DP.H2H.victim and DP.H2H.victim.life
        local side = traded and (mine and traded.victimToKiller or traded.killerToVictim)
        cardHead(mine and ("YOU DEALT TO " .. string.upper(killerLabel())) or (string.upper(killerLabel()) .. " DEALT TO YOU"), u(12), u(10), w - u(24))
        local dmg, hits = num(side and side.dmg), num(side and side.hits)
        if not side and not mine then
            -- before the ledger lands, the hits you took are known from the replay sequence
            local instances = DP.Seq and DP.Seq.instances
            if istable(instances) then for _, it in ipairs(instances) do dmg, hits = dmg + num(it.dmg), hits + math.max(1, num(it.hits)) end end
        end
        local colW = (w - u(24)) / 3
        local x, y = u(12), u(30)
        cell("DAMAGE", tostring(dmg), x, y, mine and T.green or T.red, true)
        cell("HITS", tostring(hits), x + colW, y, nil, true)
        local dealt = num(traded and traded.victimToKiller and traded.victimToKiller.dmg)
        local taken = num(traded and traded.killerToVictim and traded.killerToVictim.dmg)
        local total = dealt + taken
        local share = total > 0 and math.floor((mine and dealt or taken) / total * 100 + 0.5) or nil
        cell("SHARE", share and (share .. "%") or "—", x + colW * 2, y, nil, true)
        if life and mine and num(life.hits) > 0 then text(num(life.hits) .. " hits this life", 9, 500, w - u(12), u(10), T.muted, TEXT_ALIGN_RIGHT) end
        draw.RoundedBox(2, u(12), h - u(16), w - u(24), u(4), K.Alpha(T.ink, 235))
        if total > 0 then draw.RoundedBox(2, u(12), h - u(16), (w - u(24)) * (mine and dealt or taken) / total, u(4), mine and T.green or T.accent) end
    end
    return card
end

local function buildPointsCard(parent)
    local card = K.Panel(parent)
    card.Paint = function(_, w, h)
        K.Card(0, 0, w, h, T.cardGlass, K.Alpha(T.edge, 180))
        local points = DP.H2H and DP.H2H.victim and DP.H2H.victim.life and DP.H2H.victim.life.points
        if not points then return end
        local combat, heals, zp = num(points.combat), num(points.heals or points.heal), num(points.zp)
        cardHead("POINTS THIS LIFE", u(12), u(10), w - u(24))
        text("+" .. (combat + heals + zp), 18, 800, w - u(12), u(6), T.green, TEXT_ALIGN_RIGHT)
        local colW = (w - u(24)) / 3
        local x, y = u(12), u(34)
        cell("COMBAT", "+" .. combat, x, y)
        cell("HEALS", "+" .. heals, x + colW, y)
        cell("ZP", "+" .. zp, x + colW * 2, y, T.gold)
    end
    return card
end

-- ACTION TIMELINE (owner canvas note 2026-09-25: "an action timeline for this life, that shows what important actions
-- occurred, on hover, with timestamps"). Events come from what the panel has: the hits you took (replay sequence,
-- timed by `ago`), your death, and an ADDITIVE per-life event log `h2h.timeline` = {{t = seconds into the life,
-- kind = "kill"|"heal"|"dealt"|"taken"|"other", text = "..."}, ...} when the ledger ships one (nothing does yet).
local function buildTimeline()
    local events = {}
    local life = DP.H2H and DP.H2H.victim and DP.H2H.victim.life
    local alive = life and tonumber(life.alive) or nil
    local eng = engagementSeconds() or 0
    local span = alive or math.max(eng, 1)
    local instances = DP.Seq and DP.Seq.instances
    if istable(instances) then
        for i, it in ipairs(instances) do
            events[#events + 1] = {t = span - num(it.ago), kind = "taken", hit = i,
                text = "-" .. num(it.dmg) .. "  " .. (it.attacker or "?") .. " · " .. weaponName(it.wep)}
        end
    end
    local log = DP.H2H and DP.H2H.timeline
    if istable(log) then
        for _, e in ipairs(log) do
            if istable(e) and isnumber(e.t) then events[#events + 1] = {t = e.t, kind = e.kind or "other", text = tostring(e.text or e.kind or "")} end
        end
    end
    events[#events + 1] = {t = span, kind = "death", text = "Killed by " .. killerLabel()}
    table.sort(events, function(a, b) return a.t < b.t end)
    return events, span
end

local function timelineColor(kind)
    if kind == "taken" or kind == "death" then return T.red end
    if kind == "kill" then return T.gold end
    if kind == "heal" or kind == "dealt" then return T.green end
    return T.muted
end

-- Hit-stepper pips: one play function per pip index, and hit tables reused between frames.
local pipPlay = {}
local function pipPlayFn(i)
    local fn = pipPlay[i]
    if not fn then fn = function() P.Call("Play", i) end pipPlay[i] = fn end
    return fn
end

local function buildTimelineCard(parent)
    local card = K.Panel(parent)
    card:SetMouseInputEnabled(true)
    card.hits = {}
    card.Paint = function(s, w, h)
        local hits = s.hits -- reused in place (HUD perf pass pattern): no tables or closures per frame
        for k = #hits, 1, -1 do hits[k] = nil end
        s.hitPool = s.hitPool or {}
        K.Card(0, 0, w, h, T.cardGlass, K.Alpha(T.edge, 180))
        local events, span = DP.Timeline, DP.TimelineSpan
        if not istable(events) or #events == 0 then return end
        local traded = DP.H2H and DP.H2H.traded
        local right = traded and string.format("You dealt %d   ·   You took %d", num(traded.victimToKiller and traded.victimToKiller.dmg), num(traded.killerToVictim and traded.killerToVictim.dmg)) or nil
        cardHead("ACTION TIMELINE  ·  THIS LIFE", u(12), u(10), w - u(24), right, T.text)
        local x0, x1, ry = u(16), w - u(16), u(52)
        surface.SetDrawColor(T.hair)
        surface.DrawRect(x0, ry, x1 - x0, 1)
        text("0:00", 9, 500, x0, ry + u(6), T.muted)
        text(clock(span) or "", 9, 500, x1, ry + u(6), T.muted, TEXT_ALIGN_RIGHT)
        local mx, my = s:CursorPos()
        local hovered
        for _, e in ipairs(events) do
            local frac = span > 0 and math.Clamp(e.t / span, 0, 1) or 1
            local ex = x0 + (x1 - x0) * frac
            local up = e.kind == "kill" or e.kind == "heal" or e.kind == "dealt"
            local color = timelineColor(e.kind)
            local tall = e.kind == "death" and u(14) or u(10)
            draw.RoundedBox(1, ex - 1, up and (ry - tall) or ry, e.kind == "death" and u(3) or u(2), tall, color)
            if e.hit then
                local n = #hits + 1
                local hit = s.hitPool[n]
                if not hit then hit = {} s.hitPool[n] = hit end
                hit.x, hit.y, hit.w, hit.h, hit.fn = ex - u(6), ry - u(12), u(12), u(24), pipPlayFn(e.hit)
                hits[n] = hit
            end
            if not hovered and mx >= ex - u(6) and mx <= ex + u(6) and my >= u(30) and my <= h then hovered = {e = e, x = ex} end
        end
        if hovered then
            local e = hovered.e
            local label = (clock(e.t) or "") .. "   " .. e.text
            local tw = measure(label, 11, 600) + u(16)
            local bx = math.Clamp(hovered.x - tw / 2, u(8), w - tw - u(8))
            draw.RoundedBox(3, bx, u(24), tw, u(20), K.Alpha(T.ink, 240))
            text(label, 11, 600, bx + u(8), u(34), timelineColor(e.kind), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        elseif DP.T and DP.T.phase == "playing" then
            text("Hover a mark for what happened   ·   click a hit to replay it", 9, 500, w / 2, u(34), K.Alpha(T.muted, 160), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    end
    card.OnMousePressed = function(s, code)
        if code ~= MOUSE_LEFT then return end
        local mx, my = s:CursorPos()
        for _, hit in ipairs(s.hits) do
            if mx >= hit.x and mx <= hit.x + hit.w and my >= hit.y and my <= hit.y + hit.h then hit.fn() return end
        end
    end
    return card
end

local function kd(kills, deaths)
    kills, deaths = num(kills), num(deaths)
    if deaths == 0 then return kills > 0 and tostring(kills) or "0" end
    return string.format("%.2f", kills / deaths)
end

-- HEAD TO HEAD as mirrored bars: your bar grows left from the centred label, the killer's grows right; the larger
-- value is lit. Tabs switch This life / Lifetime (lifetime only when the ledger sent it).
local function drawMirrorRow(y, w, label, you, them, youNum, themNum)
    local labelW, valW, gap = u(110), u(56), u(10)
    local barW = (w - u(24) - labelW - valW * 2 - gap * 4) / 2
    local cx = w / 2
    text(label, 10, 600, cx, y + u(9), T.muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    local most = math.max(youNum or 0, themNum or 0)
    local youWins, themWins = (youNum or 0) > (themNum or 0), (themNum or 0) > (youNum or 0)
    local lx1 = cx - labelW / 2 - gap
    draw.RoundedBox(2, lx1 - barW, y + u(6), barW, u(6), K.Alpha(T.ink, 235))
    if most > 0 and youNum then draw.RoundedBox(2, lx1 - barW * youNum / most, y + u(6), barW * youNum / most, u(6), youWins and T.green or K.Alpha(T.green, 110)) end
    text(tostring(you), 13, 700, lx1 - barW - gap, y + u(9), youWins and T.green or T.text, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    local rx0 = cx + labelW / 2 + gap
    draw.RoundedBox(2, rx0, y + u(6), barW, u(6), K.Alpha(T.ink, 235))
    if most > 0 and themNum then draw.RoundedBox(2, rx0, y + u(6), barW * themNum / most, u(6), themWins and T.accent or K.Alpha(T.accent, 110)) end
    text(tostring(them), 13, 700, rx0 + barW + gap, y + u(9), themWins and T.red or T.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    return y + u(22)
end

local function buildCompareCard(parent)
    local card = K.Panel(parent)
    card.Tabs = K.Tabs(card, {"This life", "Lifetime"}, 1)
    card.Paint = function(_, w, h)
        K.Card(0, 0, w, h, T.cardGlass, K.Alpha(T.edge, 180))
        local life = DP.H2H and DP.H2H.victim and DP.H2H.victim.life
        if not life then return end
        local killerName = killerLabel()
        local killerLife = DP.H2H.killer and DP.H2H.killer.life
        local lifetime = DP.H2H.lifetime
        text("YOU", 10, 700, u(16), u(9), T.green, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        text(fit(string.upper(killerName), 10, 700, u(160)), 10, 700, w - u(16), u(9), T.red, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        local y = u(34)
        local showLifetime = card.Tabs.Selected == 2 and lifetime
        if not showLifetime then
            local kl = killerLife or {}
            local function v(t, k) return t and t[k] ~= nil and num(t[k]) or nil end
            y = drawMirrorRow(y, w, "Kills", num(life.kills), killerLife and num(kl.kills) or "—", num(life.kills), v(killerLife, "kills"))
            y = drawMirrorRow(y, w, "Hits landed", num(life.hits), killerLife and num(kl.hits) or "—", num(life.hits), v(killerLife, "hits"))
            y = drawMirrorRow(y, w, "Damage dealt", num(life.dealt), killerLife and num(kl.dealt) or "—", num(life.dealt), v(killerLife, "dealt"))
            y = drawMirrorRow(y, w, "Damage taken", num(life.taken), killerLife and num(kl.taken) or "—", num(life.taken), v(killerLife, "taken"))
            drawMirrorRow(y, w, "Time alive", clock(life.alive) or "—", (killerLife and clock(kl.alive)) or "—", num(life.alive), v(killerLife, "alive"))
        else
            local you, them = lifetime.victim or {}, lifetime.killer or {}
            local function v(t, k) return t[k] ~= nil and num(t[k]) or nil end
            y = drawMirrorRow(y, w, "Kills", num(you.kills), them.kills and num(them.kills) or "—", num(you.kills), v(them, "kills"))
            y = drawMirrorRow(y, w, "Deaths", num(you.deaths), them.deaths and num(them.deaths) or "—", num(you.deaths), v(them, "deaths"))
            y = drawMirrorRow(y, w, "K/D", kd(you.kills, you.deaths), them.kills and kd(them.kills, them.deaths) or "—", tonumber(kd(you.kills, you.deaths)), them.kills and tonumber(kd(them.kills, them.deaths)) or nil)
            y = drawMirrorRow(y, w, "Damage", num(you.damage), them.damage and num(them.damage) or "—", num(you.damage), v(them, "damage"))
            drawMirrorRow(y, w, "Rounds", num(you.rounds), them.rounds and num(them.rounds) or "—", num(you.rounds), v(them, "rounds"))
        end
    end
    return card
end

----------------------------------------------------------------------------------------------
-- The inset: the replay itself and its three states (canvas boards Inset_Incoming / Inset_Playing / Inset_Verdict).
----------------------------------------------------------------------------------------------
local function chip(label, x, y, color, bg, align)
    local tw = measure(label, 10, 700) + u(14)
    local bx = align == TEXT_ALIGN_RIGHT and x - tw or x
    draw.RoundedBox(3, bx, y, tw, u(20), bg or K.Alpha(CHIP_BG, 200))
    text(label, 10, 700, bx + tw / 2, y + u(10), color or T.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    return tw
end

-- The hit rail: a progress line with one numbered pip per hit, the current one lit; pips are click zones and 1-9 jump.
local function hitRail(s, x, y, w, t)
    local count = math.min(t.count or 1, 12)
    local index = math.Clamp(t.index or 1, 1, count)
    local frac = 0
    if t.cs and t.first and t.last and t.last > t.first then frac = math.Clamp((t.cs - t.first) / (t.last - t.first), 0, 1) end
    draw.RoundedBox(2, x, y + u(8), w, u(4), K.Alpha(T.white, 40))
    local pipSpan = count > 1 and (w - u(24)) or 0
    local lit = count > 1 and (index - 1) / (count - 1) or 1
    draw.RoundedBox(2, x, y + u(8), math.max(u(4), w * (t.phase == "playing" and math.max(frac, lit) or lit)), u(4), T.accent)
    for i = 1, count do
        local px = x + u(12) + (count > 1 and pipSpan * (i - 1) / (count - 1) or w / 2 - u(12))
        local current = i == index
        draw.RoundedBox(3, px - u(11), y - u(14), u(22), u(18), current and T.main or K.Alpha(T.ink, 220))
        text(tostring(i), 10, 700, px, y - u(5), current and T.white or T.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.RoundedBox(u(5), px - u(5), y + u(5), u(10), u(10), current and T.gold or ((t.reported and t.reported[i]) and T.green or T.text))
        local hit = s.hitPool[i]
        if not hit then hit = {} s.hitPool[i] = hit end
        hit.x, hit.y, hit.w, hit.h, hit.fn = px - u(12), y - u(16), u(24), u(34), pipPlayFn(i)
        s.hits[#s.hits + 1] = hit
    end
end

local function paintInset(s, w, h)
    local hits = s.hits
    if not hits then hits = {} s.hits = hits end
    for k = #hits, 1, -1 do hits[k] = nil end
    s.hitPool = s.hitPool or {}
    local t = DP.T
    local phase = t and t.phase
    K.Card(0, 0, w, h, INSET_BG)
    local drawn = phase == "playing" and P.RenderInset(s, 0, 0, w, h)
    if phase == "waiting" or (phase == "playing" and not drawn) then
        -- Loading: the live spectator camera renders under the panel here (P3_SEAM) - dim it, letterbox it, say what is
        -- coming and show the hit rail already complete (the sequence is known on arrival). Never a black frame.
        draw.RoundedBox(4, 0, 0, w, h, INSET_DIM)
        local bar = u(40)
        draw.RoundedBoxEx(4, 0, 0, w, bar, LETTERBOX, true, true, false, false)
        draw.RoundedBoxEx(4, 0, h - bar, w, bar, LETTERBOX, false, false, true, true)
        chip("SCENE OF DEATH", u(12), u(10))
        local pulse = 0.7 + 0.3 * math.abs(math.sin(RealTime() * 2.2))
        text("Loading replay", 22, 700, u(20), h - bar - u(72), K.Alpha(T.text, 255 * pulse))
        local wep = weaponName(DP.Inst and DP.Inst.wep)
        text(fit("Killed by " .. killerLabel() .. " with " .. withArticle(wep), 13, 500, w - u(40)), 13, 500, u(20), h - bar - u(44), T.muted)
        text("Hold Space to skip", 11, 500, u(20), h - bar - u(24), K.Alpha(T.muted, 200))
        if t and (t.count or 0) > 0 then hitRail(s, u(16), h - u(30), w - u(32), t) end
        return
    end
    if phase == "over" or phase == "leaving" then
        -- KILLING BLOW verdict (canvas Inset_Verdict): the last frame stays under a scrim, the verdict headlines it.
        draw.RoundedBox(4, 0, 0, w, h, INSET_DIM)
        local cy = h / 2 - u(30)
        text("KILLING BLOW", 11, 700, w / 2, cy - u(46), T.gold, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        text(verdictWord(), 40, 800, w / 2, cy - u(14), T.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        local dist = distanceLabel()
        local how = DP.H2H and DP.H2H.how
        local line1 = killerLabel() .. " killed you" .. (dist and (" from " .. dist) or "") .. " with " .. withArticle(weaponName(how and how.weapon or (DP.Inst and DP.Inst.wep)))
        text(fit(line1, 16, 500, w - u(40)), 16, 500, w / 2, cy + u(22), T.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        local eng = engagementSeconds()
        text(eng and string.format("The engagement lasted %.1f seconds", eng) or (DP.OverLine or ""), 16, 500, w / 2, cy + u(44), T.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        local keys = {{"Space", "Close"}, {"Q", "Replay"}, {"V", (t and t.saved) and "Saved" or "Save"}}
        local kx = w / 2 - u(110)
        for _, k in ipairs(keys) do
            local kw = measure(k[1], 10, 700) + u(10)
            draw.RoundedBox(3, kx, cy + u(66), kw, u(18), K.Alpha(T.edge, 220))
            text(k[1], 10, 700, kx + kw / 2, cy + u(75), T.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            text(k[2], 11, 500, kx + kw + u(6), cy + u(75), T.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            kx = kx + kw + u(6) + measure(k[2], 11, 500) + u(16)
        end
        local left = math.Clamp(1 - (RealTime() - (DP.OverAt or RealTime())) / END_CARD_SECONDS, 0, 1)
        text("Returning to spectating", 10, 500, u(16), h - u(30), T.muted)
        text(string.format("0:%02d", math.ceil(left * END_CARD_SECONDS)), 10, 600, w - u(16), h - u(30), T.text, TEXT_ALIGN_RIGHT)
        draw.RoundedBox(2, u(16), h - u(16), w - u(32), u(4), K.Alpha(T.white, 40))
        draw.RoundedBox(2, u(16), h - u(16), (w - u(32)) * left, u(4), T.gold)
        return
    end
    if not drawn or not t then return end
    -- chips over the frame: what you are watching, the rate, the beta tag
    local cw = chip("ATTACKER VIEW", u(12), u(10), T.white, K.Alpha(T.main, 220))
    if t.inst and t.inst.attacker then chip(fit(weaponName(t.inst.wep) .. "  ·  " .. tostring(t.inst.attacker), 10, 700, w * 0.45), u(12) + cw + u(6), u(10)) end
    local rx = w - u(12)
    rx = rx - chip("BETA", rx, u(10), T.text, nil, TEXT_ALIGN_RIGHT) - u(6)
    if t.rate and t.rate < 0.99 then chip(string.format("%.2gx", t.rate), rx, u(10), T.accent, nil, TEXT_ALIGN_RIGHT) end
    -- the hit rail, then the caption line under it
    hitRail(s, u(16), h - u(40), w - u(32), t)
    local count, index = t.count or 1, t.index or 1
    text("Hit " .. index .. " of " .. count, 11, 600, u(16), h - u(20), T.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    text("Space to skip   |   Hold Space to skip all", 10, 500, w / 2, h - u(20), T.muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    if t.cs and t.first and t.last and t.last > t.first then
        text(clock((t.cs - t.first) / 100) .. " / " .. clock((t.last - t.first) / 100), 11, 500, w - u(16), h - u(20), T.muted, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    end
end

----------------------------------------------------------------------------------------------
-- Panel construction (built once, lazily; torn down and rebuilt on re-include per LESSONS.md).
----------------------------------------------------------------------------------------------
local function roleChip(role, x, y, align)
    if not role then return end
    local tw = measure(string.upper(role), 9, 700) + u(12)
    local bx = align == TEXT_ALIGN_RIGHT and x - tw or x
    draw.RoundedBox(3, bx, y, tw, u(16), K.Alpha(T.ink, 220))
    text(string.upper(role), 9, 700, bx + tw / 2, y + u(8), role == "Traitor" and T.red or T.green, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

local function buildPanel()
    local root = K.Panel(nil)
    -- A top-level panel is painted by the VGUI pass regardless of what the killcam's RenderScene returns (a
    -- HUD-parented one vanished the moment playback began, 2026-09-24).
    root:SetDrawOnTop(true)
    root.Paint = function() end

    local card = K.Panel(root)
    card.Paint = function(_, w, h) K.Card(0, 0, w, h, T.glass, K.Alpha(T.edge, 220)) end

    -- HEADER band: caption, headline, the how-line; chips and the N key on the right.
    local header = K.Panel(card)
    header.Paint = function(_, w, h)
        local zbT = rawget(_G, "zb")
        local parts = {"YOU DIED"}
        if zbT and zbT.CROUND then parts[#parts + 1] = string.upper(tostring(zbT.CROUND)) end
        if zbT and tonumber(zbT.Roundscount) then parts[#parts + 1] = "ROUND " .. tonumber(zbT.Roundscount) end
        text(table.concat(parts, "   ·   "), 11, 700, 0, 0, T.red)
        text(fit(killerLabel() .. " killed you", 40, 800, w - u(360)), 40, 800, 0, u(16), T.text)
        local how = DP.H2H and DP.H2H.how
        local line = {weaponName(how and how.weapon or (DP.Inst and DP.Inst.wep))}
        local hit = hitLabel()
        if hit then line[#line + 1] = hit end
        local dist = distanceLabel()
        if dist then line[#line + 1] = dist end
        local eng = engagementSeconds()
        if eng then line[#line + 1] = string.format("%.1fs engagement", eng) end
        text(fit(table.concat(line, "   ·   "), 13, 500, w - u(400)), 13, 500, 0, h - u(18), T.muted)
        local tag = DP.Inst and TAGS[DP.Inst.tag]
        if tag then
            local lw = measure(table.concat(line, "   ·   "), 13, 500)
            text("   ·   " .. tag, 13, 500, lw, h - u(18), DP.Inst.tag == "ivi" and T.gold or T.muted)
        end
        -- right side
        local rx = w
        rx = rx - chip("BETA", rx, 0, T.text, nil, TEXT_ALIGN_RIGHT) - u(6)
        local count = DP.T and DP.T.count
        if count then chip(count .. (count == 1 and " HIT TAKEN" or " HITS TAKEN"), rx, 0, T.text, nil, TEXT_ALIGN_RIGHT) end
        if DP.Note and RealTime() < (DP.NoteUntil or 0) then
            text(DP.Note, 12, 600, w, h - u(18), T.green, TEXT_ALIGN_RIGHT)
        else
            local kw = measure("N", 10, 700) + u(10)
            local label = "disable killcams"
            local lw = measure(label, 11, 500)
            draw.RoundedBox(3, w - lw - u(6) - kw, h - u(20), kw, u(18), K.Alpha(T.edge, 200))
            text("N", 10, 700, w - lw - u(6) - kw / 2, h - u(11), T.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            text(label, 11, 500, w, h - u(11), T.muted, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        end
    end

    -- YOU / KILLER blocks: avatar, name, role chip. The killer's is right-aligned.
    local youBlock, killerBlock = K.Panel(card), K.Panel(card)
    local victimAv = K.Avatar(youBlock, 64)
    local killerAv = K.Avatar(killerBlock, 64)
    local killerInit = miniAvatar(killerBlock, "?")
    youBlock.Paint = function(_, w, h)
        local av = h
        text("YOU", 10, 700, av + u(14), u(2), T.muted)
        text(fit(LocalPlayer():Nick(), 22, 700, w - av - u(14)), 22, 700, av + u(14), u(16), T.text)
        roleChip(DP.Roles and DP.Roles[2], av + u(14), h - u(18))
    end
    killerBlock.Paint = function(_, w, h)
        local av = h
        text("KILLER", 10, 700, w - av - u(14), u(2), T.muted, TEXT_ALIGN_RIGHT)
        text(fit(killerLabel(), 22, 700, w - av - u(14)), 22, 700, w - av - u(14), u(16), T.text, TEXT_ALIGN_RIGHT)
        roleChip(DP.Roles and DP.Roles[1], w - av - u(14), h - u(18), TEXT_ALIGN_RIGHT)
    end

    local body = K.Panel(card)
    local inset = K.Panel(body)
    inset:SetMouseInputEnabled(true)
    inset.hits = {}
    inset.Paint = paintInset
    inset.OnMousePressed = function(s, code)
        if code ~= MOUSE_LEFT then return end
        local mx, my = s:CursorPos()
        for _, hit in ipairs(s.hits) do
            if mx >= hit.x and mx <= hit.x + hit.w and my >= hit.y and my <= hit.y + hit.h then
                hit.fn()
                return
            end
        end
    end

    -- the chat's dock (owner 2026-09-24 / canvas 2026-09-25: bottom-left): a backing card; the chat frame itself moves
    -- onto it (panels.lua P.ChatDock, published from refreshFrame while the panel is up)
    local chatDock = K.Panel(body)
    chatDock.Paint = function(_, w, h)
        K.Card(0, 0, w, h, DOCK_FILL, DOCK_EDGE)
        text("CHAT", 10, 700, u(12), u(8), T.muted)
    end

    local pointsCard = buildPointsCard(body)
    local dealtCard = buildDealtCard(body, true)
    local tradeCard = buildTimelineCard(body) -- the action timeline (was "damage traded"; the name is kept for the tests)
    local compareCard = buildCompareCard(body)
    local happenedCard = buildHappenedCard(body)
    local takenCard = buildDealtCard(body, false)
    local forgiveCard = buildForgiveCard(body)

    local keyRow = K.Panel(card)
    keyRow.Paint = function(_, w, h)
        surface.SetDrawColor(T.hair)
        surface.DrawRect(0, 0, w, 1)
        local x = 0
        local over = DP.T and DP.T.phase == "over"
        for _, hint in ipairs(KEY_HINTS) do
            local action = hint[2]
            if over and hint[1] == "Space" then action = "Close" elseif over and hint[1] == "Q" then action = "Replay" end
            local kw = measure(hint[1], 11, 700) + u(10)
            local aw = measure(action, 11, 500)
            local limit = IsValid(DP.reportBtn) and DP.reportBtn:GetX() - u(20) or w
            if x + kw + u(6) + aw > limit then break end
            draw.RoundedBox(3, x, h / 2 - u(9), kw, u(18), K.Alpha(T.edge, 200))
            text(hint[1], 11, 700, x + kw / 2, h / 2, T.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            text(action, 11, 500, x + kw + u(6), h / 2, T.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            x = x + kw + u(6) + aw + u(18)
        end
    end
    local footer = keyRow -- the buttons sit on the key row's right (one band, canvas footer)
    local reportBtn = kitButton(footer, function() return (DP.T and DP.T.reported and DP.T.index and DP.T.reported[DP.T.index]) and "Reported" or "Report" end, "secondary",
        function() return DP.Inst ~= nil and DP.Inst.reportable == true and not (DP.T and DP.T.reported and DP.T.index and DP.T.reported[DP.T.index]) end,
        function() P.Call("Report", DP.T and DP.T.index) end, "G")
    local saveBtn = kitButton(footer, function() return (DP.T and DP.T.saved) and "Saved" or "Save replay" end, "primary",
        function() return not (DP.T and DP.T.saved) end, function() P.Call("Save") end, "V")
    local skipBtn = kitButton(footer, "Spectate now", "ghost", nil, function() P.Call("Skip") end, "Q")

    DP.root, DP.card, DP.header = root, card, header
    DP.youBlock, DP.killerBlock, DP.victimAv, DP.killerAv, DP.killerInit = youBlock, killerBlock, victimAv, killerAv, killerInit
    DP.body, DP.inset, DP.keyRow, DP.chatDock = body, inset, keyRow, chatDock
    DP.pointsCard, DP.dealtCard, DP.tradeCard, DP.compareCard = pointsCard, dealtCard, tradeCard, compareCard
    DP.happenedCard, DP.takenCard, DP.forgiveCard = happenedCard, takenCard, forgiveCard
    DP.footer, DP.reportBtn, DP.saveBtn, DP.skipBtn = footer, reportBtn, saveBtn, skipBtn
    return root
end

local function place(panel, x, y, w, h)
    panel:SetPos(math.floor(x), math.floor(y))
    panel:SetSize(math.floor(w), math.floor(h))
end

local function layout()
    U = P.Unit()
    local card = DP.card
    -- Owner, 2026-09-24: "full-screen" means the screen, not a card floating in a margin. The card IS the screen.
    local w, h = ScrW(), ScrH()
    local rise = 1 - K.EaseOut(K.Progress(DP.BornAt, 0.28))
    DP.root:SetSize(w, h)
    DP.root:SetPos(0, math.floor(rise * u(12)))
    DP.root:SetAlpha(math.floor(255 * (1 - rise)))
    card:SetPos(0, 0)
    card:SetSize(w, h)

    -- the printable area: a page margin, and the voice column's gutter on the right (canvas note, all panels)
    local pad = u(40)
    local innerX, innerW = pad, w - pad * 2 - P.RightGutter()
    local headerH, footerH = u(88), u(44)
    place(DP.header, innerX, u(28), innerW, headerH)
    place(DP.keyRow, innerX, h - u(24) - footerH, innerW, footerH)
    local bodyY = u(28) + headerH + u(14)
    local bodyH = h - u(24) - footerH - u(12) - bodyY
    place(DP.body, innerX, bodyY, innerW, bodyH)

    -- footer buttons, right-aligned on the key row
    local btnH = u(32)
    local bx = innerW
    for _, btn in ipairs({DP.skipBtn, DP.saveBtn, DP.reportBtn}) do
        local bw = math.max(u(100), btn:Measure())
        bx = bx - bw
        btn:SetPos(bx, (footerH - btnH) / 2)
        btn:SetSize(bw, btnH)
        bx = bx - u(8)
    end

    -- three columns: YOU | replay | KILLER. The replay column keeps 40% of the width; when that leaves a side column
    -- narrower than the chat frame's 384 px minimum (720p with the voice gutter) the chat dock spans the bottom of the
    -- YOU and replay columns instead of the YOU column's remainder.
    local gap = u(28)
    local centerW = math.max(math.floor(innerW * 0.4), u(480))
    local colW = math.floor((innerW - centerW - gap * 2) / 2)
    local leftX, centerX, rightX = 0, colW + gap, colW + gap + centerW + gap
    local wideDock = colW < 384
    local dockW = wideDock and (colW + gap + centerW) or colW
    local dockH = wideDock and math.max(180, math.floor(bodyH * 0.3)) or nil

    -- YOU column
    local blockH = u(64)
    place(DP.youBlock, leftX, 0, colW, blockH)
    DP.victimAv:SetPos(0, 0); DP.victimAv:SetSize(blockH, blockH)
    local y = blockH + u(12)
    local hasPoints = DP.H2H and DP.H2H.victim and DP.H2H.victim.life and DP.H2H.victim.life.points ~= nil
    DP.pointsCard:SetVisible(hasPoints and true or false)
    if hasPoints then place(DP.pointsCard, leftX, y, colW, u(72)) y = y + u(72) + u(10) end
    local hasTrade = DP.H2H and DP.H2H.traded ~= nil
    DP.dealtCard:SetVisible(hasTrade and true or false)
    if hasTrade then place(DP.dealtCard, leftX, y, colW, u(84)) y = y + u(84) + u(10) end
    dockH = dockH or math.max(180, bodyH - y)
    place(DP.chatDock, leftX, bodyH - dockH, dockW, dockH)

    -- replay column
    local centerH = wideDock and (bodyH - dockH - u(10)) or bodyH
    local insetH = math.min(math.floor(centerW * 9 / 16), math.floor(centerH * 0.6))
    place(DP.inset, centerX, 0, centerW, insetH)
    local cy = insetH + u(12)
    local instances = DP.Seq and DP.Seq.instances
    local hasTimeline = istable(instances) and #instances > 0
    DP.tradeCard:SetVisible(hasTimeline and true or false)
    local tlH = u(84)
    if hasTimeline then place(DP.tradeCard, centerX, cy, centerW, tlH) cy = cy + tlH + u(10) end
    local hasLife = DP.H2H and DP.H2H.victim and DP.H2H.victim.life ~= nil
    local cmpH = centerH - cy
    local showCompare = hasLife and cmpH >= u(120)
    DP.compareCard:SetVisible(showCompare and true or false)
    if showCompare then
        place(DP.compareCard, centerX, cy, centerW, cmpH)
        DP.compareCard.Tabs:SetVisible(DP.H2H.lifetime ~= nil)
        DP.compareCard.Tabs:SetPos(centerW / 2 - u(90), u(4)); DP.compareCard.Tabs:SetSize(u(180), u(22))
    end

    -- KILLER column
    place(DP.killerBlock, rightX, 0, colW, blockH)
    DP.killerAv:SetPos(colW - blockH, 0); DP.killerAv:SetSize(blockH, blockH)
    DP.killerInit:SetPos(colW - blockH, 0); DP.killerInit:SetSize(blockH, blockH)
    local showKillerAv = findSteamID(DP.H2H and DP.H2H.killer) ~= nil or findSteamID(DP.Inst) ~= nil
    DP.killerAv:SetVisible(showKillerAv); DP.killerInit:SetVisible(not showKillerAv)
    y = blockH + u(12)
    DP.happenedCard:SetVisible(DP.Inst ~= nil)
    if DP.Inst then place(DP.happenedCard, rightX, y, colW, u(104)) y = y + u(104) + u(10) end
    DP.takenCard:SetVisible((hasTrade or hasTimeline) and true or false)
    if hasTrade or hasTimeline then place(DP.takenCard, rightX, y, colW, u(84)) y = y + u(84) + u(10) end
    -- forgiveness anchors to the bottom of the killer column
    local forgiveOn = DP.GuiltRow ~= nil or DP.GuiltDecided ~= nil
    local fH = DP.GuiltDecided and u(40) or u(150)
    forgiveOn = forgiveOn and y + fH <= bodyH
    DP.forgiveCard:SetVisible(forgiveOn and true or false)
    if forgiveOn then
        place(DP.forgiveCard, rightX, bodyH - fH, colW, fH)
        DP.forgiveCard.Bar:SetVisible(DP.GuiltDecided == nil)
        DP.forgiveCard.Bar:SetPos(u(12), u(34)); DP.forgiveCard.Bar:SetSize(colW - u(24), u(4))
        for i, btn in ipairs(DP.forgiveCard.Buttons) do
            btn:SetVisible(DP.GuiltDecided == nil and btn.Label ~= nil)
            btn:SetPos(u(12) + ((i - 1) % 2) * (colW - u(24) + u(6)) / 2, u(46) + math.floor((i - 1) / 2) * u(34))
            btn:SetSize((colW - u(30)) / 2, u(30))
        end
    end
end

----------------------------------------------------------------------------------------------
-- Open/close lifecycle + key polling.
----------------------------------------------------------------------------------------------
local keysDown = {}

local function closeToast(alive)
    if not (ZCGoobApps.Notify and isfunction(ZCGoobApps.Notify.Push)) then return end
    -- Only a real respawn cuts a replay short. The highlight taking the screen, the end card timing out or Q are
    -- not "you missed it".
    if alive and DP.LastPhase and DP.LastPhase ~= "over" and DP.LastKillerName then
        ZCGoobApps.Notify.Push({app = "Replays", glyph = "play", title = "Find it in Replays", body = "Killed by " .. DP.LastKillerName})
    end
end

local function overLine(seq)
    local hits, dmg, who, attackers = 0, 0, {}, 0
    for _, it in ipairs(seq and seq.instances or {}) do
        hits, dmg = hits + num(it.hits), dmg + num(it.dmg)
        if not who[it.attacker or "?"] then who[it.attacker or "?"] = true attackers = attackers + 1 end
    end
    return string.format("%d hit%s   ·   %d attacker%s   ·   %d damage", hits, hits == 1 and "" or "s", attackers, attackers == 1 and "" or "s", dmg)
end

-- prevote_sb_20260925 (owner 2026-09-25, relayed by the killcam session: "the scoreboard should ALWAYS take
-- precedence over those screens"): while ZCKillcamView.ScoreboardUp() says the scoreboard is up this panel steps aside
-- (hidden, no hotkeys; a key held through it is not a press). Feature-detected: without it nothing changes, and an
-- error in it never hides the panel.
function DP.ScoreboardUp()
    local V = rawget(_G, "ZCKillcamView")
    if not (istable(V) and isfunction(V.ScoreboardUp)) then return false end
    local ok, up = pcall(V.ScoreboardUp)
    return ok and up == true
end
local function refreshFrame()
    local enabled = P.Enabled()
    local t = enabled and P.Replay() or nil
    local me = LocalPlayer()
    local alive = IsValid(me) and me:Alive()
    -- The round-end panel outranks this one once its PANEL is up. Not in its "winner" phase: that card is HUDPaint only,
    -- and while a life replay still plays under a full claim the killcam blanks RenderScene, which skips HUDPaint, so
    -- stepping aside then left the screen black for up to 3 s (review 2026-09-26).
    local roundEnd = A.RoundEnd and A.RoundEnd.Phase == "panel"
    -- The killcam only hands its screens over with zc_killcam_ui 1 (panels.lua sets it unless the player chose 0):
    -- with 0 it draws its own replay and takes its own keys, and this panel would render the replay a second time.
    local kcui = GetConVar("zc_killcam_ui")
    local wants = enabled and kcui ~= nil and kcui:GetBool() and not alive and istable(t) and t.kind == "life" and not roundEnd

    if wants and not IsValid(DP.root) then buildPanel() end
    if not wants then
        if DP.Open then closeToast(alive) P.ChatDock(nil) end
        DP.Open, DP.WantGuilt, DP.GuiltDecided, DP.OverAt, DP.OverLine = false, false, nil, nil, nil
        DP.Timeline, DP.TimelineSpan, DP.TimelineKey = nil, nil, nil
        DP.SpaceSince, DP.SpaceHeld = nil, nil
        if IsValid(DP.root) then DP.root:SetVisible(false) end
        -- Hand the cursor over rather than switch it off under the round-end panel that is taking the screen now.
        if DP.ScreenClicker then
            if not (A.RoundEnd and A.RoundEnd.CursorOn) then gui.EnableScreenClicker(false) end
            DP.ScreenClicker = false
        end
        P.Release(keysDown)
        return
    end

    DP.T, DP.Inst, DP.Seq, DP.H2H = t, t.inst, t.seq, t.h2h
    DP.KillerName = (DP.H2H and DP.H2H.killer and DP.H2H.killer.name) or (DP.Inst and DP.Inst.attacker)
    DP.Roles = DP.Inst and ROLES[DP.Inst.tag] or nil
    DP.GuiltRow = DP.MatchGuiltRow(DP.KillerName)
    DP.LastPhase, DP.LastKillerName = t.phase, DP.KillerName
    if t.phase == "over" then
        if not DP.OverAt then DP.OverAt, DP.OverLine = RealTime(), overLine(t.seq) end
    else
        DP.OverAt = nil
    end
    -- the action timeline is rebuilt only when its inputs change (table identity of the sequence / ledger)
    local tlKey = tostring(DP.Seq) .. "/" .. tostring(DP.H2H)
    if DP.TimelineKey ~= tlKey then
        DP.TimelineKey = tlKey
        DP.Timeline, DP.TimelineSpan = buildTimeline()
    end

    if not DP.Open then
        DP.Open, DP.WantGuilt = true, true
        DP.OpenedAt, DP.BornAt = RealTime(), RealTime()
        DP.Note, DP.GuiltDecided = nil, nil
        DP.GuiltRows = nil -- a previous death's rows must not match this killer before the fresh reply lands
        gui.EnableScreenClicker(true); DP.ScreenClicker = true
        requestGuiltRows()
        installNoteWrap()
        P.Track(keysDown, WAIT_KEYS) -- a key held through the entrance is not a press (owner 2026-09-24: skipped replays)
        DP.SpaceSince, DP.SpaceHeld = nil, true -- a Space held through the entrance never counts as a hold either
    end
    if DP.ScoreboardUp() then
        DP.root:SetVisible(false)
        P.Track(keysDown, WAIT_KEYS)
        DP.SpaceSince, DP.SpaceHeld = nil, true -- a Space held through the scoreboard never counts as a hold
        return
    end
    DP.root:SetVisible(true)
    DP.victimAv:SetPlayer(me)
    local killerSid = findSteamID(DP.H2H and DP.H2H.killer) or findSteamID(DP.Inst)
    if killerSid then DP.killerAv:SetSteamID(killerSid) end
    DP.killerInit.Letter = string.upper(string.sub(DP.KillerName or "?", 1, 1))
    layout()
    local dx, dy = DP.chatDock:LocalToScreen(0, 0)
    P.ChatDock(dx, dy, DP.chatDock:GetWide(), DP.chatDock:GetTall())

    if DP.GuiltRow and DP.OpenedAt and not DP.GuiltDecided then
        DP.forgiveCard.Bar:SetFraction(1 - math.Clamp((RealTime() - DP.OpenedAt) / FORGIVE_WINDOW, 0, 1))
        local row = DP.GuiltRow
        -- Rebuild the four action labels only when the matched case row changes (avoid
        -- rebuilding small tables/strings every Think while the same row is shown).
        if row ~= DP.LastGuiltRow then
            DP.LastGuiltRow = row
            local labels = {}
            if row.canForgive then labels[#labels + 1] = {string.format("Forgive (+%.1f karma)", row.refundable or 0), "forgive"} end
            if row.respectEligible then labels[#labels + 1] = {"Give respect", "respect"} end
            labels[#labels + 1] = {(row.karma or 0) > 0 and "Keep penalty" or "Acknowledge", "keep"}
            if row.canReport then labels[#labels + 1] = {"Report abuse to staff", "report"} end
            for i, btn in ipairs(DP.forgiveCard.Buttons) do
                local spec = labels[i]
                btn:SetVisible(spec ~= nil)
                btn.Label = spec and spec[1] or nil
                if spec then btn.DoClick = function() sendGuiltAction(row, spec[2]) end end
            end
        end
    else
        DP.LastGuiltRow = nil
    end

    -- Letters typed into chat or the console must not skip, save, report or open the guilt prompt. Edge state keeps
    -- tracking while typing so a key held through the chat closing does not fire on release.
    if P.Typing() then
        P.Track(keysDown, WAIT_KEYS)
        DP.SpaceSince, DP.SpaceHeld = nil, true
        return
    end
    -- Canvas vocabulary: Space skips the current hit (Close on the verdict), holding Space skips everything;
    -- Q spectates (Replay on the verdict); V saves; G reports; F forgives; N turns killcams off for this player.
    if P.Edge(keysDown, KEY_SPACE) then if t.phase == "over" then P.Call("Skip") else P.Call("Next") end end
    if input.IsKeyDown(KEY_SPACE) then
        if DP.SpaceSince == nil and not DP.SpaceHeld then DP.SpaceSince = RealTime() end
        if DP.SpaceSince and not DP.SpaceHeld and RealTime() - DP.SpaceSince >= HOLD_SKIP then
            DP.SpaceHeld = true
            P.Call("Skip")
        end
    else
        DP.SpaceSince, DP.SpaceHeld = nil, nil
    end
    if P.Edge(keysDown, KEY_G) and DP.Inst and DP.Inst.reportable then P.Call("Report", t.index) end
    if P.Edge(keysDown, KEY_V) then P.Call("Save") end
    if P.Edge(keysDown, KEY_Q) then if t.phase == "over" then P.Call("Play") else P.Call("Skip") end end
    for n = 1, math.min(t.count or 0, 9) do
        if P.Edge(keysDown, HIT_KEYS[n]) then P.Call("Play", n) break end
    end
    if P.Edge(keysDown, KEY_F) then
        if DP.GuiltRow and DP.GuiltRow.canForgive and not DP.GuiltDecided then sendGuiltAction(DP.GuiltRow, "forgive") else requestGuiltRows() end
    end
    if P.Edge(keysDown, KEY_N_CODE) then
        -- zc_killcam_show is the killcam's own opt-out (Settings > Gameplay); the server's K.Wants honours it.
        RunConsoleCommand("zc_killcam_show", "0")
        DP.Note, DP.NoteUntil = "Killcams disabled for you  ·  Settings > Gameplay to turn them back on", RealTime() + 5
    end
end
hook.Add("Think", "GoobOS.DeathPanel.Think", refreshFrame)

P.Claim("death", function() return DP.Open == true end)

-- 1-9 (jump to a hit) are polled in refreshFrame with the other keys (HIT_KEYS). Drop a handler an older load registered.
if istable(P.KeyHandlers) then P.KeyHandlers["death.hit"] = nil end
