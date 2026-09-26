-- Z-City killcam: WHO STARTED IT.
--
-- K.Classify (sv_recorder.lua) sees roles only: an innocent killing an innocent is "ivi" whatever happened first.
-- That is right for the replay's "can this be reported" question and wrong for every judgement built on top of it.
-- An innocent who is shot and shoots back, or who drops somebody opening fire on a third player, reads exactly like
-- an RDMer - and before this file the karma ledger counted it as a bad act, the highlight buried it as an offence,
-- and the points faucet docked it. Punishing the player who defended themselves teaches everybody not to shoot
-- back, which is "deter gameplay altogether", the opposite of what the owner asked for (2026-09-26: "deter bad
-- gameplay, not gameplay altogether... encouraged to be good").
--
-- So this file keeps, for the current round, who has been going at whom and who went FIRST in each exchange, and
-- when an innocent kills an innocent it records one of four answers:
--   "defense"    the victim struck the killer first, in this exchange
--   "threatened" the victim had held a gun on the killer (THREAT seconds) before anybody fired
--   "stopped"    the victim was attacking somebody else, and had started it, before the killer joined in
--   "unprovoked" none of those: the killer started it. The only one the ledger, reel and faucet treat as wrong.
-- An exchange is a run of hits between two players with no gap longer than GAP seconds; after a quiet spell the
-- next hit starts a new one, so an old scuffle never excuses a fresh attack.
--
-- Owner, 2026-09-26, on the ways players start fights WITHOUT firing first:
--   "look directly at another player, with their gun equipped, to bait them into combat" -> a THREAT. Holding a gun
--     steadily on somebody opens an exchange exactly as a shot would, so the baiter can no longer claim self-defence
--     when the bait works, and the player who fires at somebody aiming at them is not the one who started it.
--     Aiming at somebody who is actively attacking a third player does not count: that is stopping them.
--   "kick AFK players to the ground and search them in the early seconds of the round... very frustrating for a
--     traitor who was occupied" -> an AMBUSH: the first blow of an exchange landed on a player who has given no input
--     for IDLE seconds. Kicks and punches already arrive here as hits (HomigradDamage). Searching that player after
--     is noted on the same incident. A kill that follows an ambush earns no reel and no points, even when the victim
--     turns out to be a traitor: the kill may be correct, but the way it was found is what the owner wants less of.
--   "break the box someone is looting to steal the loot" -> a LOOT break: a loot container broken by somebody else
--     within LOOT_WINDOW of another player opening it, while that player is still standing at it.
-- The last three are CONDUCT incidents, published on the ZCKillcam_Conduct hook for the ledger (sv_karma.lua). They
-- only count in traitor rounds and only when the offender is not a traitor: harassing people is a traitor's job.
--
-- THIS FILE JUDGES NOTHING ON ITS OWN. It does not change karma (the gamemode's guilt library owns that), punish,
-- or hide a replay: "ivi" is still reportable in every case and staff still see every incident. It only stops the
-- killcam's own scoring from rewarding the player who started it and from punishing the one who didn't.
--
-- Existing owner: zc_killcam. Extension seams: ZCKillcam_Hit and ZCKillcam_Death from sv_recorder.lua,
-- ZB_InventoryOpened (sv_inventory.lua, searcher + searched) and PropBreak (sv_lootspawn.lua drops a box's loot).
-- Consumers: sv_highlight.lua (H.Score, H.Funny), sv_karma.lua (ledger), sv_points.lua (heals, via K.HurtRecently).
if not SERVER then return end
local K = assert(ZCKillcam, "recorder must load first")

K.Intent = K.Intent or {}
local I = K.Intent
I.Version = "20260926.int2"

-- PROVISIONAL(2026-09-26, every number below is a first guess to be checked against zc_killcam_intent_stats and the
-- ledger's incident lines; ratify-by: 2026-10-26)
-- 20 s covers a firefight including a reload and a chase round a corner, and is short enough that a scuffle two
-- minutes ago does not excuse a fresh attack.
local GAP = CreateConVar("zc_killcam_intent_gap", "20", FCVAR_ARCHIVE, "Seconds of quiet after which the next hit between two players starts a new exchange")
-- 3 s of a gun held steadily on somebody's body is deliberate: people glance across each other with guns out all
-- round, and a glance must never count. 0 turns threats off entirely.
local THREAT = CreateConVar("zc_killcam_intent_threat", "3", FCVAR_ARCHIVE, "Seconds of steady gun aim at a player that count as starting a fight (0 = aiming never counts)")
-- 10 s with no key, no turning and no moving. Somebody standing still but looking around is NOT idle.
local IDLE = CreateConVar("zc_killcam_intent_idle", "10", FCVAR_ARCHIVE, "Seconds without input after which a player counts as idle, so hitting them first is an ambush (0 = off)")
local THREAT_RANGE = 1200 -- Source units (~23 m): past this a pointed gun is not a face-to-face threat
local THREAT_DOT = 0.985  -- ~10 degrees either side of the line to the target's centre: aimed AT them, not near them
local THREAT_SLACK = 0.6  -- seconds the aim may slip off the target (recoil, a step) without starting the count again
local TURN = 1.5          -- degrees of view change between ticks that counts as input
local MOVE = 40           -- units/s of own movement that counts as input
local SEARCH_AFTER = 60   -- seconds after the ambush's last blow in which a search is part of it
local LOOT_WINDOW, LOOT_REACH = 20, 160 -- how long after opening a box, and how near it, the looter still counts
local TICK = 0.25

-- [attackerUid][victimUid] = {s = start of this exchange, l = last contact, first = attacker went first,
--   hits = hits landed, threat = opened by aiming, ambush = opened on an idle victim, searched = ambush then searched}
-- UserIDs, not SteamIDs: bots have none of the latter and are still part of a fight.
I.pairs = I.pairs or {}
-- ["<killerUid>:<victimUid>"] = {why = verdict for an ivi kill or nil, ambush = bool, t = CurTime() of the death}
I.kills = I.kills or {}
I.active = I.active or {} -- [uid] = last CurTime() the player gave any input
I.view = I.view or {}     -- [uid] = {pitch, yaw} at the last tick
I.aim = I.aim or {}       -- [aimerUid] = {v = targetUid, since = aim began, seen = last tick on target}
I.looting = I.looting or {} -- [container entity] = {ply = looter, t = opened at}
I.stats = I.stats or {}
local stats = I.stats

local function active(rec, now) return rec ~= nil and now - rec.l <= GAP:GetFloat() end
local function inRound() return zb ~= nil and zb.ROUND_STATE == 1 end
local function traitorRound() return K.TraitorRound ~= nil and K.TraitorRound() == true end
local function bump(key) stats[key] = (stats[key] or 0) + 1 end

hook.Add("ZB_PreRoundStart", "ZCKillcam.Intent", function()
    I.pairs, I.kills, I.aim, I.looting = {}, {}, {}, {}
end)
-- Everybody starts the round "just active": a player is only idle once IDLE seconds pass with nothing from them.
hook.Add("ZB_StartRound", "ZCKillcam.Intent", function()
    local now = CurTime()
    for _, p in ipairs(player.GetAll()) do I.active[p:UserID()] = now end
end)
hook.Add("PlayerSpawn", "ZCKillcam.Intent", function(p) if IsValid(p) then I.active[p:UserID()] = CurTime() end end)
hook.Add("KeyPress", "ZCKillcam.Intent", function(p) if IsValid(p) then I.active[p:UserID()] = CurTime() end end)
hook.Add("PlayerDisconnected", "ZCKillcam.Intent", function(p)
    local u = p:UserID()
    I.active[u], I.view[u], I.aim[u] = nil, nil, nil
end)

-- Bots are never idle: there is nobody behind them to be frustrated, and nobody to have been ambushed.
function I.Idle(p, now)
    local limit = IDLE:GetFloat()
    if limit <= 0 or not IsValid(p) or p:IsBot() or not p:Alive() then return false end
    return (now or CurTime()) - (I.active[p:UserID()] or 0) >= limit
end

-- A player actively attacking somebody else right now: an exchange they opened that is still going.
local function attacking(uid, except, now)
    for other, rec in pairs(I.pairs[uid] or {}) do
        if other ~= except and rec.first and not rec.threat and active(rec, now) then return true end
    end
    return false
end

-- A conduct incident: published for the ledger, only where it means something (see the header).
local function conduct(kind, offender, victim, detail)
    if not traitorRound() or not IsValid(offender) or offender:IsBot() or offender.isTraitor == true then return end
    bump(kind)
    local ok, err = pcall(hook.Run, "ZCKillcam_Conduct", kind, offender, victim, detail)
    if not ok then bump("errors") ErrorNoHalt("[Killcam] conduct listener: " .. tostring(err) .. "\n") end
end

-- Opens (or continues) the exchange a -> v. `how` = "hit" | "threat". Returns the record and whether it is new.
local function open(a, v, now, how, since)
    local au, vu = a:UserID(), v:UserID()
    local row = I.pairs[au]
    if not row then row = {} I.pairs[au] = row end
    local rec = row[vu]
    if active(rec, now) then
        rec.l = now
        if how == "hit" then rec.hits = (rec.hits or 0) + 1 end
        return rec, false
    end
    local back = I.pairs[vu] and I.pairs[vu][au]
    rec = {s = since or now, l = now, first = not active(back, now), hits = how == "hit" and 1 or 0, threat = how == "threat" or nil}
    row[vu] = rec
    return rec, true, back
end

hook.Add("ZCKillcam_Hit", "ZCKillcam.Intent", function(attacker, victim)
    if not IsValid(attacker) or not IsValid(victim) or attacker == victim then return end
    local now = CurTime()
    local idle = I.Idle(victim, now) -- read BEFORE anything below: the blow itself is not the victim's input
    local rec, new, back = open(attacker, victim, now, "hit")
    if not new then return end
    if rec.first and idle then
        rec.ambush = true
        conduct("ambush", attacker, victim, {traitor = victim.isTraitor == true})
    end
    -- The bait worked: somebody held a gun on the attacker, never fired, and the attacker fired first. Only between
    -- innocents - a traitor shooting somebody aiming at them is a traitor being a traitor, not somebody baited.
    if back and back.threat and back.first and (back.hits or 0) == 0 and active(back, now)
        and victim.isTraitor ~= true and attacker.isTraitor ~= true then
        conduct("bait", victim, attacker)
    end
end)

-- ------------------------------------------------------------------------------------- aim and activity
-- A firearm, not hands, melee, a grenade or a medkit: the homigrad base marks its guns (homigrad_base/shared.lua).
local function isGun(w)
    if not IsValid(w) or w.ishgweapon ~= true or w.ismelee then return false end
    local ammo = w.Primary and w.Primary.Ammo
    return isstring(ammo) and ammo ~= "" and ammo ~= "none"
end
local function bodyOf(p)
    local rag = p.FakeRagdoll
    return IsValid(rag) and rag or p
end
local trace = {mask = MASK_SHOT}

local function threaten(a, v, now, since)
    -- Aiming at somebody who is attacking a third player is stopping them, not threatening them.
    local justified = attacking(v:UserID(), a:UserID(), now)
    local rec, new = open(a, v, now, "threat", since)
    if new and justified then rec.first = false end
    if new then bump("threats") end
end

local function tick()
    local now = CurTime()
    local all = player.GetAll()
    local armed, bodies = {}, {}
    for _, p in ipairs(all) do
        if IsValid(p) and p:Alive() then
            local u = p:UserID()
            local ang, last = p:EyeAngles(), I.view[u]
            if last and (math.abs(math.AngleDifference(ang.p, last[1])) > TURN or math.abs(math.AngleDifference(ang.y, last[2])) > TURN) then
                I.active[u] = now
            end
            if last then last[1], last[2] = ang.p, ang.y else I.view[u] = {ang.p, ang.y} end
            local rag = IsValid(p.FakeRagdoll)
            if not rag and p:GetVelocity():Length() > MOVE then I.active[u] = now end
            bodies[#bodies + 1] = p
            if not rag and isGun(p:GetActiveWeapon()) then armed[#armed + 1] = p end
        end
    end
    local need = THREAT:GetFloat()
    if need <= 0 or not inRound() or (GetGlobalFloat and GetGlobalFloat("RS_GraceUntil", 0) > now) then
        I.aim = {}
        return
    end
    for _, a in ipairs(armed) do
        local au = a:UserID()
        local eye, dir = a:EyePos(), a:GetAimVector()
        local best, bestDot, bestPos
        for _, v in ipairs(bodies) do
            if v ~= a then
                local pos = bodyOf(v):WorldSpaceCenter()
                local d = pos - eye
                local dist = d:Length()
                if dist > 1 and dist <= THREAT_RANGE then
                    local dot = dir:Dot(d / dist)
                    if dot >= THREAT_DOT and (not bestDot or dot > bestDot) then best, bestDot, bestPos = v, dot, pos end
                end
            end
        end
        if best then
            trace.start, trace.endpos, trace.filter = eye, bestPos, a
            local tr = util.TraceLine(trace)
            if tr.Hit and tr.Entity ~= best and tr.Entity ~= bodyOf(best) then best = nil end
        end
        local cur = I.aim[au]
        if best then
            local vu = best:UserID()
            if not cur or cur.v ~= vu then cur = {v = vu, since = now} I.aim[au] = cur end
            cur.seen = now
            if now - cur.since >= need then threaten(a, best, now, cur.since) end
        elseif cur and now - cur.seen > THREAT_SLACK then
            I.aim[au] = nil
        end
    end
end
timer.Create("ZCKillcam.IntentTick", TICK, 0, function()
    local ok, err = pcall(tick)
    if not ok then bump("errors") I.lastError = tostring(err) end
end)

-- ------------------------------------------------------------------------------------- searching and loot
-- Resolves what was opened: a downed-but-alive player (sv_inventory.lua resolves the ragdoll to its owner), a dead
-- body (prop_ragdoll carrying .ply), or anything else - a loot container.
hook.Add("ZB_InventoryOpened", "ZCKillcam.Intent", function(searcher, ent)
    if not IsValid(searcher) or not IsValid(ent) or not inRound() then return end
    local target = ent:IsPlayer() and ent or (ent:GetClass() == "prop_ragdoll" and (ent.ply or (hg and hg.RagdollOwner and hg.RagdollOwner(ent)))) or nil
    if ent:GetClass() == "prop_ragdoll" and not IsValid(target) then return end
    if not IsValid(target) then
        I.looting[ent] = {ply = searcher, t = CurTime()}
        return
    end
    if target == searcher then return end
    local rec = I.pairs[searcher:UserID()] and I.pairs[searcher:UserID()][target:UserID()]
    if rec and rec.ambush and not rec.searched and CurTime() - rec.l <= SEARCH_AFTER then
        rec.searched = true
        conduct("search", searcher, target, {traitor = target.isTraitor == true})
    end
end)

hook.Add("PropBreak", "ZCKillcam.Intent", function(breaker, prop)
    local look = I.looting[prop]
    I.looting[prop] = nil
    if not look or not inRound() or not IsValid(breaker) or not breaker:IsPlayer() or not IsValid(prop) then return end
    local looter = look.ply
    if not IsValid(looter) or looter == breaker or not looter:Alive() then return end
    if CurTime() - look.t > LOOT_WINDOW or looter:GetPos():Distance(prop:GetPos()) > LOOT_REACH then return end
    conduct("loot", breaker, looter)
end)

-- ------------------------------------------------------------------------------------- verdicts
-- The answer for one kill, worked out from the exchanges as they stood when it happened.
function I.Judge(killerUid, victimUid, now)
    now = now or CurTime()
    local mine = I.pairs[killerUid] and I.pairs[killerUid][victimUid]
    local theirs = I.pairs[victimUid]
    if theirs then
        local back = theirs[killerUid]
        if active(back, now) and back.first then
            return (back.threat and (back.hits or 0) == 0) and "threatened" or "defense"
        end
        -- The victim opened an exchange on somebody else that was still going, and it began no later than the
        -- killer's own attack on them: the killer came in to stop it. Aiming alone is not attacking anybody here.
        local joined = mine and mine.s or now
        for other, rec in pairs(theirs) do
            if other ~= killerUid and rec.first and not rec.threat and active(rec, now) and rec.s <= joined then return "stopped" end
        end
    end
    return "unprovoked"
end

-- Frozen at the moment of death: the ledger, the reel and the faucet all read the same answer, and a hit landed
-- after the fact (a body shot at) cannot change it. Callable from any ZCKillcam_Death listener - hook order is
-- not guaranteed, so sv_karma.lua asks for the answer rather than hoping this listener ran first - and the same
-- death is judged once however many listeners ask. Returns the ivi verdict (nil for any other tag) and whether the
-- killer's own exchange with the victim was an ambush.
function K.JudgeDeath(victim, killer, tag)
    if not tag or not killer or not killer.uid or not IsValid(victim) then return nil, false end
    local key, now = killer.uid .. ":" .. victim:UserID(), CurTime()
    local got = I.kills[key]
    if got and got.t == now then return got.why, got.ambush end
    local mine = I.pairs[killer.uid] and I.pairs[killer.uid][victim:UserID()]
    local why = tag == "ivi" and I.Judge(killer.uid, victim:UserID(), now) or nil
    local ambush = mine ~= nil and mine.ambush == true and active(mine, now)
    I.kills[key] = {why = why, ambush = ambush, t = now}
    if why then bump(why) end
    if ambush then bump("ambushKills") end
    return why, ambush
end
hook.Add("ZCKillcam_Death", "ZCKillcam.Intent", function(victim, killer, tag) K.JudgeDeath(victim, killer, tag) end)

-- The recorded answer for an innocent-on-innocent kill this round, or nil when there is none (not a kill, not ivi,
-- or before this file loaded). Callers treat nil as "unknown", never as "guilty".
function K.KillIntent(killerUid, victimUid)
    if not killerUid or not victimUid then return nil end
    local got = I.kills[killerUid .. ":" .. victimUid]
    return got and got.why or nil
end

-- Whether a's exchange with b was opened as an ambush on an idle player: frozen at the kill if there was one,
-- otherwise as the exchange stands at `now`.
function K.Ambushed(aUid, bUid, now)
    if not aUid or not bUid then return false end
    local got = I.kills[aUid .. ":" .. bUid]
    if got then return got.ambush == true end
    local rec = I.pairs[aUid] and I.pairs[aUid][bUid]
    return rec ~= nil and rec.ambush == true and active(rec, now or CurTime())
end

-- True when `attacker` hit `victim` in the last `within` seconds of this round. The points faucet uses it so a
-- player cannot hurt somebody and then be paid for patching them up. Aiming is not hurting.
function K.HurtRecently(attacker, victim, within)
    if not IsValid(attacker) or not IsValid(victim) then return false end
    local rec = I.pairs[attacker:UserID()] and I.pairs[attacker:UserID()][victim:UserID()]
    return rec ~= nil and (rec.hits or 0) > 0 and CurTime() - rec.l <= within
end

concommand.Add("zc_killcam_intent_stats", function(p)
    if IsValid(p) and not p:IsAdmin() then return end
    local line = string.format("[Killcam] intent %s gap=%.0fs threat=%.1fs idle=%.0fs | innocent-on-innocent kills: %d unprovoked, %d self-defence, %d threatened first, %d stopping an attacker"
        .. " | conduct: %d ambushes (%d searched, %d ended in a kill), %d baits, %d loot breaks | %d threats seen | errors %d%s",
        I.Version, GAP:GetFloat(), THREAT:GetFloat(), IDLE:GetFloat(), stats.unprovoked or 0, stats.defense or 0, stats.threatened or 0,
        stats.stopped or 0, stats.ambush or 0, stats.search or 0, stats.ambushKills or 0, stats.bait or 0, stats.loot or 0,
        stats.threats or 0, stats.errors or 0, I.lastError and (" (" .. I.lastError .. ")") or "")
    if IsValid(p) then p:PrintMessage(HUD_PRINTCONSOLE, line) else print(line) end
end)
