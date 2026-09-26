-- GoobOS Death Panel (step 5, canvas revamp 2026-09-25; UI cohesion U1 2026-09-26): fullscreen "you died" recap. Claims
-- the killcam's P3 seam (work/loader/killcam_revitalize/P3_SEAM.txt) while ZCGoobApps.Panels.Enabled() and the local
-- player is dead mid death-replay. Loads after kit.lua, panels.lua and deathbody.lua.
--
-- Layout (owner canvas claude.ai/artifact/PdDUK2yBacj3PkEFd3SspA, reworked for U1): ONE header line says how you died.
-- YOU on the left: your body with its organs tinted by the damage up to the timeline's scrub time (deathbody.lua), the
-- points of this life and the chat dock. The replay inset in the middle, the DAMAGE TIMELINE of the whole life under it
-- (every hit; scrub it, click a hit to replay it) and the head-to-head. The KILLER on the right: the cause of death from
-- the observer debrief (zc_observer), then forgiveness. One hint row in the footer; every fact is said once. The inset
-- draws its own three states (Loading replay / playing / KILLING BLOW verdict). Sizes are P.Unit() units via K.Scaler.
if not CLIENT then return end
local A = ZCGoobApps
if not A or not A.Kit then return end
local P = A.Panels
if not P then return end
local K, T = A.Kit, A.Theme
local DB = A.DeathBody

local DP = A.DeathPanel or {}
A.DeathPanel = DP
DP.Version = "20260926.deathpanel9"
-- Autorefresh reinstalls this file while the old panel lives on with the old painters (LESSONS.md): tear it down so the
-- next open builds it from this file's code.
if IsValid(DP.root) then DP.root:Remove() end
DP.root, DP.Open = nil, false
if DB and DB.Release then DB.Release() end

-- Roles each tag implies (attacker, victim), for the chips under the two names (tag vocabulary: zc_killcam/cl_life.lua).
local ROLES = {ivi = {"Innocent", "Innocent"}, tvt = {"Traitor", "Traitor"}, ivt = {"Innocent", "Traitor"}, tvi = {"Traitor", "Innocent"}}
local VERDICTS = {[1] = "HEADSHOT", [2] = "CHEST SHOT", [3] = "GUT SHOT", [4] = "ARM SHOT", [5] = "ARM SHOT", [6] = "LEG SHOT", [7] = "LEG SHOT"}
local FORGIVE_WINDOW = 5 -- the gamemode forgiveness window (zc_killcam/cl_life.lua)
local END_CARD_SECONDS = 8 -- P3_SEAM: the end card leaves by itself after 8 s
local HOLD_SKIP = 0.6 -- a Space held this long hands the screen back
local N_CONFIRM = 2 -- N turns killcams off only when pressed twice within this many seconds
-- The contributions disclaimer, as the observer debrief worded it (zc_observer/cl_observer.lua before U1).
local DISCLAIMER = "Harm is injury severity, not HP damage. A contribution does not establish the cause of death."
local KEY_N_CODE = rawget(_G, "KEY_N") or 24
-- 1-9 jump to that hit. Polled as raw keys like the rest: the killcam's own PlayerBindPress swallows every slot bind
-- during a life replay, and hook order decides whether a bind handler would ever see them (review 2026-09-26).
local HIT_KEYS = {}
for n = 1, 9 do HIT_KEYS[n] = KEY_1 + n - 1 end
local WAIT_KEYS = {KEY_SPACE, KEY_G, KEY_V, KEY_Q, KEY_F, KEY_S, KEY_LEFT, KEY_RIGHT, KEY_N_CODE, unpack(HIT_KEYS)}
-- The one hint row. The footer buttons carry their own keycaps (S Share, V Save, G Report, Q Spectate) and are the
-- clickable half of the row, so the row itself holds the keys that have no button. Trimmed from the end to fit.
local HINTS = {
    play = {{"Space", "Next"}, {"Hold Space", "Skip all"}, {"1-9", "Hit"}, {"N", "Killcams off"}},
    playForgive = {{"Space", "Next"}, {"Hold Space", "Skip all"}, {"1-9", "Hit"}, {"F", "Forgive"}, {"N", "Killcams off"}},
    over = {{"Space", "Close"}, {"1-9", "Hit"}, {"N", "Killcams off"}},
    overForgive = {{"Space", "Close"}, {"1-9", "Hit"}, {"F", "Forgive"}, {"N", "Killcams off"}},
}

-- One painter set for the whole panel; layout() sets S.U = P.Unit() once per pass.
local S = K.Scaler()
local u, text, fit, measure = S.u, S.text, S.fit, S.measure

local function weaponName(wep) return P.WeaponName(wep) end

local function findSteamID(tbl)
    if not istable(tbl) then return nil end
    local id = tbl.steamid64 or tbl.steamID64 or tbl.sid64 or tbl.SteamID64
    return isstring(id) and id or nil
end

local function num(v) return tonumber(v) or 0 end
local function fmtDmg(v)
    v = tonumber(v) or 0
    return v >= 10 and string.format("%d", math.floor(v + 0.5)) or string.format("%.1f", v)
end
-- Seconds before the death ("-4.2 s"). ASCII minus: hg_font's default face has no guaranteed U+2212.
local function before(span, t)
    local s = math.max(0, (span or 0) - (t or 0))
    return s < 0.05 and "0.0 s" or string.format("-%.1f s", s)
end

-- One hit group vocabulary (zc_killcam/cl_analysis.lua V.HitGroups / V.HitGroupBones: head, neck, chest, abdomen, left
-- arm, right arm, left leg, right leg, gear), capitalised for display. `bone` (an organ bone) wins when given.
local function hitGroupName(id, bone)
    local V = rawget(_G, "ZCKillcamView")
    if not istable(V) then return nil end
    local name = bone and istable(V.HitGroupBones) and V.HitGroupBones[bone] or nil
    if not name and id then
        if istable(V.HitGroups) then name = V.HitGroups[tonumber(id) or -1]
        elseif isfunction(V.HitGroupName) then name = V.HitGroupName(tonumber(id) or -1) end
    end
    if not isstring(name) or name == "" then return nil end
    return (string.gsub(name, "^%l", string.upper))
end

-- Footer and forgive-card buttons: the kit's one button, free-positioned and sized through the panel's scaler.
-- `label` may be a function() -> string (live state: Saved, Reported); btn.Label overrides it (forgive rows).
local function kitButton(parent, label, kind, enabledFn, click, key)
    return K.Button(parent, {label = label, kind = kind, enabled = enabledFn, click = click, key = key, scaler = S, dock = false, size = 13})
end

-- Initials avatar: used for the killer block when no SteamID is available anywhere on h2h/inst.
local function miniAvatar(parent)
    local p = K.Panel(parent)
    p.Letter = "?"
    p.Paint = function(s, w, h)
        draw.RoundedBox(T.radius.card, 0, 0, w, h, T.card)
        surface.SetDrawColor(T.main)
        surface.DrawOutlinedRect(0, 0, w, h, 2)
        text(s.Letter, math.floor(w / S.U * 0.36), 700, w / 2, h / 2, T.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    return p
end

local function note(str, color, seconds)
    DP.Note, DP.NoteColor, DP.NoteUntil = str, color, RealTime() + (seconds or 4)
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
    -- a reply already on its way when the action left was built before the server applied it: only the reply to the
    -- 0.3 s follow-up request may reconcile (final review 2026-09-26)
    if RealTime() - (sent.at or 0) < 0.3 then return end -- the follow-up request leaves at 0.3 s; a stale reply on a >300 ms ping can still slip past
    DP.GuiltSent = nil
    for _, row in ipairs(DP.GuiltRows) do
        if row.caseid == sent.caseid and row.steamid64 == sent.steamid64 then
            local done = (sent.action == "report" and row.reported == true) or (sent.action ~= "report" and row.decided and row.decision == sent.action)
            if not done and DP.GuiltDecided == sent.action then
                DP.GuiltDecided = nil
                note("That didn't go through. Try again, or use the guilt menu", T.red, 5)
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
            if DP.WantGuilt or (DP.GuiltSent and RealTime() < (DP.GuiltQuietUntil or 0)) then
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
    DP.GuiltSent = {caseid = row.caseid, steamid64 = row.steamid64, action = action, at = RealTime()}
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
        if isstring(str) then note(str, T.green, 4) end
        if DP.NoteOriginal then return DP.NoteOriginal(str) end
    end
    V.Note = DP.NoteWrap
end

-- The observer debrief (zc_observer): pushed by the server at the death; asked for again when the panel opens without
-- one (the reply reuses ZCObserverSnapshot). ZCObserver.Snapshot is this life's, cleared on respawn.
local function debrief()
    local O = rawget(_G, "ZCObserver")
    return istable(O) and istable(O.Snapshot) and O.Snapshot or nil, istable(O) and O.Revision or 0
end
local function askDebrief()
    local O = rawget(_G, "ZCObserver")
    if istable(O) and not O.Snapshot and isfunction(O.Request) then O.Request() end
end

----------------------------------------------------------------------------------------------
-- Derived facts shared by the header, the inset verdict and the cards. The damage of the life (DP.Damage) comes from
-- deathbody.lua's DB.Damage over the life sequence's clips; its last event is the fatal hit.
----------------------------------------------------------------------------------------------
local function killerLabel() return DP.KillerName or "Someone" end
local function fatalHit()
    local d = DP.Damage
    return d and d.events[#d.events] or nil
end

-- The engagement: from the killer's first hit on you to your death (the earliest instance's `ago`).
local function engagementSeconds()
    local instances = DP.Seq and DP.Seq.instances
    if not istable(instances) or #instances == 0 then return nil end
    local most = 0
    for _, it in ipairs(instances) do if istable(it) then most = math.max(most, num(it.ago)) end end
    return most
end

-- The life's length in seconds: the ledger's time alive, never shorter than the engagement.
local function lifeSpan()
    local life = DP.H2H and DP.H2H.victim and DP.H2H.victim.life
    return math.max(num(life and life.alive), num(DP.H2H and DP.H2H.span), engagementSeconds() or 0, 1)
end

-- The fatal hit's hit group: the ledger's organ name, else the region the clip's last hit entered, else the hit group.
local function hitLabel()
    local how = DP.H2H and DP.H2H.how
    if how and isstring(how.organ) and how.organ ~= "" then return how.organ end
    local last = fatalHit()
    local first = last and last.organs[1]
    local name = first and not first.entry.region and hitGroupName(nil, first.entry.bone)
    if name then return name end
    local group = how and tonumber(how.hitgroup)
    if (not group or group == 0) and last then group = last.hitgroup end
    return group and hitGroupName(group) or nil
end

-- The verdict word only: the most damaged organ when the clips carry organs, else the ledger's organ, else the hit group.
local function verdictWord()
    local d = DP.Damage
    local top = d and d.order[1]
    if top and not top.region then return string.upper(top.label) end
    local how = DP.H2H and DP.H2H.how
    if how and isstring(how.organ) and how.organ ~= "" then return string.upper(how.organ) end
    local group = how and tonumber(how.hitgroup)
    local last = fatalHit()
    if (not group or group == 0) and last then group = last.hitgroup end
    return VERDICTS[group or 0] or "KILLED"
end

-- Distance: the ledger / instance field when one ships (metres), else the fatal bullet's recorded range.
local function distanceLabel()
    local how = DP.H2H and DP.H2H.how
    local last = fatalHit()
    local d = tonumber(how and how.dist) or tonumber(DP.Inst and DP.Inst.dist) or (last and last.range)
    return d and string.format("%d m", math.floor(d + 0.5)) or nil
end

local function fatalWeapon()
    local how = DP.H2H and DP.H2H.how
    local last = fatalHit()
    return (how and isstring(how.weapon) and how.weapon ~= "" and how.weapon) or (last and last.weapon) or (DP.Inst and DP.Inst.wep)
end

-- " · WEAPON · HITGROUP · 12 m · 3.4 s": the rest of the header line after "KILLER killed you".
local function buildHowLine()
    local parts = {weaponName(fatalWeapon())}
    local hit = hitLabel()
    if hit then parts[#parts + 1] = hit end
    local dist = distanceLabel()
    if dist then parts[#parts + 1] = dist end
    local eng = engagementSeconds()
    if eng then parts[#parts + 1] = string.format("%.1f s", eng) end
    return " · " .. table.concat(parts, " · ")
end

-- The timeline marks: every hit of the life (not one per instance), the ledger's additive per-life log `h2h.timeline`
-- = {{t = seconds into the life, kind = "kill"|"heal"|"dealt"|"taken"|"other", text}} when it ships one, and the death.
-- Each carries its one tooltip line, built here, never per frame.
local function buildTimeline()
    local span = lifeSpan()
    local damage = DB and DB.Damage and DB.Damage(DP.Seq, span) or nil
    local marks, peak, attackers = {}, 1, {}
    local function add(m) m.n = #marks marks[#marks + 1] = m end
    if damage and #damage.events > 0 then
        for _, ev in ipairs(damage.events) do
            local names, keys = {}, {}
            for i, share in ipairs(ev.organs) do
                keys[share.entry.key] = true
                if i <= 3 then names[i] = share.entry.label end
            end
            if #ev.organs > 3 then names[#names + 1] = "+" .. (#ev.organs - 3) end
            local parts = {before(span, ev.t), ev.attacker or killerLabel(), weaponName(ev.weapon), fmtDmg(ev.dmg) .. " dmg"}
            if #names > 0 then parts[#parts + 1] = table.concat(names, ", ") end
            add({t = ev.t, kind = "hit", inst = ev.inst, dmg = ev.dmg, keys = keys, text = table.concat(parts, " · ")})
            peak = math.max(peak, ev.dmg)
            attackers[ev.attacker or "?"] = true
        end
    else
        -- no hit events in the clips: one mark per instance, where it started
        for i, it in ipairs(DP.Seq and DP.Seq.instances or {}) do
            if istable(it) then
                local t = math.Clamp(span - num(it.ago), 0, span)
                add({t = t, kind = "hit", inst = i, dmg = num(it.dmg), text = before(span, t) .. " · " .. tostring(it.attacker or "?") .. " · "
                    .. weaponName(it.wep) .. " · " .. fmtDmg(it.dmg) .. " dmg"})
                peak = math.max(peak, num(it.dmg))
                attackers[it.attacker or "?"] = true
            end
        end
    end
    -- 2026-09-26: zc_killcam/sv_timeline.lua ships the log (owner: "transparent karma ledger, per-life, per-player"),
    -- adding kinds "bad" (counted against you), "good", "flag" (counts only if a fight follows) and "death", plus
    -- `mine` (you did it) and `tag` (whether it counted, and why). The logged lines are also listed in words below.
    local log = DP.H2H and DP.H2H.timeline
    local said, logged = false, {}
    if istable(log) then
        for _, e in ipairs(log) do
            if istable(e) and isnumber(e.t) then
                local t = math.Clamp(e.t, 0, span)
                local kind = isstring(e.kind) and e.kind or "other"
                local tag = isstring(e.tag) and e.tag or nil
                local m = {t = t, kind = kind, mine = e.mine, tag = tag, line = tostring(e.text or e.kind or ""),
                    text = before(span, t) .. " · " .. tostring(e.text or e.kind or "") .. (tag and (" · " .. tag) or "")}
                add(m)
                logged[#logged + 1] = m
                if kind == "death" then said = true end
            end
        end
    end
    if not said then add({t = span, kind = "death", text = "0.0 s · Death"}) end
    table.sort(logged, function(a, b) return a.t < b.t end)
    DP.TimelineLog = logged
    table.sort(marks, function(a, b)
        if a.t ~= b.t then return a.t < b.t end
        if (a.kind == "death") ~= (b.kind == "death") then return b.kind == "death" end
        return a.n < b.n
    end)
    local many = 0
    for _ in pairs(attackers) do many = many + 1 end
    return marks, span, damage, peak, many > 1
end

local function markColor(kind)
    if kind == "hit" or kind == "taken" or kind == "bad" then return T.kill end
    if kind == "death" then return T.death end
    if kind == "kill" then return T.gold end
    if kind == "heal" or kind == "dealt" or kind == "good" then return T.green end
    return T.muted
end

-- CAUSE OF DEATH (the observer debrief, absorbed): one cause line, final vitals, the top three harm contributions.
local function buildCause()
    if not (DB and DB.Cause) then return nil end
    local snap = debrief()
    local me = LocalPlayer()
    local line, kind = DB.Cause(snap, DP.Damage, DP.H2H and DP.H2H.how, {sid = IsValid(me) and me:SteamID64() or nil})
    if not snap and kind == "other" then return nil end
    return {line = line, vitals = DB.Vitals(snap), parts = (DB.Contributions(snap, 3))}
end

-- Scrubbing: a time the player chose holds while they drag and until the replay moves to another hit; otherwise the
-- scrub follows the replay's own time inside the playing hit, and rests on the death between hits and on the verdict.
function DP.SetScrub(t)
    DP.ScrubManual = t
    DP.ScrubIndex = DP.T and DP.T.index
end
local function scrubTime(t)
    local span = DP.TimelineSpan
    if not span then return nil end
    if DP.ScrubManual and (DP.Dragging or DP.ScrubIndex == t.index) then return math.Clamp(DP.ScrubManual, 0, span) end
    DP.ScrubManual = nil
    if t.phase == "playing" and istable(t.inst) and isnumber(t.cs) then
        return math.Clamp(span - (num(t.inst.ago) - t.cs / 100), 0, span)
    end
    return span
end
local function stepMark(dir)
    local marks, span = DP.Marks, DP.TimelineSpan
    if not istable(marks) or #marks == 0 or not span then return end
    local at = DP.ScrubT or span
    if dir > 0 then
        for _, m in ipairs(marks) do if m.t > at + 0.01 then DP.SetScrub(m.t) return end end
    else
        for i = #marks, 1, -1 do if marks[i].t < at - 0.01 then DP.SetScrub(marks[i].t) return end end
    end
end

----------------------------------------------------------------------------------------------
-- Cards.
----------------------------------------------------------------------------------------------
local function cardHead(title, x, y, w, right, rightColor)
    text(title, 10, 700, x, y, T.muted)
    if right then text(right, 10, 700, x + w, y, rightColor or T.gold, TEXT_ALIGN_RIGHT) end
end

-- label above value
local function cell(label, value, x, y, color, big)
    text(label, 9, 600, x, y, T.muted)
    text(value, big and 18 or 14, 700, x, y + u(12), color or T.text)
end

local function buildForgiveCard(parent)
    local card = K.Panel(parent)
    card.Bar = K.Bar(card, 1, T.gold)
    card.Buttons = {}
    -- labels and clicks are assigned per case row in refreshFrame()
    for i = 1, 4 do card.Buttons[i] = kitButton(card, "", i == 1 and "primary" or (i <= 2 and "secondary" or "ghost")) end
    card.Paint = function(_, w, h)
        K.Card(0, 0, w, h, T.cardGlass, K.Alpha(T.gold, 140))
        local row = DP.GuiltRow
        if DP.GuiltDecided then
            local msg = DP.GuiltDecided == "forgive" and "Forgiven" or DP.GuiltDecided == "respect" and "Respect given" or DP.GuiltDecided == "report" and "Reported to staff" or "Penalty kept"
            text(msg, 13, 700, u(12), h / 2, T.green, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            return
        end
        if not row then return end
        text(fit("Forgive " .. killerLabel() .. "?", 15, 700, w - u(80)), 15, 700, u(12), u(10), T.text)
        local left = math.max(0, FORGIVE_WINDOW - (RealTime() - (DP.OpenedAt or RealTime())))
        text(string.format("%.1f", left), 15, 800, w - u(12), u(10), T.gold, TEXT_ALIGN_RIGHT)
        if (row.karma or 0) > 0 then
            local penalty = string.format("%s's penalty: -%.0f karma unless forgiven", killerLabel(), row.karma)
            text(fit(penalty, 10, 500, w - u(24)), 10, 500, u(12), h - u(18), T.muted)
        end
    end
    return card
end

local function buildCauseCard(parent)
    local card = K.Panel(parent)
    card.Paint = function(s, w, h)
        local c = DP.Cause
        if not c then return end
        K.Card(0, 0, w, h, T.cardGlass, K.Alpha(T.edge, 180))
        cardHead("CAUSE OF DEATH", u(12), u(10), w - u(24))
        text(fit(c.line, 16, 700, w - u(24)), 16, 700, u(12), u(26), T.text)
        local y = u(54)
        local v = c.vitals
        if v then
            local colW = (w - u(24)) / 3
            cell("BLOOD", v.blood and string.format("%d mL", math.floor(v.blood + 0.5)) or "—", u(12), y, v.blood and v.blood < 2900 and T.red or nil)
            cell("PULSE", v.pulse and string.format("%d bpm", math.floor(v.pulse + 0.5)) or "—", u(12) + colW, y)
            cell("PAIN", v.pain and string.format("%d", math.floor(v.pain + 0.5)) or "—", u(12) + colW * 2, y)
            y = y + u(40)
        end
        if s.Full and #c.parts > 0 then
            text("HARM CONTRIBUTIONS", 9, 700, u(12), y, T.muted)
            y = y + u(16)
            for _, part in ipairs(c.parts) do
                text(fit(part.name, 12, 600, w - u(72)), 12, 600, u(12), y, T.text)
                text(math.floor(part.share * 100 + 0.5) .. "%", 12, 700, w - u(12), y, T.gold, TEXT_ALIGN_RIGHT)
                draw.RoundedBox(2, u(12), y + u(17), w - u(24), u(3), K.Alpha(T.ink, 235))
                draw.RoundedBox(2, u(12), y + u(17), math.max(u(3), (w - u(24)) * part.share), u(3), T.accent)
                y = y + u(26)
            end
            local small = S.font(9, 500)
            for i, line in ipairs(K.Wrap(DISCLAIMER, small, w - u(24), 2)) do
                draw.SimpleText(line, small, u(12), y + (i - 1) * u(12), T.muted)
            end
        end
    end
    -- Height the card needs; full = with the contributions and the disclaimer.
    function card:Needed(full)
        local c = DP.Cause
        if not c then return 0 end
        local h = u(54) + (c.vitals and u(40) or 0)
        if full and #c.parts > 0 then h = h + u(16) + #c.parts * u(26) + u(24) end
        return h + u(6)
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

-- YOUR BODY: the translucent playermodel with its organs tinted by the damage up to the scrub time (deathbody.lua), and
-- the five most damaged organs as bars. The organs of the hit under the mouse on the timeline pulse and are lit here.
local function buildBodyCard(parent)
    local card = K.Panel(parent)
    card.top = {}
    card.Paint = function(s, w, h)
        K.Card(0, 0, w, h, T.cardGlass, K.Alpha(T.edge, 180))
        local damage, span = DP.Damage, DP.TimelineSpan
        if not damage or not span then return end
        local at = DP.ScrubT or span
        cardHead("YOUR BODY", u(12), u(10), w - u(24))
        local bw = math.floor((w - u(24)) * 0.5)
        local drawn = DB.Paint(s, u(6), u(26), bw, h - u(32), damage, DP.HoverKeys, at)
        local lx = drawn and (u(6) + bw + u(10)) or u(12)
        local lw = w - lx - u(12)
        local peak = damage.peak > 0 and damage.peak or 1
        local y = u(34)
        for _, row in ipairs(DB.Top(damage, at, 5, s.top)) do
            local e = row.entry
            local hot = DP.HoverKeys and DP.HoverKeys[e.key]
            text(fit(e.label, 12, 600, lw - u(44)), 12, 600, lx, y, hot and T.gold or T.text)
            text(fmtDmg(row.amount), 12, 700, lx + lw, y, hot and T.gold or T.muted, TEXT_ALIGN_RIGHT)
            draw.RoundedBox(2, lx, y + u(18), lw, u(4), K.Alpha(T.ink, 235))
            draw.RoundedBox(2, lx, y + u(18), math.max(u(4), lw * math.Clamp(row.amount / peak, 0, 1)), u(4), T.kill)
            y = y + u(32)
        end
    end
    return card
end

-- DAMAGE TIMELINE: the whole life on one track. Hits hang under the line (taller = more damage), the ledger's events sit
-- above it, the death closes it. Hover a mark for its one tooltip; click a hit to replay it; click or drag anywhere
-- else to scrub; the left of the scrub head is what the body card shows.
local TL_H = 98
-- How many logged karma lines the card lists under the axis (the newest; the Karma app - !karma - has them all).
local TIMELINE_ROWS = 5
local function timelineRows() return istable(DP.TimelineLog) and math.min(#DP.TimelineLog, TIMELINE_ROWS) or 0 end
local function timelineH()
    local rows = timelineRows()
    return u(TL_H) + (rows > 0 and (rows * u(17) + u(22)) or 0)
end
local function buildTimelineCard(parent)
    local card = K.Panel(parent)
    card:SetMouseInputEnabled(true)
    local function trackOf(w) return u(16), w - u(16) end
    local function timeAt(s, mx)
        local x0, x1 = trackOf(s:GetWide())
        return math.Clamp((mx - x0) / math.max(1, x1 - x0), 0, 1) * (DP.TimelineSpan or 1)
    end
    card.Paint = function(s, w, h)
        K.Card(0, 0, w, h, T.cardGlass, K.Alpha(T.edge, 180))
        s.hover, DP.HoverKeys = nil, nil
        local marks, span = DP.Marks, DP.TimelineSpan
        if not istable(marks) or #marks == 0 or not span then return end
        local at = DP.ScrubT or span
        cardHead("DAMAGE TIMELINE", u(12), u(10), w - u(24), "at " .. before(span, at), T.text)
        local x0, x1 = trackOf(w)
        local tw, ry = x1 - x0, u(58)
        local hx = x0 + tw * math.Clamp(at / span, 0, 1)
        draw.RoundedBox(1, x0, ry - 1, tw, u(2), K.Alpha(T.white, 30))
        draw.RoundedBox(1, x0, ry - 1, hx - x0, u(2), K.Alpha(T.kill, 160))
        text(K.Clock(0), 9, 500, x0, ry + u(24), T.muted)
        text(K.Clock(span), 9, 500, x1, ry + u(24), T.muted, TEXT_ALIGN_RIGHT)
        local mx, my = s:CursorPos()
        local inside = s:IsHovered() and my >= u(30)
        local playing = DP.T and DP.T.phase == "playing" and DP.T.index
        local best, bestD
        for _, m in ipairs(marks) do
            local ex = x0 + tw * math.Clamp(m.t / span, 0, 1)
            m.x = ex
            if m.kind == "death" then
                draw.RoundedBox(1, ex - u(1), ry - u(14), u(3), u(28), T.death)
            elseif m.kind == "hit" then
                local tall = u(6) + math.floor(u(12) * math.Clamp(m.dmg / (DP.MarkPeak or 1), 0, 1))
                local lit = m.t <= at + 0.001
                draw.RoundedBox(1, ex - 1, ry + u(2), u(2), tall, lit and T.kill or K.Alpha(T.kill, 90))
                if playing and m.inst == playing then draw.RoundedBox(1, ex - 1, ry + u(4) + tall, u(2), u(2), T.gold) end
            elseif m.mine == false then
                draw.RoundedBox(1, ex - 1, ry + u(2), u(2), u(10), markColor(m.kind))
            else
                draw.RoundedBox(1, ex - 1, ry - u(12), u(2), u(10), markColor(m.kind))
            end
            if inside then
                local d = math.abs(mx - ex)
                if d <= u(6) and (not bestD or d < bestD) then best, bestD = m, d end
            end
        end
        draw.RoundedBox(1, hx - 1, ry - u(16), u(2), u(34), T.text)
        draw.RoundedBox(u(4), hx - u(4), ry - u(20), u(8), u(8), T.text)
        s.hover = best
        if best then
            DP.HoverKeys = best.keys
            local bw = measure(best.text, 11, 600) + u(16)
            local bx = math.Clamp(best.x - bw / 2, u(8), w - bw - u(8))
            draw.RoundedBox(T.radius.chip, bx, u(26), bw, u(20), K.Alpha(T.ink, 240))
            text(best.text, 11, 600, bx + u(8), u(36), markColor(best.kind), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
        -- The logged karma lines in words: time, what happened, and whether it counted (the tag, right-aligned).
        local log = DP.TimelineLog
        if istable(log) and #log > 0 then
            local first = math.max(1, #log - TIMELINE_ROWS + 1)
            local y, tagW = u(TL_H) - u(4), u(190)
            for i = first, #log do
                local e = log[i]
                local color = markColor(e.kind)
                draw.RoundedBox(1, x0, y + u(4), u(3), u(8), color)
                text(K.Clock(e.t), 10, 600, x0 + u(8), y, T.muted)
                text(fit(e.line, 11, 600, x1 - x0 - tagW - u(52)), 11, 600, x0 + u(44), y, T.text)
                if e.tag then text(fit(e.tag, 10, 500, tagW), 10, 500, x1, y + u(1), K.Alpha(color, 220), TEXT_ALIGN_RIGHT) end
                y = y + u(17)
            end
            local foot = DP.H2H and DP.H2H.held and "Verdicts that would reveal a role are shown when the round ends   ·   !karma for every life"
                or ((#log > TIMELINE_ROWS and (#log - TIMELINE_ROWS) .. " earlier   ·   " or "") .. "!karma for every life")
            text(foot, 9, 500, w / 2, h - u(12), K.Alpha(T.muted, 160), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    end
    card.OnMousePressed = function(s, code)
        if code ~= MOUSE_LEFT then return end
        local mx = s:CursorPos()
        s.press, s.dragging = {x = mx, mark = s.hover}, false
        s:MouseCapture(true)
    end
    card.OnMouseReleased = function(s, code)
        if code ~= MOUSE_LEFT or not s.press then return end
        s:MouseCapture(false)
        local press, dragged = s.press, s.dragging
        s.press, s.dragging, DP.Dragging = nil, false, false
        if dragged then return end
        local m = press.mark
        if m and m.inst then
            P.Call("Play", m.inst)
            DP.SetScrub(nil)
        elseif m then
            DP.SetScrub(m.t)
        else
            DP.SetScrub(timeAt(s, press.x))
        end
    end
    card.Think = function(s)
        if not s.press then return end
        if not input.IsMouseDown(MOUSE_LEFT) then s:OnMouseReleased(MOUSE_LEFT) return end -- a release lost to another panel
        local mx = s:CursorPos()
        if not s.dragging and math.abs(mx - s.press.x) > u(4) then s.dragging = true end
        if s.dragging then
            DP.Dragging = true
            DP.SetScrub(timeAt(s, mx))
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
-- value is lit. Tabs switch This life / Lifetime (lifetime only when the ledger sent it). What the two of you traded
-- (h2h.traded) is the one damage row - said here and nowhere else; the life totals stand in only when it is missing.
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
        local killerLife = DP.H2H.killer and DP.H2H.killer.life
        local lifetime = DP.H2H.lifetime
        text("YOU", 10, 700, u(16), u(9), T.green, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        text(fit(string.upper(killerLabel()), 10, 700, u(160)), 10, 700, w - u(16), u(9), T.red, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        local y, limit = u(34), h - u(24)
        local function row(label, you, them, youNum, themNum)
            if y <= limit then y = drawMirrorRow(y, w, label, you, them, youNum, themNum) end
        end
        if not (card.Tabs.Selected == 2 and lifetime) then
            local traded = DP.H2H.traded
            local kl = killerLife or {}
            local function v(k) return killerLife and kl[k] ~= nil and num(kl[k]) or nil end
            local function shown(k) return killerLife and num(kl[k]) or "—" end
            if istable(traded) then
                local vk, kv = traded.victimToKiller or {}, traded.killerToVictim or {}
                row("Damage traded", fmtDmg(vk.dmg), fmtDmg(kv.dmg), num(vk.dmg), num(kv.dmg))
                row("Hits traded", num(vk.hits), num(kv.hits), num(vk.hits), num(kv.hits))
            end
            row("Kills", num(life.kills), shown("kills"), num(life.kills), v("kills"))
            if not istable(traded) then -- the life totals stand in for what the two of you traded
                row("Damage dealt", num(life.dealt), shown("dealt"), num(life.dealt), v("dealt"))
                row("Damage taken", num(life.taken), shown("taken"), num(life.taken), v("taken"))
                row("Hits landed", num(life.hits), shown("hits"), num(life.hits), v("hits"))
            end
            row("Time alive", K.Clock(life.alive) or "—", (killerLife and K.Clock(kl.alive)) or "—", num(life.alive), v("alive"))
        else
            local you, them = lifetime.victim or {}, lifetime.killer or {}
            local function v(k) return them[k] ~= nil and num(them[k]) or nil end
            row("Kills", num(you.kills), them.kills and num(them.kills) or "—", num(you.kills), v("kills"))
            row("Deaths", num(you.deaths), them.deaths and num(them.deaths) or "—", num(you.deaths), v("deaths"))
            row("K/D", kd(you.kills, you.deaths), them.kills and kd(them.kills, them.deaths) or "—", tonumber(kd(you.kills, you.deaths)), them.kills and tonumber(kd(them.kills, them.deaths)) or nil)
            row("Damage", num(you.damage), them.damage and num(them.damage) or "—", num(you.damage), v("damage"))
            row("Rounds", num(you.rounds), them.rounds and num(them.rounds) or "—", num(you.rounds), v("rounds"))
        end
    end
    return card
end

----------------------------------------------------------------------------------------------
-- The inset: the replay itself and its three states (canvas boards Inset_Incoming / Inset_Playing / Inset_Verdict).
----------------------------------------------------------------------------------------------
-- Hit-stepper pips: one play function per pip index, and hit tables reused between frames.
local pipPlay = {}
local function pipPlayFn(i)
    local fn = pipPlay[i]
    if not fn then fn = function() P.Call("Play", i) end pipPlay[i] = fn end
    return fn
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
    K.Card(0, 0, w, h, T.inset)
    local drawn = phase == "playing" and P.RenderInset(s, 0, 0, w, h)
    if phase == "waiting" or (phase == "playing" and not drawn) then
        -- Loading: the live spectator camera renders under the panel here (P3_SEAM) - dim it, letterbox it and show the
        -- hit rail already complete (the sequence is known on arrival). Never a black frame.
        draw.RoundedBox(T.radius.card, 0, 0, w, h, T.dim)
        local bar = u(40)
        draw.RoundedBoxEx(T.radius.card, 0, 0, w, bar, T.ink, true, true, false, false)
        draw.RoundedBoxEx(T.radius.card, 0, h - bar, w, bar, T.ink, false, false, true, true)
        S.chip("SCENE OF DEATH", u(12), u(10))
        local pulse = K.Reduced() and 1 or (0.7 + 0.3 * math.abs(math.sin(RealTime() * 2.2)))
        text("Loading replay", 22, 700, u(20), h - bar - u(40), K.Alpha(T.text, 255 * pulse))
        if t and (t.count or 0) > 0 then hitRail(s, u(16), h - u(30), w - u(32), t) end
        return
    end
    if phase == "over" or phase == "leaving" then
        -- KILLING BLOW verdict (canvas Inset_Verdict): the last frame stays under a scrim, the verdict word headlines it.
        draw.RoundedBox(T.radius.card, 0, 0, w, h, T.dim)
        local cy = h / 2 - u(12)
        text("KILLING BLOW", 11, 700, w / 2, cy - u(34), T.gold, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        text(fit(verdictWord(), 40, 800, w - u(40)), 40, 800, w / 2, cy, T.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        local left = math.Clamp(1 - (RealTime() - (DP.OverAt or RealTime())) / END_CARD_SECONDS, 0, 1)
        text("Returning to spectating", 10, 500, u(16), h - u(30), T.muted)
        text(K.Clock(math.ceil(left * END_CARD_SECONDS)), 10, 600, w - u(16), h - u(30), T.text, TEXT_ALIGN_RIGHT)
        draw.RoundedBox(2, u(16), h - u(16), w - u(32), u(4), K.Alpha(T.white, 40))
        draw.RoundedBox(2, u(16), h - u(16), (w - u(32)) * left, u(4), T.gold)
        return
    end
    if not drawn or not t then return end
    -- chips over the frame: what you are watching (whose hits, when more than one player hit you) and the rate
    local cx = u(12)
    cx = cx + S.chip("ATTACKER VIEW", cx, u(10), T.white, K.Alpha(T.main, 220)) + u(6)
    if DP.ManyAttackers and t.inst and t.inst.attacker then
        S.chip(fit(weaponName(t.inst.wep) .. " · " .. tostring(t.inst.attacker), 10, 700, w * 0.45), cx, u(10))
    end
    if t.rate and t.rate < 0.99 then S.chip(string.format("%.2gx", t.rate), w - u(12), u(10), T.accent, nil, TEXT_ALIGN_RIGHT) end
    -- the hit rail, then the caption line under it
    hitRail(s, u(16), h - u(40), w - u(32), t)
    text("Hit " .. (t.index or 1) .. " of " .. (t.count or 1), 11, 600, u(16), h - u(20), T.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    if t.cs and t.first and t.last and t.last > t.first then
        text(K.Clock((t.cs - t.first) / 100) .. " / " .. K.Clock((t.last - t.first) / 100), 11, 500, w - u(16), h - u(20), T.muted, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    end
end

----------------------------------------------------------------------------------------------
-- Panel construction (built once, lazily; torn down and rebuilt on re-include per LESSONS.md).
----------------------------------------------------------------------------------------------
local function roleChip(role, x, y, align)
    if not role then return end
    local tw = measure(string.upper(role), 9, 700) + u(12)
    local bx = align == TEXT_ALIGN_RIGHT and x - tw or x
    draw.RoundedBox(T.radius.chip, bx, y, tw, u(16), K.Alpha(T.ink, 220))
    text(string.upper(role), 9, 700, bx + tw / 2, y + u(8), role == "Traitor" and T.red or T.green, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

-- Sharing the life (UI cohesion U2): the share sheet is ZCGoobApps.Share.Open (zc_goobos/share.lua).
local function shareLife()
    local Sh = A.Share
    local id = DP.Seq and DP.Seq.id or (DP.T and DP.T.id)
    if not (istable(Sh) and isfunction(Sh.Open)) then note("Sharing is not available yet", T.muted, 4) return end
    local ok = pcall(Sh.Open, {kind = "life", seq = id, title = killerLabel() .. " killed you · " .. weaponName(fatalWeapon())})
    if not ok then note("Sharing is not available yet", T.muted, 4) end
end

local shownHints = {}
local function fitHints(list, limit)
    for n = #list, 1, -1 do
        for i = 1, n do shownHints[i] = list[i] end
        for i = #shownHints, n + 1, -1 do shownHints[i] = nil end
        if S.hintWidth(shownHints) <= limit then return shownHints end
    end
    for i = #shownHints, 1, -1 do shownHints[i] = nil end
    return shownHints
end

local function buildPanel()
    local root = K.Panel(nil)
    -- A top-level panel is painted by the VGUI pass regardless of what the killcam's RenderScene returns (a
    -- HUD-parented one vanished the moment playback began, 2026-09-24).
    root:SetDrawOnTop(true)
    root.Paint = function() end

    local card = K.Panel(root)
    card.Paint = function(_, w, h) K.Card(0, 0, w, h, T.glass, K.Alpha(T.edge, 220)) end

    -- HEADER: the round caption, then ONE line - "KILLER killed you · WEAPON · HITGROUP · 12 m · 3.4 s"; the BETA chip
    -- and the panel's one-line replies on the right.
    local header = K.Panel(card)
    header.Paint = function(_, w, h)
        local zbT = rawget(_G, "zb")
        local parts = {"YOU DIED"}
        if zbT and zbT.CROUND then parts[#parts + 1] = string.upper(tostring(zbT.CROUND)) end
        if zbT and tonumber(zbT.Roundscount) then parts[#parts + 1] = "ROUND " .. tonumber(zbT.Roundscount) end
        text(table.concat(parts, " · "), 11, 700, 0, 0, T.red)
        S.chip("BETA", w, 0, T.text, nil, TEXT_ALIGN_RIGHT)
        local noteOn = DP.Note and RealTime() < (DP.NoteUntil or 0)
        local reserve = u(24) + (noteOn and measure(DP.Note, 12, 600) or 0)
        local room = w - reserve
        local base = h - u(2)
        local head = fit(killerLabel() .. " killed you", 34, 800, room)
        text(head, 34, 800, 0, base, T.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
        local hw = measure(head, 34, 800)
        if DP.HowLine and room - hw > u(40) then
            text(fit(DP.HowLine, 18, 500, room - hw), 18, 500, hw, base - u(3), T.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
        end
        if noteOn then text(DP.Note, 12, 600, w, base - u(3), DP.NoteColor or T.green, TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM) end
    end

    -- YOU / KILLER blocks: avatar, name, role chip. The killer's is right-aligned.
    local youBlock, killerBlock = K.Panel(card), K.Panel(card)
    local victimAv = K.Avatar(youBlock, 64)
    local killerAv = K.Avatar(killerBlock, 64)
    local killerInit = miniAvatar(killerBlock)
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
        K.Card(0, 0, w, h, K.Alpha(T.ink, 150), K.Alpha(T.edge, 120))
        text("CHAT", 10, 700, u(12), u(8), T.muted)
    end

    local pointsCard = buildPointsCard(body)
    local bodyCard = buildBodyCard(body)
    local tradeCard = buildTimelineCard(body) -- the damage timeline (the name is kept from the "damage traded" card)
    local compareCard = buildCompareCard(body)
    local causeCard = buildCauseCard(body)
    local forgiveCard = buildForgiveCard(body)

    -- FOOTER: the one hint row on the left, the four buttons (its clickable half, each with its keycap) on the right.
    local keyRow = K.Panel(card)
    keyRow.Paint = function(_, w, h)
        surface.SetDrawColor(T.hair)
        surface.DrawRect(0, 0, w, 1)
        local phase = DP.T and DP.T.phase
        local over = phase == "over" or phase == "leaving"
        local forgive = DP.GuiltRow ~= nil and DP.GuiltRow.canForgive and not DP.GuiltDecided and IsValid(DP.forgiveCard) and DP.forgiveCard:IsVisible()
        local list = over and (forgive and HINTS.overForgive or HINTS.over) or (forgive and HINTS.playForgive or HINTS.play)
        local limit = (IsValid(DP.shareBtn) and DP.shareBtn:GetX() or w) - u(20)
        S.hints(fitHints(list, limit), 0, math.floor(h / 2 - u(10)))
    end
    local reported = function() return DP.T and DP.T.reported and DP.T.index and DP.T.reported[DP.T.index] end
    local shareBtn = kitButton(keyRow, "Share", "secondary", function() return DP.T ~= nil and DP.T.id ~= nil end, shareLife, "S")
    local saveBtn = kitButton(keyRow, function() return (DP.T and DP.T.saved) and "Saved" or "Save replay" end, "primary",
        function() return not (DP.T and DP.T.saved) end, function() P.Call("Save") end, "V")
    local reportBtn = kitButton(keyRow, function() return reported() and "Reported" or "Report" end, "secondary",
        function() return DP.Inst ~= nil and DP.Inst.reportable == true and not reported() end,
        function() P.Call("Report", DP.T and DP.T.index) end, "G")
    local skipBtn = kitButton(keyRow, "Spectate", "ghost", nil, function() P.Call("Skip") end, "Q")

    DP.root, DP.card, DP.header = root, card, header
    DP.youBlock, DP.killerBlock, DP.victimAv, DP.killerAv, DP.killerInit = youBlock, killerBlock, victimAv, killerAv, killerInit
    DP.body, DP.inset, DP.keyRow, DP.chatDock = body, inset, keyRow, chatDock
    DP.pointsCard, DP.bodyCard, DP.tradeCard, DP.compareCard = pointsCard, bodyCard, tradeCard, compareCard
    DP.causeCard, DP.forgiveCard = causeCard, forgiveCard
    DP.footer, DP.shareBtn, DP.saveBtn, DP.reportBtn, DP.skipBtn = keyRow, shareBtn, saveBtn, reportBtn, skipBtn
    return root
end

local function place(panel, x, y, w, h)
    panel:SetPos(math.floor(x), math.floor(y))
    panel:SetSize(math.floor(w), math.floor(h))
end

local function layout()
    S.U = P.Unit()
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
    local headerH, footerH = u(62), u(44)
    place(DP.header, innerX, u(28), innerW, headerH)
    place(DP.keyRow, innerX, h - u(24) - footerH, innerW, footerH)
    local bodyY = u(28) + headerH + u(16)
    local bodyH = h - u(24) - footerH - u(12) - bodyY
    place(DP.body, innerX, bodyY, innerW, bodyH)

    -- footer buttons, right-aligned on the key row: Share · Save · Report · Spectate
    local btnH = u(32)
    local bx = innerW
    for _, btn in ipairs({DP.skipBtn, DP.reportBtn, DP.saveBtn, DP.shareBtn}) do
        local bw = math.max(u(96), btn:Measure())
        bx = bx - bw
        btn:SetPos(bx, (footerH - btnH) / 2)
        btn:SetSize(bw, btnH)
        bx = bx - u(8)
    end

    -- three columns: YOU | replay | KILLER. The replay column keeps 40% of the width; when that leaves a side column
    -- narrower than the chat frame's 384 px minimum (720p with the voice gutter) the chat dock spans the bottom of the
    -- YOU and replay columns instead of sitting under the YOU column.
    local gap = u(28)
    local centerW = math.max(math.floor(innerW * 0.4), u(480))
    local colW = math.floor((innerW - centerW - gap * 2) / 2)
    local leftX, centerX, rightX = 0, colW + gap, colW + gap + centerW + gap
    local wideDock = colW < 384
    local dockW = wideDock and (colW + gap + centerW) or colW
    local dockH = math.max(180, math.floor(bodyH * 0.3)) -- 180 px: the chat frame's own minimum height

    -- YOU column: the name, your body (the rest of the column), the points of this life, the chat dock at the bottom
    local blockH = u(64)
    place(DP.youBlock, leftX, 0, colW, blockH)
    DP.victimAv:SetPos(0, 0); DP.victimAv:SetSize(blockH, blockH)
    place(DP.chatDock, leftX, bodyH - dockH, dockW, dockH)
    local top, bottom = blockH + u(12), bodyH - dockH - u(10)
    local hasPoints = DP.H2H and DP.H2H.victim and DP.H2H.victim.life and DP.H2H.victim.life.points ~= nil
    DP.pointsCard:SetVisible(hasPoints and true or false)
    if hasPoints then
        place(DP.pointsCard, leftX, bottom - u(72), colW, u(72))
        bottom = bottom - u(72) - u(10)
    end
    local showBody = DB ~= nil and DP.Damage ~= nil and #DP.Damage.events > 0 and bottom - top >= u(160)
    DP.bodyCard:SetVisible(showBody and true or false)
    if showBody then place(DP.bodyCard, leftX, top, colW, bottom - top) end

    -- replay column: the inset, the damage timeline, the head-to-head
    local centerH = wideDock and (bodyH - dockH - u(10)) or bodyH
    local insetH = math.min(math.floor(centerW * 9 / 16), math.floor(centerH * 0.58))
    place(DP.inset, centerX, 0, centerW, insetH)
    local cy = insetH + u(12)
    local hasTimeline = (istable(DP.Marks) and #DP.Marks > 1) or timelineRows() > 0
    DP.tradeCard:SetVisible(hasTimeline and true or false)
    if hasTimeline then local tlH = timelineH() place(DP.tradeCard, centerX, cy, centerW, tlH) cy = cy + tlH + u(10) end
    local hasLife = DP.H2H and DP.H2H.victim and DP.H2H.victim.life ~= nil
    local cmpH = centerH - cy
    local showCompare = hasLife and cmpH >= u(34) + u(22) * 2
    DP.compareCard:SetVisible(showCompare and true or false)
    if showCompare then
        place(DP.compareCard, centerX, cy, centerW, cmpH)
        DP.compareCard.Tabs:SetVisible(DP.H2H.lifetime ~= nil)
        DP.compareCard.Tabs:SetPos(centerW / 2 - u(90), u(4)); DP.compareCard.Tabs:SetSize(u(180), u(22))
    end

    -- KILLER column: the name, the cause of death, forgiveness anchored to the bottom
    place(DP.killerBlock, rightX, 0, colW, blockH)
    DP.killerAv:SetPos(colW - blockH, 0); DP.killerAv:SetSize(blockH, blockH)
    DP.killerInit:SetPos(colW - blockH, 0); DP.killerInit:SetSize(blockH, blockH)
    local showKillerAv = findSteamID(DP.H2H and DP.H2H.killer) ~= nil or findSteamID(DP.Inst) ~= nil
    DP.killerAv:SetVisible(showKillerAv); DP.killerInit:SetVisible(not showKillerAv)
    local y = blockH + u(12)
    local forgiveOn = DP.GuiltRow ~= nil or DP.GuiltDecided ~= nil
    local fH = DP.GuiltDecided and u(40) or u(150)
    local room = bodyH - y - (forgiveOn and (fH + u(10)) or 0)
    local causeH = DP.causeCard:Needed(true)
    DP.causeCard.Full = causeH <= room
    if not DP.causeCard.Full then causeH = DP.causeCard:Needed(false) end
    local showCause = DP.Cause ~= nil and causeH > 0 and causeH <= room
    DP.causeCard:SetVisible(showCause and true or false)
    if showCause then place(DP.causeCard, rightX, y, colW, causeH) y = y + causeH + u(10) end
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
        ZCGoobApps.Notify.Push({app = "Replays", glyph = "play", title = "Death replay cut short", body = "Killed by " .. DP.LastKillerName})
    end
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
        if DP.Open and DB and DB.Release then DB.Release() end
        DP.Open, DP.WantGuilt, DP.GuiltDecided, DP.OverAt = false, false, nil, nil
        DP.Marks, DP.TimelineSpan, DP.TimelineKey, DP.Damage, DP.Cause, DP.CauseKey = nil, nil, nil, nil, nil, nil
        DP.TimelineLog = nil
        DP.ScrubT, DP.ScrubManual, DP.Dragging, DP.HoverKeys, DP.NArmedAt, DP.DebriefAskAt = nil, nil, false, nil, nil, nil
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
        if not DP.OverAt then DP.OverAt = RealTime() end
    else
        DP.OverAt = nil
    end
    -- the damage timeline and the header line are rebuilt only when their inputs change (table identity of the
    -- sequence / ledger); the cause of death also when the observer debrief arrives
    local tlKey = tostring(DP.Seq) .. "/" .. tostring(DP.H2H)
    if DP.TimelineKey ~= tlKey then
        DP.TimelineKey = tlKey
        DP.Marks, DP.TimelineSpan, DP.Damage, DP.MarkPeak, DP.ManyAttackers = buildTimeline()
        DP.HowLine = buildHowLine()
    end
    local _, revision = debrief()
    local causeKey = tlKey .. "/" .. tostring(revision)
    if DP.CauseKey ~= causeKey then DP.CauseKey, DP.Cause = causeKey, buildCause() end

    if not DP.Open then
        DP.Open, DP.WantGuilt = true, true
        DP.OpenedAt, DP.BornAt = RealTime(), RealTime()
        DP.Note, DP.GuiltDecided = nil, nil
        DP.GuiltRows = nil -- a previous death's rows must not match this killer before the fresh reply lands
        DP.ScrubManual, DP.Dragging, DP.NArmedAt = nil, false, nil
        gui.EnableScreenClicker(true); DP.ScreenClicker = true
        requestGuiltRows()
        askDebrief()
        DP.DebriefAskAt = RealTime() + 1.5 -- once more if the debrief has still not arrived
        installNoteWrap()
        P.Track(keysDown, WAIT_KEYS) -- a key held through the entrance is not a press (owner 2026-09-24: skipped replays)
        DP.SpaceSince, DP.SpaceHeld = nil, true -- a Space held through the entrance never counts as a hold either
    end
    if DP.DebriefAskAt and RealTime() >= DP.DebriefAskAt then DP.DebriefAskAt = nil askDebrief() end
    DP.ScrubT = scrubTime(t)
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
    DP.killerInit.Letter = K.Initial(DP.KillerName)
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
                btn.Spec.click = spec and function() sendGuiltAction(row, spec[2]) end or nil
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
    -- One key, one meaning (UI cohesion principle 3): Space next (close on the verdict), holding Space skips everything,
    -- 1-9 play that hit, S shares, V saves, G reports, F forgives, Q spectates, left/right step the timeline's marks,
    -- N twice turns killcams off for this player.
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
    if P.Edge(keysDown, KEY_S) then shareLife() end
    if P.Edge(keysDown, KEY_Q) then P.Call("Skip") end
    if P.Edge(keysDown, KEY_LEFT) then stepMark(-1) end
    if P.Edge(keysDown, KEY_RIGHT) then stepMark(1) end
    for n = 1, math.min(t.count or 0, 9) do
        if P.Edge(keysDown, HIT_KEYS[n]) then P.Call("Play", n) break end
    end
    if P.Edge(keysDown, KEY_F) then
        if DP.GuiltRow and DP.GuiltRow.canForgive and not DP.GuiltDecided then sendGuiltAction(DP.GuiltRow, "forgive") else requestGuiltRows() end
    end
    if P.Edge(keysDown, KEY_N_CODE) then
        if DP.NArmedAt and RealTime() - DP.NArmedAt <= N_CONFIRM then
            DP.NArmedAt = nil
            -- zc_killcam_show is the killcam's own opt-out (Settings › Replays & killcam); the server's K.Wants honours it.
            RunConsoleCommand("zc_killcam_show", "0")
            note("Killcams off · Settings › Replays & killcam turns them back on", T.green, 5)
        else
            DP.NArmedAt = RealTime()
            note("Press N again to turn killcams off", T.gold, N_CONFIRM)
        end
    end
end
hook.Add("Think", "GoobOS.DeathPanel.Think", refreshFrame)

P.Claim("death", function() return DP.Open == true end)

-- 1-9 (jump to a hit) are polled in refreshFrame with the other keys (HIT_KEYS). Drop a handler an older load registered.
if istable(P.KeyHandlers) then P.KeyHandlers["death.hit"] = nil end
