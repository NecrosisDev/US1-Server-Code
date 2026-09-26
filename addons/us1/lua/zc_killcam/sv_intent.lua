-- Z-City killcam: WHO STARTED IT.
--
-- K.Classify (sv_recorder.lua) sees roles only: an innocent killing an innocent is "ivi" whatever happened first.
-- That is right for the replay's "can this be reported" question and wrong for every judgement built on top of it.
-- An innocent who is shot and shoots back, or who drops somebody opening fire on a third player, reads exactly like
-- an RDMer. Punishing the player who defended themselves teaches everybody not to shoot back, which is "deter
-- gameplay altogether", the opposite of what the owner asked for (2026-09-26: "deter bad gameplay, not gameplay
-- altogether... encouraged to be good").
--
-- THE MODEL. Two kinds of thing happen between two players, and they are kept apart on purpose:
--
--   EXCHANGES are attacks: a hit (bullet, blade, kick, punch - everything HomigradDamage sees) or a SHOT AT somebody
--   that missed (a bullet that passes within NEAR units of them and hits nobody). An exchange a -> v is a run of them
--   with no gap longer than GAP seconds. Whoever opened the first one between two players "went first".
--
--   PROVOCATIONS are flags: things that are not an attack but are how fights get started (owner, 2026-09-26):
--     aim    holding a RAISED gun on somebody's body for THREAT seconds ("look directly at another player, with their
--            gun equipped, to bait them into combat")
--     melee  squaring up to somebody within arm's reach, blade or raised fists, for the same time
--     loot   breaking a loot box somebody else is still standing at, within LOOT_WINDOW of them opening it ("break the
--            box someone is looting to steal the loot")
--   Owner: "Most things like this are contextual. It should flag, but only trip if something follows." A provocation
--   on its own costs NOTHING: it is logged on both players' timelines as a flag and that is all. It TRIPS only if a
--   fight between the same two players follows while it is still fresh (PROV_WINDOW):
--     - the target fights back: their attack is a RESPONSE, not "going first", so a kill that follows is
--       "threatened" / "provoked" and never counts against them; and the provoker is charged a conduct incident
--       (bait / loot). A provoker who then kills the player they provoked is "unprovoked" - they started it.
--     - for loot only, the provoker attacking the looter also trips it: theft followed by assault.
--   A provocation is JUSTIFIED, and never trips, when the target was attacking somebody at the time or was
--   provoking somebody themselves: covering a player being shot at or held at gunpoint, or aiming back at somebody
--   aiming at you, is the behaviour the owner wants more of.
--
--   AMBUSH: the first blow of an exchange landing on a player who has given no input (no key, no turning, no moving)
--   for IDLE seconds. That is not a flag - somebody already got hit - so it is a conduct incident straight away, and
--   a kill that follows earns no reel and no points even when the victim turns out to be a traitor ("kick AFK players
--   to the ground and search them in the early seconds of the round... very frustrating for a traitor who was
--   occupied"). Searching them afterwards is noted on the same incident.
--
-- VERDICTS for an innocent-on-innocent kill (K.JudgeDeath):
--   "defense"    the victim went first in this exchange
--   "threatened" the killer was responding to the victim holding a gun on them / squaring up to them
--   "provoked"   the killer was responding to the victim breaking the box they were looting
--   "stopped"    the victim was attacking somebody else, and had started it, before the killer joined in
--   "unprovoked" none of those: the killer started it. The only one the ledger, reel and faucet treat as wrong.
--
-- Conduct incidents (ambush, bait, loot, search) are published on ZCKillcam_Conduct for the ledger. They only count
-- in traitor rounds and only when the offender is not a traitor: harassing people is a traitor's job. EVERYTHING -
-- flags, trips, fights, kills - is also published on ZCKillcam_Incident for the per-life timeline (sv_timeline.lua),
-- whether or not it counts, so a player can see what was logged about them and why it did or did not count.
--
-- THIS FILE JUDGES NOTHING ON ITS OWN. It does not change karma (the gamemode's guilt library owns that), punish,
-- or hide a replay: "ivi" is still reportable in every case and staff still see every incident.
--
-- Existing owner: zc_killcam. Extension seams: ZCKillcam_Hit / ZCKillcam_Death (sv_recorder.lua), PostEntityFireBullets
-- (sh_luabullets.lua, once per traced bullet segment - the gamemode's own suppression code uses it the same way,
-- sv_util.lua "bulletsuppression"), ZB_InventoryOpened (sv_inventory.lua) and PropBreak (sv_lootspawn.lua).
if not SERVER then return end
local K = assert(ZCKillcam, "recorder must load first")

K.Intent = K.Intent or {}
local I = K.Intent
I.Version = "20260926.int3"

-- PROVISIONAL(2026-09-26, every number below is a first guess to be checked against zc_killcam_intent_stats and the
-- per-life timelines; ratify-by: 2026-10-26)
-- 20 s covers a firefight including a reload and a chase round a corner. The gamemode's own retaliation window
-- (zc_guilt_justice/policy.lua J.Defending) is 12 s; this is longer because it only decides who STARTED a fight.
local GAP = CreateConVar("zc_killcam_intent_gap", "20", FCVAR_ARCHIVE, "Seconds of quiet after which the next attack between two players starts a new exchange")
-- 3 s of a raised gun held on somebody's body is deliberate: people glance across each other with guns out all
-- round, and a glance must never count. 0 turns aim and squaring-up flags off entirely.
local THREAT = CreateConVar("zc_killcam_intent_threat", "3", FCVAR_ARCHIVE, "Seconds of steady aim (raised gun, or blade/fists at arm's reach) before it is flagged as a provocation (0 = never)")
-- 10 s with no key, no turning and no moving. Somebody standing still but looking around is NOT idle.
local IDLE = CreateConVar("zc_killcam_intent_idle", "10", FCVAR_ARCHIVE, "Seconds without input after which a player counts as idle, so hitting them first is an ambush (0 = off)")
-- Half the gamemode's suppression radius (sv_util.lua uses 120 to make somebody flinch). A bullet this close to
-- your body with nobody else nearer was fired at you.
local NEAR = CreateConVar("zc_killcam_intent_near", "60", FCVAR_ARCHIVE, "A missed bullet passing this close (units) to a player, nearer them than anybody, counts as shooting at them (0 = off)")

local THREAT_RANGE = 1200 -- Source units (~23 m): past this a pointed gun is not a face-to-face threat
-- "Aimed at their body": the aim line passes within BODY units of the target's centre, plus a little per unit of
-- distance for sway. That is a wide cone up close and a narrow one far away, which is how aiming actually works;
-- a fixed angle is too strict at arm's length and far too loose across a courtyard.
local BODY, BODY_SLOP = 30, 0.02
local MELEE_RANGE, MELEE_FACING = 80, 0.8 -- arm's reach, and facing them (the guilt library's own IsLookingAt dot)
local THREAT_SLACK = 0.6  -- seconds the aim may slip off the target (recoil, a step) without starting the count again
local TURN = 1.5          -- degrees of view change between ticks that counts as input
local MOVE = 40           -- units/s of own movement that counts as input
local SEARCH_AFTER = 60   -- seconds after the ambush's last blow in which a search is part of it
local LOOT_WINDOW, LOOT_REACH = 20, 160 -- how long after opening a box, and how near it, the looter still counts
local SHOT_FROM = 150     -- a bullet segment starting further than this from the shooter is a ricochet/penetration
local SHOT_GAP = 0.1      -- one near-miss check per shooter per this many seconds (pellets, full auto)
local TICK = 0.25
-- How long a provocation stays fresh after its last moment (the aim was last held / the box was broken).
local PROV_WINDOW = {aim = 8, melee = 8, loot = 30}
I.PROV_WINDOW = PROV_WINDOW
local VERDICT = {aim = "threatened", melee = "threatened", loot = "provoked"}
local TRIPS_AS = {aim = "bait", melee = "bait", loot = "loot"}

-- [aUid][vUid] = {s = start, l = last contact, first = a went first, hits, shots, provoked = kind a was answering,
--   ambush = opened on an idle v, searched = ambush then searched}. UserIDs: bots have no SteamID and still fight.
I.pairs = I.pairs or {}
-- [aUid][vUid][kind] = {kind, s, l, justified, tripped}
I.prov = I.prov or {}
-- ["<killerUid>:<victimUid>"] = {why = verdict for an ivi kill or nil, ambush = bool, t = CurTime() of the death}
I.kills = I.kills or {}
I.active = I.active or {} -- [uid] = last CurTime() the player gave any input
I.view = I.view or {}     -- [uid] = {pitch, yaw} at the last tick
I.aim = I.aim or {}       -- [aimerUid] = {v = targetUid, kind, since = aim began, seen = last tick on target}
I.looting = I.looting or {} -- [container entity] = {ply = looter, t = opened at}
I.shotAt = I.shotAt or {} -- [shooterUid] = CurTime() of the last near-miss check
I.stats = I.stats or {}
local stats = I.stats

local function active(rec, now) return rec ~= nil and now - rec.l <= GAP:GetFloat() end
local function fresh(p, now) return p ~= nil and not p.justified and now - p.l <= PROV_WINDOW[p.kind] end
local function inRound() return zb ~= nil and zb.ROUND_STATE == 1 end
local function graced(now) return GetGlobalFloat ~= nil and GetGlobalFloat("RS_GraceUntil", 0) > now end
local function traitorRound() return K.TraitorRound ~= nil and K.TraitorRound() == true end
local function bump(key) stats[key] = (stats[key] or 0) + 1 end

-- Who, as the timeline needs it: UserID for matching, SteamID64 for the record, a display name for the text.
local function who(p)
    if istable(p) and p.uid and not p.UserID then return {uid = p.uid, sid = p.id, name = p.name} end -- a recorder identity
    if not IsValid(p) then return nil end
    return {uid = p:UserID(), sid = not p:IsBot() and p:SteamID64() or nil, name = K.DisplayName and K.DisplayName(p) or p:Nick()}
end
I.Who = who

-- Everything, counted or not, for the per-life timeline. A listener that errors costs a line, never the round.
local function incident(kind, a, b, info)
    local ok, err = pcall(hook.Run, "ZCKillcam_Incident", kind, who(a), who(b), info or {})
    if not ok then bump("errors") ErrorNoHalt("[Killcam] incident listener: " .. tostring(err) .. "\n") end
end

-- A conduct incident for the ledger, only where it means something (see the header). Returns whether it counts.
local function conduct(kind, offender, victim, detail)
    if not traitorRound() or not IsValid(offender) or offender:IsBot() or offender.isTraitor == true then return false end
    bump(kind)
    local ok, err = pcall(hook.Run, "ZCKillcam_Conduct", kind, offender, victim, detail)
    if not ok then bump("errors") ErrorNoHalt("[Killcam] conduct listener: " .. tostring(err) .. "\n") end
    return true
end

hook.Add("ZB_PreRoundStart", "ZCKillcam.Intent", function()
    I.pairs, I.prov, I.kills, I.aim, I.looting, I.shotAt = {}, {}, {}, {}, {}, {}
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
    I.active[u], I.view[u], I.aim[u], I.shotAt[u] = nil, nil, nil, nil
end)

-- Bots are never idle: there is nobody behind them to be frustrated, and nobody to have been ambushed.
function I.Idle(p, now)
    local limit = IDLE:GetFloat()
    if limit <= 0 or not IsValid(p) or p:IsBot() or not p:Alive() then return false end
    return (now or CurTime()) - (I.active[p:UserID()] or 0) >= limit
end

-- Attacking somebody right now: an exchange they opened that is still going. `except` leaves one player out.
local function attacking(uid, except, now)
    for other, rec in pairs(I.pairs[uid] or {}) do
        if other ~= except and rec.first and active(rec, now) then return true end
    end
    return false
end
-- Provoking somebody right now (a fresh, unjustified flag). `only` limits it to one target.
local function provoking(uid, only, now)
    for other, kinds in pairs(I.prov[uid] or {}) do
        if only == nil or other == only then
            for _, p in pairs(kinds) do if fresh(p, now) then return p end end
        end
    end
end

-- Flags a -> v. Returns the provocation and whether it is new.
local function provoke(a, v, kind, now, since)
    local au, vu = a:UserID(), v:UserID()
    local row = I.prov[au]
    if not row then row = {} I.prov[au] = row end
    local kinds = row[vu]
    if not kinds then kinds = {} row[vu] = kinds end
    local p = kinds[kind]
    if p and now - p.l <= PROV_WINDOW[kind] then
        p.l = now
        return p, false
    end
    -- Covering somebody (the target is attacking or provoking anybody - including you) is not provoking them.
    local justified = attacking(vu, nil, now) or provoking(vu, nil, now) ~= nil
    p = {kind = kind, s = since or now, l = now, justified = justified or nil}
    kinds[kind] = p
    bump(justified and "flagsJustified" or "flags")
    incident("flag", a, v, {kind = kind, justified = justified or nil})
    return p, true
end

-- The fight followed: charge the provoker (conduct) and tell the timeline. Bait is only between innocents - a
-- traitor opening fire on somebody aiming at them is a traitor being a traitor, not somebody who was baited.
local function trip(p, provoker, target, how)
    if p.tripped then return end
    p.tripped = how
    local kind = TRIPS_AS[p.kind]
    local counts = false
    if kind ~= "bait" or (target.isTraitor ~= true and provoker.isTraitor ~= true) then
        counts = conduct(kind, provoker, target, {how = how})
    end
    bump("trips")
    incident("trip", provoker, target, {kind = p.kind, how = how, counts = counts or nil})
end

-- Opens (or continues) the exchange a -> v. `how` = "hit" | "shot". Returns the record and whether it is new.
local function open(a, v, now, how)
    local au, vu = a:UserID(), v:UserID()
    local row = I.pairs[au]
    if not row then row = {} I.pairs[au] = row end
    local rec = row[vu]
    if active(rec, now) then
        rec.l = now
        if how == "hit" then rec.hits = rec.hits + 1 else rec.shots = rec.shots + 1 end
        return rec, false
    end
    local back = I.pairs[vu] and I.pairs[vu][au]
    local answered = provoking(vu, au, now) -- v provoked a, and a is answering it
    rec = {s = now, l = now, first = not active(back, now) and answered == nil, hits = how == "hit" and 1 or 0,
        shots = how == "shot" and 1 or 0, provoked = answered and answered.kind or nil}
    row[vu] = rec
    if answered then trip(answered, v, a, "answered") end
    -- Theft followed by assault trips the theft too. An aim followed by the aimer attacking is just the attack.
    local own = I.prov[au] and I.prov[au][vu] and I.prov[au][vu].loot
    if fresh(own, now) then trip(own, a, v, "followed") end
    return rec, true
end

hook.Add("ZCKillcam_Hit", "ZCKillcam.Intent", function(attacker, victim)
    if not IsValid(attacker) or not IsValid(victim) or attacker == victim then return end
    local now = CurTime()
    local idle = I.Idle(victim, now) -- read BEFORE anything below: the blow itself is not the victim's input
    local rec, new = open(attacker, victim, now, "hit")
    if not new then return end
    if rec.first and idle then
        rec.ambush = true
        local counts = conduct("ambush", attacker, victim, {traitor = victim.isTraitor == true})
        incident("ambush", attacker, victim, {counts = counts or nil})
    end
    incident("fight", attacker, victim, {how = "hit", first = rec.first or nil, provoked = rec.provoked, ambush = rec.ambush})
end)

-- ------------------------------------------------------------------------------------- shots that missed
-- Once per traced bullet segment. A segment that hit a player is a hit and arrives through ZCKillcam_Hit; one that
-- starts away from the shooter is a ricochet or a penetration and is not a fresh aim. What is left: a bullet that
-- hit nothing living. The player it passed nearest, if within NEAR, was shot at. Guns on the physics-bullet path
-- (sh_plugin.lua, its PostEntityFireBullets call is commented out upstream) are not seen here.
local function nearMiss(ent, data)
    local near = NEAR:GetFloat()
    if near <= 0 or not inRound() or not istable(data) then return end
    local now = CurTime()
    if graced(now) then return end
    local a = data.Attacker
    if not IsValid(a) or not a:IsPlayer() then return end
    local tr = data.Trace
    if not istable(tr) or not tr.StartPos or not tr.HitPos then return end
    local au = a:UserID()
    if (I.shotAt[au] or 0) > now then return end
    if tr.StartPos:Distance(a:EyePos()) > SHOT_FROM then return end
    local hit = tr.Entity
    if IsValid(hit) and (hit:IsPlayer() or (hg and hg.RagdollOwner and IsValid(hg.RagdollOwner(hit)))) then return end
    I.shotAt[au] = now + SHOT_GAP
    local best, bestDist
    for _, v in ipairs(player.GetAll()) do
        if v ~= a and v:Alive() then
            local rag = v.FakeRagdoll
            local d = util.DistanceToLine(tr.StartPos, tr.HitPos, (IsValid(rag) and rag or v):WorldSpaceCenter())
            if d <= near and (not bestDist or d < bestDist) then best, bestDist = v, d end
        end
    end
    if not best then return end
    bump("nearMisses")
    local rec, new = open(a, best, now, "shot")
    if new then incident("fight", a, best, {how = "shot", first = rec.first or nil, provoked = rec.provoked}) end
end
hook.Add("PostEntityFireBullets", "ZCKillcam.Intent", function(ent, data)
    local ok, err = pcall(nearMiss, ent, data)
    if not ok then bump("errors") I.lastError = tostring(err) end
end)

-- ------------------------------------------------------------------------------------- aim and activity
-- A firearm, not hands, melee, a grenade or a medkit: the homigrad base marks its guns (homigrad_base/shared.lua).
local function isGun(w)
    if not IsValid(w) or w.ishgweapon ~= true or w.ismelee then return false end
    local ammo = w.Primary and w.Primary.Ammo
    return isstring(ammo) and ammo ~= "" and ammo ~= "none"
end
local function method(w, name)
    local fn = w[name]
    if not isfunction(fn) then return nil end
    local ok, r = pcall(fn, w)
    return ok and r or nil
end
-- Pointed, not carried: not sprinting, not in the low- or high-ready stance (homigrad_base sh_anim.lua ReadyStance),
-- not mid-switch, and able to fire right now (CanUse: not reloading, deploying or unconscious).
local function raised(w)
    if method(w, "ReadyStance") or method(w, "IsSprinting") then return false end
    local hol, dep = method(w, "GetHolster"), method(w, "GetDeploy")
    if (isnumber(hol) and hol ~= 0) or (isnumber(dep) and dep ~= 0) then return false end
    if isfunction(w.CanUse) and method(w, "CanUse") == false then return false end
    return true
end
-- A blade or club, or fists actually raised (weapon_hands_sh GetFists) - the same test the guilt library uses when
-- it decides a victim was squaring up (libraries/guilt/sv_guilt.lua).
local function isMelee(w)
    if not IsValid(w) then return false end
    if w.ismelee2 then return true end
    return w.GetClass and w:GetClass() == "weapon_hands_sh" and method(w, "GetFists") == true
end
local function bodyOf(p)
    local rag = p.FakeRagdoll
    return IsValid(rag) and rag or p
end
local trace = {mask = MASK_SHOT}

-- The player `a` is pointing at, or nil: nearest to the aim line inside the body tolerance, in line of sight.
local function target(a, bodies, kind)
    local eye, dir = a:EyePos(), a:GetAimVector()
    local best, bestMiss, bestPos
    for _, v in ipairs(bodies) do
        if v ~= a then
            local pos = bodyOf(v):WorldSpaceCenter()
            local d = pos - eye
            local along = d:Dot(dir) -- how far down the aim line the target sits; behind the aimer is negative
            if along > 1 then
                local dist = d:Length()
                local miss
                if kind == "aim" then
                    if dist <= THREAT_RANGE then miss = math.sqrt(math.max(dist * dist - along * along, 0)) - dist * BODY_SLOP end
                    if miss and miss > BODY then miss = nil end
                elseif dist <= MELEE_RANGE and along / dist >= MELEE_FACING then
                    miss = dist
                end
                if miss and (not bestMiss or miss < bestMiss) then best, bestMiss, bestPos = v, miss, pos end
            end
        end
    end
    if not best then return nil end
    trace.start, trace.endpos, trace.filter = eye, bestPos, a
    local tr = util.TraceLine(trace)
    if tr.Hit and tr.Entity ~= best and tr.Entity ~= bodyOf(best) then return nil end
    return best
end

local function tick()
    local now = CurTime()
    local armed, bodies = {}, {}
    for _, p in ipairs(player.GetAll()) do
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
            if not rag then
                local w = p:GetActiveWeapon()
                if isGun(w) then
                    if raised(w) then armed[#armed + 1] = {p, "aim"} end
                elseif isMelee(w) then
                    armed[#armed + 1] = {p, "melee"}
                end
            end
        end
    end
    local need = THREAT:GetFloat()
    if need <= 0 or not inRound() or graced(now) then
        I.aim = {}
        return
    end
    local held = {}
    for _, entry in ipairs(armed) do
        local a, kind = entry[1], entry[2]
        local au = a:UserID()
        held[au] = true
        local v = target(a, bodies, kind)
        local cur = I.aim[au]
        if v then
            local vu = v:UserID()
            if not cur or cur.v ~= vu or cur.kind ~= kind then cur = {v = vu, kind = kind, since = now} I.aim[au] = cur end
            cur.seen = now
            if now - cur.since >= need then provoke(a, v, kind, now, cur.since) end
        elseif cur and now - cur.seen > THREAT_SLACK then
            I.aim[au] = nil
        end
    end
    for au in pairs(I.aim) do if not held[au] then I.aim[au] = nil end end -- lowered, holstered, dead or down
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
    local isRag = ent:GetClass() == "prop_ragdoll"
    local body = ent:IsPlayer() and ent or (isRag and (ent.ply or (hg and hg.RagdollOwner and hg.RagdollOwner(ent)))) or nil
    if isRag and not IsValid(body) then return end
    if not IsValid(body) then
        I.looting[ent] = {ply = searcher, t = CurTime()}
        return
    end
    if body == searcher then return end
    local rec = I.pairs[searcher:UserID()] and I.pairs[searcher:UserID()][body:UserID()]
    if rec and rec.ambush and not rec.searched and CurTime() - rec.l <= SEARCH_AFTER then
        rec.searched = true
        local counts = conduct("search", searcher, body, {traitor = body.isTraitor == true})
        incident("search", searcher, body, {counts = counts or nil})
    end
end)

-- Breaking the box somebody is looting is a FLAG (owner: "only if it leads to one"): it trips if a fight follows.
hook.Add("PropBreak", "ZCKillcam.Intent", function(breaker, prop)
    local look = I.looting[prop]
    I.looting[prop] = nil
    if not look or not inRound() or not IsValid(breaker) or not breaker:IsPlayer() or not IsValid(prop) then return end
    local looter = look.ply
    if not IsValid(looter) or looter == breaker or not looter:Alive() then return end
    if CurTime() - look.t > LOOT_WINDOW or looter:GetPos():Distance(prop:GetPos()) > LOOT_REACH then return end
    provoke(breaker, looter, "loot", CurTime())
end)

-- ------------------------------------------------------------------------------------- verdicts
-- The answer for one kill, worked out from the exchanges as they stood when it happened.
function I.Judge(killerUid, victimUid, now)
    now = now or CurTime()
    local mine = I.pairs[killerUid] and I.pairs[killerUid][victimUid]
    local theirs = I.pairs[victimUid]
    local back = theirs and theirs[killerUid]
    if active(back, now) and back.first then return "defense" end
    if mine and mine.provoked and active(mine, now) then return VERDICT[mine.provoked] or "provoked" end
    if theirs then
        -- The victim opened an exchange on somebody else that was still going, and it began no later than the
        -- killer's own attack on them: the killer came in to stop it.
        local joined = mine and mine.s or now
        for other, rec in pairs(theirs) do
            if other ~= killerUid and rec.first and active(rec, now) and rec.s <= joined then return "stopped" end
        end
    end
    return "unprovoked"
end

-- Frozen at the moment of death: the ledger, the reel, the faucet and the timeline all read the same answer, and a
-- hit landed after the fact (a body shot at) cannot change it. Callable from any ZCKillcam_Death listener - hook
-- order is not guaranteed - and the same death is judged once however many listeners ask. Returns the ivi verdict
-- (nil for any other tag) and whether the killer's own exchange with the victim was an ambush.
function K.JudgeDeath(victim, killer, tag)
    if not killer or not killer.uid or not IsValid(victim) then return nil, false end
    local key, now = killer.uid .. ":" .. victim:UserID(), CurTime()
    local got = I.kills[key]
    if got and got.t == now then return got.why, got.ambush end
    local mine = I.pairs[killer.uid] and I.pairs[killer.uid][victim:UserID()]
    local why = tag == "ivi" and I.Judge(killer.uid, victim:UserID(), now) or nil
    local ambush = mine ~= nil and mine.ambush == true and active(mine, now)
    I.kills[key] = {why = why, ambush = ambush, t = now}
    if why then bump(why) end
    if ambush then bump("ambushKills") end
    incident("kill", killer, victim, {tag = tag, why = why, ambush = ambush or nil, traitorKiller = killer.traitor == true or nil})
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

-- True when `attacker` HIT `victim` in the last `within` seconds of this round. The points faucet uses it so a player
-- cannot hurt somebody and then be paid for patching them up. Aiming or missing is not hurting.
function K.HurtRecently(attacker, victim, within)
    if not IsValid(attacker) or not IsValid(victim) then return false end
    local rec = I.pairs[attacker:UserID()] and I.pairs[attacker:UserID()][victim:UserID()]
    return rec ~= nil and rec.hits > 0 and CurTime() - rec.l <= within
end

concommand.Add("zc_killcam_intent_stats", function(p)
    if IsValid(p) and not p:IsAdmin() then return end
    local line = string.format("[Killcam] intent %s gap=%.0fs threat=%.1fs idle=%.0fs near=%.0fu | innocent-on-innocent kills: %d unprovoked,"
        .. " %d self-defence, %d threatened first, %d provoked, %d stopping an attacker | flags: %d (+%d justified), %d tripped"
        .. " | conduct: %d ambushes (%d searched, %d ended in a kill), %d baits, %d loot | %d near-misses | errors %d%s",
        I.Version, GAP:GetFloat(), THREAT:GetFloat(), IDLE:GetFloat(), NEAR:GetFloat(), stats.unprovoked or 0, stats.defense or 0,
        stats.threatened or 0, stats.provoked or 0, stats.stopped or 0, stats.flags or 0, stats.flagsJustified or 0, stats.trips or 0,
        stats.ambush or 0, stats.search or 0, stats.ambushKills or 0, stats.bait or 0, stats.loot or 0, stats.nearMisses or 0,
        stats.errors or 0, I.lastError and (" (" .. I.lastError .. ")") or "")
    if IsValid(p) then p:PrintMessage(HUD_PRINTCONSOLE, line) else print(line) end
end)
