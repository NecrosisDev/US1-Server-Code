-- GoobOS round-end panel (round_v2 Stage 2 / Step 5, polish pass 2026-09-24). Behind ZCGoobApps.Panels.Enabled()
-- (server switch zc_goobos_panels, replicated, default 0): with the switch off nothing here draws, nothing here is
-- suppressed, and every wrapped receiver below calls the live original unchanged.
--
-- Sequence (BLUEPRINT.md Stage 2 owner decision 2, amendment 2026-09-24): on ROUND_STATE leaving 1 a full-screen
-- WINNER CARD (HUDPaint only, no vgui, no input) shows for up to 3 s or until the killcam highlight starts, then the
-- PANEL (a vgui frame, click-driven) rises in: killcam highlight inset, round summary, mode vote, map pre-vote. When
-- SolidMapVote opens its ballot at PreRound the ballot is drawn INSIDE this panel (maps with their images, play
-- counts, nominations, live votes, extend / random / reroll, the result) - the addon's own menu never opens while the
-- switch is on. A mode vote that starts mid-round (sh_mode_vote decides the round early) shows as a compact card at
-- the bottom of the screen until the intermission, never as a full-screen takeover of live play.
--
-- The FINAL intermission (owner 2026-09-24): before a map change the server opens the map vote at round end
-- (zc_vote_manager.lua Integration 7) and the round system holds the intermission for ~a minute. Here that means:
-- the right column is the ballot and nothing else (no mode vote, no pre-vote - both are pointless when the map is
-- changing), the inset plays the killcam's MAP REEL (every round's best moment), the stats card shows the whole map
-- (zc_map_summary), and the chat has a dock of its own at the bottom of the left column - in both panels.
--
-- Killcam seam: work/loader/killcam_revitalize/P3_SEAM.txt (ZCKillcamView / V). Never touches lua/zc_killcam.
if not CLIENT then return end
local A = ZCGoobApps
if not A then return end
local K, T, P = A.Kit, A.Theme, A.Panels
if not K or not T or not P then return end

local RE = A.RoundEnd or {}
A.RoundEnd = RE
RE.Version = "20260926.roundend14+modevote6"
-- Autorefresh reinstalls this file while the old panel lives on with the old painters (LESSONS.md): drop it so the next
-- phase entry rebuilds it from this file's code (ensurePanel).
if IsValid(RE.Panel) then RE.Panel:Remove() end
RE.Panel, RE.SearchEntry = nil, nil

-- sh_mode_vote.lua (admin_max_karma) sends its options in zc_modevote_start (modevote6, owner 2026-09-25: six random
-- rotation modes plus "Play again"; the four categories when zc_modevote_random is 0). Option order == the index Cast(i)
-- writes with WriteUInt(i, 3), so at most 7.
local MODE_MAX_OPTS = 7
local MODE_QUORUM = 4 -- sh_mode_vote.lua's own "min 4 votes needed" line
local WINNER_SECONDS = 3
local PANEL_RISE = 0.4
local SKIP_AFTER = 1.0 -- seconds of highlight watched before Space may skip it
local RECAP_AFTER = 4 -- seconds without a replay before the inset shows the round recap instead of "waiting"
local TITLE_SECONDS = 1.2 -- canvas Highlight_Title: the title card holds this long over the start of the shot, no cut
local ROSTER_ROW = 30 -- canvas: "give each player more room" - roster rows in units
local function num(v) return tonumber(v) or 0 end

-- === state ================================================================================
local function freshModeVote() return {active = false, endsAt = 0, locked = {}, tally = {}, options = {}, myVote = nil, resultLabel = nil, resultVotes = nil, seen = false} end
local function freshMapVote() return {active = false, maps = {}, finish = 0, length = 0, allowExtend = false, allowRandom = false, myVote = nil, result = nil} end

RE.Phase = nil -- nil | "winner" | "panel"
RE.WinnerBorn = 0
RE.PanelBorn = 0
RE.RoundMeta = nil -- {mode, length} captured at the ROUND_STATE 1 -> 3 edge
RE.Summary = nil -- zc_round_summary payload
RE.CopsSummary = nil -- cb_roundend-derived rows (cops_gangsters CreateEndMenu's data, read instead of opened)
RE.Prevote = nil -- zc_map_prevote_state payload
RE.MapSummary = nil -- zc_map_summary payload (the whole map, sent before a map vote)
RE.Dock = nil -- the chat dock rect inside the panel, published through P.ChatDock while the panel is up
RE.PrevoteAskedAt = nil
RE.ModeVote = freshModeVote()
RE.MapVote = freshMapVote()
-- a re-included file must hand back a cursor the previous load turned on: nothing else would ever turn it off
if RE.CursorOn then gui.EnableScreenClicker(false) end
RE.CursorOn = false
RE.Wraps = RE.Wraps or {}
-- modevote6: a re-included file must not keep the previous load's wrappers (installWrap sees its own old wrapper in the
-- slot and would leave the old reader - and the old wire format - in place). Hand each slot back to the addon's
-- original; the 0.5 s poll re-wraps it with this file's code.
for name, rec in pairs(RE.Wraps) do
    local key = string.lower(name)
    if rec.wrapper and net.Receivers[key] == rec.wrapper and rec.original then net.Receivers[key] = rec.original end
    rec.wrapper = nil
end
local keysDown = {}

local function resetRoundState()
    RE.Summary, RE.CopsSummary, RE.Prevote, RE.PrevoteAskedAt, RE.MapSummary, RE.PrevoteAnswered = nil, nil, nil, nil, nil, nil
    -- A mode vote that started before the round formally ended is still running: keep it.
    if not RE.ModeVote.active then RE.ModeVote = freshModeVote() end
    -- The final ballot opens server-side in the same tick as ZB_EndRound (zc_vote_manager Integration 7), so it can
    -- arrive before this poll sees the 1 -> 3 edge (up to ~1.4 s late in the round-end slow motion). Keep it.
    if not RE.MapVote.active then RE.MapVote = freshMapVote() end
    RE.SawReplay = false
    RE.RosterScroll, RE.RosterKey, RE.LastHighlight = 0, nil, nil
end

-- A vote this panel took over at its start stays with the panel until it ends, even if the switch is flipped
-- off meanwhile: the addon's own UI can only be armed by that start message, so handing back mid-vote would leave
-- players with no way to vote (adversarial review, 2026-09-24). New votes follow the switch.
local function voting() return RE.ModeVote ~= nil and RE.ModeVote.active or RE.MapVote ~= nil and RE.MapVote.active end
local function live() return P.Enabled() or voting() end
RE.Live = live
-- The final intermission: a map ballot is running (or has just resolved) - the map is about to change.
local function final() return RE.MapVote.active or RE.MapVote.result ~= nil end
RE.Final = final

local function roundState()
    local zbT = rawget(_G, "zb")
    return istable(zbT) and zbT.ROUND_STATE or nil, zbT
end
-- The intermission and the pre-round preparation: the only times the full-screen panel may cover the view.
local function intermission()
    local state = roundState()
    return state == 3 or state == 0
end

local function closePanel()
    RE.Phase = nil
    RE.Dock = nil
    P.ChatDock(nil)
    if RE.CursorOn then gui.EnableScreenClicker(false) RE.CursorOn = false end
    if IsValid(RE.SearchEntry) then RE.SearchEntry:SetText("") end
    RE.PrevoteQuery = nil
    P.Release(keysDown)
end

-- === round-state edge detection (same zb-polling idiom as notify.lua's roundBanner) =========
local lastRoundState
local function onRoundState(state, prev)
    if state == 3 and prev == 1 and P.Enabled() then
        RE.Phase = "winner"
        RE.WinnerBorn = RealTime()
        RE.WinnerToldFrom, RE.WinnerToldTo = nil, nil -- U3.1: this round's winner card has not told anyone yet
        local _, zbT = roundState()
        local mode = zbT and zbT.CROUND
        local length
        if zbT and isnumber(zbT.ROUND_START) then length = math.max(0, CurTime() - zbT.ROUND_START) end
        RE.RoundMeta = {mode = mode, length = length}
        resetRoundState()
    elseif state == 1 then
        -- Players can move again: whatever was up leaves now. A resolved ballot (extend won: the server's reset sent
        -- cancel, which keeps the result for the intermission) ends here too, or final() stays true all round and hides
        -- the compact mode-vote card.
        if not RE.MapVote.active then RE.MapVote = freshMapVote() end
        closePanel()
    elseif state ~= 3 and not voting() then
        -- Owner, 2026-09-24: the panel used to linger through the preparation state with nothing to show. It now
        -- leaves the moment the intermission ends unless a ballot is running inside it (the map vote opens in state 0).
        closePanel()
    end
end

local blockAddonMenus -- defined beside the wrap installer below; the poll runs it too
local installWraps -- likewise: a re-included cl_net.lua re-registers the addon's raw receivers, and the poll re-wraps them within 0.5 s
local function pollRoundState()
    if RE.Phase and not live() then closePanel() end
    installWraps()
    blockAddonMenus()
    -- Owner 2026-09-24: the cops_gangsters round-end list (global hmcdEndMenu, a ZFrame with a close button and a
    -- clickable player list) is standalone and overlaps this panel. While the panels are on it may not exist.
    if P.Enabled() and IsValid(rawget(_G, "hmcdEndMenu")) then
        hmcdEndMenu:Remove()
        hmcdEndMenu = nil
    end
    local state = roundState()
    if state == nil then return end
    if state == lastRoundState then
        -- A ballot that ended outside the intermission (extend won, vote cancelled) leaves nothing to show.
        if RE.Phase == "panel" and state ~= 3 and not voting() then closePanel() end
        return
    end
    local prev = lastRoundState
    lastRoundState = state
    if prev == nil then return end -- first read after load: don't fire on a round already in progress
    local ok, err = pcall(onRoundState, state, prev)
    if not ok then ErrorNoHalt("[GoobOS roundend] round-state edge: " .. tostring(err) .. "\n") end
end
timer.Create("GoobOS.RoundEnd.Poll", 0.5, 0, pollRoundState)
-- roundend_polish_20260925 (owner 2026-09-25: "the Blur bug casts itself OVER the 'Round end' part"): every mode's own
-- round-end list - global hmcdEndMenu, a ZFrame popup that paints a screen blur (homicide, tdm, dm, riot, mayhem,
-- gwars, wildcard, defense, sfd, criresp, coop, event, hl2dm, uncontained riot) - is removed the frame it appears.
-- The poll above does it too, but that is a CurTime timer: in the round-end slow motion (0.35) it ran only every ~1.4
-- real seconds, long enough for the blurred popup to sit over this panel. Think runs before the frame is painted.
hook.Add("Think", "GoobOS.RoundEnd.NoModeMenu", function()
    local menu = rawget(_G, "hmcdEndMenu")
    if menu ~= nil and IsValid(menu) and P.Enabled() then
        menu:Remove()
        hmcdEndMenu = nil
    end
end)

-- === wrap installer for net.Receivers we must take over (already have a live client receiver) =====
-- STEP5_BRIEF.md: identity-checked, installed at InitPostEntity + a 2 s timer, calls the original when
-- the switch is off, re-wraps if the slot is replaced under us.
local function installWrap(name, onTake, follows)
    local rec = RE.Wraps[name]
    if not rec then rec = {} RE.Wraps[name] = rec end
    local key = string.lower(name)
    local current = net.Receivers[key]
    if isfunction(current) and current ~= rec.wrapper then
        rec.original = current
        rec.wrapper = function(...)
            if not P.Enabled() and not (follows and follows()) then
                if rec.original then return rec.original(...) end
                return
            end
            local ok, err = pcall(onTake, rec.original, ...)
            if not ok then ErrorNoHalt("[GoobOS roundend] " .. name .. ": " .. tostring(err) .. "\n") end
        end
        net.Receive(name, rec.wrapper)
    end
end

-- Mode vote (sh_mode_vote.lua client ~539-698). Taking over start/tally/end/extend leaves its own
-- voteActive permanently false, so its HUDPaint ("ModeVote_Draw") and keys ("ModeVote_Keys" /
-- "ModeVote_KeyPoll") never fire again -- that IS the suppression, nothing else to hook off.
-- A vote this file takes over must always have somewhere to show: the full panel during the intermission
-- (a late joiner gets the panel opened for it), the compact card at any other time.
local openForVote
local function takeModeStart()
    local seconds = net.ReadUInt(8)
    local options, locked, tally = {}, {}, {}
    for i = 1, net.ReadUInt(3) do
        options[i] = {label = net.ReadString(), locked = net.ReadBool(), again = net.ReadBool()}
        locked[i], tally[i] = options[i].locked, 0
    end
    RE.ModeVote.active = true
    RE.ModeVote.endsAt = CurTime() + seconds
    RE.ModeVote.length = seconds
    RE.ModeVote.startedAt = RealTime()
    RE.ModeVote.options = options
    RE.ModeVote.locked = locked
    RE.ModeVote.tally = tally
    RE.ModeVote.myVote = nil
    RE.ModeVote.resultLabel, RE.ModeVote.resultVotes = nil, nil
    openForVote()
end
local function takeModeTally()
    for i = 1, net.ReadUInt(3) do RE.ModeVote.tally[i] = net.ReadUInt(8) end
end
-- an option's name as players read it; "Play again" carries the current mode's name
local function modeOptionLabel(i)
    local o = RE.ModeVote.options[i]
    if not o then return "" end
    return o.again and ("Play again: " .. o.label) or o.label
end
local function takeModeEnd()
    -- sh_mode_vote.lua writes the category it applied ("" when nobody voted); that beats re-deriving it from a
    -- tally that may be one update behind.
    local applied = net.ReadString()
    RE.ModeVote.active = false
    local bestI, bestV = 1, -1
    for i, v in ipairs(RE.ModeVote.tally) do if v > bestV then bestV, bestI = v, i end end
    RE.ModeVote.resultLabel = (isstring(applied) and applied ~= "") and applied or (bestV > 0 and modeOptionLabel(bestI) or nil)
    RE.ModeVote.resultVotes = math.max(0, bestV)
end
local function takeModeExtend()
    local seconds = net.ReadUInt(8)
    RE.ModeVote.endsAt = CurTime() + seconds
end

-- Map vote (SolidMapVote). Taking over start/cancel/deadline/end and never calling M.open is the P3-seam-
-- adjacent rule the brief gives for this addon: mirror the M fields the real open path resets so the
-- rest of SolidMapVote (UpdateVotes/UpdateNominations/MapPlayCounts, all left un-wrapped -- they only
-- ever write data fields, no UI) stays consistent, but never create SolidMapVote.Menu.
local function takeMapStart()
    local maps, finish, length = net.ReadTable(), net.ReadFloat(), net.ReadFloat()
    local allowExtend, allowRandom = net.ReadBool(), net.ReadBool()
    local _, bits = net.BytesLeft()
    local ballotRevision = (bits and bits >= 32) and net.ReadUInt(32) or 0
    -- Owner 2026-09-24: zc_vote_early re-sends the SAME ballot to everyone a second after it opens (and a late joiner's
    -- sync does too). The same revision refreshes the deadline and keeps the vote already cast instead of wiping it.
    local same = RE.MapVote.active and RE.MapVote.revision == ballotRevision and #RE.MapVote.maps == #(istable(maps) and maps or {})
    RE.MapVote.active = true
    RE.MapVote.maps = istable(maps) and maps or {}
    RE.MapVote.finish, RE.MapVote.length = finish, length
    RE.MapVote.allowExtend, RE.MapVote.allowRandom = allowExtend, allowRandom
    RE.MapVote.revision = ballotRevision
    if not same then
        RE.MapVote.myVote = nil
        RE.MapVote.result = nil
        RE.MapVote.startedAt = RealTime()
    end
    openForVote()
    local M = rawget(_G, "SolidMapVote")
    if istable(M) and not same then
        M.rerollState, M.sendVotes, M.sendPlayCounts, M.receivedSync, M.ballotRevision = nil, {}, {}, true, ballotRevision
    elseif istable(M) then
        M.receivedSync = true
    end
end
local function takeMapCancel()
    RE.MapVote.active = false
    -- Adversarial pass (2026-09-24): after a result the addon's reset (extend won, or the winner turned out to be
    -- unavailable) also sends "cancel". That is the end of the vote, not a cancellation: the result stays on the
    -- card and the final layout stays put until the next round starts (resetRoundState) or a new ballot arrives
    -- (takeMapStart clears it). A cancel with no result is a real cancellation and still clears everything.
    -- Only in the final intermission (ROUND_STATE 3): the old state-0 ballot flow still clears and lets the panel close.
    if RE.MapVote.result ~= nil and roundState() == 3 then
        local M = rawget(_G, "SolidMapVote")
        if istable(M) then M.receivedSync = true end
        return
    end
    RE.MapVote.result = nil
    local M = rawget(_G, "SolidMapVote")
    if istable(M) then M.receivedSync = true end
end
local function takeMapDeadline()
    local finish, length = net.ReadFloat(), net.ReadFloat()
    RE.MapVote.finish = finish
    if length then RE.MapVote.length = length end
end
-- Results: the addon's menu would show "WINNING MAP IS X" for Post Vote Length seconds and then the map changes
-- (or the vote resets on extend). The ballot stays on screen in its result state until that happens.
local function takeMapEnd()
    local winners, real, fixed = net.ReadTable(), net.ReadString(), net.ReadString()
    RE.MapVote.result = {winners = istable(winners) and winners or {}, real = real or "", fixed = fixed or "", at = RealTime()}
    hook.Run("SolidMapVote.WinningMaps", RE.MapVote.result.winners, RE.MapVote.result.real, RE.MapVote.result.fixed)
end

-- cops_gangsters cb_roundend: same data CreateEndMenu() itself reads (live player.Iterator(), plus the
-- zc_scoreboard globals PATSB_MutationTitle / HMCD_PoliceETA / HMCD_PoliceHere), just never opening the
-- popup. No payload on the wire (confirmed: the receiver takes no net.ReadX() calls either way).
local function takeCopsRoundEnd()
    local rows = {}
    for _, ply in player.Iterator() do
        if IsValid(ply) and ply:Team() ~= TEAM_SPECTATOR then
            rows[#rows + 1] = {name = ply:Nick(), frags = ply:Frags(), alive = ply:Alive()}
        end
    end
    table.sort(rows, function(a, b) return a.frags > b.frags end)
    RE.CopsSummary = {
        players = rows,
        mutation = GetGlobalString("PATSB_MutationTitle", ""),
        policeETA = GetGlobalFloat("HMCD_PoliceETA", 0),
        policeHere = GetGlobalBool("HMCD_PoliceHere", false),
    }
end

installWraps = function()
    local modeTaken = function() return RE.ModeVote.active end
    installWrap("zc_modevote_start", takeModeStart, modeTaken)
    installWrap("zc_modevote_tally", takeModeTally, modeTaken)
    installWrap("zc_modevote_end", takeModeEnd, modeTaken)
    installWrap("zc_modevote_extend", takeModeExtend, modeTaken)
    local mapTaken = function() return RE.MapVote.active end
    installWrap("SolidMapVote.start", takeMapStart, mapTaken)
    installWrap("SolidMapVote.cancel", takeMapCancel, mapTaken)
    installWrap("SolidMapVote.deadline", takeMapDeadline, mapTaken)
    installWrap("SolidMapVote.end", takeMapEnd, mapTaken)
    installWrap("cb_roundend", takeCopsRoundEnd)
    -- cops_gangsters assigns CreateEndMenu as a GLOBAL and may call it from more than the net path; wrap it too
    -- (identity re-checked on the same 2 s timer, so a mode reload that reassigns it is re-wrapped).
    local cem = rawget(_G, "CreateEndMenu")
    if isfunction(cem) and cem ~= RE.EndMenuWrap then
        RE.EndMenuOriginal = cem
        RE.EndMenuWrap = function(...)
            if P.Enabled() then return end
            return RE.EndMenuOriginal(...)
        end
        CreateEndMenu = RE.EndMenuWrap
    end
end
-- Owner 2026-09-24 ("we are still seeing the default RTV vote menu, hidden behind the panel"): belt and braces
-- around the receiver wraps above. Whatever path creates the addon's own menu (its deferred-open Think, a receiver
-- slot replaced under us, the gamemode's vanilla RTV menu - retired server-side by solidmapvote, client half still
-- loaded) - while these panels are live SolidMapVote.open is a no-op and any menu that exists is removed on the
-- next poll. Both are counted for zc_goobos_roundend_print.
blockAddonMenus = function()
    local M = rawget(_G, "SolidMapVote")
    if istable(M) then
        if isfunction(M.open) and M.open ~= RE.OpenWrap then
            RE.OpenOriginal = M.open
            RE.OpenWrap = function(...)
                if live() then RE.MenuBlocked = (RE.MenuBlocked or 0) + 1 return end
                return RE.OpenOriginal(...)
            end
            M.open = RE.OpenWrap
        end
        if live() and IsValid(M.Menu) then
            RE.MenuRemoved = (RE.MenuRemoved or 0) + 1
            M.Menu:Remove()
            M.Menu, M.isOpen = nil, false
        end
    end
    local zbT = rawget(_G, "zb")
    if istable(zbT) and isfunction(zbT.RTVMenu) and zbT.RTVMenu ~= RE.RTVWrap then
        RE.RTVOriginal = zbT.RTVMenu
        RE.RTVWrap = function(...)
            if live() then RE.MenuBlocked = (RE.MenuBlocked or 0) + 1 return end
            return RE.RTVOriginal(...)
        end
        zbT.RTVMenu = RE.RTVWrap
    end
end
local function installAll()
    installWraps()
    blockAddonMenus()
end
hook.Add("InitPostEntity", "GoobOS.RoundEnd.Wraps", installAll)
timer.Create("GoobOS.RoundEnd.Wraps", 2, 0, installAll)
installAll()

-- === first-owner receivers (STEP5_BRIEF.md: no client receiver exists yet for either) ============
net.Receive("zc_round_summary", function()
    local version = net.ReadUInt(8)
    local mode = net.ReadString()
    local duration = net.ReadUInt(16)
    local winner = net.ReadString()
    local nSurv = net.ReadUInt(4)
    local survivors = {}
    for i = 1, nSurv do survivors[i] = net.ReadString() end
    local nTop = net.ReadUInt(3)
    local top = {}
    for i = 1, nTop do
        top[i] = {
            name = net.ReadString(), zp = net.ReadUInt(16), combat = net.ReadUInt(24),
            heals = net.ReadUInt(8), kills = net.ReadUInt(8),
        }
    end
    RE.Summary = {
        version = version, mode = mode, duration = duration, winner = winner, survivors = survivors,
        top = top, totalKills = net.ReadUInt(12), totalHeals = net.ReadUInt(12),
    }
end)

net.Receive("zc_map_prevote_state", function()
    net.ReadUInt(8) -- version, always 1 today
    local n = net.ReadUInt(5)
    local ranked = {}
    for i = 1, n do ranked[i] = {map = net.ReadString(), count = net.ReadUInt(8)} end
    local yourVote = net.ReadString()
    local canChange = net.ReadBool()
    local p = net.ReadUInt(9)
    local pool
    if p > 0 then
        pool = {}
        for i = 1, p do pool[i] = net.ReadString() end
    end
    RE.Prevote = RE.Prevote or {}
    RE.Prevote.ranked = ranked
    -- prevote_sb_20260925: only a reply to THIS client carries its own canChange - the reply to an ask (it has the
    -- pool), one naming our vote, or the reply to our cast. Broadcasts always say "" / false (zc_map_prevote.lua:
    -- net.Broadcast cannot personalise), and taking that locked everyone's pre-vote the moment anyone else voted.
    if pool or yourVote ~= "" or (RE.PrevoteCastAt and RealTime() - RE.PrevoteCastAt < 3) then RE.Prevote.canChange = canChange end
    -- Broadcasts after a change carry an empty yourVote: keep the one the reply to our ask gave us.
    if yourVote ~= "" or pool then RE.Prevote.yourVote = yourVote end
    if pool then RE.Prevote.pool = pool end
    if pool or yourVote ~= "" or (RE.PrevoteAskedAt and RealTime() - RE.PrevoteAskedAt < 3) then RE.PrevoteAnswered = true end
end)

-- The whole map's numbers (zc_round_summary.lua rs2: sent with the last round summary before a map vote).
net.Receive("zc_map_summary", function()
    net.ReadUInt(8) -- version, always 1 today
    local map = net.ReadString()
    local rounds = net.ReadUInt(8)
    local elapsed = net.ReadUInt(16)
    local n = net.ReadUInt(3)
    local top = {}
    for i = 1, n do
        top[i] = {name = net.ReadString(), points = net.ReadUInt(24), kills = net.ReadUInt(12), heals = net.ReadUInt(12), rounds = net.ReadUInt(8), wins = net.ReadUInt(8)}
    end
    RE.MapSummary = {map = map, rounds = rounds, elapsed = elapsed, top = top, totalKills = net.ReadUInt(16), totalHeals = net.ReadUInt(16)}
end)

-- === actions ================================================================================
local function castMode(i)
    if not live() or not RE.ModeVote.active then return end
    if RE.ModeVote.locked[i] then return end
    if RE.ModeVote.myVote == i then return end
    net.Start("zc_modevote_cast")
    net.WriteUInt(i, 3)
    net.SendToServer()
    RE.ModeVote.myVote = i
end

local function castMap(choice)
    if not live() or not choice or not RE.MapVote.active or RE.MapVote.result then return end
    local M = rawget(_G, "SolidMapVote")
    if not (istable(M) and isfunction(M.SendBallotVote)) then return end
    M.SendBallotVote(choice)
    RE.MapVote.myVote = choice
end

local function requestReroll()
    local M = rawget(_G, "SolidMapVote")
    if not istable(M) or not isfunction(M.RerollButtonState) then return end
    local _, enabled = M.RerollButtonState(RE.MapVote.result ~= nil)
    if not enabled or (RE.RerollClick or 0) > RealTime() then return end
    RE.RerollClick = RealTime() + 1
    RunConsoleCommand("solidmapvote_reroll", tostring(M.ballotRevision or 0))
end

-- prevote_sb_20260925: RE.PrevoteAsk / RE.PrevoteCast are also the scoreboard's (addons/scoreboard cl_view.lua, the
-- pre-vote card), so they are not tied to the panels switch; this file's own callers still are.
function RE.PrevoteAsk()
    net.Start("zc_map_prevote_ask")
    net.SendToServer()
    RE.PrevoteAskedAt = RealTime()
    local zbT = rawget(_G, "zb")
    RE.PrevoteAskRound = istable(zbT) and zbT.ROUND_START or nil
end
function RE.PrevoteCast(mapname)
    net.Start("zc_map_prevote_cast")
    net.WriteString(mapname or "")
    net.SendToServer()
    RE.PrevoteCastAt = RealTime()
    if RE.Prevote then RE.Prevote.yourVote = mapname or "" end
end
local function askPrevote()
    if not P.Enabled() then return end
    RE.PrevoteAsk()
end

local function castPrevote(mapname)
    if not P.Enabled() then return end
    RE.PrevoteCast(mapname)
end

-- The ballot's slots in key order: maps first, then extend and random when the ballot offers them.
local function ballotChoices()
    local out = {}
    for i, name in ipairs(RE.MapVote.maps) do out[i] = name end
    if RE.MapVote.allowExtend then out[#out + 1] = "extend" end
    if RE.MapVote.allowRandom then out[#out + 1] = "random" end
    return out
end

-- Per-candidate live vote weight from SolidMapVote.sendVotes ({sid64 -> choice}), same computation
-- solidmapvotemap.lua:UpdateVotes uses (VotePower-weighted; falls back to a flat 1 if VotePower is gone).
-- Also returns the voters' names (initials go on the tile).
-- One pass over the ballot builds every candidate's tally; it is rebuilt when SolidMapVote replaces sendVotes (each
-- net update assigns a new table, solidmapvote/core/client/cl_net.lua:80-86) or after 1 s, so names stay current.
local NO_VOTERS = {}
local tally = {src = false, at = 0, count = 0, byChoice = {}}
local function voteTally()
    local M = rawget(_G, "SolidMapVote")
    local votes = istable(M) and M.sendVotes or nil
    local now = RealTime()
    if tally.src == votes and now - tally.at < 1 then return tally end
    tally.src, tally.at, tally.count, tally.byChoice = votes, now, 0, {}
    if not istable(votes) then return tally end
    for sid, chosen in pairs(votes) do
        tally.count = tally.count + 1
        local row = tally.byChoice[chosen]
        if not row then row = {total = 0, names = {}} tally.byChoice[chosen] = row end
        local power, ply = 1, player.GetBySteamID64 and player.GetBySteamID64(sid)
        if isfunction(M.VotePower) and IsValid(ply) then
            local ok, p = pcall(M.VotePower, ply)
            if ok and isnumber(p) then power = p end
        end
        row.total = row.total + power
        row.names[#row.names + 1] = IsValid(ply) and ply:Nick() or (isfunction(M.PlayerName) and M.PlayerName(sid)) or "?"
    end
    return tally
end
local function mapVotes(choice)
    local row = voteTally().byChoice[choice]
    if not row then return 0, NO_VOTERS end
    return math.floor(row.total), row.names
end
local function mapVoteTotal()
    return voteTally().count
end
local noms = {src = false, at = 0, byMap = {}}
local function nominatorOf(mapname)
    local M = rawget(_G, "SolidMapVote")
    local src = istable(M) and M.sendNominations or nil
    local now = RealTime()
    if noms.src ~= src or now - noms.at >= 1 then
        noms.src, noms.at, noms.byMap = src, now, {}
        if istable(src) then
            for sid, chosen in pairs(src) do
                if noms.byMap[chosen] == nil then
                    local ply = player.GetBySteamID64 and player.GetBySteamID64(sid)
                    noms.byMap[chosen] = IsValid(ply) and ply:Nick() or (isfunction(M.PlayerName) and M.PlayerName(sid)) or false
                end
            end
        end
    end
    return noms.byMap[mapname] or nil
end
local function playCountOf(mapname)
    local M = rawget(_G, "SolidMapVote")
    local counts = istable(M) and M.sendPlayCounts
    return istable(counts) and tonumber(counts[mapname]) or nil
end
-- Cached per map name: GetMapConfigInfo walks the whole Specific Maps list and builds a table, and this runs per row,
-- tile and ballot item every frame. The addon's config is fixed for the map, so the cache lives until a reload.
local mapInfoCache = {}
local function mapInfo(mapname)
    local hit = mapInfoCache[mapname]
    if hit then return hit end
    local M = rawget(_G, "SolidMapVote")
    if istable(M) and isfunction(M.GetMapConfigInfo) then
        local ok, info = pcall(M.GetMapConfigInfo, mapname)
        if ok and istable(info) then mapInfoCache[mapname] = info return info end
    end
    return {filename = mapname, displayname = string.gsub(mapname, "_", " "), image = "", width = 16, height = 9}
end

-- === drawing helpers =========================================================================
-- UI cohesion U3 (2026-09-26): the kit's painter set (K.Scaler: u/font/text/fit/measure/chip/keycap/hint row), K.Clock
-- and K.Initial replace this file's own copies. Each paint entry sets S.U = P.Unit(); the aliases read it per call.
local S = K.Scaler()
RE.Scaler = S
local u, text, fit, measure = S.u, S.text, S.fit, S.measure

-- data colours (initials avatars, map tiles without an image): a palette, not chrome
local avatarHues = {Color(122, 59, 59), Color(59, 90, 122), Color(90, 122, 59), Color(122, 106, 59), Color(106, 59, 122), Color(59, 122, 114)}
local function avatarColor(index) return avatarHues[((index - 1) % #avatarHues) + 1] end
local tileHues = {Color(70, 34, 34), Color(34, 50, 70), Color(48, 66, 34), Color(70, 60, 34), Color(60, 34, 70), Color(34, 68, 62)}
local function tileColor(index) return tileHues[((index - 1) % #tileHues) + 1] end

-- Round summary rows: prefer the real zc_round_summary top list; fall back to the cops_gangsters live
-- roster (name/frags only) when only that arrived -- "zp+combat as you see fit, label it": both fold
-- into one "Points" column here, kills/heals stay separate.
local function summaryRows()
    if RE.Summary and RE.Summary.top and #RE.Summary.top > 0 then
        local rows = {}
        for i, row in ipairs(RE.Summary.top) do
            rows[i] = {name = row.name, points = row.zp + row.combat, kills = row.kills, heals = row.heals}
        end
        return rows, true
    end
    if RE.CopsSummary and RE.CopsSummary.players and #RE.CopsSummary.players > 0 then
        local rows = {}
        for i, row in ipairs(RE.CopsSummary.players) do
            if i > 5 then break end
            rows[i] = {name = row.name, points = nil, kills = row.frags, heals = nil}
        end
        return rows, false
    end
    return nil
end

local function winnerLabel()
    local winner = RE.Summary and RE.Summary.winner ~= "" and RE.Summary.winner or nil
    if not winner then return nil end
    return winner == "nobody" and "Nobody wins" or (winner .. " win")
end

-- U3.1 (UI cohesion 2026-09-26, "say it once"): the winner card is the round end's one announcement. Both cards note
-- how long they have shown the result; the panel header and the side card's title repeat it only for a player whose
-- card never did (a late joiner, a highlight that cut the card short, a result that arrived after the card), and they
-- never say "Round over".
local function noteWinner(label)
    if not label then return end
    local now = RealTime()
    RE.WinnerToldFrom = RE.WinnerToldFrom or now
    RE.WinnerToldTo = now
end
local function winnerTold()
    return RE.WinnerToldFrom ~= nil and (RE.WinnerToldTo or 0) - RE.WinnerToldFrom >= 1
end
RE.WinnerTold = winnerTold

-- The round's mode as players read it: zc_round_summary's display name, else zb.CROUND ("the_hunt" -> "The hunt").
local function modeLabel()
    local mode = (RE.Summary and RE.Summary.mode ~= "" and RE.Summary.mode) or (RE.RoundMeta and RE.RoundMeta.mode) or ""
    return (string.gsub(string.gsub(tostring(mode), "_", " "), "^%l", string.upper))
end

-- The header's words: info = {winner, told, mode, map, final, extended, voteOpen}. Returns the title, whether the title
-- is the result, and the caption line (upper case, "   ·   " between parts). Pure: the tests call it directly.
function RE.HeaderText(info)
    local caption, title, isResult = {}, "", false
    local mode, map = tostring(info.mode or ""), tostring(info.map or "")
    if info.winner and not info.told then
        title, isResult = tostring(info.winner), true
        if mode ~= "" then caption[#caption + 1] = string.upper(mode) end
    elseif mode ~= "" then
        title = mode
    else
        title, map = map, ""
    end
    if map ~= "" then caption[#caption + 1] = string.upper(map) end
    if info.final then
        -- the pill says "Map extended" while the ballot is open; the caption only once it has closed
        if not info.extended then caption[#caption + 1] = "LAST ROUND"
        elseif not info.voteOpen then caption[#caption + 1] = "MAP EXTENDED" end
    end
    return title, isResult, table.concat(caption, "   ·   ")
end

-- === panel painting ==========================================================================
-- Colours not already on A.Theme/kit, hoisted here so Paint never allocates one (KIT_API.md). U3.4: the inset, scrims,
-- chips and keycaps read the theme (T.inset, T.dim, T.ink, T.chip, T.line); what is left derives from its tokens.
local LOCKED = Color(T.muted.r, T.muted.g, T.muted.b, 150) -- a locked option's text (reads ~110 grey over a tile)
-- K.Alpha returns ONE shared scratch colour, so a call that needs two tinted colours at once (K.Card fill + edge) gets
-- real Color tables hoisted here (adversarial review 2026-09-25).
-- roundend_polish_20260925: opaque, so K.Card's edge (painted under the whole fill) shows as a 1 px border only
local DOCK_FILL = Color(T.glass.r, T.glass.g, T.glass.b)
local DOCK_EDGE = Color(T.edge.r, T.edge.g, T.edge.b, 120)
-- roundend_polish_20260925 (canvas RoundEnd): neutral tiles, red only for your own vote. Opaque, because K.Card paints
-- the edge colour under the whole fill and a translucent fill turned every tile red.
local TILE_FILL = Color(34, 31, 31)
local TILE_FILL_MINE = Color(77, 23, 23)
local TILE_EDGE = Color(T.edge.r, T.edge.g, T.edge.b, 200)
local TILE_EDGE_LOCKED = Color(T.edge.r, T.edge.g, T.edge.b, 70)

-- Hit areas reuse their tables between frames; fn(arg) runs on click, so call sites pass a shared function and its
-- argument instead of building a closure every frame.
local function addHit(panel, x, y, w, h, fn, arg)
    local hits, pool = panel.hits, panel.hitPool
    if not pool then pool = {} panel.hitPool = pool end
    local n = #hits + 1
    local hit = pool[n]
    if not hit then hit = {} pool[n] = hit end
    hit.x, hit.y, hit.w, hit.h, hit.fn, hit.arg = x, y, w, h, fn, arg
    hits[n] = hit
end
local function clearHits(panel)
    local hits = panel.hits
    if not hits then panel.hits = {} return end
    for i = #hits, 1, -1 do hits[i] = nil end
end
local function callSkip() P.Call("Skip") end
local SKIP_HINTS = {{"Space", "Skip"}}
local function openPlayerMenu(r) P.PlayerMenu(r.sid, r.ply) end

-- U3.3 (UI cohesion 2026-09-26): one vote hint everywhere - the number keys as one keycap and the verb ("1–6 Vote"),
-- plus "Click a tile" where a click casts too - drawn with S.hints. The list is notify.lua's (N.VoteHints, the ULX vote
-- card draws the same); notify.lua loads before this file (autorun/zc_goobos_apps.lua), the fallback is for a broken load.
local function voteHints(n, clicks)
    local N = A.Notify
    if istable(N) and isfunction(N.VoteHints) then return N.VoteHints(n, clicks) end
    return {{"1–" .. tostring(n), "Vote"}}
end
RE.VoteHints = voteHints

-- The caption line over the inset. A map reel (sv_highlight.lua hl7: seq.reel, one instance per round) captions each
-- part from its own instance (star / kills / victims / round); a single highlight reads the sequence as before.
-- hl_captions_20260925 (owner D5 2026-09-25, via the killcam session: "These labels HAVE to be accurate. People already
-- call some of the highlights cheesy/stupid."): sv_highlight's v2 sequence sends inst.caps, the beats the server PROVED
-- (CLUTCH 1vN, REVENGE, DOUBLE, TRIPLE, N KILLS, HEADSHOT, N HEADSHOTS, LONG SHOT 76 m). A table replaces the guess
-- below (heads is a weighted float - a blind or bot headshot counts 0.25 - and any 2 kills in 8 s, teamkills
-- included, read "Double"); an empty one means nothing was proven: a plain count, no hype. nil: the old sequence.
local function provenBeat(inst, src, kills)
    local caps = (istable(inst) and istable(inst.caps)) and inst.caps or (istable(src) and istable(src.caps) and src.caps) or nil
    if not caps then return nil end
    if #caps > 0 then
        local out = {}
        for i = 1, #caps do out[i] = tostring(caps[i]) end
        return table.concat(out, " · ")
    end
    return kills == 1 and "1 kill" or (kills .. " kills")
end
local function highlightMeta(replay)
    local seq = replay and replay.seq
    if not seq then return nil, nil end -- nothing on screen: the frame says nothing (owner 2026-09-26: "highlight" x5)
    local inst = replay.inst
    local src = (istable(inst) and inst.star ~= nil) and inst or seq
    local star = tostring(src.star or (inst and inst.attacker) or "?")
    local kills = tonumber(src.kills) or 1
    local parts = {star}
    if seq.reel and src.round then table.insert(parts, 1, "Round " .. tostring(src.round)) end
    parts[#parts + 1] = provenBeat(inst, src, kills) or (kills == 1 and ((tonumber(src.heads) or 0) > 0 and "headshot kill" or "1 kill") or (kills .. " kills"))
    local wep = src.wep or (inst and inst.wep)
    if isstring(wep) then parts[#parts + 1] = (string.gsub(wep, "^weapon_", "")) end
    local victims = istable(src.victims) and #src.victims > 0 and table.concat(src.victims, ", ") or nil
    return table.concat(parts, "  ·  "), victims
end

-- The round recap: winner, the star of the round (top summary row), totals and survivors, drawn inside the inset
-- when there is no replay to show. `finished` = a highlight already played; otherwise the line says why none is up.
local function killcamsOff()
    local cv = GetConVar("zc_killcam_show")
    return cv ~= nil and not cv:GetBool()
end
local function noHighlightReason()
    if killcamsOff() then return "Killcams are off for you · Settings › Replays & killcam" end
    if RE.Summary and (RE.Summary.totalKills or 0) == 0 then return "A quiet round: nothing to replay" end
    return "No highlight cleared the bar this round"
end
RE.NoHighlightReason = noHighlightReason
-- U3 "every promise resolves": the client cannot tell whether this round's highlight was saved (the server's
-- zc_killcam_persist_missed is not replicated), so the recap points at Replays only when the Replays app's own index
-- (replays.lua, scope "highlights") has listed round highlights - i.e. the server keeps them. Otherwise: no line.
function RE.ReplaysLine()
    local state = istable(A.State) and A.State.replays or nil
    local rows = istable(state) and istable(state.rows) and state.rows.highlights or nil
    if not istable(rows) then return nil end
    for _, row in ipairs(rows) do
        if istable(row) and (row.kind == "highlight" or row.tag == "highlight") then return "Find it in Replays › Highlights" end
    end
    return nil
end
local function paintRecap(x, y, w, h, finished)
    local pad = u(16)
    local rows = summaryRows()
    local star = rows and rows[1]
    local ty = y + pad
    -- the winner and the round length are in the header already; this frame is the star and the totals
    -- owner 2026-09-26: no chip here - the card's subtitle already says ROUND RECAP; the one line is the reason
    local note
    if finished then note = RE.ReplaysLine() else note = noHighlightReason() end
    if note then
        text(fit(note, 11, 500, w - pad * 2), 11, 500, x + pad, ty, T.muted)
        ty = ty + u(26)
    end
    if star then
        local av = u(44)
        draw.RoundedBox(4, x + pad, ty, av, av, avatarColor(1))
        text(K.Initial(star.name), 18, 700, x + pad + av / 2, ty + av / 2, T.white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        text("STAR OF THE ROUND", 9, 700, x + pad + av + u(10), ty, T.gold)
        text(fit(star.name, 16, 700, w - pad * 2 - av - u(10)), 16, 700, x + pad + av + u(10), ty + u(12), T.text)
        local line = {}
        if star.points then line[#line + 1] = star.points .. " points" end
        line[#line + 1] = (star.kills or 0) .. (star.kills == 1 and " kill" or " kills")
        if star.heals then line[#line + 1] = star.heals .. (star.heals == 1 and " heal" or " heals") end
        text(table.concat(line, "  ·  "), 12, 500, x + pad + av + u(10), ty + u(32), T.muted)
        ty = ty + av + u(12)
    else
        text("Round data is on its way", 12, 500, x + pad, ty, T.muted)
        ty = ty + u(22)
    end
    if RE.Summary then
        local totals = string.format("Round total: %d kills  ·  %d heals", RE.Summary.totalKills or 0, RE.Summary.totalHeals or 0)
        text(totals, 12, 600, x + pad, ty, T.text)
        if RE.Summary.survivors and #RE.Summary.survivors > 0 then
            text(fit("Survived: " .. table.concat(RE.Summary.survivors, ", "), 11, 500, w - pad * 2), 11, 500, x + pad, ty + u(18), T.muted)
        end
    end
    -- a thin timeline strip at the bottom, so the frame still reads as a "player" surface
    local barY = y + h - u(24)
    draw.RoundedBox(2, x + u(8), barY, w - u(16), u(3), K.Alpha(T.white, 40))
    if finished then draw.RoundedBox(2, x + u(8), barY, w - u(16), u(3), K.Alpha(T.accent, 160)) end
end

-- The star and the beat line of the highlight on screen (or the last one seen), for the title card and the stamp.
local function highlightStar(replay)
    local seq = replay and replay.seq
    local inst = replay and replay.inst
    local src = (istable(inst) and inst.star ~= nil) and inst or seq or {}
    local star = tostring(src.star or (inst and inst.attacker) or "?")
    local kills = tonumber(src.kills) or 1
    local beat = provenBeat(inst, src, kills) or (kills == 1 and ((tonumber(src.heads) or 0) > 0 and "Headshot kill" or "1 kill") or (kills == 2 and "Double kill" or (kills == 3 and "Triple kill" or (kills .. " kills"))))
    local round = tonumber(src.round) or (rawget(_G, "zb") and tonumber(zb.Roundscount)) or nil
    return star, beat, round, kills
end

-- U3.2: the caption of the reel part after the one on screen, in the inset's own caption form (highlightMeta), or nil
-- when there is no next part or the sequence does not say who it is about. Pure: the tests call it directly.
function RE.NextCaption(replay)
    local seq = istable(replay) and replay.seq or nil
    local list = istable(seq) and seq.instances or nil
    if not istable(list) then return nil end
    local nextInst = list[(tonumber(replay.index) or 1) + 1]
    if not (istable(nextInst) and nextInst.star ~= nil) then return nil end
    return (highlightMeta({seq = seq, inst = nextInst}))
end

-- The end stamp (canvas Highlight_Stamp): what just played, and what comes next in a reel (only when there is a next part).
local function paintStamp(panel, x, y, w, h, replay)
    local last = RE.LastHighlight
    if not last then return false end
    draw.RoundedBox(4, x, y, w, h, K.Alpha(T.dim, 200))
    text((last.round and ("ROUND " .. last.round .. " ") or "ROUND ") .. "HIGHLIGHT", 11, 700, x + u(20), y + u(18), T.gold)
    text(fit(last.star .. "  ·  " .. last.beat, 26, 800, w - u(40)), 26, 800, x + u(20), y + u(34), T.text)
    if last.victims then text(fit("Victims: " .. last.victims, 12, 500, w - u(40)), 12, 500, x + u(20), y + u(68), T.muted) end
    local upNext = RE.NextCaption(replay)
    if upNext then text(fit("Up next  ·  " .. upNext, 11, 700, w - u(40)), 11, 700, x + w - u(20), y + h - u(22), T.muted, TEXT_ALIGN_RIGHT) end
    return true
end

local function paintInset(panel, x, y, w, h)
    K.Card(x, y, w, h, T.inset, K.Alpha(T.edge, 200))
    local replay = P.Replay()
    local phase = replay and replay.phase
    local drawn, recap = false, false
    if phase == "playing" then drawn = P.RenderInset(panel, x + 1, y + 1, w - 2, h - 2) end
    if drawn and replay.kind == "highlight" then
        -- remember what is playing for the stamp, and hold the title card over the first beat (no cut: the shot runs on)
        local star, beat, round = highlightStar(replay)
        local _, victims = highlightMeta(replay)
        RE.LastHighlight = {star = star, beat = beat, round = round, victims = victims}
        local shown = RE.ReplayWatched and RealTime() - RE.ReplayWatched or TITLE_SECONDS
        if shown < TITLE_SECONDS then
            local a = math.Clamp((TITLE_SECONDS - shown) / 0.4, 0, 1)
            draw.RoundedBox(4, x + 1, y + 1, w - 2, h - 2, K.Alpha(T.dim, 170 * a))
            local bar = u(28)
            draw.RoundedBoxEx(4, x + 1, y + 1, w - 2, bar, K.Alpha(T.ink, 255 * a), true, true, false, false)
            draw.RoundedBoxEx(4, x + 1, y + h - 1 - bar, w - 2, bar, K.Alpha(T.ink, 255 * a), false, false, true, true)
            local cx, cy = x + w / 2, y + h / 2
            text("HIGHLIGHT OF THE ROUND", 11, 700, cx, cy - u(40), K.Alpha(T.gold, 255 * a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            text(fit(string.upper(star), 36, 800, w - u(60)), 36, 800, cx, cy - u(4), K.Alpha(T.text, 255 * a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            text(beat .. (round and ("  ·  Round " .. round) or ""), 14, 500, cx, cy + u(26), K.Alpha(T.text, 255 * a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    end
    if not drawn then
        draw.RoundedBox(4, x + 1, y + 1, w - 2, h - 2, T.dim)
        if replay then RE.SawReplay = true end
        local finished = RE.SawReplay and (phase == "over" or phase == "leaving" or not replay)
        local starting = phase == "waiting" or phase == "playing"
        local waited = RealTime() - (RE.PanelBorn or RealTime())
        if starting or (not finished and waited < RECAP_AFTER) then
            local msg = starting and (final() and "Map reel starting" or "Highlight starting") or "Waiting for the highlight"
            local pulse = 0.6 + 0.4 * math.abs(math.sin(RealTime() * 2.2))
            text(msg, 16, 700, x + w / 2, y + h / 2 - u(4), K.Alpha(T.text, 255 * pulse), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        elseif not (finished and replay and paintStamp(panel, x + 1, y + 1, w - 2, h - 2, replay)) then
            -- Owner 2026-09-24: the inset is never an empty box. No replay to draw (quiet round, killcams off for this
            -- player, or the highlight has already played) -> the round recap takes the frame.
            paintRecap(x + 1, y + 1, w - 2, h - 2, finished)
            recap = true
        end
    end
    -- chips: what this is (a round's highlight, or part N of the map reel) and the slow-motion rate
    RE.InsetRecap = recap
    if recap then return y + h + u(8) + u(20) + u(10), true end -- the recap labels itself: no chip, no meta over it
    local label = "HIGHLIGHT"
    if replay and replay.seq and replay.seq.reel then
        -- hl_captions_20260925: seq.scope "round" is this round's reel (several of its moments), not the map's
        label = string.format(replay.seq.scope == "round" and "HIGHLIGHTS  %d / %d" or "MAP REEL  %d / %d", tonumber(replay.index) or 1, tonumber(replay.count) or replay.seq.reel)
    elseif final() then
        label = "MAP REEL"
    end
    local cw = S.chip(label, x + u(8), y + u(8))
    if replay and replay.rate and replay.rate < 0.99 then S.chip(string.format("%.2gx", replay.rate), x + w - u(8), y + u(8), T.accent, nil, TEXT_ALIGN_RIGHT) end
    local meta, victims = highlightMeta(replay)
    if meta then text(fit(meta, 11, 600, w - cw - u(30)), 11, 600, x + u(8) + cw + u(8), y + u(18), T.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
    -- scrub bar + meta
    local barY = y + h - u(24)
    if replay and replay.cs and replay.first and replay.last then
        local span = math.max(1, replay.last - replay.first)
        local frac = math.Clamp((replay.cs - replay.first) / span, 0, 1)
        draw.RoundedBox(2, x + u(8), barY, w - u(16), u(3), K.Alpha(T.white, 40))
        draw.RoundedBox(2, x + u(8), barY, math.max(u(3), (w - u(16)) * frac), u(3), T.accent)
        text(K.Clock((replay.cs - replay.first) / 100) .. " / " .. K.Clock(span / 100), 10, 500, x + w - u(8), barY + u(7), T.muted, TEXT_ALIGN_RIGHT)
    end
    if victims then text(fit("Victims: " .. victims, 10, 500, w * 0.6), 10, 500, x + u(8), barY + u(7), T.muted) end
    -- keycap row under the inset: Space = Skip only (P3_SEAM: V.Save is death-replay-only, never shown for a highlight).
    -- Nothing is written here when there is nothing to press (owner 2026-09-24: no filler text). U3: Space calls V.Skip,
    -- which leaves the whole replay - a reel too - so the verb is "Skip" there as well (it used to promise "Next part").
    local kcY = y + h + u(8)
    if replay and replay.kind == "highlight" and phase == "playing" and RE.ReplayWatched and RealTime() - RE.ReplayWatched >= SKIP_AFTER and not RE.Side() then
        local _, spans = S.hints(SKIP_HINTS, x, kcY)
        addHit(panel, spans[1][1], kcY, spans[1][2], u(20), callSkip)
    end
    return kcY + u(20) + u(10)
end

-- === roster: every player, scrollable, clickable (owner canvas note 2026-09-25) ==================================
-- Rows come from the round's summary top list (zc_round_summary: points/kills/heals) or the map's (zc_map_summary), then
-- every other player on the server (live roster, kills from Frags()) so nobody is missing. Each row resolves to a player
-- by name for the actions (P.PlayerMenu: CityLeak profile, Steam profile, mute, private message).
local function playerByName(name)
    for _, ply in player.Iterator() do
        if IsValid(ply) and ply:Nick() == name then return ply end
    end
    return nil
end

local function rosterRows(useMap)
    local rows, seen = {}, {}
    local top = useMap and RE.MapSummary and RE.MapSummary.top or (RE.Summary and RE.Summary.top) or nil
    local hasPoints = istable(top) and #top > 0
    if hasPoints then
        for _, r in ipairs(top) do
            local ply = playerByName(r.name)
            rows[#rows + 1] = {name = r.name, points = useMap and num(r.points) or (num(r.zp) + num(r.combat)), kills = r.kills, heals = r.heals,
                rounds = r.rounds, wins = r.wins, ply = ply, sid = IsValid(ply) and ply:SteamID64() or nil}
            seen[r.name] = true
        end
    elseif RE.CopsSummary and istable(RE.CopsSummary.players) then
        for _, r in ipairs(RE.CopsSummary.players) do
            local ply = playerByName(r.name)
            rows[#rows + 1] = {name = r.name, kills = r.frags, ply = ply, sid = IsValid(ply) and ply:SteamID64() or nil}
            seen[r.name] = true
        end
    end
    local rest = {}
    for _, ply in player.Iterator() do
        if IsValid(ply) and ply:Team() ~= TEAM_SPECTATOR and not seen[ply:Nick()] then
            rest[#rest + 1] = {name = ply:Nick(), kills = ply:Frags(), ply = ply, sid = ply:SteamID64()}
        end
    end
    table.sort(rest, function(a, b) return num(a.kills) > num(b.kills) end)
    for _, r in ipairs(rest) do rows[#rows + 1] = r end
    return rows, hasPoints
end

-- Rebuilt when its source table changes or every 2 s (players join and leave during the intermission).
local function currentRoster(useMap)
    local src = useMap and RE.MapSummary or RE.Summary or RE.CopsSummary
    local count = isfunction(player.GetCount) and player.GetCount() or 0
    local key = tostring(src) .. "/" .. tostring(useMap) .. "/" .. count
    if RE.RosterKey ~= key or RealTime() - (RE.RosterAt or 0) > 2 then
        RE.RosterKey, RE.RosterAt = key, RealTime()
        RE.Roster, RE.RosterPoints = rosterRows(useMap)
    end
    return RE.Roster or {}, RE.RosterPoints
end

local function paintRoster(panel, x, y, w, h, useMap)
    K.Card(x, y, w, h, T.cardGlass)
    local pad = u(16)
    local ty = y + pad
    local ms = useMap and RE.MapSummary or nil
    local mapName = (ms and ms.map ~= "" and ms.map) or game.GetMap()
    text(fit(string.upper(useMap and ("This map  ·  " .. tostring(mapName)) or "Round summary"), 11, 700, w - pad * 2 - u(150)), 11, 700, x + pad, ty, T.muted)
    local totals
    if useMap and ms then
        totals = string.format("%d round%s  ·  %d kills  ·  %d heals", ms.rounds or 0, ms.rounds == 1 and "" or "s", ms.totalKills or 0, ms.totalHeals or 0)
    elseif useMap then
        totals = "Map totals are on their way"
    elseif RE.Summary then
        totals = string.format("%d kills  ·  %d heals", RE.Summary.totalKills or 0, RE.Summary.totalHeals or 0)
    end
    if totals then text(totals, 11, 500, x + w - pad, ty, T.muted, TEXT_ALIGN_RIGHT) end
    ty = ty + u(22)
    local rows, hasPoints = currentRoster(useMap)
    RE.RosterRect = nil
    if #rows == 0 then
        text("Round data is on its way", 12, 500, x + pad, ty + u(6), T.muted)
        return
    end
    -- the podium: the top three when points are known and the card has the room (canvas RoundEnd summary)
    local podium = hasPoints and #rows >= 3 and h >= u(280)
    if podium then
        local slotW = (w - pad * 2) / 3
        for i, rank in ipairs({2, 1, 3}) do
            local r = rows[rank]
            local cx = x + pad + slotW * (i - 1) + slotW / 2
            local av = rank == 1 and u(44) or u(36)
            local top = ty + (rank == 1 and 0 or u(8))
            draw.RoundedBox(4, cx - av / 2, top, av, av, avatarColor(rank))
            if rank == 1 then
                surface.SetDrawColor(T.gold)
                surface.DrawOutlinedRect(cx - av / 2, top, av, av, 2)
            end
            text(K.Initial(r.name), rank == 1 and 18 or 14, 700, cx, top + av / 2, T.white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            text(fit(r.name, rank == 1 and 13 or 12, 700, slotW - u(8)), rank == 1 and 13 or 12, 700, cx, top + av + u(4), T.text, TEXT_ALIGN_CENTER)
            text(tostring(r.points or 0), 12, 800, cx, top + av + u(20), rank == 1 and T.gold or T.muted, TEXT_ALIGN_CENTER)
            S.chip("#" .. rank, cx, top + av + u(38), rank == 1 and T.gold or T.text, nil, TEXT_ALIGN_CENTER)
            addHit(panel, cx - slotW / 2, top, slotW, av + u(58), openPlayerMenu, r)
        end
        ty = ty + u(44) + u(66)
    end
    -- column header; trailing columns are dropped rather than squeezing the names when the card is narrow
    local cols = useMap and {{"Pts", "points", u(50), T.gold}, {"K", "kills", u(34)}, {"H", "heals", u(34)}, {"Rnd", "rounds", u(38)}, {"W", "wins", u(30)}}
        or (hasPoints and {{"Pts", "points", u(50), T.gold}, {"K", "kills", u(34)}, {"H", "heals", u(34)}} or {{"K", "kills", u(34)}})
    local right = 0
    for _, c in ipairs(cols) do right = right + c[3] end
    while w - pad * 2 - u(60) - right < u(100) and #cols > 1 do
        right = right - cols[#cols][3]
        cols[#cols] = nil
    end
    local nameW = w - pad * 2 - u(60) - right
    text("#", 10, 700, x + pad, ty, T.muted)
    text("Player", 10, 700, x + pad + u(60), ty, T.muted)
    local hx = x + pad + u(60) + nameW
    for _, c in ipairs(cols) do
        text(c[1], 10, 700, hx + c[3], ty, T.muted, TEXT_ALIGN_RIGHT)
        hx = hx + c[3]
    end
    ty = ty + u(16)
    -- the scrollable list (wheel over it scrolls: ensurePanel's OnMouseWheeled reads RE.RosterRect)
    local listH = y + h - u(8) - ty
    if listH < u(20) then return end
    local rowH = u(ROSTER_ROW)
    local first = podium and 4 or 1
    local count = #rows - first + 1
    local maxScroll = math.max(0, count * rowH - listH)
    RE.RosterScroll = math.Clamp(RE.RosterScroll or 0, 0, maxScroll)
    RE.RosterRect = {x = x + pad, y = ty, w = w - pad * 2, h = listH, max = maxScroll, row = rowH}
    local sx, sy = panel:LocalToScreen(x + pad - u(6), ty)
    local clip = istable(render) and isfunction(render.SetScissorRect)
    if clip then render.SetScissorRect(sx, sy, sx + w - pad * 2 + u(12), sy + listH, true) end
    local mx, my = panel:CursorPos()
    local ry = ty - RE.RosterScroll
    local me = LocalPlayer()
    -- pcall: an error inside the rows must never leave the scissor on (it would clip everything drawn after it)
    local ok, err = pcall(function()
    for i = first, #rows do
        if ry + rowH > ty and ry < ty + listH then
            local r = rows[i]
            local y0, y1 = math.max(ry, ty), math.min(ry + rowH, ty + listH)
            local hover = mx >= x + pad and mx <= x + w - pad and my >= y0 and my <= y1
            if hover then draw.RoundedBox(3, x + pad - u(6), ry, w - pad * 2 + u(12), rowH - u(2), K.Alpha(T.main, 40)) end
            local cx = x + pad
            text(tostring(i), 12, 600, cx + u(11), ry + rowH / 2, T.muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            cx = cx + u(28)
            local av = u(22)
            draw.RoundedBox(4, cx, ry + (rowH - av) / 2, av, av, avatarColor(i))
            text(K.Initial(r.name), 9, 700, cx + av / 2, ry + rowH / 2, T.white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            cx = cx + av + u(10)
            local online = IsValid(r.ply)
            local label = r.name .. ((online and r.ply == me) and "  (you)" or ((not online) and "  (left)" or ""))
            text(fit(label, 13, 500, nameW - av - u(10)), 13, 500, cx, ry + rowH / 2, online and T.text or T.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            cx = x + pad + u(60) + nameW
            for _, c in ipairs(cols) do
                local v = r[c[2]]
                if v ~= nil then text(tostring(v), 12, 600, cx + c[3], ry + rowH / 2, c[4] or T.text, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
                else text("-", 12, 500, cx + c[3], ry + rowH / 2, T.muted, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER) end -- no gaps in a row
                cx = cx + c[3]
            end
            addHit(panel, x + pad, y0, w - pad * 2, y1 - y0, openPlayerMenu, r)
        end
        ry = ry + rowH
    end
    end)
    if clip then render.SetScissorRect(0, 0, 0, 0, false) end
    if not ok then ErrorNoHalt("[GoobOS roundend] roster: " .. tostring(err) .. "\n") end
    if maxScroll > 0 then
        local thumbH = math.max(u(20), listH * listH / (count * rowH))
        local thumbY = ty + (listH - thumbH) * (RE.RosterScroll / maxScroll)
        draw.RoundedBox(2, x + w - pad + u(6), thumbY, u(4), thumbH, K.Alpha(T.main, 160))
    end
end

local function queuedPillTitle()
    local N = A.Notify
    if not (istable(N) and istable(N.VMState)) then return nil end
    for _, e in ipairs(N.VMState) do
        if istable(e) and e.queued then return e.title end
    end
    return nil
end

local function paintModeCard(panel, x, y, w, h)
    K.Card(x, y, w, h, T.cardGlass)
    local pad = u(16)
    local ty = y + pad
    text("NEXT MODE", 11, 700, x + pad, ty, T.muted)
    local left = math.max(0, RE.ModeVote.endsAt - CurTime())
    if RE.ModeVote.active then
        local span = math.max(1, RE.ModeVote.length or 1)
        local bw = u(90)
        draw.RoundedBox(2, x + w - pad - u(48) - bw, ty + u(6), bw, u(4), K.Alpha(T.ink, 235))
        draw.RoundedBox(2, x + w - pad - u(48) - bw, ty + u(6), bw * math.Clamp(left / span, 0, 1), u(4), left < 6 and T.accent or T.main)
        text(K.Clock(left), 12, 600, x + w - pad, ty, left < 6 and T.accent or T.text, TEXT_ALIGN_RIGHT)
    elseif RE.ModeVote.resultLabel then
        text("Decided", 11, 600, x + w - pad, ty, T.muted, TEXT_ALIGN_RIGHT)
    else
        text("No vote yet", 11, 600, x + w - pad, ty, T.muted, TEXT_ALIGN_RIGHT)
    end
    ty = ty + u(24)
    local total, most, bestI = 0, 0, 1
    for i, v in ipairs(RE.ModeVote.tally) do
        total = total + v
        if v > most then most, bestI = v, i end
    end
    -- modevote6: the drawn modes two to a row, "Play again" as a full-width row under them; tiles go compact (no
    -- second text line) when there are more than four options so the card keeps the column's height budget.
    local options = RE.ModeVote.options
    local compact = #options > 4
    local gap = u(8)
    local tileW = (w - pad * 2 - gap) / 2
    local tileH = compact and u(40) or u(56)
    local labelY = compact and u(16) or u(19)
    local slot, rows = 0, 0
    for i, opt in ipairs(options) do
        local tx, tyy, tw
        if opt.again then
            local row = math.ceil(slot / 2)
            tx, tyy, tw = x + pad, ty + row * (tileH + gap), w - pad * 2
            rows = math.max(rows, row + 1)
        else
            local col, row = slot % 2, math.floor(slot / 2)
            tx, tyy, tw = x + pad + col * (tileW + gap), ty + row * (tileH + gap), tileW
            slot = slot + 1
            rows = math.max(rows, row + 1)
        end
        local mine = RE.ModeVote.myVote == i
        local locked = RE.ModeVote.locked[i] == true
        local barY = tyy + tileH - u(compact and 10 or 14)
        K.Card(tx, tyy, tw, tileH, mine and TILE_FILL_MINE or TILE_FILL, locked and TILE_EDGE_LOCKED or TILE_EDGE)
        S.keycap(tostring(i), tx + u(10), tyy + labelY - u(10), locked and 0.35 or 1)
        local label = opt.again and ("Play again: " .. opt.label .. (compact and "  ·  new roles" or "")) or opt.label
        text(fit(label, 14, 700, tw - u(80)), 14, 700, tx + u(34), tyy + labelY, locked and LOCKED or T.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        text(locked and "locked" or tostring(RE.ModeVote.tally[i] or 0), 16, 800, tx + tw - u(10), tyy + labelY, locked and LOCKED or (mine and T.accent or T.text), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        draw.RoundedBox(2, tx + u(10), barY, tw - u(20), u(4), K.Alpha(T.ink, 235))
        if not locked and most > 0 then draw.RoundedBox(2, tx + u(10), barY, (tw - u(20)) * (RE.ModeVote.tally[i] or 0) / most, u(4), mine and T.accent or T.main) end
        if not compact then
            if mine then
                text("Your vote", 9, 600, tx + u(10), tyy + tileH - u(26), T.accent)
            elseif locked then
                text("Played last", 9, 600, tx + u(10), tyy + tileH - u(26), LOCKED)
            elseif opt.again then
                text("Same mode, new roles", 9, 600, tx + u(10), tyy + tileH - u(26), T.muted)
            end
        end
        if panel and RE.ModeVote.active and not locked then addHit(panel, tx, tyy, tw, tileH, castMode, i) end
    end
    ty = ty + rows * tileH + math.max(0, rows - 1) * gap + u(8)
    local foot
    if RE.ModeVote.active and total < MODE_QUORUM then
        foot = string.format("At least %d votes needed  (%d/%d)", MODE_QUORUM, total, MODE_QUORUM)
    elseif RE.ModeVote.active then
        foot = string.format("%d vote%s  ·  quorum %d  ·  %s leads", total, total == 1 and "" or "s", MODE_QUORUM, modeOptionLabel(bestI))
    elseif RE.ModeVote.resultLabel then
        foot = "Next: " .. RE.ModeVote.resultLabel
    end
    if foot then text(fit(foot, 11, 500, w - pad * 2), 11, 500, x + pad, ty, T.muted) end
end
-- the card's height for the current ballot (header, tile rows, footer): 210 units for four tiles, as before
local function modeCardHeight()
    local options = RE.ModeVote.options
    local plain, again = 0, 0
    for _, opt in ipairs(options) do if opt.again then again = 1 else plain = plain + 1 end end
    local rows = math.ceil(plain / 2) + again
    -- the same rule as paintModeCard: compact 40 px tiles over four options, else 56. Three modes plus "Play again" is
    -- three 56 px rows, which the old fixed u(210) cut off (review 2026-09-26).
    local tileH = #options > 4 and 40 or 56
    return math.max(u(210), u(16 + 24) + rows * u(tileH) + math.max(0, rows - 1) * u(8) + u(8 + 14 + 16))
end

-- roundend_polish_20260925 (owner 2026-09-25, "this looks bad"; canvas RoundEnd, "Map pre-vote"): ranked picks as full
-- rows with their counts, your own tinted and chipped "Yours", a gold divider after the six that become the map vote.
-- The free rows (owner 2026-09-24: "map pre-voting doesn't populate") offer other maps by display name under their own
-- divider - a sample shuffled per round, not the first file names of the alphabet with a "+". Typing in the search box
-- filters the whole pool live; clicking a result picks it and clears the search.
local function prevoteLabel(map)
    local name = mapInfo(map).displayname
    return isstring(name) and name ~= "" and name or map
end
local function prevoteSuggestions(pool)
    local zbT = rawget(_G, "zb")
    local seed = math.floor(tonumber(istable(zbT) and zbT.ROUND_START) or 0)
    local cache = RE.PrevoteSuggest
    if cache and cache.pool == pool and cache.seed == seed then return cache.list end
    local list = {}
    for i, m in ipairs(pool) do list[i] = m end
    local s = (seed % 2147483646) + 1
    for i = #list, 2, -1 do
        s = (s * 48271) % 2147483647
        local j = s % i + 1
        list[i], list[j] = list[j], list[i]
    end
    RE.PrevoteSuggest = {pool = pool, seed = seed, list = list}
    return list
end
local function pickPrevote(map)
    castPrevote(map)
    RE.PrevoteQuery = nil
    if IsValid(RE.SearchEntry) then RE.SearchEntry:SetText("") end
end
local function paintPrevote(panel, x, y, w, h)
    K.Card(x, y, w, h, T.cardGlass)
    local pad = u(16)
    text("MAP PRE-VOTE", 11, 700, x + pad, y + pad, T.muted)
    text("Top picks seed the next map vote", 10, 500, x + pad + measure("MAP PRE-VOTE", 11, 700) + u(10), y + pad + u(1), T.muted)
    local entry = RE.SearchEntry
    if IsValid(entry) then
        local ew = u(170)
        entry:SetPos(x + w - pad - ew, y + pad - u(6))
        entry:SetSize(ew, u(26))
        entry:SetVisible(true)
        RE.EntryPaint = RE.PaintCount
    end
    local ty = y + pad + u(28)
    if not RE.Prevote then
        if RE.PrevoteAskedAt and RealTime() - RE.PrevoteAskedAt >= 3 then
            text("No pre-vote data (server switch off)", 12, 500, x + pad, ty, T.muted)
        end
        return
    end
    local rowH, gapH = u(24), u(2)
    local bottom = y + h - u(26) -- the footer line lives below
    local mine = RE.Prevote.yourVote or ""
    local canPick = RE.Prevote.canChange ~= false
    local ranked = RE.Prevote.ranked or {}
    local counts = {}
    for _, r in ipairs(ranked) do counts[r.map] = r.count end
    local function row(map, count, dim)
        local isMine = mine ~= "" and mine == map
        if isMine then draw.RoundedBox(4, x + pad - u(8), ty, w - pad * 2 + u(16), rowH, K.Alpha(T.main, 70)) end
        local name = fit(prevoteLabel(map), 13, 500, w - pad * 2 - (isMine and u(96) or u(44)))
        local col = K.Alpha(T.text, dim and 150 or 255)
        text(name, 13, 500, x + pad, ty + rowH / 2, col, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        if isMine then S.chip("YOURS", x + pad + measure(name, 13, 500) + u(8), ty + (rowH - u(20)) / 2, T.text) end
        if count then text(tostring(count), 13, 700, x + w - pad, ty + rowH / 2, col, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER) end
        if canPick and not isMine then addHit(panel, x + pad - u(8), ty, w - pad * 2 + u(16), rowH, pickPrevote, map) end
        ty = ty + rowH + gapH
    end
    local function divider(label, color)
        local tw = measure(label, 9, 700)
        local side = math.max(0, (w - pad * 2 - tw) / 2 - u(10))
        surface.SetDrawColor(T.hair.r, T.hair.g, T.hair.b, T.hair.a)
        surface.DrawRect(x + pad, ty + u(9), side, 1)
        surface.DrawRect(x + w - pad - side, ty + u(9), side, 1)
        text(label, 9, 700, x + w / 2, ty + u(9), color, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        ty = ty + u(20)
    end
    local pool = RE.Prevote.pool
    local current = string.lower(game.GetMap())
    local q = string.lower(tostring(RE.PrevoteQuery or ""):match("^%s*(.-)%s*$"))
    if q ~= "" then
        local n = 0
        -- the lowercased "name\nlabel" per map is cached per pool: this runs every frame while a query is typed
        local lc = RE.PrevoteLower
        if not lc or lc.pool ~= pool then lc = {pool = pool, keys = {}} RE.PrevoteLower = lc end
        for _, map in ipairs(istable(pool) and pool or {}) do
            if ty + rowH > bottom then break end
            local key = lc.keys[map]
            if not key then key = string.lower(map) .. "\n" .. string.lower(prevoteLabel(map)) lc.keys[map] = key end
            if string.lower(map) ~= current and string.find(key, q, 1, true) then
                n = n + 1
                row(map, counts[map], false)
            end
        end
        if n == 0 then text(istable(pool) and "No map matches" or "Loading maps…", 12, 500, x + pad, ty + rowH / 2, T.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
    else
        for i, r in ipairs(ranked) do
            if ty + rowH > bottom then break end
            if i == 7 then divider("TOP 6 BECOME THE MAP VOTE", T.gold) end
            row(r.map, r.count, i > 6)
        end
        if istable(pool) and #pool > 0 and ty + u(20) + rowH <= bottom then
            divider(#ranked == 0 and "PICK A MAP" or "OR PICK ANOTHER", T.muted)
            for _, map in ipairs(prevoteSuggestions(pool)) do
                if ty + rowH > bottom then break end
                if counts[map] == nil and string.lower(map) ~= current then row(map, nil, true) end
            end
        elseif #ranked == 0 then
            text("No maps available to pre-vote", 12, 500, x + pad, ty + rowH / 2, T.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
    end
    local foot
    if RE.Prevote.canChange == false then
        foot = mine ~= "" and "Your pick is locked until next round" or "Locked until next round"
    elseif mine ~= "" then
        foot = "One change per round"
    else
        foot = "Click a map to pick it  ·  one pick per round"
    end
    if istable(pool) and #pool > 0 and q == "" then foot = foot .. "  ·  search all " .. #pool .. " maps" end
    text(fit(foot, 10, 500, w - pad * 2), 10, 500, x + pad, y + h - u(14), T.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
end

-- One map tile of the inlaid ballot: the addon's own map image when it has one (SolidMapVote.DrawWebImage, the
-- same call its tiles make), otherwise a coloured plate; name, play count, nominator, live votes and voters.
local function paintMapTile(panel, x, y, w, h, index, mapname, result)
    local info = mapInfo(mapname)
    local mine = RE.MapVote.myVote == mapname
    local won = result and result.real == mapname
    local M = rawget(_G, "SolidMapVote")
    draw.RoundedBox(4, x, y, w, h, tileColor(index))
    if istable(M) and isfunction(M.DrawWebImage) and isstring(info.image) and info.image ~= "" then
        local iw, ih = tonumber(info.width) or 16, tonumber(info.height) or 9
        if iw <= 0 or ih <= 0 then iw, ih = 16, 9 end
        -- cover-fit inside the tile, clipped to it
        local scale = math.max(w / iw, h / ih)
        local dw, dh = iw * scale, ih * scale
        local sx, sy = panel:LocalToScreen(x, y)
        local clip = istable(render) and isfunction(render.SetScissorRect)
        if clip then render.SetScissorRect(sx, sy, sx + w, sy + h, true) end
        pcall(M.DrawWebImage, info.image, x + (w - dw) / 2, y + (h - dh) / 2, dw, dh, T.white)
        if clip then render.SetScissorRect(0, 0, 0, 0, false) end
    end
    -- bottom shade so the name always reads
    draw.RoundedBoxEx(4, x, y + h * 0.5, w, h * 0.5, K.Alpha(T.ink, 150), false, false, true, true)
    draw.RoundedBoxEx(4, x, y + h * 0.72, w, h * 0.28, K.Alpha(T.ink, 120), false, false, true, true)
    if mine or won then
        surface.SetDrawColor(won and T.gold or T.accent)
        surface.DrawOutlinedRect(x, y, w, h, 2)
    end
    -- number keycap
    S.keycap(tostring(index), x + u(6), y + u(6))
    local nominator = nominatorOf(mapname)
    if nominator then S.chip(fit("NOMINATED BY " .. string.upper(nominator), 10, 700, w - u(40)), x + w - u(6), y + u(6), T.gold, nil, TEXT_ALIGN_RIGHT) end
    local plays = playCountOf(mapname)
    local nameY = y + h - u(30)
    text(fit(string.upper(info.displayname or mapname), 13, 700, w - u(12)), 13, 700, x + u(8), nameY, T.white)
    local votes, voters = mapVotes(mapname)
    local total = mapVoteTotal()
    local pct = total > 0 and math.floor(votes / total * 100 + 0.5) or 0
    local line = plays and (string.Comma(plays) .. (plays == 1 and " play" or " plays")) or ""
    text(line, 10, 500, x + u(8), y + h - u(13), K.Alpha(T.white, 190))
    text(votes .. (votes == 1 and " vote" or " votes") .. "  ·  " .. pct .. "%", 10, 700, x + w - u(8), y + h - u(13), mine and T.accent or T.white, TEXT_ALIGN_RIGHT)
    -- voters as initials, up to six, top-left under the keycap
    local vx = x + u(6)
    for i = 1, math.min(#voters, 6) do
        draw.RoundedBox(u(8), vx, y + u(30), u(16), u(16), avatarColor(i))
        text(K.Initial(voters[i]), 8, 700, vx + u(8), y + u(38), T.white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        vx = vx + u(18)
    end
    if #voters > 6 then text("+" .. (#voters - 6), 9, 600, vx + u(2), y + u(38), T.white, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
    if won then S.chip("WINNER", x + w / 2, y + h * 0.42, T.gold, nil, TEXT_ALIGN_CENTER) end
    if not result then addHit(panel, x, y, w, h, castMap, mapname) end
end

local function paintOptionTile(panel, x, y, w, h, index, choice, label, result)
    local mine = RE.MapVote.myVote == choice
    local won = result and result.real == choice
    K.Card(x, y, w, h, TILE_FILL, (won and T.gold) or (mine and T.accent) or K.Alpha(T.edge, 160)) -- opaque: an edge, not a tint
    S.keycap(tostring(index), x + u(6), y + (h - u(20)) / 2)
    text(label, 12, 700, x + u(32), y + h / 2, mine and T.accent or T.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    local votes = mapVotes(choice)
    text(tostring(votes), 11, 600, x + w - u(8), y + h / 2, T.muted, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    if not result then addHit(panel, x, y, w, h, castMap, choice) end
end

local function resultLine(result)
    if not result then return nil end
    local function display(name)
        local info = mapInfo(name)
        return string.upper(info.displayname or name)
    end
    local tie = #result.winners > 1
    if result.real == "extend" then return tie and "Map extended as the tie breaker" or "The map has been extended" end
    if result.real == "random" then return display(result.fixed) .. (tie and " was picked at random as the tie breaker" or " was picked at random") end
    return "Winning map: " .. display(result.real) .. (tie and " (tie breaker)" or "")
end

local function paintMapBallot(panel, x, y, w, h)
    K.Card(x, y, w, h, T.cardGlass)
    local pad = u(16)
    local ty = y + pad
    local result = RE.MapVote.result
    text("Next map", 12, 700, x + pad, ty, T.accent)
    local total = mapVoteTotal()
    text(total .. (total == 1 and " vote cast" or " votes cast"), 11, 500, x + pad + measure("Next map", 12, 700) + u(10), ty + u(1), T.muted)
    local left = math.max(0, RE.MapVote.finish - CurTime())
    if result then
        text("Changing map", 12, 600, x + w - pad, ty, T.gold, TEXT_ALIGN_RIGHT)
    else
        text(K.Clock(left), 12, 600, x + w - pad, ty, left < 6 and T.accent or T.text, TEXT_ALIGN_RIGHT)
    end
    ty = ty + u(20)
    -- countdown bar
    local length = math.max(1, RE.MapVote.length or 1)
    draw.RoundedBox(2, x + pad, ty, w - pad * 2, u(3), K.Alpha(T.ink, 235))
    if not result then draw.RoundedBox(2, x + pad, ty, (w - pad * 2) * math.Clamp(left / length, 0, 1), u(3), left < 6 and T.accent or T.main) end
    ty = ty + u(12)
    if result then
        local line = resultLine(result) or ""
        text(fit(line, 14, 700, w - pad * 2), 14, 700, x + pad, ty, T.gold)
        ty = ty + u(24)
    end
    local maps = RE.MapVote.maps
    local count = math.min(#maps, 6)
    local extras = (RE.MapVote.allowExtend and 1 or 0) + (RE.MapVote.allowRandom and 1 or 0)
    local optionH = extras > 0 and u(34) or 0
    local rerollH = u(30)
    local cols, gap = count > 3 and 3 or math.max(1, count), u(10)
    local rows = math.max(1, math.ceil(count / cols))
    local gridH = y + h - pad - ty - (optionH > 0 and optionH + gap or 0) - rerollH - gap
    local tileW = math.floor((w - pad * 2 - (cols - 1) * gap) / cols)
    local tileH = math.floor((gridH - (rows - 1) * gap) / rows)
    tileH = math.min(tileH, math.floor(tileW * 9 / 16) + u(24))
    for i = 1, count do
        local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
        paintMapTile(panel, x + pad + col * (tileW + gap), ty + row * (tileH + gap), tileW, tileH, i, maps[i], result)
    end
    ty = ty + rows * (tileH + gap)
    local index = count
    if optionH > 0 then
        local ow = math.floor((w - pad * 2 - (extras - 1) * gap) / extras)
        local ox = x + pad
        if RE.MapVote.allowExtend then
            index = index + 1
            paintOptionTile(panel, ox, ty, ow, optionH, index, "extend", "Extend this map", result)
            ox = ox + ow + gap
        end
        if RE.MapVote.allowRandom then
            index = index + 1
            paintOptionTile(panel, ox, ty, ow, optionH, index, "random", "Random map", result)
        end
        ty = ty + optionH + gap
    end
    -- U3.3: the one vote hint (keys and a click cast here), right-aligned on the reroll row while the ballot is open
    local hints = not result and voteHints(index, true) or nil
    local hintY = ty + math.floor((rerollH - u(20)) / 2)
    -- reroll (SolidMapVote's own button state, so the label and the gate are the addon's, not ours)
    local M = rawget(_G, "SolidMapVote")
    if istable(M) and isfunction(M.RerollButtonState) then
        local ok, label, enabled, tip = pcall(M.RerollButtonState, result ~= nil)
        if ok then
            local bw = u(150)
            local hintW = hints and S.hintWidth(hints) + u(16) or 0
            local voted = istable(M.rerollState) and istable(M.rerollState.voters) and IsValid(LocalPlayer()) and M.rerollState.voters[LocalPlayer():SteamID64()]
            K.Card(x + pad, ty, bw, rerollH, T.card, enabled and (voted and T.green or K.Alpha(T.edge, 200)) or K.Alpha(T.edge, 90))
            text(tostring(label or "REROLL"), 11, 700, x + pad + bw / 2, ty + rerollH / 2, enabled and (voted and T.green or T.text) or LOCKED, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            text(fit(tostring(tip or ""), 10, 500, w - pad * 2 - bw - u(10) - hintW), 10, 500, x + pad + bw + u(10), ty + rerollH / 2, T.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            if enabled and not result then addHit(panel, x + pad, ty, bw, rerollH, requestReroll) end
        end
        if hints then S.hints(hints, x + w - pad, hintY, TEXT_ALIGN_RIGHT) end
    elseif hints then
        S.hints(hints, x + pad, hintY)
    end
end

-- The header's facts for RE.HeaderText (U3.1): the result only matters to it while the winner card has not told it.
local function headerText()
    local result = RE.MapVote.result
    return RE.HeaderText({winner = winnerLabel(), told = winnerTold(), mode = modeLabel(), map = mapInfo(game.GetMap()).displayname or game.GetMap(),
        final = final(), extended = result ~= nil and result.real == "extend", voteOpen = RE.MapVote.active})
end

local function paintHeader(panel, x, y, w, h)
    local state, zbT = roundState()
    -- U3.1: the mode, the map and what happens next; the round's result and length were the winner card's to say
    local title, isResult, caption = headerText()
    if caption ~= "" then text(caption, 11, 700, x, y, T.muted) end
    if title ~= "" then text(fit(title, 40, 800, w - u(360)), 40, 800, x, y + u(16), isResult and T.gold or T.text) end
    -- the sub line is the mutation alone (canvas: police/survivor facts cut)
    local mutation = RE.CopsSummary and RE.CopsSummary.mutation ~= "" and RE.CopsSummary.mutation or nil
    if mutation then text(fit("Mutation: " .. mutation, 13, 500, w - u(400)), 13, 500, x, y + h - u(18), T.muted) end
    -- right side: what happens next as a red pill, and what is queued behind it
    local pill, clockStr
    if RE.MapVote.active then
        pill = RE.MapVote.result and (RE.MapVote.result.real == "extend" and "Map extended" or "Changing map") or "Map vote open"
        if not RE.MapVote.result then clockStr = K.Clock(math.max(0, RE.MapVote.finish - CurTime())) end
    elseif zbT and isnumber(zbT.END_TIME) and state == 3 then
        local left = zbT.END_TIME - CurTime()
        if left > 0 then pill, clockStr = "Next round", K.Clock(left) end
    elseif state == 0 then
        pill = "Preparing the next round"
    end
    if pill then
        local label = clockStr and (pill .. "   ·   " .. clockStr) or pill
        local tw = measure(label, 13, 700) + u(24)
        draw.RoundedBox(4, x + w - tw, y + u(4), tw, u(30), K.Alpha(T.main, 220))
        text(label, 13, 700, x + w - tw / 2, y + u(19), T.white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    local queued = queuedPillTitle()
    if queued then text("Queued after this: " .. queued, 11, 500, x + w, y + h - u(18), T.muted, TEXT_ALIGN_RIGHT) end
end

-- The ballot's natural height for a column of width w (mirrors paintMapBallot's own arithmetic).
local function ballotHeight(w)
    local pad = u(16)
    local maps = RE.MapVote.maps
    local count = math.min(#maps, 6)
    local extras = (RE.MapVote.allowExtend and 1 or 0) + (RE.MapVote.allowRandom and 1 or 0)
    local cols, gap = count > 3 and 3 or math.max(1, count), u(10)
    local rows = math.max(1, math.ceil(count / cols))
    local tileW = math.floor((w - pad * 2 - (cols - 1) * gap) / cols)
    local tileH = math.floor(tileW * 9 / 16) + u(24)
    local hgt = pad + u(20) + u(12) + (RE.MapVote.result and u(24) or 0) + rows * (tileH + gap) + (extras > 0 and (u(34) + gap) or 0) + u(30) + pad
    return hgt
end

-- === side card (postround_20260925) ============================================================================
-- Owner 2026-09-25: "some players dislike the highlight screen and just want to observe the post-round chaos ...
-- suppress the highlight screen into a side panel that doesn't obscure vision for living players; I don't want to
-- steal their input". While the local player is ALIVE (or `zc_goobos_roundend_side 1`), the round end is a card on
-- the right, clear of the voice column: the highlight plays inside it (no sound, the killcam leaves the world and the
-- HUD alone, cl_part_06 V.UISide), no cursor, no Space skip, and the number keys stay the player's own unless the
-- server sets zc_postround_alive_vote 1. Dead players keep the full panel.
local sideCv = CreateClientConVar("zc_goobos_roundend_side", "0", true, false, "Round end: 0 = side card while alive, full panel when dead; 1 = always the side card")
function RE.Side()
    if sideCv:GetBool() then return true end
    local me = LocalPlayer()
    return IsValid(me) and me:Alive() and me:Team() ~= TEAM_SPECTATOR
end
local function aliveVoteKeys() return GetGlobalBool("zc_postround_alive_vote", false) end
-- Whether the number keys cast the MODE vote right now: the "roundend.mode" key handler's own gate (P.SetKeys below),
-- read by the hints too so a card only shows "1–N Vote" when the keys really vote (U3.3).
local function modeKeysOk()
    if not RE.ModeVote.active or RE.MapVote.active or not live() then return false end
    return not (intermission() and RE.Side() and not aliveVoteKeys()) -- postround_20260925: a living player's keys stay theirs
end
-- ballot_alive_20260926: the MAP ballot is the one vote a living player has no other way to cast (the addon's own menu
-- is blocked while this panel holds the vote, and the side card has no cursor), so its number keys are always taken
-- while it is open. zc_postround_alive_vote still governs the mode vote.
local function aliveMapKeys() return aliveVoteKeys() or (RE.MapVote.active and RE.MapVote.result == nil and roundState() == 3) end -- final review 2026-09-26: never during prep (state 0), where 1-9 pick weapons
-- postround2_20260925 (owner 2026-09-25: living players vote with the number keys, zc_postround_alive_vote 1): the
-- open map ballot as numbered choices, in ballot order (ballotChoices: maps, then extend, then random), wrapped over at
-- most three rows; the last row is trimmed to the card if a long ballot still overflows.
local function sideBallotRows(width)
    local rows, cur = {}, ""
    for i, choice in ipairs(ballotChoices()) do
        local label = choice == "extend" and "EXTEND" or choice == "random" and "RANDOM" or string.upper(mapInfo(choice).displayname or choice)
        local item = string.format("%s%d %s", RE.MapVote.myVote == choice and "*" or "", i, label)
        local joined = cur == "" and item or (cur .. "   " .. item)
        if cur ~= "" and #rows < 2 and measure(joined, 10, 700) > width then
            rows[#rows + 1] = cur
            cur = item
        else
            cur = joined
        end
    end
    if cur ~= "" then rows[#rows + 1] = cur end
    return rows
end
-- The side card's one label for its frame: what the frame holds right now.
function RE.SideSubtitle(isFinal, recap)
    if isFinal then return "MAP REEL" end
    return recap and "ROUND RECAP" or "HIGHLIGHT OF THE ROUND"
end
RE.HighlightMeta = highlightMeta
local function paintSide(panel, w, h)
    local cw = math.min(u(440), math.floor(w * 0.32))
    local x = w - P.RightGutter() - cw - u(24)
    local y = math.floor(h * 0.14)
    local pad = u(12)
    local iw = cw - pad * 2
    local ih = math.floor(iw * 9 / 16)
    local hasVote = RE.ModeVote.active or final()
    local keysOk = aliveVoteKeys() or not RE.Side()
    local ballot = hasVote and not RE.ModeVote.active and (keysOk or aliveMapKeys()) and RE.MapVote.active and not RE.MapVote.result and sideBallotRows(iw) or nil
    K.HudPlate(x, y, cw, u(52) + ih + (hasVote and (u(54) + (ballot and (#ballot - 1) * u(16) or 0)) or pad)) -- U3.4: the HUD plate (theme glass + edge)
    local _, recap = paintInset(panel, x + pad, y + u(52), iw, ih) -- before the title: see paintPanel's header note
    -- U3.1: the mode (the result only if this player's winner card never showed it), never "ROUND OVER"
    local title, isResult = headerText()
    text(fit(string.upper(title), 16, 800, iw), 16, 800, x + pad, y + u(10), isResult and T.gold or T.text)
    text(RE.SideSubtitle(final(), recap), 9, 700, x + pad, y + u(34), T.muted)
    if not hasVote then return end
    local fy = y + u(52) + ih + u(10)
    if RE.ModeVote.active then
        local parts = {}
        for i, opt in ipairs(RE.ModeVote.options) do
            local mine = RE.ModeVote.myVote == i and "*" or ""
            parts[#parts + 1] = string.format("%s%d %s %d", mine, i, opt.again and "Again" or opt.label, tonumber(RE.ModeVote.tally[i]) or 0)
        end
        text(fit("MODE VOTE   " .. table.concat(parts, "   "), 10, 700, iw), 10, 700, x + pad, fy, T.text)
        local left = K.Clock(math.max(0, (RE.ModeVote.endsAt or 0) - CurTime()))
        if modeKeysOk() then
            S.hints({voteHints(#RE.ModeVote.options)[1], {nil, left}}, x + pad, fy + u(16))
        else
            text(left, 11, 500, x + pad, fy + u(26), T.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
    elseif ballot then
        for i, row in ipairs(ballot) do text(fit(row, 10, 700, iw), 10, 700, x + pad, fy + (i - 1) * u(16), T.text) end
        S.hints(voteHints(#ballotChoices()), x + pad, fy + #ballot * u(16) + u(1))
    else
        local r = RE.MapVote.result
        local leader = r and ((isstring(r.fixed) and r.fixed ~= "" and r.fixed) or (isstring(r.real) and r.real ~= "" and r.real)) or nil
        local line = leader and ("Next map: " .. tostring(leader)) or "Map vote open"
        if r and r.real == "extend" then line = "Map extended" end -- fixed is the current map on an extend
        text(fit(line, 10, 700, iw), 10, 700, x + pad, fy, T.text)
    end
end
local function paintPanel(panel, w, h)
    clearHits(panel)
    RE.PaintCount = (RE.PaintCount or 0) + 1 -- roundend_polish_20260925: paintPrevote stamps RE.EntryPaint with it
    if not live() or RE.Phase ~= "panel" then return end
    S.U = P.Unit()
    if RE.Side() then
        if IsValid(RE.SearchEntry) and RE.SearchEntry:IsVisible() then RE.SearchEntry:SetVisible(false) end -- no cursor here: no focus to lose
        return paintSide(panel, w, h)
    end
    -- the printable area: a page margin, and the voice column's gutter on the right (canvas note, all panels)
    local pad = u(40)
    local innerX, innerW = pad, w - pad * 2 - P.RightGutter()
    local headerH = u(88)
    local bodyY = u(28) + headerH + u(14)
    local bodyH = h - bodyY - u(24)
    local gap = u(28)
    local leftW = math.floor(innerW * 0.6)
    local rightX, rightW = innerX + leftW + gap, innerW - leftW - gap
    -- left: the highlight (16:9), then the chat's dock filling the rest (canvas: "chat always docks to bottom left";
    -- the chat frame's own minimums are 384 x 180 px, not unit-scaled)
    local insetH = math.min(math.floor(leftW * 9 / 16), math.floor(bodyH * 0.62))
    local after = paintInset(panel, innerX, bodyY, leftW, insetH)
    local dockY = after + u(4)
    local dockH = math.max(180, bodyY + bodyH - dockY)
    local dockW = math.max(384, leftW)
    K.Card(innerX, dockY, dockW, dockH, DOCK_FILL, DOCK_EDGE)
    text("CHAT", 10, 700, innerX + u(12), dockY + u(8), T.muted)
    RE.Dock = {x = innerX, y = dockY, w = dockW, h = dockH}
    -- right: the votes, then the roster (canvas: the player list lives on the right, scrollable, clickable)
    if final() then
        -- the final intermission: the ballot, then the whole map's roster under it (mode vote and pre-vote are pointless)
        local bh = math.min(ballotHeight(rightW), bodyH - u(180) - u(16))
        paintMapBallot(panel, rightX, bodyY, rightW, bh)
        paintRoster(panel, rightX, bodyY + bh + u(16), rightW, bodyH - bh - u(16), true)
    else
        local modeH = modeCardHeight()
        local prevoteH = math.max(u(120), math.min(u(280), math.floor((bodyH - modeH - u(32)) * 0.45)))
        paintModeCard(panel, rightX, bodyY, rightW, modeH)
        paintPrevote(panel, rightX, bodyY + modeH + u(16), rightW, prevoteH)
        paintRoster(panel, rightX, bodyY + modeH + prevoteH + u(32), rightW, bodyH - modeH - prevoteH - u(32), false)
    end
    -- inset_bloom_20260926: the header is painted LAST. The inset is a render.RenderView in the middle of this paint and
    -- anything full-frame it triggers lands on what is already drawn; the title must not be under it.
    paintHeader(panel, innerX, u(28), innerW, headerH)
end

-- === Think: visibility, geometry, cursor rule, Space=Skip ====================================
local function wantsCursor()
    if RE.Phase ~= "panel" then return false end
    if RE.Side() then return false end
    if intermission() then return true end
    local me = LocalPlayer()
    if IsValid(me) and (not me:Alive() or me:Team() == TEAM_SPECTATOR) then return true end
    return false
end

-- prevote_sb_20260925 (owner 2026-09-25, relayed by the killcam session: "the scoreboard should ALWAYS take
-- precedence over those screens"): while ZCKillcamView.ScoreboardUp() says the scoreboard is up this panel steps aside
-- (hidden, no hotkeys; a key held through it is not a press). Feature-detected: without it nothing changes, and an
-- error in it never hides the panel.
function RE.ScoreboardUp()
    local V = rawget(_G, "ZCKillcamView")
    if not (istable(V) and isfunction(V.ScoreboardUp)) then return false end
    local ok, up = pcall(V.ScoreboardUp)
    return ok and up == true
end
local function thinkPanel(panel)
    if RE.Phase ~= "panel" or not live() then
        panel:SetVisible(false)
        if IsValid(RE.SearchEntry) then RE.SearchEntry:SetVisible(false) end
        if RE.CursorOn then gui.EnableScreenClicker(false) RE.CursorOn = false end
        return
    end
    if RE.ScoreboardUp() then
        panel:SetVisible(false)
        if IsValid(RE.SearchEntry) then RE.SearchEntry:SetVisible(false) end
        P.Track(keysDown, {KEY_SPACE})
        RE.SBHidden = true -- a hidden panel's Think never runs: "GoobOS.RoundEnd.ScoreboardReturn" brings it back
        return
    end
    RE.SBHidden = false
    panel:SetVisible(true)
    -- roundend_polish_20260925: a layout without the pre-vote card (the final ballot) hides its search box within a frame.
    -- Not toggled per paint: hiding a focused text entry drops its focus mid-typing.
    if IsValid(RE.SearchEntry) and RE.SearchEntry:IsVisible() and RE.EntryPaint ~= RE.PaintCount then RE.SearchEntry:SetVisible(false) end
    local side = RE.Side()
    if panel.zcMouse ~= not side then panel:SetMouseInputEnabled(not side) panel.zcMouse = not side end
    -- Owner, 2026-09-24: "full-screen" means the screen, not a card in a margin. The panel rises in over 0.4 s.
    local w, h = ScrW(), ScrH()
    if panel:GetWide() ~= w or panel:GetTall() ~= h then panel:SetSize(w, h) end
    local rise = 1 - K.EaseOut(K.Progress(RE.PanelBorn, PANEL_RISE))
    panel:SetPos(0, math.floor(rise * u(12)))
    panel:SetAlpha(math.floor(255 * (1 - rise)))
    if RE.Dock and not side then
        local px, py = panel:GetPos()
        P.ChatDock(px + RE.Dock.x, py + RE.Dock.y, RE.Dock.w, RE.Dock.h)
    end

    -- A broadcast (someone else pre-voting) can create RE.Prevote with only the ranking before this client ever asked;
    -- keep asking every 3 s until the personal reply (pool, yourVote, canChange) is in.
    -- no pool at all (final ballot, prevote closed) answers p = 0: once answered, stop asking (final review 2026-09-26)
    if not RE.PrevoteAnswered and (not RE.Prevote or not RE.Prevote.pool) and RealTime() - (RE.PrevoteAskedAt or -60) >= 3 then askPrevote() end

    local want = wantsCursor()
    -- The screen clicker is one global switch: the death panel stepping aside (or SolidMapVote's own close) can turn it
    -- off in the same frame this panel turned it on, and a cached "on" would never re-assert it (review 2026-09-26).
    if want ~= RE.CursorOn or (want and not vgui.CursorVisible()) then gui.EnableScreenClicker(want) RE.CursorOn = want end

    local replay = P.Replay()
    local playing = replay and replay.kind == "highlight" and replay.phase == "playing"
    if playing then RE.ReplayWatched = RE.ReplayWatched or RealTime() else RE.ReplayWatched = nil end
    -- Owner 2026-09-24 ("highlights get skipped"): a Space already held when the panel appeared used to count as a
    -- press on the very first frame. The key state is primed on entry (enterPanel), only a FRESH press counts, and
    -- not before the highlight has been on screen for SKIP_AFTER seconds. Typing into chat/console never skips.
    local skippable = playing and RealTime() - RE.ReplayWatched >= SKIP_AFTER
    if side or P.Typing() then
        P.Track(keysDown, {KEY_SPACE})
        return
    end
    if P.Edge(keysDown, KEY_SPACE) and skippable then P.Call("Skip") end
end

local function ensurePanel()
    if IsValid(RE.Panel) then return RE.Panel end
    local panel = vgui.Create("DPanel")
    panel:SetMouseInputEnabled(true)
    panel:SetKeyboardInputEnabled(false)
    panel:SetDrawOnTop(true)
    panel.hits = {}
    panel.Paint = paintPanel
    panel.Think = thinkPanel
    panel.OnMousePressed = function(s, code)
        if code ~= MOUSE_LEFT then return end
        local mx, my = s:CursorPos()
        for _, hit in ipairs(s.hits) do
            if mx >= hit.x and mx <= hit.x + hit.w and my >= hit.y and my <= hit.y + hit.h then
                hit.fn(hit.arg)
                return
            end
        end
    end
    -- the wheel scrolls the roster while the cursor is over it (canvas: "make this scrollable")
    panel.OnMouseWheeled = function(s, delta)
        local r = RE.RosterRect
        if not r then return end
        local mx, my = s:CursorPos()
        if mx < r.x or mx > r.x + r.w or my < r.y or my > r.y + r.h then return end
        RE.RosterScroll = math.Clamp((RE.RosterScroll or 0) - delta * r.row * 2, 0, r.max)
        return true
    end
    local entry = vgui.Create("DTextEntry", panel)
    entry:SetVisible(false)
    entry:SetPlaceholderText("Search maps")
    entry:SetFont(K.Font(12, 500))
    -- roundend_polish_20260925: the canvas search field (the default Derma box drew grey), filtering as you type
    entry:SetUpdateOnType(true)
    entry.OnValueChange = function(_, value) RE.PrevoteQuery = value end
    entry.Paint = function(e, ew, eh)
        K.Card(0, 0, ew, eh, TILE_FILL, e:HasFocus() and T.main or T.line)
        if e.DrawTextEntryText then e:DrawTextEntryText(T.text, T.main, T.text) end
        if (e:GetValue() or "") == "" and not e:HasFocus() then
            text("Search maps…", 11, 500, u(8), eh / 2, T.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
    end
    entry.OnEnter = function(e)
        local q = string.Trim(e:GetValue() or "")
        if q == "" then return end
        if RE.Prevote and RE.Prevote.canChange == false then return end -- locked: the server would drop it silently
        local best
        local pool = RE.Prevote and RE.Prevote.pool
        if istable(pool) then
            for _, name in ipairs(pool) do
                if A.Matches and A.Matches(name, q) then best = name break end
            end
        end
        if best then pickPrevote(best) end -- never cast raw typed text that matched no map
    end
    RE.SearchEntry = entry
    RE.Panel = panel
    return panel
end

-- PANEL:Think only runs while the panel is visible, and thinkPanel hides the panel when the phase ends, so
-- every path that enters the "panel" phase must SetVisible(true) itself (review 2026-09-24: from the second
-- round on, the hidden panel never came back).
local function enterPanel()
    if RE.Phase ~= "panel" then
        RE.PanelBorn = RealTime()
        P.Track(keysDown, {KEY_SPACE}) -- a key held through the entrance is not a press
    end
    RE.Phase = "panel"
    RE.WinnerBorn = RE.WinnerBorn or RealTime()
    ensurePanel():SetVisible(true)
end
openForVote = function()
    if RE.Phase == "panel" or not P.Enabled() then return end
    -- The ballot beat the 0.5 s poll to the 1 -> 3 edge: the poll is about to show the winner card, and advanceWinner hands
    -- over to the panel with the ballot in it. Opening now would flash the panel and then snap back to the card.
    local state = roundState()
    if state == 3 and lastRoundState == 1 then return end
    -- Only the intermission may be covered by the full panel; a mid-round vote shows as the compact card until then.
    if not intermission() then return end
    -- Owner 2026-09-24: the final intermission's ballot arrives AT round end, while the winner card is up. The card
    -- keeps its beat and hands over to the panel with the ballot already in it (advanceWinner) - never a jump cut.
    if RE.Phase == "winner" then return end
    enterPanel()
end

-- === winner card: HUDPaint only, no vgui, no cursor, no input eaten ==========================
-- The winner -> panel hand-over must NOT live in HUDPaint: while this file claims the screen (phase "winner" or
-- "panel") and a highlight plays, the killcam blanks the frame and returns from RenderScene, which skips the HUD pass
-- - so a transition checked in HUDPaint never fired once playback began and the screen stayed black for the whole
-- highlight (review 2026-09-24). Think runs every frame regardless of what RenderScene does.
local function advanceWinner()
    if RE.Phase ~= "winner" then return end
    if not P.Enabled() then RE.Phase = nil return end
    local replay = P.Replay()
    -- The summary (winner name) is sent 2.5 s of GAME time after the horn, ~4.4 real s in the round-end slow motion: hold
    -- the card for it, up to 6 s, or it only ever said "ROUND OVER" (review 2026-09-26).
    local age = RealTime() - (RE.WinnerBorn or 0)
    if (age >= WINNER_SECONDS and (RE.Summary ~= nil or age >= 6)) or (replay and replay.kind == "highlight") then enterPanel() end
end
hook.Add("Think", "GoobOS.RoundEnd.Phase", advanceWinner)
-- prevote_sb_20260925: the scoreboard hid the panel (thinkPanel) and PANEL:Think does not run while it is hidden, so
-- the return is driven from here - the same rule as enterPanel.
hook.Add("Think", "GoobOS.RoundEnd.ScoreboardReturn", function()
    local panel = RE.Panel
    if not RE.SBHidden or RE.Phase ~= "panel" or not IsValid(panel) or panel:IsVisible() or not live() or RE.ScoreboardUp() then return end
    RE.SBHidden = false
    panel:SetVisible(true)
end)

local function drawWinnerCard()
    advanceWinner()
    if RE.Phase ~= "winner" then return end
    S.U = P.Unit()
    local sw, sh = ScrW(), ScrH()
    local p = K.EaseOut(K.Progress(RE.WinnerBorn, 0.35))
    noteWinner(winnerLabel()) -- U3.1: this card is the one announcement; the panel header leaves the result to it
    if RE.Side() then
        local title = winnerLabel()
        title = title and string.upper(title) or "ROUND OVER"
        local mode = (RE.Summary and RE.Summary.mode ~= "" and RE.Summary.mode) or (RE.RoundMeta and RE.RoundMeta.mode) or ""
        local length = (RE.Summary and RE.Summary.duration) or (RE.RoundMeta and RE.RoundMeta.length)
        local sub = {}
        if mode ~= "" then sub[#sub + 1] = tostring(mode) end
        if length then sub[#sub + 1] = K.Clock(length) end
        local cw = math.min(u(520), sw - P.RightGutter() * 2)
        local x, y = sw / 2 - cw / 2, u(64) + (1 - p) * u(10)
        K.HudPlate(x, y, cw, #sub > 0 and u(58) or u(40)) -- U3.4: the HUD plate (theme glass + edge)
        text(fit(title, 22, 800, cw - u(24)), 22, 800, sw / 2, y + u(20), K.Alpha(T.text, 255 * p), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        if #sub > 0 then text(table.concat(sub, "   ·   "), 10, 500, sw / 2, y + u(42), K.Alpha(T.muted, 220 * p), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER) end
        return
    end
    -- letterbox bars close in with the round-end slow-mo (mockup frame 1), then the card fades up over them
    local bar = math.floor(sh * 0.11 * p)
    draw.RoundedBox(0, 0, 0, sw, sh, K.Alpha(T.ink, 120 * p))
    draw.RoundedBox(0, 0, 0, sw, bar, K.Alpha(T.ink, 235))
    draw.RoundedBox(0, 0, sh - bar, sw, bar, K.Alpha(T.ink, 235))
    local title = winnerLabel()
    title = title and string.upper(title) or "ROUND OVER"
    local mode = (RE.Summary and RE.Summary.mode ~= "" and RE.Summary.mode) or (RE.RoundMeta and RE.RoundMeta.mode) or ""
    local length = (RE.Summary and RE.Summary.duration) or (RE.RoundMeta and RE.RoundMeta.length)
    local sub = {}
    if mode ~= "" then sub[#sub + 1] = tostring(mode) end
    if length then sub[#sub + 1] = K.Clock(length) end
    local a = 255 * p
    surface.SetDrawColor(T.accent.r, T.accent.g, T.accent.b, a)
    surface.DrawRect(sw / 2 - u(24), sh / 2 - u(34), u(48), u(2))
    text(title, 34, 800, sw / 2, sh / 2 - u(8) + (1 - p) * u(10), K.Alpha(T.text, a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    if #sub > 0 then text(table.concat(sub, "   ·   "), 13, 500, sw / 2, sh / 2 + u(26), K.Alpha(T.muted, a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER) end
    -- U3 "every promise resolves": a player who turned killcams off is never sent the highlight
    if not killcamsOff() then text("Highlight of the round starts shortly", 11, 500, sw / 2, sh - bar - u(20), K.Alpha(T.muted, 220 * p), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER) end
end
hook.Add("HUDPaint", "GoobOS.RoundEnd.Winner", drawWinnerCard)

-- === compact mode-vote card: a vote taken over while the full panel is not up ==================
-- sh_mode_vote starts its vote the moment a round is decided, often seconds before the formal end, and the
-- addon's own HUD box is suppressed by the takeover. This is its replacement until the intermission panel opens:
-- bottom-centre, no cursor, keys 1-4 (P.SetKeys below) - never a full-screen takeover of live play.
local function drawCompactModeVote()
    if RE.Phase == "panel" or not RE.ModeVote.active or not live() or final() then return end
    S.U = P.Unit()
    local sw, sh = ScrW(), ScrH()
    -- modevote6: up to four tiles a row (six drawn modes + "Play again" = two rows)
    local options = RE.ModeVote.options
    local perRow = math.max(1, math.min(#options, 4))
    local tileRows = math.max(1, math.ceil(#options / perRow))
    local w, h = math.min(u(820), sw - P.RightGutter() * 2 - u(40)), u(118) + (tileRows - 1) * u(44)
    -- 2026-09-25 HUD pass: centred as before, but lifted to end u(24) above the stamina bar (864/1080); at
    -- sh - h - u(150) it covered the stamina bar and the status line.
    local x, y = sw / 2 - w / 2, math.floor(sh * 864 / 1080) - h - u(24)
    local p = K.EaseOut(K.Progress(RE.ModeVote.startedAt, 0.25))
    y = y + (1 - p) * u(10)
    K.Card(x, y, w, h, T.glass, K.Alpha(T.edge, 200 * p))
    local pad = u(14)
    text("MODE VOTE", 10, 700, x + pad, y + u(10), T.muted)
    local left = math.max(0, RE.ModeVote.endsAt - CurTime())
    local span = math.max(1, RE.ModeVote.length or 1)
    local bw = u(90)
    draw.RoundedBox(2, x + w - pad - u(44) - bw, y + u(14), bw, u(4), K.Alpha(T.ink, 235))
    draw.RoundedBox(2, x + w - pad - u(44) - bw, y + u(14), bw * math.Clamp(left / span, 0, 1), u(4), left < 6 and T.accent or T.main)
    text(K.Clock(left), 12, 600, x + w - pad, y + u(8), left < 6 and T.accent or T.text, TEXT_ALIGN_RIGHT)
    local total, most, bestI = 0, 0, 1
    for i, v in ipairs(RE.ModeVote.tally) do
        total = total + v
        if v > most then most, bestI = v, i end
    end
    local gap = u(8)
    local tileW = (w - pad * 2 - gap * (perRow - 1)) / perRow
    local tileH = u(36)
    local ty0 = y + u(30)
    for i, opt in ipairs(options) do
        local label = opt.again and ("Again: " .. opt.label) or opt.label
        local tx = x + pad + ((i - 1) % perRow) * (tileW + gap)
        local ty = ty0 + math.floor((i - 1) / perRow) * (tileH + gap)
        local mine = RE.ModeVote.myVote == i
        local locked = RE.ModeVote.locked[i] == true
        draw.RoundedBox(4, tx, ty, tileW, tileH, mine and K.Alpha(T.main, 90) or K.Alpha(T.card, locked and 110 or 255))
        S.keycap(tostring(i), tx + u(8), ty + u(8), locked and 0.45 or 1)
        text(fit(label, 13, 700, tileW - u(70)), 13, 700, tx + u(32), ty + u(18), locked and LOCKED or T.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        text(locked and "locked" or tostring(RE.ModeVote.tally[i]), 13, 800, tx + tileW - u(8), ty + u(18), locked and LOCKED or (mine and T.accent or T.text), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    end
    local foot
    if total < MODE_QUORUM then
        foot = string.format("At least %d votes needed  (%d/%d)", MODE_QUORUM, total, MODE_QUORUM)
    else
        foot = string.format("%s leads  ·  quorum %d met", modeOptionLabel(bestI), MODE_QUORUM)
    end
    -- U3.3: the one vote hint, bottom right, only while the number keys really vote (no cursor here: no clicks)
    local hintW = 0
    if modeKeysOk() then
        local hints = voteHints(#options)
        hintW = S.hintWidth(hints) + u(16)
        S.hints(hints, x + w - pad, y + h - u(30), TEXT_ALIGN_RIGHT)
    end
    text(fit(foot, 10, 500, w - pad * 2 - hintW), 10, 500, x + pad, y + h - u(20), T.muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
end
hook.Add("HUDPaint", "GoobOS.RoundEnd.ModeVote", drawCompactModeVote)

-- === killcam seam ownership + number-key routing =============================================
P.Claim("round", function()
    if RE.Phase ~= "winner" and RE.Phase ~= "panel" then return false end
    return RE.Side() and "side" or true
end)

P.SetKeys("roundend.mode", function(n)
    if not modeKeysOk() then return false end -- the same two gates as before, shared with the vote hints
    if n < 1 or n > math.min(#RE.ModeVote.options, MODE_MAX_OPTS) then return false end
    castMode(n)
    return true
end)

P.SetKeys("roundend.map", function(n)
    if not RE.MapVote.active or RE.MapVote.result or not live() then return false end
    -- Only while the ballot is actually on screen: not under the winner card or the death panel, not while the
    -- scoreboard hides the panel - a number key there switched no weapon and silently cast a vote (review 2026-09-26).
    if RE.Phase ~= "panel" or not IsValid(RE.Panel) or not RE.Panel:IsVisible() then return false end
    if RE.Side() and not aliveMapKeys() then return false end -- ballot_alive_20260926: see aliveMapKeys
    local choice = ballotChoices()[n]
    if not choice then return false end
    castMap(choice)
    return true
end)

-- Client diagnostic (review 2026-09-24): which receivers this file holds right now, and whether the switch reads on.
concommand.Add("zc_goobos_roundend_print", function()
    print(string.format("[GoobOS roundend] %s enabled=%s phase=%s modeVote=%s mapVote=%s result=%s prevote=%s", RE.Version,
        tostring(P.Enabled()), tostring(RE.Phase), tostring(RE.ModeVote.active), tostring(RE.MapVote.active), tostring(RE.MapVote.result ~= nil), tostring(RE.Prevote ~= nil)))
    for name, rec in pairs(RE.Wraps) do
        local current = net.Receivers[string.lower(name)]
        print(string.format("  wrap %-22s installed=%s slot=%s", name, tostring(rec.wrapper ~= nil),
            current == rec.wrapper and "ours" or (current == nil and "none" or "REPLACED")))
    end
    local M = rawget(_G, "SolidMapVote")
    local zbT = rawget(_G, "zb")
    print(string.format("  final=%s mapSummary=%s addon menu: open wrapped=%s blocked=%d removed=%d menu=%s rtv wrapped=%s dock=%s",
        tostring(final()), tostring(RE.MapSummary ~= nil), tostring(istable(M) and M.open == RE.OpenWrap), RE.MenuBlocked or 0, RE.MenuRemoved or 0,
        tostring(istable(M) and IsValid(M.Menu)), tostring(istable(zbT) and zbT.RTVMenu == RE.RTVWrap),
        RE.Dock and string.format("%dx%d", RE.Dock.w, RE.Dock.h) or "none"))
end)
