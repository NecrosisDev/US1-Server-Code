-- Z-City killcam: highlight of the round.
-- While a round runs, every burst of kills is scored from the recorder's event ring. When a burst beats the round's
-- best so far, it is cut straight away (the sample rings only reach back 20 s) from the side of the player who did the
-- most in it. When the round ends the best cut is sent to everyone allowed to see it, and the intermission is held
-- until it has played. It rides the life sequence's channel and player (kind = "highlight"): no new net string.
-- Owner, 2026-09-21: "show the most action-packed moment to all players at the end of the round, holding the
-- intermission until the clip is done showing".
if not SERVER then return end
local K = assert(ZCKillcam, "recorder must load first")
assert(K.Cut and K.SendBlob and K.Life, "clips, net and life sequence must load first")

K.Highlight = K.Highlight or {}
local H = K.Highlight
H.Version = "20260926.hl9"

-- PROVISIONAL(2026-09-21, window and weights are first guesses; tune from the per-round pick line in the server log, ratify-by: 2026-10-05)
local PRE, POST, MAX_LEN, RADIUS = 4, 1.5, 8, 1200 -- seconds before the first kill, after the last, longest window; who is in the scene
local KILL, HEAD, MULTI, CROWD, DMG_CAP = 100, 40, 60, 15, 100 -- per kill, per headshot kill, per extra kill by the star, per participant past two, damage counted per victim
-- The client slows to SLOW between these moments (seconds around the peak kill); shorter than a death replay's, to keep the hold short.
local SLOW_FROM, SLOW_TO, SLOW = -0.6, 0.4, 0.25
local CARD, FADES, GM_FADE, HOLD_MAX, PACK_TIME = 1.25, 1.0, 1.5, 20, 1 -- title card, curtains, the gamemode's own fade to black, longest extension, packing and transfer
H.Tuning = {Pre = PRE, Post = POST, MaxLen = MAX_LEN, Kill = KILL, Head = HEAD, Multi = MULTI, Crowd = CROWD, DmgCap = DMG_CAP, HoldMax = HOLD_MAX}

local enabled = CreateConVar("zc_killcam_highlight", "1", FCVAR_ARCHIVE, "Score and cut the round's best moment: 0 off, 1 on")
-- PROVISIONAL(2026-09-21, owner rule: player-facing killcam surfaces stay staff-only on US1 until he opens them; 0 until he has seen it, ratify-by: 2026-10-21)
local show = CreateConVar("zc_killcam_highlight_show", "2", FCVAR_ARCHIVE, "Who is shown the highlight at round end: 0 nobody, 1 admins only, 2 everyone") -- 2: owner, 2026-09-21 (see zc_killcam_flash)
local hold = CreateConVar("zc_killcam_highlight_hold", "1", FCVAR_ARCHIVE, "Hold the intermission until the highlight has played (only when somebody is shown it)")
-- PROVISIONAL(2026-09-22, 120 clears an ordinary clean kill (~200) and rejects a lone bot or through-wall one (~45);
-- tune it from the "scored N, under M" line in the server log, ratify-by: 2026-10-22)
local minScore = CreateConVar("zc_killcam_highlight_min", "120", FCVAR_ARCHIVE, "Lowest score worth showing as the round's highlight; under it the round's heaviest killcam is shown instead (0 = show anything)")

local stats = H.stats or {rounds = 0, bursts = 0, cuts = 0, shown = 0, held = 0, errors = 0, unstuck = 0, max = {}, last = "none yet"}
H.stats = stats
local function book(stage, began)
    local cost = SysTime() - began
    if cost > (stats.max[stage] or 0) then stats.max[stage] = cost end
end

-- Moved up from below (adversarial review 2026-09-24) so the zckc_hl_done receiver can use it too -
-- see the long comment where it used to live, further down: a killcam bug sharing a dispatch with
-- the round system, or with an external hook.Run listener, must cost a log line, never the round.
local function fenced(name, fn)
    return function(...)
        local ok, err = pcall(fn, ...)
        if not ok then
            stats.errors = stats.errors + 1
            stats.lastError = name .. ": " .. tostring(err)
            print("[Killcam] " .. stats.lastError)
        end
    end
end

local EV_HIT, EV_DEATH = K.Kinds.hit, K.Kinds.death
local HEADSHOT = 1 -- HITGROUP_HEAD
-- What a reel is worth is not what the scoreboard says: it is what the camera can SHOW. A kill landed through a wall
-- is invisible, and a bot dying is not a moment. Damage the star SURVIVED is the opposite - it is most of the drama.
local BLIND, BOT, CLUTCH = 0.25, 0.35, 0.5
-- An innocent killing an innocent in a traitor round is the thing players get BANNED for. Scored plainly it beats a
-- real play - an RDMer who mows down three teammates racks up kills, headshots and a multi-kill bonus - and the round
-- ends by showing the whole server a highlight reel of it, captioned as the best moment of the round. That is the
-- server celebrating the offence. It is discounted to near nothing instead; the clip is still CUT and still
-- reportable through the normal death replay, it just stops competing to be the reel.
-- Only an UNPROVOKED one (sv_intent.lua, 2026-09-26): an innocent who is shot first and wins the fight, or who drops
-- somebody opening fire on a third player, is the kind of play the owner wants MORE of, and burying it as an offence
-- told the server the opposite. Those score like any other kill.
local RDM = 0.1
local function isBot(slot)
    local who = K.Identity(slot)
    return who ~= nil and who.id == nil -- no SteamID64. An unknown slot is a player who left, not a bot.
end
-- The attacker's flag is stamped on every shot (sv_recorder claim()), but a player who never attacked has only the
-- `false` it was created with - so the live entity wins where there still is one, exactly as sv_recorder does when
-- it classifies a death. Wrong either way only ever costs a reel, never shows one it should not have.
local function isTraitor(slot)
    local who = K.Identity(slot)
    if not who then return false end
    local live = Player and Player(who.uid)
    if IsValid(live) and live:IsPlayer() and live:UserID() == who.uid then return live.isTraitor == true end
    return who.traitor == true
end

-- Scores the events between t0 and t1. Returns the score, the star's slot and what they did. No star, no highlight:
-- a moment needs somebody who got a kill in it.
-- Whether a's wrongful-looking attack on b was a's own doing. A kill between them this round was judged when it
-- happened (K.KillIntent); an exchange with no kill in it is judged as it stands at the window's end. With no intent
-- layer loaded the answer is "yes", which is exactly the behaviour before it existed.
local function unprovokedAt(a, b, t)
    local wa, wb = K.Identity(a), K.Identity(b)
    if not (wa and wb and K.KillIntent and K.Intent and K.Intent.Judge) then return true end
    return (K.KillIntent(wa.uid, wb.uid) or K.Intent.Judge(wa.uid, wb.uid, t)) == "unprovoked"
end

function H.Score(t0, t1)
    local by, taken, lastGroup, lastClear, seen, people = {}, {}, {}, {}, {}, 0
    local function unprovoked(a, b) return unprovokedAt(a, b, t1) end
    -- Only traitor modes have "innocent" and "traitor" at all; everywhere else every frag would read as friendly
    -- fire (K.TraitorRound, sv_clips.lua). Read once for the whole window, not per event.
    local traitorRound = K.TraitorRound and K.TraitorRound() or false
    local lawful = {} -- [attacker][victim] -> multiplier, so the tag is worked out once per pair, not per bullet
    local function worthShowing(a, b)
        if not traitorRound then return 1 end
        local row = lawful[a]
        if not row then row = {} lawful[a] = row end
        local m = row[b]
        if m == nil then
            -- UNKNOWN IS NOT GUILTY. A slot with no identity - the player left and the ring was reused, or the
            -- recorder was hot reloaded under us - reads as "not a traitor" for both sides, which would classify it
            -- ivi and quietly bury a legitimate play as if it were an offence. Only discount what is actually known.
            if not K.Identity(a) or not K.Identity(b) then
                m = 1
            else
                -- "ivi" alone. "ivt" is the hero play and "tvt" is the game working; only innocent-on-innocent is the offence.
                m = K.InstanceTag(true, isTraitor(a), isTraitor(b)) == "ivi" and RDM or 1
                if m < 1 and not unprovoked(a, b) then m = 1 end
            end
            row[b] = m
        end
        return m
    end
    K.EachEvent(t0, t1, function(t, kind, a, b, dmg, hitgroup, wep, los)
        if a == 0 or a == b then return end
        local clear = los == true or los == 1 -- the ring stores 1/0, and 0 is TRUE in Lua: never test `los` on its own
        if not seen[a] then seen[a] = true people = people + 1 end
        if not seen[b] then seen[b] = true people = people + 1 end
        local s = by[a]
        if not s then s = {kills = 0, lawful = 0, heads = 0, dmg = 0, shown = 0, victims = {}, payShown = 0, payHeads = 0, payDmg = 0} by[a] = s end
        local show = worthShowing(a, b)
        -- What the faucet pays on: the same weights with an unprovoked teamkill worth NOTHING rather than a tenth.
        -- The reel keeps its tenth (a clip must still be cuttable and reportable); an economy has no reason to pay
        -- anything at all for the act players are banned for.
        local pays = show < 1 and 0 or 1
        local look = (clear and 1 or BLIND) * (isBot(b) and BOT or 1)
        if kind == EV_HIT then
            local take = math.min(dmg, DMG_CAP - (taken[b] or 0)) -- a victim is only worth so much, however long they are shot at
            if take > 0 then
                taken[b] = (taken[b] or 0) + take
                s.dmg = s.dmg + take * look * show
                s.payDmg = s.payDmg + take * look * pays
            end
            lastGroup[b], lastClear[b] = hitgroup, clear
            s.wep = wep
        elseif kind == EV_DEATH then
            s.kills, s.peak = s.kills + 1, t
            if show >= 1 then s.lawful = s.lawful + 1 end
            -- `shown` is the kill count the SCORE uses: a kill the camera cannot show is most of a kill missing.
            local seenKill = (lastClear[b] == false and BLIND or 1) * (isBot(b) and BOT or 1)
            s.shown = s.shown + seenKill * show
            s.payShown = s.payShown + seenKill * pays
            s.victims[#s.victims + 1] = b
            if lastGroup[b] == HEADSHOT then
                local seenHead = lastClear[b] == false and BLIND or 1
                s.heads = s.heads + seenHead * show
                s.payHeads = s.payHeads + seenHead * pays
            end
        end
    end)
    local total, star, starWorth = 0, nil, 0
    for slot, s in pairs(by) do
        local worth = s.shown * KILL + s.heads * HEAD + s.dmg
        -- Kept on the row so a payer (sv_points.lua) reads the SAME weights the reel was picked by,
        -- rather than keeping a second copy of this formula that can drift away from this one.
        s.worth = worth
        s.pay = s.payShown * KILL + s.payHeads * HEAD + s.payDmg
        total = total + worth
        if s.kills > 0 and (worth > starWorth or (worth == starWorth and slot < star)) then star, starWorth = slot, worth end
    end
    if not star then return 0 end
    local s = by[star]
    -- What the star survived is half the moment: a clean sweep and a bloody one are not the same reel.
    local clutch = math.min(taken[star] or 0, DMG_CAP) * CLUTCH
    -- `by` is returned as a fifth value so a payer can reach every participant's worth, not just the
    -- star's. Purely additive: the four callers ahead of it are unchanged.
    -- The multi-kill bonus counts LAWFUL kills only. Counted on every kill, it handed an RDMer who dropped three
    -- teammates +120 on top of the discounted kills - enough to clear the floor and beat a clean single kill, which
    -- put the spree back on every screen as the round's best moment and undid the discount above.
    return total + math.max(s.lawful - 1, 0) * MULTI + math.max(people - 2, 0) * CROWD + clutch, star, s, seen, by
end

local best, burst, last -- this round's best cut; the burst of kills being waited out; the last round's packed highlight
-- The intermission hold, kept honest: `natural` is when the round would have ended on its own (captured at
-- ZB_EndRound, before anything moved it) and `heldTo` is what this file wrote, if it wrote anything. Both are the
-- watchdog's evidence, and `heldTo` being set is also what stops a second finalize() extending the round again.
local natural, heldTo
local generation, ending = 0, false

local function cutFor(t0, t1, star, s, seen, breathe)
    local origin
    K.EachSample(star, s.peak - 0.5, s.peak + 0.1, function(_, x, y, z) origin = {x = x, y = y, z = z} end)
    if not origin then return end
    local victim = s.victims[#s.victims]
    local held = s.wep
    -- A bleed-out kill has no hit inside the window: name the weapon the star was holding at the kill instead.
    if not held or held == 0 then K.EachSample(star, s.peak - 0.5, s.peak + 0.1, function(_, _, _, _, _, _, _, wep) held = wep end) end
    local parties = {}
    for slot in pairs(seen) do -- the round is over when this is shown: everyone who took part keeps their name
        local who = K.Identity(slot)
        if who then parties[slot] = {name = who.name, steam = who.steam, role = slot == star and "killer" or slot == victim and "victim" or "party"} end
    end
    if not parties[star] then return end
    local mode = CurrentRound and CurrentRound()
    local clip = K.Cut(s.peak, origin, parties, mode and mode.name or nil, "highlight", t0, t1, RADIUS, breathe)
    for i, actor in ipairs(clip.actors) do
        if actor.role == "killer" then clip.pov = i elseif actor.role == "victim" then clip.target = i end
    end
    if not clip.pov then return end
    clip.t = nil
    local names = {}
    for _, slot in ipairs(s.victims) do names[#names + 1] = parties[slot] and parties[slot].name or "?" end
    return {clip = clip, star = parties[star].name, kills = s.kills, heads = s.heads, dmg = math.Round(s.dmg), wep = K.WeaponName(held or 0) or "unknown weapon",
        victims = names, len = t1 - t0, mode = clip.mode,
        t0 = t0, t1 = t1, facts = H.SafeFacts(t0, t1, star)} -- step 1: the window (reel overlap) and the caption facts, read while the rings still hold them
end

local function evaluate()
    local b = burst
    burst = nil
    if not b or not enabled:GetBool() then return end
    local began = SysTime()
    local t1 = CurTime()
    local t0 = math.max(b.first - PRE, t1 - MAX_LEN)
    local score, star, s, seen, by = H.Score(t0, t1)
    book("score", began)
    -- Every burst is scored here and all but the round's best are thrown away a few lines down. Anything
    -- that pays out on what the camera judged worth showing hangs off this, so it sees them all; it runs
    -- before the comparison below for that reason. A listener that errors must not cost the reel.
    if by then
        local ok, err = pcall(hook.Run, "ZCKillcam_Burst", by, t0, t1, star, score)
        if not ok then stats.errors = stats.errors + 1 ErrorNoHalt("[Killcam] burst listener: " .. tostring(err) .. "\n") end
    end
    stats.bursts = stats.bursts + 1
    -- Step 1 (owner D4, 2026-09-25): while somebody who gets the v2 copy is online, this round's other moments that clear
    -- the floor are cut too (at most H.Cap.RoundKeep), so the reel can fill the intermission. Otherwise unchanged.
    local extra = star ~= nil and score >= minScore:GetInt() and #H.RoundCuts < H.Cap.RoundKeep and H.WantsV2()
    if not star or (score <= (best and best.score or 0) and not extra) then return end
    -- The cut is a job (K.Work): a slice a tick. A better burst may be scored before this one is done, so the
    -- comparison is made again when it lands.
    local token = generation
    K.Work("highlight.cut", function(breathe)
        if token ~= generation then return end
        local cut = cutFor(t0, t1, star, s, seen, breathe)
        if token ~= generation or not cut then return end
        cut.score = score
        stats.cuts = stats.cuts + 1
        if not best or score > best.score then best = cut end
        if #H.RoundCuts < H.Cap.RoundKeep then H.RoundCuts[#H.RoundCuts + 1] = cut end
    -- P1 (adversarial review 2026-09-24): a highlight cut reads the rings too, so it carries the same ring deadline
    -- as a life cut (`due`: its window's start leaving the ring); zc_killcam_work_sched 1 runs it before any packing.
    end, function() stats.errors = stats.errors + 1 end, nil, t0 + (K.RingReach or 20))
end

local function inRound() return zb ~= nil and zb.ROUND_STATE == 1 end

hook.Add("ZCKillcam_Death", "ZCKillcam.Highlight", function(_, killer)
    if not killer or not enabled:GetBool() or not inRound() then return end -- pre-round cleanup kills and post-round brawls are not the round
    local now = CurTime()
    burst = burst or {first = now}
    -- wait out the burst, but never so long that its first kill's lead-in has left the 20 s rings or the window
    local due = math.min(now + POST, burst.first + MAX_LEN - PRE)
    timer.Create("ZCKillcam.Highlight", math.max(due - now, 0), 1, evaluate)
end)

function H.Allowed(p)
    local mode = show:GetInt()
    return IsValid(p) and not p:IsBot() and (mode >= 2 or (mode == 1 and K.Trial(p))) -- mode 1: the trial audience, see sv_life.lua
end

-- How long the client takes to play it: the clip, the stretch the slow motion adds, the title card and the curtains.
-- Reserve the complete cinematic reveal even for clients with presentation disabled.
-- An explicit budget keeps cleanup and the next round behind the longest supported view.
function H.PlayTime(len) return len + (SLOW_TO - SLOW_FROM) * (1 / SLOW - 1) + CARD + FADES + 3.6 end

-- One sequence for one or more cuts: a single round's highlight, or - in the final intermission before a map change -
-- the map's reel (owner 2026-09-24), one instance per cut in the order they happened. The instance carries its own
-- star / kills / victims / round so the panel can caption each part of a reel; the top-level fields describe the last.
local function sequence(cuts, scope)
    local head = cuts[#cuts]
    local seq = {v = 3, kind = "highlight", cinematic = 1, map = game.GetMap(), t = os.time(), mode = head.mode, star = head.star, kills = head.kills, heads = head.heads,
        victims = head.victims, play = 0, slow = {SLOW_FROM * 100, SLOW_TO * 100, SLOW}, reel = #cuts > 1 and #cuts or nil, instances = {}}
    for i, cut in ipairs(cuts) do
        seq.play = seq.play + H.PlayTime(cut.len)
        seq.instances[i] = {tag = "highlight", reportable = false, attacker = cut.star, wep = cut.wep, dmg = cut.dmg, hits = cut.kills, ago = 0, clip = cut.clip,
            star = cut.star, kills = cut.kills, heads = cut.heads, victims = cut.victims, round = cut.round, mode = cut.mode, funny = cut.funny or nil,
            caps = scope and (cut.caps or {}) or nil} -- step 1: proven captions, v2 copy only; {} = nothing proven, show no label
    end
    seq.scope = scope -- step 1: "round" (this round's reel) or "map" (final intermission) on the v2 copy; nil on the everyone copy
    return seq
end
-- The map reel: the shown cut of each earlier round this map, kept for the last intermission before the map changes
-- (finalize() below). Bounded; the newest cut of a round always joins, the lowest-scoring one leaves when full.
local REEL_KEEP, REEL_MARGIN = 3, 20
H.Reel = H.Reel or {}
local function rememberCut(cut)
    local reel = H.Reel
    reel[#reel + 1] = cut
    while #reel > REEL_KEEP do
        local lowest = 1
        for i = 2, #reel do if (reel[i].score or 0) < (reel[lowest].score or 0) then lowest = i end end
        table.remove(reel, lowest)
    end
end

-- R3 addendum: the "contract for zc_vote_manager" (documented in REPORT.md) - who this round's highlight was
-- actually SENT to, and the hooks that track them watching it. A player never in the audience: opted out
-- (K.Wants), gated by zc_killcam_highlight_show/K.Trial, or a manual staff replay (zc_killcam_highlight_replay -
-- that is not the round's audience and must never touch the round's hold).
local audience = {} -- ply -> true, only ever the ROUND's own highlight, never a manual staff replay
-- Adversarial review 2026-09-24 (griefing vector, item 5): when each recipient was actually sent the
-- highlight, and how long it runs - so a zckc_hl_done that arrives implausibly fast can be told apart
-- from a real one. audienceExpected is one shared number (every recipient gets the same clip).
local sentAt, audienceExpected = {}, 0
function K.HighlightAudience()
    local out = {}
    for ply in pairs(audience) do if IsValid(ply) then out[ply] = true end end
    return out
end
-- R3: releases the intermission hold the moment nobody is left to watch, instead of waiting out the
-- precomputed worst case. GRACE/unstick below remains the backstop if this never fires for any reason
-- (in particular: a client still on the pre-patch bundle never sends zckc_hl_done at all).
local function releaseHold()
    if heldTo and zb and zb.ROUND_STATE == 3 and zb.END_TIME == heldTo then zb.END_TIME = CurTime() + 1 end
end
-- Adversarial review 2026-09-24 (item 4): the release itself (audience emptying -> releaseHold) now
-- happens BEFORE hook.Run("ZCKillcam_HighlightEnded") / "...Done", and both hook.Run calls are
-- pcalled, so an external listener (zc_vote_manager's ZCVoteManager_EarlyVoteViewerDone, or any
-- future one) throwing can never stop the round's own hold from being released.
local function runHook(name, ...)
    local ok, err = pcall(hook.Run, name, ...)
    if not ok then
        stats.errors = stats.errors + 1
        stats.lastError = name .. " listener: " .. tostring(err)
        print("[Killcam] " .. stats.lastError)
    end
end
local function audienceEnded()
    if next(audience) == nil then return end
    audience, sentAt, H.ExpectedFor = {}, {}, {}
    runHook("ZCKillcam_HighlightEnded")
end
local function audienceDone(ply)
    if not audience[ply] then return end
    audience[ply], sentAt[ply] = nil, nil
    if H.ExpectedFor then H.ExpectedFor[ply] = nil end
    if next(audience) == nil then audienceEnded() releaseHold() end
    runHook("ZCKillcam_HighlightDone", ply)
end
util.AddNetworkString("zckc_hl_done")
local nextDone = {}
net.Receive("zckc_hl_done", fenced("zckc_hl_done", function(_, ply)
    if not IsValid(ply) or not audience[ply] then return end -- only honoured from players actually sent the highlight
    local now = CurTime()
    if (nextDone[ply] or 0) > now then return end
    nextDone[ply] = now + 2
    -- Item 5: a client could send this the instant the blob arrives, releasing the hold for everyone
    -- long before anyone actually watched anything. Ignore a report earlier than half the clip's own
    -- expected play time after it was sent; count it instead of silently eating it.
    if sentAt[ply] and now - sentAt[ply] < 0.5 * ((H.ExpectedFor and H.ExpectedFor[ply]) or audienceExpected) then
        K.Drops.earlyDone = (K.Drops.earlyDone or 0) + 1
        return
    end
    audienceDone(ply)
end))
hook.Add("PlayerDisconnected", "ZCKillcam.HighlightAudience", function(ply) nextDone[ply] = nil audienceDone(ply) end)

local serial = 0
local function send(to, isRoundAudience)
    local sent = 0
    for _, p in ipairs(to) do
        -- Adversarial review 2026-09-24: only count/join the audience when K.SendBlob actually
        -- scheduled the send (it now returns true/false - sv_net.lua), not just because it was called.
        if IsValid(p) and not K.Busy(p) and K.SendBlob(p, "zckc_life", last.id, last.blob) then
            if isRoundAudience then audience[p], sentAt[p] = true, CurTime() end
            sent = sent + 1
        end
    end
    -- Item 5: `last.play` is this highlight's own expected play time, known by the time anything is
    -- ever sent (finalize() sets it before deliver() runs on either path below).
    if isRoundAudience and sent > 0 then audienceExpected = last.play or 0 end
    return sent
end
-- P1 (killcam_revitalize, 2026-09-24): the round's highlight, saved to disk once for the Replays app through the same
-- writer as a death sequence (K.Persist, sv_life.lua), filed under the "_round" owner with kind "highlight" - listed
-- to any player by zckc_index "highlights" (sv_net.lua). Only while zc_killcam_persist_missed is on. The id it is sent
-- under is not checked against the disk (8xxx serials restart with the map), so the saved copy gets a free one.
local function saveHighlight(mine, blob, breathe)
    local cut = mine.cut
    if not cut then return end -- a reel of earlier rounds' cuts only (final intermission, nothing new this round): each was saved in its own round
    local id, n = mine.id, 0
    while file.Exists(K.Root .. "/clips/" .. id .. ".dat", "DATA") and n < 50 do n = n + 1 id = mine.id .. n end
    if file.Exists(K.Root .. "/clips/" .. id .. ".dat", "DATA") then return end -- never overwrite another clip
    stats.saved = (stats.saved or 0) + 1
    K.Persist(K.HIGHLIGHT_OWNER or "_round", {id = id, blob = blob, kind = "highlight", t = os.time(), map = game.GetMap(),
        victim = table.concat(cut.victims or {}, ", "), attackers = {},
        items = {{tag = "highlight", reportable = false, attacker = cut.star, wep = cut.wep, dmg = cut.dmg}}}, breathe)
end
local function wantSave() return K.PersistMissed ~= nil and K.Persist ~= nil and K.PersistMissed() end

-- Packs the last cut if that has not been done yet, then sends it. Nothing is packed for nobody.
-- `isRoundAudience` is true ONLY from finalize(): a manual staff replay must never join the round's audience
-- or touch its hold.
local function deliver(to, isRoundAudience)
    if last.blob then
        local sent = send(to, isRoundAudience)
        if isRoundAudience and sent > 0 and not last.started then last.started = true hook.Run("ZCKillcam_HighlightStarted", K.HighlightAudience(), last.play) end
        return sent
    end
    if last.packing then return end
    local mine = last
    mine.packing = true
    local token = generation
    K.Work("highlight.pack", function(breathe)
        local blob = K.PackSequence(sequence(mine.cuts or {mine.cut}), breathe)
        serial = serial + 1
        mine.id, mine.blob, mine.packing = os.time() .. "_" .. (8000 + serial % 1000), blob, nil -- 8xxx: clear of clip and life serials
        stats.bytes = #blob
        if token == generation and mine == last then
            local sent = send(to, isRoundAudience)
            if sent > 0 then
                stats.shown = stats.shown + 1
                if isRoundAudience and not mine.started then mine.started = true hook.Run("ZCKillcam_HighlightStarted", K.HighlightAudience(), mine.play) end
                -- Owner 2026-09-24: this used to call zb:BeginReplayTransition(heldTo) 2 s after the send ("native
                -- preparation" of the next round under the replay). That transition (sv_roundsystem.lua
                -- PrepareReplayRound) runs the mode's Intermission - game.CleanUpMap() - and KillPlayers - which
                -- RESPAWNS everyone - and a living player's replay stops the same frame (cl_life.lua: "never hijack a
                -- living player's view"), so every highlight the panel showed was cut off a couple of seconds in.
                -- The next round is prepared when the intermission ends, as before that experiment.
            end
        end
        -- P1: after the send, never before it - the disk writes must not delay the reel the intermission is held for.
        if not mine.persisted and wantSave() then
            mine.persisted = true
            saveHighlight(mine, blob, breathe)
        end
    end, function() mine.packing = nil stats.errors = stats.errors + 1 end)
end

-- Owner decision, 2026-09-24: REPLACES the old "show the last death instead" fallback. When nothing clears the
-- action floor, try a "funny moment" instead; if there is none either, show nothing (a bare short intermission
-- is correct - the owner would rather show nothing than a lackluster clip).
--
-- Of the owner's list (a prop/door/vehicle inflictor, a fall, a groin hit, an explosive self-kill, a melee kill
-- with an improvised weapon), only a MELEE KILL is something this pass can actually show: every other one is a
-- death with no PLAYER attacker, and the recorder only ever cuts footage from a player's own HomigradDamage hit
-- (sv_recorder.lua's HomigradDamage hook bails when the attacker is not a player, INCLUDING attacker == victim
-- for a self-kill - so there is no clip, ever, for a prop/fall/explosive-self death under the current recorder).
-- There is also no groin hitgroup in this game (cl_analysis.lua's own HITGROUPS table: 1 head .. 7 right leg,
-- verified against the same table the client already uses to label a hit). Building any of those four would be
-- new recording, which this pass does not add - logged for the owner in REPORT.md as a follow-up decision.
-- "Improvised" is dropped too: no existing data distinguishes an improvised melee weapon from an ordinary one,
-- only weapons.GetStored(class).Category == "Melee" (SWEP.Category, already authored on every melee weapon).
local meleeCache = {} -- weapon id -> true/false, so weapons.GetStored is not called per event
local function isMelee(wep)
    if wep == nil or wep == 0 then return false end
    local hit = meleeCache[wep]
    if hit == nil then
        local class = K.WeaponName(wep)
        local stored = class and weapons and weapons.GetStored and weapons.GetStored(class)
        hit = istable(stored) and stored.Category == "Melee"
        meleeCache[wep] = hit
    end
    return hit
end
-- The killing blow's weapon for every death in [t0, t1]; the newest melee one wins (funniest is "most recent",
-- there being no better ordering available). Mirrors H.Score's own (t0, t1) window shape.
-- An unprovoked teamkill is never the funny moment (2026-09-26): with nothing clearing the floor, the fallback used to
-- pick ANY melee kill, so an innocent axing an innocent was shown to the whole server as the round's comic relief.
function H.Funny(t0, t1)
    local lastWep, pick = {}, nil
    local traitorRound = K.TraitorRound and K.TraitorRound() or false
    K.EachEvent(t0, t1, function(t, kind, a, b, _, _, wep)
        if kind == EV_HIT and wep and wep > 0 then lastWep[b] = wep end
        if kind == EV_DEATH and a and a > 0 then
            local w = lastWep[b]
            local wrong = traitorRound and K.Identity(a) and K.Identity(b) and K.InstanceTag(true, isTraitor(a), isTraitor(b)) == "ivi"
                and unprovokedAt(a, b, t)
            if isMelee(w) and not wrong and (not pick or t > pick.t) then pick = {t = t, star = a, victim = b, wep = w} end
        end
    end)
    return pick
end
local function funnyCut(t0, t1, breathe)
    local funny = H.Funny(t0, t1)
    if not funny then return nil end
    local seen = {[funny.star] = true, [funny.victim] = true}
    local s = {peak = funny.t, victims = {funny.victim}, wep = funny.wep, kills = 1, heads = 0, dmg = 0}
    local cut = cutFor(t0, t1, funny.star, s, seen, breathe)
    if not cut then return nil end
    cut.score, cut.funny = 0, true
    stats.funnies = (stats.funnies or 0) + 1
    return cut
end

-- What the server's rounds actually score. zc_killcam_highlight_min decides what EVERY player watches at the end of
-- EVERY round, and it shipped as a guess (120) with a note saying to tune it from the log - but the log rolls in
-- minutes on a busy server, so the evidence was gone before anyone could read it. Kept here instead: the last
-- SCORE_KEEP rounds, in memory only, so the floor can be set from the distribution rather than from a hunch.
-- Bounded, allocation-free after the first lap, and survives a hot reload with the rest of `stats`.
local SCORE_KEEP = 200
stats.scores = stats.scores or {}
local function bookScore(score)
    local s = stats.scores
    s[#s + 1] = score
    -- `while`, not `if`: in normal play the list grows by one a round and one trim is enough, but this table survives
    -- a hot reload, so a build with a larger SCORE_KEEP leaves a longer list behind and a single trim would never
    -- catch up. Trimming to the cap regardless costs nothing on the path that only ever adds one.
    while #s > SCORE_KEEP do table.remove(s, 1) end
end
-- The distribution, worked out on demand rather than maintained: this runs when staff ask, not every round.
function H.ScoreSpread()
    local s = stats.scores
    local n = #s
    if n == 0 then return nil end
    local sorted = {}
    for i = 1, n do sorted[i] = s[i] end
    table.sort(sorted)
    local function at(q) return sorted[math.max(1, math.min(n, math.ceil(q * n)))] end
    local floor, cleared = minScore:GetInt(), 0
    for i = 1, n do if sorted[i] >= floor then cleared = cleared + 1 end end
    return n, sorted[1], at(0.25), at(0.5), at(0.75), sorted[n], cleared
end

-- ===== Step 1 (killcam_polish, owner D4 + D5, 2026-09-25) ======================================================
-- D5, owner: "These labels HAVE to be accurate. People already call some of the highlights cheesy/stupid." A caption
-- is stamped only when recorded facts prove it; any missing input means no caption, and every caption that fires
-- prints one console line saying why ("[Killcam] caption ..."). The old labels were guessed on the client from
-- `kills` and a WEIGHTED `heads` (a blind or bot headshot counted 0.25 / 0.35 and still read "headshot kill"; any two
-- kills in 8 s read "Double kill", teamkills included).
-- D4, owner: "Clips should run for the duration of round-end." On an ordinary round the v2 copy is this round's reel:
-- the best cut plus its other moments that cleared the floor, while they fit what is left of the intermission.
-- Both reach only the trial audience (zc_killcam_trial_steamid, K.Trial) at 1: everyone else is sent the previous
-- single-cut sequence, built by the same code as before (US1 single-client test lock).
local v2 = CreateConVar("zc_killcam_highlight_v2", "1", FCVAR_ARCHIVE, "Proven captions + round reel: 0 off, 1 trial audience only (zc_killcam_trial_steamid), 2 everyone", 0, 2)
-- PROVISIONAL(2026-09-25, caption thresholds and reel margin are first guesses to be checked against the "[Killcam]
-- caption" lines and zc_killcam_life lat, ratify-by: 2026-10-09)
-- MultiGap: seconds allowed between consecutive enemy kills of a DOUBLE/TRIPLE. HeadDelay: the killing hit on the
-- head must be the victim's last hit and death must follow within this. LongU: 60 m in Source units (1 u = 1.905 cm,
-- the same 0.75 in sv_recorder's impact line uses). Slop: how far a position sample may sit from the hit (30 Hz rings).
-- ReelMargin: seconds of the intermission kept free for packing, the paced send and the gamemode's fade.
H.Cap = {MultiGap = 4.0, HeadDelay = 1.0, LongU = 3150, Metres = 0.01905, Slop = 0.1, RoundKeep = 6, ReelMargin = 8}
H.RoundCuts = H.RoundCuts or {} -- this round's cuts (the best among them), for the reel
H.Deaths = H.Deaths or {}       -- this round's deaths, facts frozen the moment they happened
H.ExpectedFor = H.ExpectedFor or {} -- [ply] = expected play time of the copy THEY were sent (v2 only; else audienceExpected)
H.KilledBy = H.KilledBy or {}   -- [victim SteamID64] = {by = killer SteamID64, t}: who last killed each player this map (REVENGE)
-- Sides. Only where a side is KNOWN is a kill of "an enemy": modes whose sides are ply:Team() were verified 2026-09-25
-- against live addons/zcity modes/* (each ends the round on zb:CheckWinner(zb:CheckAliveTeams) over Team()); gwars is
-- left out because it has a respawn path. "dm" is everyone for themself. zcity balances EVERY player onto team 0 or 1
-- in modes without OverrideSpawn (init.lua), free-for-all included, so Team() alone proves nothing. Team 0 is a real
-- team there, so only spectator and unassigned are excluded. Every other mode captions nothing until verified.
H.TeamModes = {tdm = true, cstrike = true, hl2dm = true, criresp = true, riot = true}
H.FfaModes = {dm = true}
function H.SideOf(p, modeName, traitorRound)
    if not IsValid(p) then return nil end
    if traitorRound then return p.isTraitor == true and "t" or "i" end
    if H.TeamModes[modeName] then
        local t = p:Team()
        if t == (rawget(_G, "TEAM_SPECTATOR") or 1002) or t == (rawget(_G, "TEAM_UNASSIGNED") or 1001) then return nil end
        return t
    end
    if H.FfaModes[modeName] then return "p" .. p:UserID() end
end
function H.AliveBySide(skip)
    local mode = CurrentRound and CurrentRound()
    local name, traitorRound = istable(mode) and mode.name or nil, K.TraitorRound and K.TraitorRound() or false
    local alive = {}
    for _, p in ipairs(player.GetAll()) do
        if p ~= skip and p:Alive() then
            local s = H.SideOf(p, name, traitorRound)
            if s ~= nil then alive[s] = (alive[s] or 0) + 1 end
        end
    end
    return alive, name, traitorRound
end
-- Every in-round death, frozen as it happened: both sides, who was alive the moment before, whether it avenged the
-- killer's own last death on this map. Joined to the ring's kill events by (time, killer uid, victim uid).
hook.Add("ZCKillcam_Death", "ZCKillcam.Captions", fenced("ZCKillcam_Death", function(victim, killer)
    if not (zb and zb.ROUND_STATE == 1) or not IsValid(victim) then return end
    local alive, name, traitorRound = H.AliveBySide(victim)
    local vside = H.SideOf(victim, name, traitorRound)
    if vside ~= nil then alive[vside] = (alive[vside] or 0) + 1 end -- as it stood the moment before this death
    local kp = killer and killer.slot and Entity(killer.slot)
    if not (IsValid(kp) and kp:IsPlayer() and kp:UserID() == killer.uid) then kp = nil end
    local kside = kp and H.SideOf(kp, name, traitorRound) or nil
    local enemy = vside ~= nil and kside ~= nil and vside ~= kside
    local now = CurTime()
    local vsid = not victim:IsBot() and victim:SteamID64() or nil
    local ksid = killer and killer.id or nil
    local revenge
    if vsid and ksid and ksid ~= vsid and enemy then
        local mine = H.KilledBy[ksid]
        if mine and mine.by == vsid and not mine.avenged and mine.t < now then revenge, mine.avenged = now - mine.t, true end
    end
    -- the LAST killer: a death to the world or to oneself clears it, so an old grudge never outlives a newer death
    if vsid then H.KilledBy[vsid] = (ksid and ksid ~= vsid) and {by = ksid, t = now} or nil end
    local log = H.Deaths
    if #log < 512 then
        log[#log + 1] = {t = now, kuid = killer and killer.uid, vuid = victim:UserID(), kside = kside, vside = vside, enemy = enemy, alive = alive,
            revenge = revenge, clutchable = kside ~= nil and (H.TeamModes[name] == true or (traitorRound and kside == "i"))}
    end
end))
function H.Nearest(slot, t)
    local bx, by, bz, bt
    K.EachSample(slot, t - H.Cap.Slop, t + H.Cap.Slop, function(st, x, y, z)
        if not bt or math.abs(st - t) < math.abs(bt - t) then bx, by, bz, bt = x, y, z, st end
    end)
    return bx, by, bz
end
-- The star's kills in [t0, t1] from the ring, each with its killing hit (the victim's last hit, which sv_recorder also
-- names the killer by) and the shooter-to-victim distance at that hit, joined to the death log. Read at cut time.
function H.Facts(t0, t1, star)
    local who = K.Identity(star)
    if not who then return nil end
    local lastHit, kills = {}, {}
    K.EachEvent(t0, t1, function(t, kind, a, b, _, hitgroup, _, _, uid)
        if kind == EV_HIT then
            lastHit[b] = {t = t, a = a, uid = uid, g = hitgroup}
        elseif kind == EV_DEATH and a == star and uid == who.uid and b ~= star then
            local v = K.Identity(b)
            kills[#kills + 1] = {t = t, b = b, vuid = v and v.uid, vname = v and v.name or "?", hit = lastHit[b]}
            lastHit[b] = nil
        end
    end)
    for _, k in ipairs(kills) do
        for _, d in ipairs(H.Deaths) do
            if d.t == k.t and d.kuid == who.uid and d.vuid == k.vuid then k.d = d break end
        end
        local h = k.hit
        if h and h.a == star and h.uid == who.uid then
            local ax, ay, az = H.Nearest(star, h.t)
            local vx, vy, vz = H.Nearest(k.b, h.t)
            if ax and vx then k.dist = math.sqrt((ax - vx) ^ 2 + (ay - vy) ^ 2 + (az - vz) ^ 2) end
        end
    end
    return {name = who.name, uid = who.uid, kills = kills}
end
function H.SafeFacts(t0, t1, star)
    local ok, f = pcall(H.Facts, t0, t1, star)
    if ok then return f end
    stats.errors = stats.errors + 1
    print("[Killcam] caption facts: " .. tostring(f))
end
-- Pure: facts in, captions and one reason per caption out (same order). Missing input = no caption, never a guess.
function H.Captions(f, endAlive)
    local caps, why = {}, {}
    local function add(cap, line) caps[#caps + 1], why[#why + 1] = cap, line end
    if not f then return caps, why end
    local C = H.Cap
    local foes = {}
    for _, k in ipairs(f.kills) do if k.d and k.d.enemy then foes[#foes + 1] = k end end
    if #foes == 0 then return caps, why end -- no kill in it is PROVEN to be of an enemy: nothing to celebrate
    -- CLUTCH 1vN: the last of their side alive against N >= 2 at their first enemy kill here, and the round ended with
    -- their side alive and none of the others: no one else alive at the horn AND at least N other-side deaths since.
    local first = foes[1].d
    if first.clutchable and istable(endAlive) and first.alive then
        local us, them = first.alive[first.kside] or 0, 0
        for s, n in pairs(first.alive) do if s ~= first.kside then them = them + n end end
        local won = (endAlive[first.kside] or 0) >= 1
        for s, n in pairs(endAlive) do if s ~= first.kside and n > 0 then won = false end end
        local fell = 0
        for _, d in ipairs(H.Deaths) do if d.t >= first.t and d.vside ~= nil and d.vside ~= first.kside then fell = fell + 1 end end
        if us == 1 and them >= 2 and won and fell >= them then
            add(string.format("CLUTCH 1v%d", them), string.format("last of their side alive against %d at the kill on %s; the round ended with only their side alive (%d of the other side fell after)", them, foes[1].vname, fell))
        end
    end
    for _, k in ipairs(foes) do
        if k.d.revenge then add("REVENGE", string.format("%s had killed them %.0f s earlier on this map, and no death since", k.vname, k.d.revenge)) break end
    end
    local run, most, at = 1, 1, 1
    for i = 2, #foes do
        run = foes[i].t - foes[i - 1].t <= C.MultiGap and run + 1 or 1
        if run > most then most, at = run, i end
    end
    if most >= 2 then
        local gaps = {}
        for i = at - most + 2, at do gaps[#gaps + 1] = string.format("%.1f", foes[i].t - foes[i - 1].t) end
        add(most == 2 and "DOUBLE" or most == 3 and "TRIPLE" or (most .. " KILLS"), string.format("%d enemy kills, gaps %s s (each <= %.1f s)", most, table.concat(gaps, ", "), C.MultiGap))
    end
    local heads, names = 0, {}
    for _, k in ipairs(foes) do
        local h = k.hit
        if h and h.uid == f.uid and h.g == HEADSHOT and k.t - h.t <= C.HeadDelay then
            heads = heads + 1
            names[#names + 1] = string.format("%s (died %.2f s after)", k.vname, k.t - h.t)
        end
    end
    if heads > 0 then add(heads == 1 and "HEADSHOT" or (heads .. " HEADSHOTS"), "killing hit on the head: " .. table.concat(names, ", ")) end
    local far, farName
    for _, k in ipairs(foes) do if k.dist and k.dist >= C.LongU and (not far or k.dist > far) then far, farName = k.dist, k.vname end end
    if far then
        add(string.format("LONG SHOT %d m", math.floor(far * C.Metres)), string.format("killing hit on %s from %.0f u = %.1f m (threshold %.0f m)", farName, far, far * C.Metres, C.LongU * C.Metres))
    end
    return caps, why
end
-- Captions a cut once, in the intermission of its own round (H.EndAlive is that round's), and prints why each fired.
function H.Caption(c)
    if c.caps ~= nil then return c.caps end
    local ok, caps, why = pcall(H.Captions, c.facts, H.EndAlive)
    if not ok then
        stats.errors = stats.errors + 1
        print("[Killcam] caption error: " .. tostring(caps))
        caps, why = {}, {}
    end
    c.caps = caps
    for i, line in ipairs(why) do print(string.format("[Killcam] caption %s for %s: %s", caps[i], tostring(c.star), line)) end
    return caps
end
function H.V2For(p)
    local m = v2:GetInt()
    return m >= 2 or (m == 1 and K.Trial(p))
end
function H.WantsV2()
    if v2:GetInt() <= 0 then return false end
    for _, p in ipairs(player.GetAll()) do if H.Allowed(p) and K.Wants(p) and H.V2For(p) then return true end end
    return false
end
-- The round reel: the round's cut first, then its other cuts that cleared the floor, best first, while each fits what
-- is left of the intermission and overlaps no chosen window by more than 0.5 s; played in the order they happened.
function H.RoundReel(cut, floor, endTime)
    local chosen = {cut}
    if cut.funny or not isnumber(endTime) or endTime ~= endTime or endTime == math.huge then return chosen end
    local budget = endTime - CurTime() - H.Cap.ReelMargin - H.PlayTime(cut.len)
    local pool = {}
    for _, c in ipairs(H.RoundCuts) do if c ~= cut and (c.score or 0) >= floor and c.t0 and c.t1 then pool[#pool + 1] = c end end
    table.sort(pool, function(x, y) return x.score > y.score end)
    for _, c in ipairs(pool) do
        local cost = H.PlayTime(c.len)
        local fits = cost <= budget
        for _, o in ipairs(chosen) do if fits and o.t0 and o.t1 and c.t0 < o.t1 - 0.5 and o.t0 < c.t1 - 0.5 then fits = false end end
        if fits then chosen[#chosen + 1], budget = c, budget - cost end
    end
    table.sort(chosen, function(x, y) return (x.t0 or 0) < (y.t0 or 0) end)
    for _, c in ipairs(chosen) do c.round = c.round or cut.round end
    return chosen
end
-- The v2 copy, packed AFTER the everyone copy (the work queue runs in order), so nobody else waits for it. Its own id,
-- the same lane and the same audience bookkeeping. It never moves the shared intermission deadline: the hold (when
-- zc_killcam_highlight_hold is on) stays sized to the everyone copy, and the reel was already fitted to END_TIME.
local function deliverV2(to)
    local mine = last
    if #to == 0 or not mine or not mine.v2cuts then return end
    local token = generation
    K.Work("highlight.pack", function(breathe)
        local blob = K.PackSequence(sequence(mine.v2cuts, mine.v2scope), breathe)
        serial = serial + 1
        mine.id2, mine.blob2 = os.time() .. "_" .. (8000 + serial % 1000), blob
        if token ~= generation or mine ~= last then return end
        local sent = 0
        for _, p in ipairs(to) do
            if IsValid(p) and not K.Busy(p) and K.SendBlob(p, "zckc_life", mine.id2, blob) then
                audience[p], sentAt[p] = true, CurTime()
                H.ExpectedFor[p] = mine.v2play -- the early-done guard judges the tester by THEIR reel, not the everyone clip
                sent = sent + 1
            end
        end
        stats.v2sent = (stats.v2sent or 0) + sent
        if sent > 0 and not mine.started then
            mine.started = true
            hook.Run("ZCKillcam_HighlightStarted", K.HighlightAudience(), mine.v2play)
        end
    end, function() stats.errors = stats.errors + 1 end)
end

local function finalize(breathe)
    local cut = best
    best = nil
    stats.rounds = stats.rounds + 1
    local floor = minScore:GetInt()
    -- Booked BEFORE the floor is applied: the whole point is to see what the floor is rejecting, so a round that
    -- scored under it has to be in the record too. A round with no burst at all books a 0 - "nothing happened" is
    -- a real and common outcome, and leaving it out would flatter the distribution.
    bookScore(cut and cut.score or 0)
    local pickReason = cut and "action" or nil
    if cut and cut.score < floor then
        print(string.format("[Killcam] highlight rejected: %s scored %d, under %d", tostring(cut.star), cut.score, floor))
        K.Drops.floor = (K.Drops.floor or 0) + 1
        cut, pickReason = nil, nil
    end
    -- Owner, 2026-09-24: no burst cleared the floor (or there was none). Try a funny moment instead of the old
    -- "show the last death" fallback; the window is the same reach the event ring actually has left.
    if not cut then
        local t1c = CurTime()
        cut = funnyCut(math.max(t1c - (K.RingReach or 20), 0), t1c, breathe)
        if cut then pickReason = "funny" end
    end
    stats.pickReason = pickReason or "none"
    -- Map reel (owner, 2026-09-24): the last intermission before a map change (zc_vote_manager.lua Integration 7,
    -- zc_final_intermission > 0, SolidMapVote.mapVoteDue()) plays the best of the WHOLE map, not just this round:
    -- this round's cut plus earlier rounds' shown cuts (H.Reel, newest first, as many as fit the window), in the
    -- order they happened. Every other round is unchanged: one cut, one clip.
    local cvFinal = GetConVar("zc_final_intermission")
    local finalSeconds = cvFinal and cvFinal:GetInt() or 0
    local final = finalSeconds > 0 and SolidMapVote and isfunction(SolidMapVote.mapVoteDue) and SolidMapVote.mapVoteDue() == true
    local cuts = {}
    if cut then
        cut.round = zb and zb.Roundscount or nil
        cuts[1] = cut
    end
    if final then
        -- REEL_MARGIN (adversarial pass 2026-09-24): 12 s for the pick, the pack and the fades, plus 8 s because
        -- sv_net.lua now paces delivery (160 KB/s per client, recipients queued on a 4 MB/s lane): on a full server
        -- the last player's reel starts several seconds after the first's, and every part must still end before
        -- the post-vote map change (zc_final_intermission - Post Vote Length - 3).
        local budget = math.max(15, finalSeconds - REEL_MARGIN) - (cut and H.PlayTime(cut.len) or 0)
        for i = #H.Reel, 1, -1 do
            local old = H.Reel[i]
            local cost = H.PlayTime(old.len)
            if cost <= budget then
                budget = budget - cost
                table.insert(cuts, 1, old)
            end
        end
    end
    -- Step 1: every round's cut is captioned in its own intermission (a map reel later reuses the stored captions).
    if cut then H.Caption(cut) end
    local v2cuts
    if H.WantsV2() then
        if final then v2cuts = cuts elseif cut then v2cuts = H.RoundReel(cut, floor, zb and zb.END_TIME) end
        for _, c in ipairs(v2cuts or {}) do H.Caption(c) end
    end
    if cut then rememberCut(cut) end
    if #cuts == 0 then stats.last = "nothing worth showing this round" return end
    local line
    if cut then
        line = string.format("%s: %d kill%s (%s) with %s, score %d, %.1fs%s", cut.star, cut.kills, cut.kills == 1 and "" or "s", table.concat(cut.victims, ", "), cut.wep, cut.score, cut.len, cut.funny and " [funny moment: melee kill, no burst cleared the floor]" or "")
    else
        line = "nothing new this round"
    end
    if #cuts > 1 or not cut then line = line .. string.format(" [map reel: %d cut%s for the final intermission]", #cuts, #cuts == 1 and "" or "s") end
    stats.last = line
    print("[Killcam] highlight " .. line)
    last = {cut = cut, cuts = cuts, play = 0}
    for _, c in ipairs(cuts) do last.play = last.play + H.PlayTime(c.len) end
    local to = {}
    for _, p in ipairs(player.GetAll()) do if H.Allowed(p) and K.Wants(p) then to[#to + 1] = p end end -- K.Wants: the player's own switch (sv_life.lua)
    local toV2 = {}
    if v2cuts and #v2cuts > 0 then
        last.v2cuts, last.v2scope, last.v2play = v2cuts, final and "map" or "round", 0
        for _, c in ipairs(v2cuts) do last.v2play = last.v2play + H.PlayTime(c.len) end
        for i = #to, 1, -1 do if H.V2For(to[i]) then table.insert(toV2, 1, to[i]) table.remove(to, i) end end
        local caps = {}
        for _, c in ipairs(v2cuts) do caps[#caps + 1] = (#c.caps > 0 and table.concat(c.caps, " + ") or "no caption proven") end
        print(string.format("[Killcam] highlight v2 (%s reel): %d cut%s, %.1fs, for %d player%s | %s", last.v2scope, #v2cuts, #v2cuts == 1 and "" or "s",
            last.v2play, #toV2, #toV2 == 1 and "" or "s", table.concat(caps, " | ")))
    end
    -- P1: nobody is shown it, but the Replays app still gets it: packed for nobody (no hold, no audience) and saved.
    if #to == 0 and #toV2 == 0 and wantSave() then deliver({}, false) return end
    if #to == 0 and #toV2 == 0 then return end
    -- The gamemode leaves the intermission when zb.END_TIME passes (sv_roundsystem.lua zb:EndRoundThink) and starts its
    -- own fade 1.5 s before. Only ever pushed later, only during an intermission, and never by more than HOLD_MAX.
    -- Done before packing: a 5 s intermission would otherwise start fading while the clip is still being packed.
    --
    -- This is the one place the killcam writes another system's state, and a round that never ends is the worst thing
    -- it could do to the server (owner, 2026-09-22: stuck forever unless the map changes), so every way that could
    -- happen is closed here rather than trusted:
    --   * the ceiling is measured from the round's NATURAL end, captured at ZB_EndRound, not from the live value - so
    --     running finalize() twice in one intermission cannot stack two HOLD_MAXes, and N times cannot stack N;
    --   * once per round, full stop (`heldTo` is only cleared when a round starts);
    --   * the value written has to be a finite number that is actually in the future. A NaN here would be permanent:
    --     `zb.END_TIME < CurTime()` is false for NaN, so the round system could never leave the intermission again.
    if hold:GetBool() and zb and zb.ROUND_STATE == 3 and isnumber(zb.END_TIME) and not heldTo then
        local ceiling = (natural or zb.END_TIME) + HOLD_MAX
        local want = math.min(CurTime() + PACK_TIME + last.play + GM_FADE, ceiling)
        -- want ~= want is the NaN test; a NaN fails every comparison below too, so this is belt and braces.
        if want == want and want < math.huge and want > zb.END_TIME and want <= ceiling then
            stats.held, stats.lastHold = stats.held + 1, want - zb.END_TIME
            heldTo = want
            zb.END_TIME = want
        end
    end
    if #to > 0 then deliver(to, true) elseif wantSave() then deliver({}, false) end
    deliverV2(toV2)
end

-- The intermission watchdog. Whatever the cause - this file, a future change to it, or something else on the server -
-- a round that has sat in ROUND_STATE 3 past every legitimate deadline is broken, and a player cannot fix it: the
-- round system only clears END_TIME in state 0, which it can never reach. So it is repaired here.
--
-- It is deliberately incapable of SHORTENING an intermission. It acts in exactly two cases:
--   * END_TIME is not a finite number. Nothing legitimate wants that, and it is the one value that wedges the round
--     system permanently, because every comparison against NaN is false.
--   * the value still standing is the one WE wrote, it is well past, and the round has not moved on - so the round
--     system is not acting on it. Anything else (a mode, the map vote, staff) changed it and it is not ours to touch.
-- The map vote is untouched by construction: it holds the intermission by overriding zb:PreRound, not via END_TIME.
local GRACE = 10 -- seconds past our own deadline before the round counts as wedged (zb:Think only runs once a second)
local function unstick()
    if not zb or zb.ROUND_STATE ~= 3 then return end
    local now = CurTime()
    local e = zb.END_TIME
    if e ~= nil and (not isnumber(e) or e ~= e or e == math.huge) then
        stats.unstuck = (stats.unstuck or 0) + 1
        stats.lastUnstick = "END_TIME was " .. tostring(e) .. ": the round could never have ended"
        print("[Killcam] " .. stats.lastUnstick .. " - releasing the intermission")
        zb.END_TIME = now - 1
        return
    end
    if heldTo and isnumber(e) and e == heldTo and now > heldTo + GRACE then
        stats.unstuck = (stats.unstuck or 0) + 1
        stats.lastUnstick = string.format("intermission %.0fs past the hold this file asked for", now - heldTo)
        print("[Killcam] " .. stats.lastUnstick .. " - releasing it")
        zb.END_TIME = now - 1
    end
end

-- Everything from here down (and zckc_hl_done above, adversarial review 2026-09-24) shares a hook
-- dispatch, directly or via hook.Run, with the round system itself. GMod does not pcall hook
-- callbacks, so an error thrown here stops the rest of that dispatch dead - and ZB_PreRoundStart is
-- run from the MIDDLE of zb:EndRoundThink, between `ROUND_STATE = 0` and the code that actually
-- starts the next round. A killcam bug must cost a log line, never the round.

hook.Add("ZB_EndRound", "ZCKillcam.Highlight", fenced("ZB_EndRound", function()
    if ending then return end
    ending = true
    local okAlive, endAlive = pcall(H.AliveBySide) -- step 1: who is alive at the horn, for CLUTCH
    H.EndAlive = okAlive and endAlive or nil
    if not enabled:GetBool() then best = nil return end
    -- The round's own deadline, before anything extends it. EndRoundThink fills END_TIME in on its next think, so it
    -- is usually nil right here; the fallback is what that think is about to compute.
    -- Captured ONCE. Nothing stops zb:EndRound() being called twice in one intermission - any mode or addon can call
    -- it - and re-reading END_TIME on the second call would take an already-extended value as the natural end, which
    -- is how a bounded hold turns into an unbounded one. Only a round actually starting clears it.
    if not natural then natural = isnumber(zb and zb.END_TIME) and zb.END_TIME or (CurTime() + 5) end
    timer.Create("ZCKillcam.Unstick", 1, 0, unstick)
    local token = generation
    timer.Create("ZCKillcam.HighlightEnd", POST + 0.3, 1, function() -- the round-winning kill's aftermath, and its evaluation, come first
        -- queued behind any cut still running, so the pick is made from finished cuts only
        K.Work("highlight.pick", function(breathe) if token == generation then finalize(breathe) end end, function() stats.errors = stats.errors + 1 end)
    end)
end))
local function roundOpened()
    generation = generation + 1
    ending = false
    timer.Remove("ZCKillcam.HighlightEnd")
    best, burst = nil, nil
    H.RoundCuts, H.Deaths, H.EndAlive = {}, {}, nil
    natural, heldTo = nil, nil
    timer.Remove("ZCKillcam.Highlight")
    timer.Remove("ZCKillcam.Unstick")
    audienceEnded() -- R3: a new round starting is as much "nobody is watching any more" as everyone reporting done
end
hook.Add("ZB_StartRound", "ZCKillcam.Highlight", fenced("ZB_StartRound", roundOpened))
-- Run from inside zb:EndRoundThink the moment the intermission is over, which is the earliest the hold can be retired.
hook.Add("ZB_PreRoundStart", "ZCKillcam.HighlightRelease", fenced("ZB_PreRoundStart", roundOpened))
H.Unstick = unstick -- tests, and `zc_killcam_highlight_unstick` below

-- S1.5 (work/loader/round_v2/BLUEPRINT.md): exported predicate for the round watchdog and, in
-- Stage 2, the winner card - true only while THIS file's own hold (heldTo, :331-339) is the
-- reason the intermission has not ended yet. A one-liner over existing state, no new state.
-- Restored verbatim after a rebase miss (this pass's .orig predated it); still correct against this
-- pass's own heldTo/audience additions - releaseHold() only ever moves END_TIME to CurTime()+1
-- (never clears heldTo early; heldTo is only cleared in roundOpened()), so this reads true for the
-- same ~1s grace the round system itself needs to notice, then false, exactly as before this pass.
function K.HighlightHolding()
    return heldTo ~= nil and zb ~= nil and isnumber(zb.END_TIME) and zb.END_TIME >= CurTime()
end

-- A death replay would be cut off by the highlight and the next round: none is offered once the round is ending.
function K.RoundEnding() return zb ~= nil and zb.ROUND_STATE == 3 end

-- Staff: watch the last round's highlight again, alone, without touching the round.
-- From the server console it packs the last cut and sends it to nobody: that is how the packer's cost is measured.
concommand.Add("zc_killcam_highlight_replay", function(p)
    if not IsValid(p) then
        if last then deliver({}) end
        return print(last and "[Killcam] packing the last highlight for nobody; see zc_killcam_highlight_stats" or "[Killcam] no highlight has been cut since this file loaded")
    end
    if not K.Trial(p) then return end -- the replay is a player-facing surface: trial audience only
    if not last then return p:PrintMessage(HUD_PRINTCONSOLE, "[Killcam] no highlight has been cut since this file loaded") end
    if K.Busy(p) then return end
    deliver({p})
end)

-- Staff: the same release the watchdog does, on demand. Reports what it sees either way, so a stuck round can be
-- diagnosed from in game rather than from the logs after the fact.
concommand.Add("zc_killcam_unstick", function(p)
    if IsValid(p) and not p:IsAdmin() then return end
    local before = zb and zb.END_TIME
    local line = string.format("[Killcam] round state=%s END_TIME=%s now=%.0f heldTo=%s natural=%s unstuck=%d%s",
        tostring(zb and zb.ROUND_STATE), tostring(before), CurTime(), tostring(heldTo), tostring(natural), stats.unstuck or 0,
        stats.lastUnstick and (" | last: " .. stats.lastUnstick) or "")
    if IsValid(p) then p:PrintMessage(HUD_PRINTCONSOLE, line) else print(line) end
    if not zb or zb.ROUND_STATE ~= 3 then return end
    -- By hand, the operator is the authority: release it whatever put it there.
    zb.END_TIME = CurTime() - 1
    stats.unstuck, stats.lastUnstick = (stats.unstuck or 0) + 1, "released by hand"
    print("[Killcam] intermission released by hand (was " .. tostring(before) .. ")")
end)

concommand.Add("zc_killcam_highlight_stats", function(p)
    if IsValid(p) and not p:IsAdmin() then return end
    local m = stats.max
    local line = string.format("[Killcam] highlight %s on=%d show=%d hold=%d rounds=%d bursts=%d cuts=%d shown=%d held=%d lastHold=%.1fs unstuck=%d errors=%d bytes=%d score max=%.2fms (cut and pack costs: zc_killcam_work) | last: %s (pick=%s)",
        H.Version, enabled:GetInt(), show:GetInt(), hold:GetInt(), stats.rounds, stats.bursts, stats.cuts, stats.shown, stats.held, stats.lastHold or 0, stats.unstuck or 0, stats.errors, stats.bytes or 0,
        (m.score or 0) * 1000, stats.last, tostring(stats.pickReason or "none"))
    if IsValid(p) then p:PrintMessage(HUD_PRINTCONSOLE, line) else print(line) end
    -- R4/R7: how the last round's pick was made, and the floor-rejection count (K.Drops.floor).
    local picks = string.format("[Killcam] picks: funnies=%d floorDrops=%d audience=%d (contract for zc_vote_manager: K.HighlightAudience, ZCKillcam_HighlightStarted/Done/Ended)",
        stats.funnies or 0, K.Drops and K.Drops.floor or 0, (function() local n = 0 for _ in pairs(K.HighlightAudience()) do n = n + 1 end return n end)())
    if IsValid(p) then p:PrintMessage(HUD_PRINTCONSOLE, picks) else print(picks) end
    local saved = string.format("[Killcam] highlights saved to the records: %d this map (zc_killcam_persist_missed=%d); map reel holds %d earlier cut%s", stats.saved or 0, wantSave() and 1 or 0, #H.Reel, #H.Reel == 1 and "" or "s")
    if IsValid(p) then p:PrintMessage(HUD_PRINTCONSOLE, saved) else print(saved) end
    -- The floor is the one number here that decides what every player sees, so the evidence for setting it prints
    -- right under the counters rather than in a command nobody knows to run.
    local n, lo, q1, med, q3, hi, cleared = H.ScoreSpread()
    if n then
        local spread = string.format("[Killcam] last %d rounds scored: min %d | p25 %d | median %d | p75 %d | max %d  ->  %d of %d (%d%%) clear the floor of %d",
            n, lo, q1, med, q3, hi, cleared, n, math.floor(cleared / n * 100 + 0.5), minScore:GetInt())
        if IsValid(p) then p:PrintMessage(HUD_PRINTCONSOLE, spread) else print(spread) end
    end
end)
