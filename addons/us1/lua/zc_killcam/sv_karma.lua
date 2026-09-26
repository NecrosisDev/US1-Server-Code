-- Z-City killcam: the EVIDENCE layer for the server's karma system.
--
-- THIS IS NOT A SECOND KARMA SYSTEM. US1 already has one, and it is more developed than anything here: the
-- gamemode's guilt library (gamemodes/zcity/gamemode/libraries/guilt) prices wrongful kills, ZCityKarmaBounties
-- sets the automatic loss on a scale by target karma, and ZCityGuiltJustice runs the F-key forgive/report review.
-- That system decides guilt and what it costs. This file does not compute karma, change karma, or argue with it.
--
-- What it adds is the one thing that system cannot do: SHOW staff what happened. The killcam already classifies
-- every death (K.Classify), so each wrongful kill is recorded here with its time, victim and map, next to the
-- player's REAL karma - which means a staff member reading a record can go and watch the incident instead of
-- taking a number's word for it.
--
-- Owner's intent, recorded: automated and intent-aware, reward helping, act on the RATE of bad acts rather than the
-- count, and work with no staff online. 2026-09-26: "deter bad gameplay, not gameplay altogether... I want them to
-- be encouraged to be good." So, as of that pass:
--   * INTENT: only an UNPROVOKED innocent-on-innocent kill is a bad act (sv_intent.lua). Shooting back at somebody
--     who shot first, or dropping somebody opening fire on a third player, is recorded for staff as "contested"
--     and never raises the rate. A ledger that flags people for defending themselves teaches nobody to be good.
--   * FORGIVENESS: when the victim forgives the killer through the guilt review (ZC_RoundStars_RecordForgive), the
--     incident is marked forgiven and leaves the rate. The victim is the best judge of intent there is.
--   * RECENT, NOT LIFETIME: the rate is over a rolling window of rounds (zc_killcam_karma_halflife), so a player who
--     had a bad week and cleaned up drops off the list, and a regular with a thousand clean rounds cannot hide a
--     fresh spree behind them. Lifetime counters are kept alongside for context.
--   * CONDUCT (owner, same day): starting trouble without a kill - knocking down an idle player (and searching
--     them), baiting somebody into a fight by holding a gun on them, breaking a box somebody else is looting and a
--     fight following. Bait and loot are flags until a fight follows (sv_intent.lua); only then do they arrive. These
--     come from sv_intent.lua's ZCKillcam_Conduct hook. Each counts toward the rate at zc_killcam_karma_conduct of a
--     bad kill (default half): enough that a player who does it every round shows up, not so much that one
--     scuffle over a crate puts anyone on the list. A traitor killed after being ambushed idle is not a good act.
--
-- THIS FILE NEVER PUNISHES ANYBODY. It keeps a ledger and computes a rate; it does not kick, ban, gag, slay, or
-- change anyone's game in any way. That is deliberate and it is not an oversight: thresholds for an automated
-- sanction are the owner's to set, and the house pattern for anything that judges players (ChatGuard) is to ship in
-- shadow mode, gather real numbers first, and only then decide what a number means. A ledger that is wrong costs a
-- line in a staff console. An automatic ban that is wrong costs a player.
--
-- Existing owner: zc_killcam. Extension seam: the recorder's ZCKillcam_Death hook, which already publishes the
-- CLASSIFIED outcome of every death (K.Classify) - so nothing here re-derives who was in the wrong. Current
-- consumer: staff, through zc_killcam_karma.
if not SERVER then return end
local K = assert(ZCKillcam, "recorder must load first")

-- 0 = off, nothing recorded. 1 = record silently. 2 = record and tell staff in chat when a rate crosses the floor.
-- There is no mode that sanctions anybody, by design (see the header).
local mode = CreateConVar("zc_killcam_karma", "0", FCVAR_ARCHIVE, "Karma ledger: 0 off, 1 record, 2 record and notify staff")
-- Nobody is judged on a handful of rounds. A new player who has one bad round is not a repeat offender, and the
-- whole point of a RATE is that it needs a denominator worth dividing by.
local MIN_ROUNDS = CreateConVar("zc_killcam_karma_rounds", "8", FCVAR_ARCHIVE, "Rounds a player must have before a rate means anything")
local FLOOR = CreateConVar("zc_killcam_karma_rate", "0.5", FCVAR_ARCHIVE, "Bad acts per round at or above which a record is worth a staff look")
-- PROVISIONAL(2026-09-26, 20 rounds is roughly an evening's play: last night's spree still shows, last month's does
-- not dominate; ratify-by: 2026-10-26)
local HALF = CreateConVar("zc_killcam_karma_halflife", "20", FCVAR_ARCHIVE, "Rounds after which a bad act counts half toward the rate (0 = never fades, lifetime rate)")
-- How long after an incident a forgiveness from its victim still clears it. Guilt cases close well inside this.
local FORGIVE_WINDOW = 3600
-- PROVISIONAL(2026-09-26, half a bad kill per conduct incident; ratify-by: 2026-10-26)
local CONDUCT = CreateConVar("zc_killcam_karma_conduct", "0.5", FCVAR_ARCHIVE, "How much one conduct incident (ambush, bait, loot break) counts toward the rate, as a fraction of an unprovoked kill (0 = shown only)")

-- The ledger is rewritten WHOLE every round end, and file.Write costs 2-23 ms on Physgun. Without pruning it grows
-- with every player who ever joined, forever, and that write turns into a hitch at the end of every round on a busy
-- server. Records untouched for KEEP_DAYS are dropped at save time, and the ledger is hard-capped: past MAX_ROWS the
-- least recently seen go first. This is also the mildest honest form of "a record should decay" - someone who has
-- not played in two months is not who the ledger is for. How fast guilt SHOULD decay for an active player is still
-- the owner's call and is deliberately not decided here.
local KEEP_DAYS = CreateConVar("zc_killcam_karma_keep", "60", FCVAR_ARCHIVE, "Days a record survives without being seen")
local MAX_ROWS = 5000
local INCIDENTS = 10 -- how many recent bad acts a record keeps the WHEN and WHO of; the counters are the long memory
local FILE = K.Root .. "/karma.json"
local ledger = K.Karma and K.Karma.ledger or nil -- survives a hot reload
if not ledger then
    ledger = {}
    local saved = file.Read(FILE, "DATA")
    if isstring(saved) then
        local got = util.JSONToTable(saved)
        if istable(got) then ledger = got end
    end
end

local K_ = {ledger = ledger, stats = (K.Karma and K.Karma.stats) or {bad = 0, good = 0, rounds = 0, saves = 0}}
K.Karma = K_
local stats = K_.stats

-- One row per SteamID64: {n = display name, r = rounds taken part in, b = bad acts, g = good acts, t = last seen,
-- d = contested kills (self-defence / stopping an attacker), fg = bad acts forgiven by their victim,
-- rr / rb = rounds and bad acts with the older ones fading (the RATE is rb / rr), pb = bad acts this round, not yet
-- folded into rb, f = was over the floor at the last round end (so staff are told once, on crossing),
-- x = conduct incidents (xa ambush, xb bait, xl loot), rx / px = the same fading / pending pair as rb / pb}.
-- Short keys because this is written to disk every round and grows with the player base, not with the round.
local function row(sid, name)
    local e = ledger[sid]
    if not e then e = {r = 0, b = 0, g = 0} ledger[sid] = e end
    -- Rows from before the rolling rate start from their lifetime numbers and fade from there, so nobody's standing
    -- jumps on the day this ships.
    if e.rr == nil then e.rr, e.rb = e.r, e.b end
    if name then e.n = name end
    e.t = os.time()
    return e
end
local function fade()
    local h = HALF:GetFloat()
    return h > 0 and 0.5 ^ (1 / h) or 1
end

-- Dropped rows are gone for good, so this runs at SAVE time only (once a round, off the hot path) and never while
-- something is reading the table.
local function prune()
    local cutoff, live = os.time() - KEEP_DAYS:GetInt() * 86400, {}
    local n = 0
    for sid, e in pairs(ledger) do
        if (e.t or 0) < cutoff then
            ledger[sid] = nil
        else
            n = n + 1
            live[n] = sid
        end
    end
    if n <= MAX_ROWS then return end
    -- Over the cap: keep the most recently seen. Sorting only happens on a server that has actually collected
    -- thousands of records, which is the only case where the cost is earned.
    table.sort(live, function(a, b) return (ledger[a].t or 0) > (ledger[b].t or 0) end)
    for i = MAX_ROWS + 1, n do ledger[live[i]] = nil end
end
K_.Prune = prune

local dirty = false
-- Count participation when it happens, not from the end-of-round roster.
-- Preserve it across a file refresh, and retain disconnected participants.
local participation = K.KarmaParticipation or {players = {}, closed = false}
K.KarmaParticipation = participation
local function participate(p)
    if mode:GetInt() <= 0 or participation.closed or not zb or zb.ROUND_STATE ~= 1 then return end
    if not IsValid(p) or p:IsBot() or not p:Alive() then return end
    local sid = p:SteamID64()
    if sid then participation.players[sid] = K.DisplayName(p) end
end
local function trackPlayers()
    for _, p in ipairs(player.GetHumans and player.GetHumans() or player.GetAll()) do participate(p) end
end
hook.Add("ZB_PreRoundStart", "ZCKillcam.KarmaParticipation", function()
    participation.players, participation.closed = {}, false
end)
hook.Add("ZB_StartRound", "ZCKillcam.KarmaParticipation", trackPlayers)
hook.Add("PlayerSpawn", "ZCKillcam.KarmaParticipation", function(p)
    timer.Simple(0, function() participate(p) end)
end)
timer.Create("ZCKillcam.KarmaParticipation", 1, 0, trackPlayers)
trackPlayers()
local function save()
    if not dirty then return end
    dirty = false
    prune()
    file.CreateDir(K.Root)
    file.Write(FILE, util.TableToJSON(ledger))
    stats.saves = stats.saves + 1
end
K_.Save = save
hook.Add("ShutDown", "ZCKillcam.KarmaSave", save)

-- The player's ACTUAL karma, from the system that owns it. Online players only: guilt_GetValue reads the gamemode's
-- SQL row through the player meta, and there is no lookup by SteamID for someone who has left. nil means "not here",
-- which the view says out loud rather than printing a misleading 100.
local function liveKarma(sid)
    for _, p in ipairs(player.GetHumans and player.GetHumans() or player.GetAll()) do
        if IsValid(p) and p:SteamID64() == sid then
            if p.guilt_GetValue then
                local ok, v = pcall(p.guilt_GetValue, p)
                if ok and v then return v end
            end
            return p.Karma
        end
    end
end
K.LiveKarma = liveKarma

-- The rate, and whether it is worth a staff look. Returns nil when there is not enough of a record to say anything,
-- which is a different answer from "clean" and is reported as such.
function K.KarmaRate(sid)
    local e = ledger[sid]
    if not e then return nil end
    if e.r < MIN_ROUNDS:GetInt() then return nil, e end
    local rr, rb = e.rr or e.r, (e.rb or e.b) + (e.pb or 0)
    local rx = (e.rx or 0) + (e.px or 0)
    return math.max(rb + rx * CONDUCT:GetFloat(), 0) / math.max(rr, 1), e
end

function K.KarmaFlagged(sid)
    local rate = K.KarmaRate(sid)
    return rate ~= nil and rate >= FLOOR:GetFloat()
end

-- Every death the recorder has already classified. "ivi" is an innocent killing an innocent - the thing players are
-- banned for, WHEN the killer started it (sv_intent.lua decides; see the header). "t_killed" is an innocent killing a traitor, which is the job, and is the one unambiguous GOOD act the
-- killcam can see without inventing a signal. A traitor killing anybody classifies as nil and is not the ledger's
-- business. Bots have no SteamID64 and keep no record: there is nobody to hold responsible.
hook.Add("ZCKillcam_Death", "ZCKillcam.Karma", function(victim, killer, tag)
    if mode:GetInt() <= 0 or not killer or not killer.id then return end
    if not zb or zb.ROUND_STATE ~= 1 or participation.closed or not (K.TraitorRound and K.TraitorRound()) then return end
    if tag ~= "ivi" and tag ~= "t_killed" then return end
    participation.players[killer.id] = killer.name
    if IsValid(victim) and not victim:IsBot() then participation.players[victim:SteamID64()] = K.DisplayName(victim) end
    local e = row(killer.id, killer.name)
    -- Without the intent layer every ivi is counted, which is how this file behaved before it existed.
    local why, ambush
    if K.JudgeDeath then why, ambush = K.JudgeDeath(victim, killer, tag) end
    if tag == "ivi" then why = why or "unprovoked" end
    if why == "defense" or why == "stopped" or why == "threatened" or why == "provoked" then
        -- Kept, so staff can still see a player whose every teamkill is somehow "self-defence", but never rated.
        e.d = (e.d or 0) + 1
        stats.contested = (stats.contested or 0) + 1
        local list = e.i
        if not list then list = {} e.i = list end
        list[#list + 1] = {t = os.time(), v = IsValid(victim) and K.DisplayName(victim) or "?", m = game.GetMap(),
            vs = IsValid(victim) and not victim:IsBot() and victim:SteamID64() or nil, w = why}
        while #list > INCIDENTS do table.remove(list, 1) end
    elseif tag == "ivi" then
        e.b = e.b + 1
        e.pb = (e.pb or 0) + 1
        stats.bad = stats.bad + 1
        -- A number with no way to reach the evidence is not a moderation tool, it is an accusation. Each bad act
        -- keeps WHEN and WHO, so a staff member reading a record can go straight to the round tape for that moment
        -- (zc_killcam_tape) instead of being told only that someone "has a bad rate". Capped at INCIDENTS so the
        -- ledger stays a small file however long a player plays; the counters above are the long memory.
        local list = e.i
        if not list then list = {} e.i = list end
        list[#list + 1] = {t = os.time(), v = IsValid(victim) and K.DisplayName(victim) or "?", m = game.GetMap(),
            vs = IsValid(victim) and not victim:IsBot() and victim:SteamID64() or nil}
        while #list > INCIDENTS do table.remove(list, 1) end
    elseif ambush then
        -- The traitor was found by knocking them down while idle: the kill stands, the credit does not. The ambush
        -- itself was already recorded as conduct when it happened.
        stats.ambushKills = (stats.ambushKills or 0) + 1
    else
        e.g = e.g + 1
        stats.good = stats.good + 1
    end
    dirty = true
end)

-- Conduct incidents from sv_intent.lua. Already filtered there to traitor rounds and non-traitor offenders.
-- "search" is not a new incident: it marks the ambush it followed, so staff see "knocked down idle, then searched".
local CONDUCT_KEY = {ambush = "xa", bait = "xb", loot = "xl"}
hook.Add("ZCKillcam_Conduct", "ZCKillcam.Karma", function(kind, offender, victim, detail)
    if mode:GetInt() <= 0 or not zb or zb.ROUND_STATE ~= 1 or participation.closed then return end
    if not IsValid(offender) or offender:IsBot() then return end
    local sid = offender:SteamID64()
    if not sid then return end
    local vs = IsValid(victim) and not victim:IsBot() and victim:SteamID64() or nil
    local e = row(sid, K.DisplayName(offender))
    participation.players[sid] = e.n
    local list = e.i
    if not list then list = {} e.i = list end
    if kind == "search" then
        for i = #list, 1, -1 do
            local inc = list[i]
            if inc.k == "ambush" and inc.vs == vs and not inc.s then
                inc.s = true
                inc.tr = inc.tr or (detail and detail.traitor) or nil
                dirty = true
                return
            end
        end
        return
    end
    local key = CONDUCT_KEY[kind]
    if not key then return end
    e.x = (e.x or 0) + 1
    e[key] = (e[key] or 0) + 1
    e.px = (e.px or 0) + 1
    stats.conduct = (stats.conduct or 0) + 1
    list[#list + 1] = {t = os.time(), v = IsValid(victim) and K.DisplayName(victim) or "?", m = game.GetMap(), vs = vs, k = kind,
        tr = detail and detail.traitor or nil}
    while #list > INCIDENTS do table.remove(list, 1) end
    dirty = true
end)

-- The denominator. A round each player was actually present for, counted once, at the end - so someone who joins
-- during the intermission does not get a free round, and someone who leaves mid-round still wears the one they played.
hook.Add("ZB_EndRound", "ZCKillcam.Karma", function()
    if participation.closed then return end
    participation.closed = true
    if mode:GetInt() <= 0 then return end
    stats.rounds = stats.rounds + 1
    local d = fade()
    for sid, name in pairs(participation.players) do
        if sid then
            local e = row(sid, name)
            e.r = e.r + 1
            -- The round folds in: older rounds and older bad acts fade by the same factor, so the rate is a weighted
            -- average over recent play and a clean round always pulls it down.
            e.rr = e.rr * d + 1
            e.rb = math.max(e.rb * d + (e.pb or 0), 0)
            e.pb = nil
            if e.rx or e.px then
                e.rx = math.max((e.rx or 0) * d + (e.px or 0), 0)
                e.px = nil
            end
            dirty = true
            -- Told ONCE, when the rate crosses the floor - not every round the player stays over it. A staff chat
            -- that repeats the same name every round gets tuned out, and then it is not a moderation tool either.
            local flagged = K.KarmaFlagged(sid)
            if flagged and not e.f and mode:GetInt() >= 2 then
                local rate = K.KarmaRate(sid)
                for _, staff in ipairs(player.GetAll()) do
                    if K.IsOperator and K.IsOperator(staff) then
                        staff:ChatPrint(string.format("[Killcam] %s: %.2f bad acts/round recently (unprovoked teamkills, plus ambushes/baits/loot breaks at %.1f each; %d rounds played). Review context: zc_killcam_karma %s",
                            e.n or sid, rate, CONDUCT:GetFloat(), e.r, sid))
                    end
                end
            end
            e.f = flagged or nil
        end
    end
    save()
end)

-- The guilt review's forgive (zc_guilt_justice: legacy_server.lua doForgive, menu.lua) - the victim saying "that was
-- fine". The newest unforgiven bad act by this killer on this victim, inside FORGIVE_WINDOW, leaves the rate; it
-- stays in the incident list, marked, so a pattern of friends forgiving each other is still visible to staff.
-- Works in any mode setting above 0, including for a forgiveness that lands after the round that held the kill.
hook.Add("ZC_RoundStars_RecordForgive", "ZCKillcam.Karma", function(victim, killer)
    if mode:GetInt() <= 0 or not IsValid(victim) or not IsValid(killer) or not victim.SteamID64 or not killer.SteamID64 then return end
    local vs, e = victim:SteamID64(), ledger[killer:SteamID64()]
    if not e or not e.i then return end
    local cutoff = os.time() - FORGIVE_WINDOW
    for i = #e.i, 1, -1 do
        local inc = e.i[i]
        if inc.vs == vs and not inc.w and not inc.k and not inc.f and (inc.t or 0) >= cutoff then
            inc.f = true
            e.b = math.max(e.b - 1, 0)
            e.fg = (e.fg or 0) + 1
            if (e.pb or 0) > 0 then e.pb = e.pb - 1 else e.rb = math.max((e.rb or 0) - 1, 0) end
            stats.forgiven = (stats.forgiven or 0) + 1
            dirty = true
            return
        end
    end
end)

-- Staff read the ledger; nothing else does. No argument lists everyone worth a look, so "who should I watch" is one
-- command with no typing. An argument is part of a name or a SteamID64.
concommand.Add("zc_killcam_karma", function(p, _, args)
    if IsValid(p) and not (K.IsOperator and K.IsOperator(p)) then return end
    local function say(text) if IsValid(p) then p:PrintMessage(HUD_PRINTCONSOLE, "[Killcam] " .. text) else print("[Killcam] " .. text) end end
    local text = string.Trim(table.concat(args, " "))
    if text == "" then
        local n = 0
        for sid, e in pairs(ledger) do
            local rate = K.KarmaRate(sid)
            if rate and rate >= FLOOR:GetFloat() then
                n = n + 1
                say(string.format("%-24s %.2f bad/round recently  (%d unprovoked, %d conduct, %d contested, %d forgiven, %d traitors killed, %d rounds)  %s",
                    e.n or "?", rate, e.b, e.x or 0, e.d or 0, e.fg or 0, e.g, e.r, sid))
            end
        end
        return say(n == 0 and "nobody is above the floor (zc_killcam_karma_rate). Give a name or SteamID64 for one record." or (n .. " above the floor"))
    end
    local needle = string.lower(text)
    local found = 0
    for sid, e in pairs(ledger) do
        if sid == text or (e.n and string.find(string.lower(e.n), needle, 1, true)) then
            found = found + 1
            local rate, entry = K.KarmaRate(sid)
            local karma = liveKarma(sid)
            say(string.format("%s (%s)  karma %s", e.n or "?", sid, karma and string.format("%.0f", karma) or "(offline - karma not readable)"))
            say(string.format("  killcam evidence: %d unprovoked innocent-on-innocent, %d contested (self-defence / threatened first / stopping an attacker), %d forgiven by the victim, %d traitors killed, %d rounds",
                e.b, e.d or 0, e.fg or 0, e.g, e.r))
            say(string.format("  conduct: %d ambushes on idle players, %d baits (held a gun on someone until they fired), %d loot boxes broken under someone else",
                e.xa or 0, e.xb or 0, e.xl or 0))
            say("  recent rate: " .. (rate and string.format("%.2f bad/round%s", rate, rate >= FLOOR:GetFloat() and " ** review context **" or "")
                    or string.format("too few rounds to judge (needs %d, has %d)", MIN_ROUNDS:GetInt(), entry and entry.r or 0)))
            local mark = {defense = " [self-defence: victim struck first]", threatened = " [victim held a gun on them / squared up first]",
                provoked = " [victim broke the box they were looting]",
                stopped = " [stopped the victim attacking someone]"}
            local verb = {ambush = "knocked down idle player", bait = "baited into a fight (held a gun on / squared up to)", loot = "broke the box being looted by (a fight followed)"}
            for _, inc in ipairs(e.i or {}) do
                say(string.format("    %s  %s %s on %s%s%s%s%s", os.date("%Y-%m-%d %H:%M", inc.t), verb[inc.k] or "killed", inc.v or "?", inc.m or "?",
                    mark[inc.w] or "", inc.s and " [then searched them]" or "", inc.tr and " [victim was a traitor]" or "", inc.f and " [forgiven]" or ""))
            end
        end
    end
    if found == 0 then say("no record matches '" .. text .. "'") end
end)
