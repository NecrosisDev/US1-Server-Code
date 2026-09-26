-- Z-City killcam: the life sequence. "Your life flashing before your eyes."
-- Every time a player takes damage, a short capture is cut around it from the ATTACKER's side
-- (their eye position and aim are stamped exactly at the hit). When the player dies they are
-- sent every capture from that life, across all attackers, to watch in slow motion. Each
-- capture can be reported; the sequence can be saved to their record and reopened in zc_killcam.
if not SERVER then return end
local K = assert(ZCKillcam, "recorder must load first")
assert(K.SendBlob, "net layer must load first")
util.AddNetworkString("zckc_life")
util.AddNetworkString("zckc_save")
util.AddNetworkString("zckc_report")
util.AddNetworkString("zckc_watch")
-- R1(b)/R7: sent by the client when a death sequence it was given did not reach the screen, purely so the owner can
-- see the count instead of guessing at it. It changes nothing about zckc_life itself.
-- P1 (killcam_revitalize, 2026-09-24): the message now carries WHY - UInt(3) reason, then the sequence id (String):
--   0 the held-while-alive blob lapsed unclaimed (K.Drops.respawned, the 03:50 meaning; a client that sends no
--     payload at all reads as this), 1 the player respawned before the replay started (respawnedWait: it arrived
--     while they were alive, or was still waiting), 2 respawned while it played (respawnedPlay), 3 it belonged to
--     another map (map), 4 a newer sequence or the round highlight replaced it on screen (replaced).
-- The receiver is further down, after `throttled`; with zc_killcam_persist_missed on it also saves that sequence.
util.AddNetworkString("zckc_life_drop")
util.AddNetworkString("zckc_life_lat") -- M1: the client's share of the death-to-screen wait (see K.Lat below)

local PRE, POST, MERGE, MAX_LEN, MAX_PER_LIFE, RADIUS = 3, 1.2, 2, 6, 16, 700
local REPORTS_PER_HOUR, TEXT_MAX, PIN_DAYS = 6, 240, 45
K.Life = {Pre = PRE, Post = POST, Merge = MERGE, MaxPerLife = MAX_PER_LIFE}
-- R2: the sample rings only reach back this long (K.RingReach, sv_clips.lua, derived from sv_recorder's
-- K.Depth/K.HZ); a cut whose window is older than that would read data the ring has already overwritten.
local RING_REACH = K.RingReach or 20
K.Drops = K.Drops or {roundEnding = 0, backlog = 0, expired = 0, busy = 0, generation = 0, floor = 0, respawned = 0, overflow = 0, unsent = 0, earlyDone = 0}

-- 0 = nobody, 1 = ADMINS ONLY (owner, 2026-09-21: "make sure you are ONLY pushing this to admins"), 2 = everyone.
-- PROVISIONAL(2026-09-21, owner rule: player-facing killcam surfaces stay staff-only on US1 until he opens them, ratify-by: 2026-10-21)
-- 2 = everyone (owner, 2026-09-21: killcams for all players, with the player's own opt-out and a BETA notice).
-- FCVAR_ARCHIVE: on a server that has ever set this by hand the archived value still wins, so the live value has to be
-- set as well as this default changed - changing the default alone does nothing to a running server.
local audience = CreateConVar("zc_killcam_flash", "2", FCVAR_ARCHIVE, "Who gets the death sequence: 0 nobody, 1 the trial audience (zc_killcam_trial_steamid), 2 everyone")
-- WHO the trial audience is (owner, 2026-09-21: "only appears for me ... instead of all admins, until I'm ready to give
-- it to them"). The house pattern (zci_trial_steamid, zsf_trial_steamid): one SteamID64, or "admin" for every admin.
-- Matched on SteamID64, never on the name. The default IS the owner, so a restart cannot quietly widen it; he opens it
-- to staff with `zc_killcam_trial_steamid admin`. Modes 0 and 2 of zc_killcam_flash / zc_killcam_highlight_show are untouched.
local trial = CreateConVar("zc_killcam_trial_steamid", "76561198011536179", FCVAR_ARCHIVE, "Who mode 1 of the killcam shows to: one SteamID64, or 'admin' for all admins")
function K.Trial(p)
    if not IsValid(p) or p:IsBot() then return false end
    local who = string.Trim(trial:GetString())
    if who == "admin" then return p:IsAdmin() end
    if who == "" then return false end -- nobody: the guest list is off too
    local id = p:SteamID64()
    return id == who or (id ~= nil and K.TrialGuests[id] == true)
end

-- Guests (owner, 2026-09-21: "a concommand that allows me to extend it to other players that want to try it").
--   zc_killcam_trial add <part of a name | SteamID64>    remove <...>    list    clear
-- Only the player the trial convar names - or the server console - may run it; an admin may not. Kept by SteamID64 in
-- data/zc_killcam/trial_guests.txt so a map change does not drop it. A guest sees what the owner sees in mode 1:
-- the death replay and the round highlight. Nothing else is opened (records of other players stay staff-only).
local GUEST_FILE = K.Root .. "/trial_guests.txt"
K.TrialGuests = K.TrialGuests or {}
do
    local saved = file.Read(GUEST_FILE, "DATA")
    if isstring(saved) then
        K.TrialGuests = {}
        for id in string.gmatch(saved, "%d+") do if #id == 17 then K.TrialGuests[id] = true end end
    end
end
local function saveGuests()
    local list = {}
    for id in pairs(K.TrialGuests) do list[#list + 1] = id end
    table.sort(list)
    file.CreateDir(K.Root)
    file.Write(GUEST_FILE, table.concat(list, "\n"))
    return list
end
-- One online human by part of their name, or any well-formed SteamID64 (they need not be online).
local function findGuest(text)
    if string.match(text, "^%d+$") and #text == 17 then return text, text end
    local needle, found = string.lower(text), nil
    for _, q in ipairs(player.GetHumans()) do
        if string.find(string.lower(q:Nick()), needle, 1, true) then
            if found then return nil, "more than one player matches '" .. text .. "'" end
            found = q
        end
    end
    if not found then return nil, "nobody online matches '" .. text .. "'" end
    return found:SteamID64(), found:Nick()
end
concommand.Add("zc_killcam_trial", function(p, _, args)
    local function say(text) if IsValid(p) then p:PrintMessage(HUD_PRINTCONSOLE, "[Killcam] " .. text) else print("[Killcam] " .. text) end end
    if IsValid(p) and p:SteamID64() ~= string.Trim(trial:GetString()) then return end -- the owner or the console; silence for anyone else
    local verb, text = string.lower(args[1] or "list"), string.Trim(table.concat(args, " ", 2))
    if verb == "add" or verb == "remove" then
        if text == "" then return say("usage: zc_killcam_trial " .. verb .. " <part of a name | SteamID64>") end
        local id, label = findGuest(text)
        if not id then return say(label) end
        K.TrialGuests[id] = verb == "add" or nil
        saveGuests()
        return say((verb == "add" and "added " or "removed ") .. label .. " (" .. id .. ")")
    elseif verb == "clear" then
        K.TrialGuests = {}
        saveGuests()
        return say("guest list cleared")
    end
    local list = saveGuests()
    say(#list == 0 and "no guests; zc_killcam_trial add <part of a name | SteamID64>" or (#list .. " guest(s): " .. table.concat(list, ", ")))
end)
-- A player's own switch (client convar zc_killcam_show, userinfo; the Z-City settings menu lists it under Gameplay).
-- Asked only where something is sent UNASKED: what a player requests by hand still reaches them.
function K.Wants(p) return IsValid(p) and p:GetInfoNum("zc_killcam_show", 1) ~= 0 end

function K.LifeAllowed(p)
    local mode = audience:GetInt()
    return IsValid(p) and (mode >= 2 or (mode == 1 and K.Trial(p)))
end

-- P1 (killcam_revitalize, 2026-09-24): a sequence that was built but never watched - the round was ending, the
-- victim had already respawned, a previous blob was still streaming, the player had opted out of automatic replays,
-- or the client reported it never reached the screen (zckc_life_drop) - is saved to that player's records through
-- the same persist() a manual save uses, marked missed (and why) in the sidecar and the index. It is what the
-- Replays app will list. The round's highlight is saved the same way, once per round (sv_highlight.lua). Off (as
-- shipped) until the owner turns it on; K.Keep still caps each player's list.
local persistMissed = CreateConVar("zc_killcam_persist_missed", "0", FCVAR_ARCHIVE, "Save death sequences that were built but not watched to the player's records (marked missed), and each round's highlight: 0 off (as shipped), 1 on")
function K.PersistMissed() return persistMissed:GetBool() end
local persist, missedNow -- the save code, further down; the death hook below needs to reach it

-- Who hit whom. Traitor-on-innocent is the game working as intended, so it is shown but cannot be reported.
-- PROVISIONAL(2026-09-21, outside traitor modes every instance is "other": shown, not reportable, ratify-by: 2026-10-21)
function K.InstanceTag(traitorRound, attackerTraitor, victimTraitor)
    if not traitorRound then return "other" end
    if attackerTraitor then return victimTraitor and "tvt" or "tvi" end
    return victimTraitor and "ivt" or "ivi"
end
local REPORTABLE = {ivi = true, tvt = true, ivt = true}
K.Reportable = REPORTABLE

local generation = 0
local lifeTokens = {} -- player entity -> token; prevents a delayed death replay replacing a new life
-- Owner-approved 2026-09-24 (killcam_revitalize): a ragdoll get-up (homigrad/fake/sv_tier_0.lua) sets the global
-- OverrideSpawn and calls ply:Spawn() in the MIDDLE of a life - that is not a new life.
hook.Add("PlayerSpawn", "ZCKillcam.LifeToken", function(p)
    if OverrideSpawn then return end
    lifeTokens[p] = (lifeTokens[p] or 0) + 1
end)
local lives = {} -- victim slot -> {uid, list = {instances, oldest first}, open = {[attacker uid] = instance}}
hook.Add("PlayerSpawn", "ZCKillcam.LifeReset", function(p) if OverrideSpawn then return end lives[p:EntIndex()] = nil end)
hook.Add("ZB_PreRoundStart", "ZCKillcam.LifeReset", function()
    generation = generation + 1
    lives = {}
end)
local function lifeOf(slot, uid)
    local life = lives[slot]
    if not life or life.uid ~= uid then life = {uid = uid, list = {}, open = {}} lives[slot] = life end
    return life
end

local function cut(inst, breathe)
    if inst.clip then return end
    -- R2: a job that reaches the front of the queue after the ring has moved past its window would cut wrong (or
    -- empty) data. Drop it with a counter instead of cutting garbage; the queue already runs oldest first (K.Work).
    if CurTime() - inst.t0 > RING_REACH then
        inst.failed = true
        K.Drops.expired = K.Drops.expired + 1
        K.Stats.work.expired = (K.Stats.work.expired or 0) + 1 -- visible in zc_killcam_work, per R2
        if K.WorkQ and K.Backlog and #K.WorkQ > K.Backlog then K.Drops.backlog = K.Drops.backlog + 1 end
        return
    end
    local a, v = K.Identity(inst.a), K.Identity(inst.v)
    if inst.generation ~= generation or not a or not v or a.uid ~= inst.auid or v.uid ~= inst.vuid then
        inst.failed = true return
    end
    local parties = {[inst.a] = {name = inst.attacker, steam = inst.attackerSteam, role = "killer"}, [inst.v] = {name = inst.victim, steam = inst.victimSteam, role = "victim"}}
    local clip = K.Cut(inst.t0, inst.origin, parties, inst.mode, inst.tag, inst.t0 - PRE, inst.till + POST, RADIUS, breathe)
    -- K.Cut yields between actors. Recheck after it resumes as well.
    a, v = K.Identity(inst.a), K.Identity(inst.v)
    if inst.generation ~= generation or not a or not v or a.uid ~= inst.auid or v.uid ~= inst.vuid then
        inst.failed = true return
    end
    local dmg, hits = 0, 0
    for i, actor in ipairs(clip.actors) do
        if actor.role == "killer" then clip.pov = i elseif actor.role == "victim" then clip.target = i end
    end
    for _, e in ipairs(clip.events) do
        if e[2] == K.Kinds.hit and e[3] == clip.pov and e[4] == clip.target then dmg, hits = dmg + e[5], hits + 1 end
    end
    -- No victim rows means the rings were wiped under us (a hot reload of the recorder): drop it rather than show an empty scene.
    if not clip.target or not clip.pov then inst.failed = true return end
    clip.t = nil
    inst.clip, inst.dmg, inst.hits = clip, math.Round(dmg * 10) / 10, hits
end

-- Cuts run as jobs (K.Work, sv_clips.lua): a slice a tick, first in first out. An instance is queued once.
-- R2/P5 (revised, owner correction 2026-09-24): killcam reports are going to replace karma, and an opted-out
-- player is exactly the one who still needs to be ABLE to report - so the cut always happens and the sequence
-- is always held for zckc_save/zckc_report. Only the AUTOMATIC send is skipped (see the ZCKillcam_Death hook
-- below). What frees the slice for a victim who will actually be shown it: an opted-out victim's cut is queued
-- at LOW priority (K.Work's second tier, sv_clips.lua) - it still runs, just behind every cut that will be
-- watched, and it is still subject to the same ring-age expiry as everything else (see `cut()` above).
local function queueCut(inst)
    if inst.clip or inst.failed or inst.queued then return end
    local victim = inst.vuid and Player and Player(inst.vuid)
    local lowPriority = IsValid(victim) and victim:UserID() == inst.vuid and not K.Wants(victim)
    inst.queued = true
    K.Stats.instCuts = (K.Stats.instCuts or 0) + 1
    -- due: the moment this cut's window leaves the ring (the same test cut() applies); zc_killcam_work_sched 1 orders by it
    K.Work("life.cut", function(breathe) cut(inst, breathe) end, function() inst.failed = true end, lowPriority, inst.t0 + RING_REACH)
end
-- R6: named so a disconnect can cancel it outright instead of letting it fire against an invalid entity.
local function settleTimerName(inst) return "ZCKillcam.Settle." .. tostring(inst) end
local function settle(inst)
    timer.Create(settleTimerName(inst), POST + 0.1, 1, function()
        if inst.clip or inst.queued then return end
        if CurTime() - inst.till < POST and CurTime() - inst.t0 < MAX_LEN + POST then return settle(inst) end -- still being hit
        queueCut(inst)
    end)
end

hook.Add("ZCKillcam_Hit", "ZCKillcam.Instance", function(attacker, victim, a, v, wep)
    local now = CurTime()
    local life = lifeOf(v, victim:UserID())
    local auid = attacker:UserID()
    local inst = life.open[auid]
    if inst and not inst.clip and not inst.queued and not inst.failed and now - inst.till <= MERGE and now - inst.t0 <= MAX_LEN then inst.till = now return end -- same burst
    local pos = victim:GetPos()
    local mode = CurrentRound and CurrentRound()
    inst = {generation = generation, auid = auid, vuid = victim:UserID(), t0 = now, till = now, a = a, v = v, attacker = K.DisplayName(attacker), attackerSteam = K.SteamName and K.SteamName(attacker), victimSteam = K.SteamName and K.SteamName(victim), aid = not attacker:IsBot() and attacker:SteamID64() or nil,
        victim = K.DisplayName(victim), wep = K.WeaponName(wep), origin = {x = pos.x, y = pos.y, z = pos.z}, mode = mode and mode.name or nil,
        tag = K.InstanceTag(K.TraitorRound(), attacker.isTraitor == true, victim.isTraitor == true)}
    life.open[auid] = inst
    life.list[#life.list + 1] = inst
    if #life.list > MAX_PER_LIFE then table.remove(life.list, 1) end
    settle(inst)
end)

-- One finished sequence per player is held in memory until their next death; saving or reporting writes it to disk.
local held = {} -- SteamID64 -> {id, blob, items = {per-instance summary}, attackers = {[i] = sid64}, t, map, victim, saved}
K.Held = held
local serial = 0

-- The round's heaviest single killcam, kept so the highlight can fall back to it when no burst was worth showing
-- (owner, 2026-09-22; sv_highlight.lua heaviestCut). ONE clip reference, replaced only when beaten and dropped at the
-- start of the next round - a deliberate exception to the rule above that only the packed blob stays in memory.
local heaviest
function K.Heaviest() return heaviest end
hook.Add("ZB_StartRound", "ZCKillcam.LifeHeaviest", function() heaviest = nil end)

local function build(victim, life, death)
    local seq = {v = 3, kind = "life", map = game.GetMap(), t = os.time(), victim = victim.name, instances = {}}
    local attackers = {}
    for _, inst in ipairs(life.list) do
        if inst.clip then
            seq.instances[#seq.instances + 1] = {tag = inst.tag, reportable = REPORTABLE[inst.tag] == true, attacker = inst.attacker, wep = inst.wep,
                dmg = inst.dmg, hits = inst.hits, ago = math.Round((death - inst.t0) * 10) / 10, clip = inst.clip}
            attackers[#seq.instances] = inst.aid
            seq.mode = seq.mode or inst.mode
        end
    end
    return seq, attackers
end

-- M1 (killcam_polish, 2026-09-24): where the death-to-screen wait goes. One row per death that had hits, the last
-- LAT_KEEP kept. Server stamps are SysTime() (wall clock, finer than a tick): t0 = death hook, settle = the settle
-- timer fired, packStart = the pack job got its first slice (every cut queued before it had finished), packDone,
-- sent (+ delay = the shared wire lane's start delay, span = first->last chunk timer, from K.SendBlob). The client
-- adds its own three spans by zckc_life_lat: first->last chunk received, decode, last chunk->first replay frame.
-- `zc_killcam_life lat` prints the rows and the averages. Measurement only: nothing reads these but that command.
local LAT_KEEP = 40
K.Lat = K.Lat or {rows = {}, byId = {}}
local function latRow(sid)
    local rows = K.Lat.rows
    local row = {sid = sid, t0 = SysTime()}
    rows[#rows + 1] = row
    if #rows > LAT_KEEP then
        local old = table.remove(rows, 1)
        if old.id then K.Lat.byId[old.id] = nil end
    end
    return row
end

hook.Add("ZCKillcam_Death", "ZCKillcam.Life", function(victim)
    local slot = victim:EntIndex()
    local life = lives[slot]
    lives[slot] = nil -- the next life starts clean whatever happens below
    if not life or life.uid ~= victim:UserID() or #life.list == 0 then return end
    local who = {name = K.DisplayName(victim), sid = not victim:IsBot() and victim:SteamID64() or nil}
    if not who.sid then return end
    local death = CurTime()
    local lat = latRow(who.sid) -- M1
    local roundToken, token, uid = generation, lifeTokens[victim], victim:UserID()
    -- P1: WHY the victim is no longer the one who died, instead of one yes/no. "gone": left, or the slot is someone
    -- else now. "round": a new round started. "respawned": the same player, alive again (respawn modes). Only "ok" is
    -- ever sent. With zc_killcam_persist_missed on, "round" and "respawned" are still built and saved (missed) rather
    -- than dropped; either way each stop is counted - before this, a stop inside the pack job was silent.
    local function state()
        if not IsValid(victim) or victim:UserID() ~= uid then return "gone" end
        if generation ~= roundToken then return "round" end
        if lifeTokens[victim] ~= token then return "respawned" end
        return "ok"
    end
    local function keep(st) return st == "ok" or (persistMissed:GetBool() and (st == "round" or st == "respawned")) end
    local function lost(st)
        if st == "respawned" then K.Drops.respawnedPack = (K.Drops.respawnedPack or 0) + 1 else K.Drops.generation = K.Drops.generation + 1 end
    end
    local inRound = zb == nil or zb.ROUND_STATE == 1 -- read NOW: the cut below lands after the round may have ended
    -- R1(a): wait only as long as the ring needs to actually hold the last hit's aftermath (till + POST), not
    -- always the old flat POST+0.3 (1.5s) - this can only ever fire SOONER, never later, than before.
    local maxTill = death
    for _, inst in ipairs(life.list) do if inst.till > maxTill then maxTill = inst.till end end
    local wait = math.Clamp((maxTill + POST) - death, 0.1, POST + 0.3)
    timer.Create("ZCKillcam.Death." .. slot, wait, 1, function() -- R6: named, so a disconnect can cancel it
        lat.settle = SysTime() -- M1
        local st = state()
        if not keep(st) then lat.stop = st return lost(st) end
        -- Jobs run in order: every cut queued here, or earlier, is finished before the sequence is built and packed.
        for _, inst in ipairs(life.list) do queueCut(inst) end
        K.Work("life.pack", function(breathe)
            lat.packStart = SysTime() -- M1: every cut queued above has finished by now (jobs run in order)
            st = state()
            if not keep(st) then lat.stop = st return lost(st) end
            local seq, attackers = build(who, life, death)
            if #seq.instances == 0 then K.Drops.empty = (K.Drops.empty or 0) + 1 lat.stop = "empty" return end
            for _, inst in ipairs(seq.instances) do -- see `heaviest` above: taken before packing, while the clips still exist
                -- Only deaths from INSIDE the round, judged when they happened: pre-round cleanup and post-round
                -- brawls are not the round, and the highlight excludes them too (sv_highlight.lua inRound).
                if inRound and inst.clip and (not heaviest or (inst.dmg or 0) > heaviest.dmg) then
                    heaviest = {clip = inst.clip, dmg = inst.dmg or 0, attacker = inst.attacker, wep = inst.wep, victim = who.name}
                end
            end
            -- P2 (killcam_revitalize, 2026-09-24): the head-to-head for the death panel - both players' numbers for this
            -- life, what they traded, how it ended, lifetime rows - from lua/autorun/server/zc_killcam_ledger.lua, which
            -- answers nil while zc_killcam_ledger is 0. An additive field of the sequence: a client that does not know it
            -- never reads it. Fenced: a ledger bug costs the panel its numbers, never the replay. `death` picks the
            -- snapshot of THIS death (the player may have died again before this job ran).
            if K.LifeH2H then
                local ok, h2h = pcall(K.LifeH2H, who.sid, death)
                if ok and istable(h2h) then seq.h2h = h2h end
            end
            breathe("life.build")
            local blob = K.PackSequence(seq, breathe)
            lat.packDone, lat.bytes = SysTime(), #blob -- M1
            st = state()
            if not keep(st) then lat.stop = st return lost(st) end
            local id -- 9xxx keeps clear of per-kill clip serials; never reuse an id that is already on disk or held
            repeat
                serial = serial + 1
                id = os.time() .. "_" .. (9000 + serial)
                local taken = file.Exists(K.Root .. "/clips/" .. id .. ".dat", "DATA")
                for _, other in pairs(held) do if other.id == id then taken = true end end
            until not taken
            lat.id = id K.Lat.byId[id] = lat -- M1: the client's report names this id
            -- Only the packed blob and a one-line summary per instance stay in memory, not the sample tables.
            local items = {}
            for i, inst in ipairs(seq.instances) do items[i] = {tag = inst.tag, reportable = inst.reportable, attacker = inst.attacker, wep = inst.wep, dmg = inst.dmg} end
            local h = {id = id, blob = blob, items = items, attackers = attackers, t = seq.t, map = seq.map, victim = seq.victim, seq = K.KeepSeq and seq or nil}
            -- P1: with persisting on, the sequence before this one stays reachable (one step, no further) so a
            -- zckc_life_drop that names it - it was replaced on screen by this one - can still save it.
            local before = held[who.sid]
            if persistMissed:GetBool() and before then before.prev = nil h.prev = before end
            held[who.sid] = h
            K.Stats.lives = (K.Stats.lives or 0) + 1
            K.Stats.lifeBytes = (K.Stats.lifeBytes or 0) + #blob
            if st ~= "ok" then -- built for the records only: the victim is alive again, or the round moved on
                lat.stop = st
                lost(st)
                return missedNow(who.sid, h, st == "respawned" and "respawnedPack" or "round", breathe)
            end
            -- Owner, 2026-09-21: a death replay for everyone, "unless the round is ending" - the highlight owns that moment.
            local ending = K.RoundEnding ~= nil and K.RoundEnding()
            -- R7: count each reason a ready sequence did NOT reach the screen, so "not shown" is a number.
            -- R2/P5 (revised): the sequence is always built and held (zckc_save/zckc_report work regardless);
            -- only the AUTOMATIC send is skipped for an opted-out player, counted as "unsent" - not a failure,
            -- just never pushed unasked.
            local allowed = IsValid(victim) and K.LifeAllowed(victim)
            local wants = allowed and K.Wants(victim)
            -- P1: every reason a sequence is not sent now also saves it (missed), when zc_killcam_persist_missed is on.
            if allowed and not wants then K.Drops.unsent = K.Drops.unsent + 1 missedNow(who.sid, h, "unsent", breathe) lat.stop = "unsent"
            elseif wants and ending then K.Drops.roundEnding = K.Drops.roundEnding + 1 missedNow(who.sid, h, "roundEnding", breathe) lat.stop = "roundEnding"
            elseif wants and K.Busy(victim) then K.Drops.busy = K.Drops.busy + 1 missedNow(who.sid, h, "busy", breathe) lat.stop = "busy"
            elseif wants then
                local sent, delay, span, chunks = K.SendBlob(victim, "zckc_life", id, blob)
                if sent then
                    K.Stats.lifeSent = (K.Stats.lifeSent or 0) + 1
                    lat.sent, lat.delay, lat.span, lat.chunks = SysTime(), delay or 0, span or 0, chunks or 0 -- M1
                else lat.stop = "refused" end
            else lat.stop = "notAllowed" end
        end)
    end)
end)
hook.Add("PlayerDisconnected", "ZCKillcam.LifeForget", function(p)
    lifeTokens[p] = nil
    local slot = p:EntIndex()
    -- R6: a settle() or death timer left running against a slot nobody occupies any more is a resource leak,
    -- not a crash (the closures already guard IsValid/UserID), but there is no reason to let it fire at all.
    local life = lives[slot]
    if life then for _, inst in ipairs(life.list) do timer.Remove(settleTimerName(inst)) end end
    timer.Remove("ZCKillcam.Death." .. slot)
    lives[slot] = nil
    local sid = p:SteamID64()
    if sid then held[sid] = nil end -- a saved sequence lives on disk; nothing is lost
end)

----------------------------------------------------------------- save
-- P1 (killcam_revitalize, 2026-09-24): the ONE clip writer, now also used for missed sequences and the round
-- highlight (K.Persist). h.kind = "highlight" files it under the "_round" owner with tag "highlight"; h.missed /
-- h.reason mark a sequence nobody watched. All three are additive fields in the sidecar and the index rows (a row
-- without them is a plain life save, exactly as before). `breathe` (optional, inside a K.Work job) hands the tick
-- back between the four writes - file.Write measured 2-23 ms on Physgun. `saving` stops a manual zckc_save that
-- lands between two of those writes from starting a second copy. It is a timestamp, not a flag (adversarial review
-- 2026-09-24): a save that died half way must not block every later one, so after SAVE_STALE seconds it is retried.
local SAVE_STALE = 30
local function saving(h) return h.saving ~= nil and CurTime() - h.saving < SAVE_STALE end
function persist(sid, h, breathe)
    if h.saved or saving(h) then return end
    h.saving = CurTime()
    breathe = breathe or function() end
    local highlight = h.kind == "highlight"
    local tag = highlight and "highlight" or "life"
    file.Write(K.Root .. "/clips/" .. h.id .. ".dat", h.blob)
    breathe("persist.clip")
    -- The sidecar lets a later report be validated without unpacking the sequence.
    file.Write(K.Root .. "/clips/" .. h.id .. ".meta.json", util.TableToJSON({owner = sid, attackers = h.attackers, items = h.items, kind = h.kind, missed = h.missed, reason = h.reason}))
    breathe("persist.meta")
    local top = h.items[#h.items]
    local entry = {clip = h.id, t = h.t, map = h.map, tag = tag, role = highlight and "highlight" or "victim", other = top and top.attacker or "?", reported = false, kind = h.kind, missed = h.missed, reason = h.reason}
    local list = K.Index(sid)
    table.insert(list, 1, entry)
    while #list > K.Keep do table.remove(list) end
    file.Write(K.Root .. "/index/" .. sid .. ".json", util.TableToJSON(list))
    breathe("persist.index")
    local all = K.AllIndex()
    table.insert(all, 1, {clip = h.id, t = h.t, map = h.map, tag = tag, killer = entry.other, victim = h.victim, missed = h.missed})
    while #all > 300 do table.remove(all) end
    file.Write(K.Root .. "/index/_all.json", util.TableToJSON(all))
    h.saved, h.saving = true, nil
end
K.Persist = persist

-- Saves a sequence nobody watched, when the switch is on. Inside a job pass `breathe`; from anywhere else it is
-- queued as a job of its own (low tier, never expired - it reads no ring), so a net message never writes to disk.
function missedNow(sid, h, reason, breathe)
    -- h.missed: already queued or saved as missed once - a second drop report for the same id counts nothing more
    if not persistMissed:GetBool() or not h or h.saved or h.missed or saving(h) then return end
    h.missed, h.reason = true, reason
    K.Stats.missedSaved = (K.Stats.missedSaved or 0) + 1
    if breathe then return persist(sid, h, breathe) end
    K.Work("life.persist", function(b) persist(sid, h, b) end, nil, true, nil, true)
end

local nextAsk = {} -- per player, per request kind: saving must not swallow a report sent a moment later
local function throttled(p, kind, gap)
    local slot = nextAsk[p] or {}
    nextAsk[p] = slot
    local now = CurTime()
    if (slot[kind] or 0) > now then return true end
    slot[kind] = now + gap
end
hook.Add("PlayerDisconnected", "ZCKillcam.LifeThrottle", function(p) nextAsk[p] = nil end)

-- zckc_life_drop (see the top of this file): count the reason; with persisting on, save the sequence it names if it
-- is still held for that player (the current one, or the one it replaced). Only ever the sender's OWN sequence.
local DROP_KEYS = {[0] = "respawned", [1] = "respawnedWait", [2] = "respawnedPlay", [3] = "map", [4] = "replaced"}
net.Receive("zckc_life_drop", function(_, p)
    if not IsValid(p) or throttled(p, "drop", 0.25) then return end
    local reason = net.ReadUInt(3)
    local key = DROP_KEYS[reason] or "respawned"
    K.Drops[key] = (K.Drops[key] or 0) + 1
    local id = net.ReadString()
    if not persistMissed:GetBool() or not K.LifeAllowed(p) or #id > 24 or not string.match(id, "^%d+_%d+$") then return end
    local sid = p:SteamID64()
    local h = sid and held[sid]
    if h and h.id ~= id then h = h.prev end
    if h and h.id == id then missedNow(sid, h, key) end
end)

local function answer(p, name, id, code)
    net.Start(name)
    net.WriteString(id)
    net.WriteUInt(code, 3)
    net.Send(p)
end

net.Receive("zckc_save", function(_, p)
    if not K.LifeAllowed(p) or throttled(p, "save", 2) then return end
    local sid = p:SteamID64()
    local h = sid and held[sid]
    if not h then return answer(p, "zckc_save", "", 2) end
    persist(sid, h)
    answer(p, "zckc_save", h.id, 0)
end)

----------------------------------------------------------------- report
-- codes: 0 filed, 1 not yours, 2 gone, 3 not reportable, 4 already reported, 5 hourly limit
local function sanitize(text)
    text = string.gsub(string.sub(text or "", 1, TEXT_MAX), "[%c]", " ")
    return string.Trim(text)
end

local filed = {} -- sid -> {timestamps}
local function overLimit(sid, now)
    local list, kept = filed[sid] or {}, {}
    for _, t in ipairs(list) do if now - t < 3600 then kept[#kept + 1] = t end end
    filed[sid] = kept
    return #kept >= REPORTS_PER_HOUR
end

net.Receive("zckc_report", function(_, p)
    if not K.LifeAllowed(p) or throttled(p, "report", 2) then return end
    local id, index, text = net.ReadString(), net.ReadUInt(5), sanitize(net.ReadString())
    local sid = p:SteamID64()
    if not sid or #id > 24 or not string.match(id, "^%d+_%d+$") then return end
    local h = held[sid]
    local inst, attackerId, already
    local path = K.Root .. "/reports/" .. id .. ".json"
    local report = util.JSONToTable(file.Read(path, "DATA") or "") or {clip = id, by = sid, name = p:Nick(), items = {}}
    if h and h.id == id then
        inst, attackerId = h.items[index], h.attackers[index]
    else
        -- A saved sequence: only its owner may report from it, and the sidecar says who that is.
        local meta = util.JSONToTable(file.Read(K.Root .. "/clips/" .. id .. ".meta.json", "DATA") or "")
        if not istable(meta) then return answer(p, "zckc_report", id, 2) end
        if meta.owner ~= sid then return answer(p, "zckc_report", id, 1) end
        if not istable(meta.items) or not file.Exists(K.Root .. "/clips/" .. id .. ".dat", "DATA") then return answer(p, "zckc_report", id, 2) end
        -- JSON may hand sparse numeric keys back as strings
        inst = meta.items[index] or meta.items[tostring(index)]
        attackerId = istable(meta.attackers) and (meta.attackers[index] or meta.attackers[tostring(index)]) or nil
    end
    if not istable(report) or report.by ~= sid or not istable(report.items) then
        return answer(p, "zckc_report", id, 2)
    end
    if not istable(inst) then return answer(p, "zckc_report", id, 2) end
    if inst.reportable ~= true then return answer(p, "zckc_report", id, 3) end
    for _, item in ipairs(report.items) do if istable(item) and tonumber(item.instance) == index then already = true end end
    if already then return answer(p, "zckc_report", id, 4) end
    local now = os.time()
    if overLimit(sid, now) then return answer(p, "zckc_report", id, 5) end
    table.insert(filed[sid], now)
    if h and h.id == id then persist(sid, h) end
    file.CreateDir(K.Root .. "/reports")
    report.items[#report.items + 1] = {instance = index, t = now, by = p:Nick(), tag = inst.tag, attacker = inst.attacker, attackerId = attackerId, wep = inst.wep, dmg = inst.dmg, text = text, state = "open"}
    file.Write(path, util.TableToJSON(report))
    local pinned = K.Submitted()
    pinned[id] = now + PIN_DAYS * 86400
    file.Write(K.Root .. "/pinned.json", util.TableToJSON(pinned))
    local list = K.Index(sid)
    for _, e in ipairs(list) do if e.clip == id then e.reported = true end end
    file.Write(K.Root .. "/index/" .. sid .. ".json", util.TableToJSON(list))
    for _, staff in ipairs(player.GetAll()) do
        if K.IsOperator(staff) then staff:ChatPrint(string.format("[Killcam] %s reported %s (%s, %s dmg). Open it with: zc_killcam submitted", p:Nick(), inst.attacker, inst.tag, tostring(inst.dmg))) end
    end
    answer(p, "zckc_report", id, 0)
end)

-- === Inside a killcam: who is in one, and going quiet while they are =============================================
-- A killcam takes the screen for a few seconds. For that moment the watcher is out of the round: their spectator
-- input is locked (client side, cl_life.lua) and their voice is cut, both ways. HIGHLIGHTS ARE DELIBERATELY NOT
-- MUTED - the reel plays at round end while people talk about the round and vote on the next map, and the owner
-- asked for that carve-out by name. The client simply does not claim to be watching during a highlight.
--
-- The DEADLINE is the load-bearing half. Restoring someone's voice must not depend on their client behaving: a
-- crash, an alt-F4, a dropped packet or a hot reload must all end in voice back on. So a claim EXPIRES on its own
-- and the client has to keep re-asserting it; the explicit "stopped" message only makes it instant.
local WATCH_GRACE = 5 -- seconds a single claim is good for; the client re-asserts about twice that often
local watching = {}   -- UserID -> CurTime() the claim lapses at. UserID, not SteamID64: bots have no SteamID64.
net.Receive("zckc_watch", function(_, ply)
    if not IsValid(ply) then return end
    watching[ply:UserID()] = net.ReadBool() and (CurTime() + WATCH_GRACE) or nil
end)

local function inKillcam(ply)
    if not IsValid(ply) or not ply:IsPlayer() then return false end
    local till = watching[ply:UserID()]
    return till ~= nil and till > CurTime()
end
K.InKillcam = inKillcam

-- Voice rides the gamemode's OWN seam. All voice on this server goes through PlayerCanHearPlayersVoice
-- "RealisticVoice" (homigrad/sv_comunication.lua), which runs HG_PlayerCanHearPlayersVoice and returns the first
-- non-nil answer it gets; combine radio, zombie voice and brain damage already extend it. Using that seam instead
-- of adding another PlayerCanHearPlayersVoice hook keeps this clear of ULX's gag hooks, the persistent-gag addon
-- and zc_micbox, none of which should have to know the killcam exists.
--
-- Both directions are cut: someone inside a killcam neither hears the round nor talks over it.
--
-- PROVISIONAL(2026-09-22, hook.Run returns the FIRST non-nil answer and GMod does not order hooks, so a handler
-- that returns TRUE first - combine radio or zombie voice, for their own factions - can win the race and leave
-- that one pair audible through a killcam. Never observed; ordering would mean taking over the outer hook and
-- fighting ULX for it, which is worse. ratify-by: 2026-11-01)
-- postround_20260925 (owner 2026-09-25: "voice chat takes precedence during killcams ... do not suppress its audio"):
-- the cut is now opt-in. With zc_killcam_hush 0 (default) a player in a killcam hears and is heard exactly as the
-- gamemode's own rules say for a dead player (sv_comunication.lua ChatLogic; post-round everyone hears everyone).
-- The watching claims above stay (K.InKillcam), so zc_killcam_hush 1 brings the old cut back with no client change.
local hushCv = CreateConVar("zc_killcam_hush", "0", FCVAR_ARCHIVE, "Cut voice both ways for players inside a killcam (0 = never, the owner's default).", 0, 1)
hook.Add("HG_PlayerCanHearPlayersVoice", "ZCKillcam.Hush", function(listener, speaker)
    if not hushCv:GetBool() then return end
    if inKillcam(listener) or inKillcam(speaker) then return false end
end)

hook.Add("PlayerDisconnected", "ZCKillcam.HushGone", function(ply)
    if IsValid(ply) then watching[ply:UserID()] = nil end
end)

-- R7: the existing life stats command, extended with WHY a replay was not shown (K.Drops). This is the command
-- the brief names as zc_killcam_life_stats; it is the same command that already existed under this name.
-- M1: the client's share of a row (see K.Lat). Once per id, only from the player the row belongs to.
net.Receive("zckc_life_lat", function(_, p)
    if not IsValid(p) or p:IsBot() then return end
    local id = net.ReadString()
    local xfer, decode, wait = net.ReadUInt(16), net.ReadUInt(16), net.ReadUInt(16)
    local row = K.Lat.byId[id]
    if not row or row.client or row.sid ~= p:SteamID64() then return end
    row.client = {xfer = xfer / 1000, decode = decode / 1000, wait = wait / 1000, at = SysTime()}
end)
local function latLines()
    local rows, out = K.Lat.rows, {}
    local n, c, worst = 0, 0, 0
    local sum = {settle = 0, queue = 0, pack = 0, wire = 0, server = 0, xfer = 0, decode = 0, wait = 0, total = 0}
    for _, r in ipairs(rows) do
        if r.sent then
            local settle, queue, pack = r.settle - r.t0, r.packStart - r.settle, r.packDone - r.packStart
            local wire, server, cl = r.delay + r.span, r.sent - r.t0, r.client
            -- With a client report: server side to the send, the lane delay, then what the client saw. Without one
            -- (older client, or it never reached the screen): the chunk timers stand in for the transfer.
            local total = server + (cl and (r.delay + cl.xfer + cl.wait) or wire)
            n = n + 1
            sum.settle, sum.queue, sum.pack, sum.wire = sum.settle + settle, sum.queue + queue, sum.pack + pack, sum.wire + wire
            sum.server, sum.total = sum.server + server, sum.total + total
            if cl then c = c + 1 sum.xfer, sum.decode, sum.wait = sum.xfer + cl.xfer, sum.decode + cl.decode, sum.wait + cl.wait end
            if total > worst then worst = total end
            out[#out + 1] = string.format("[Killcam] lat %s: settle %.2f + queue/cuts %.2f + pack %.2f + lane %.2f | %d chunks %d KB, timers span %.2f | client: %s | death->screen %.2f s",
                r.id, settle, queue, pack, r.delay, r.chunks, math.floor(r.bytes / 1024), r.span,
                cl and string.format("xfer %.2f decode %.3f wait %.2f", cl.xfer, cl.decode, cl.wait) or "no report", total)
        elseif r.stop then
            out[#out + 1] = string.format("[Killcam] lat %s: stopped (%s) %.2f s after the death", r.id or "-", r.stop, (r.packDone or r.packStart or r.settle or r.t0) - r.t0)
        end
    end
    local d, dc = math.max(n, 1), math.max(c, 1)
    table.insert(out, 1, string.format("[Killcam] lat rows=%d sent=%d clientReports=%d | avg s: settle %.2f queue/cuts %.2f pack %.2f lane+wire %.2f death->send %.2f | client avg: xfer %.2f decode %.3f wait %.2f | death->screen avg %.2f max %.2f",
        #rows, n, c, sum.settle / d, sum.queue / d, sum.pack / d, sum.wire / d, sum.server / d, sum.xfer / dc, sum.decode / dc, sum.wait / dc, sum.total / d, worst))
    return out
end
K.LatLines = latLines

concommand.Add("zc_killcam_life", function(p, _, args)
    if IsValid(p) and not p:IsAdmin() then return end
    if args and args[1] == "lat" then -- M1
        for _, line in ipairs(latLines()) do if IsValid(p) then p:PrintMessage(HUD_PRINTCONSOLE, line) else print(line) end end
        return
    end
    local open, n = 0, 0
    for _, life in pairs(lives) do n = n + 1 open = open + #life.list end
    local line = string.format("[Killcam] lives tracked=%d instances=%d sequences=%d avgKB=%.1f cuts=%d audience=%d (costs: zc_killcam_work)", n, open, K.Stats.lives or 0,
        (K.Stats.lives or 0) > 0 and K.Stats.lifeBytes / K.Stats.lives / 1024 or 0, K.Stats.instCuts or 0, audience:GetInt())
    if IsValid(p) then p:PrintMessage(HUD_PRINTCONSOLE, line) else print(line) end
    local d = K.Drops
    local drops = string.format("[Killcam] not-shown drops: roundEnding=%d backlog=%d expired=%d busy=%d generation=%d floor=%d respawned=%d overflow=%d unsent=%d earlyDone=%d",
        d.roundEnding, d.backlog, d.expired, d.busy, d.generation, d.floor, d.respawned, d.overflow, d.unsent, d.earlyDone)
    if IsValid(p) then p:PrintMessage(HUD_PRINTCONSOLE, drops) else print(drops) end
    -- P1: where built sequences went. Each one is sent, or stopped at exactly one of: unsent / roundEnding / busy
    -- (line above), overflow, or a respawn / new round noticed after packing (inside respawnedPack / generation, which
    -- also count stops BEFORE a sequence existed). Of those sent, respawnedWait + respawnedPlay + map + replaced are the
    -- client's reports that it still never reached the screen. missedSaved: how many of all of those were saved.
    local account = string.format("[Killcam] account: sequences=%d sent=%d | server: respawnedPack=%d empty=%d | client: respawnedWait=%d respawnedPlay=%d map=%d replaced=%d pendingLapsed=%d | missedSaved=%d persist_missed=%d",
        K.Stats.lives or 0, K.Stats.lifeSent or 0, d.respawnedPack or 0, d.empty or 0, d.respawnedWait or 0, d.respawnedPlay or 0, d.map or 0, d.replaced or 0, d.respawned or 0, K.Stats.missedSaved or 0, persistMissed:GetInt())
    if IsValid(p) then p:PrintMessage(HUD_PRINTCONSOLE, account) else print(account) end
end)
