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
-- So this file keeps, for the current round, who has been hitting whom and who struck FIRST in each exchange, and
-- when an innocent kills an innocent it records one of three answers:
--   "defense"    the victim struck the killer first, in this exchange
--   "stopped"    the victim was attacking somebody else, and had started it, before the killer joined in
--   "unprovoked" neither: the killer started it. This is the only one the ledger, reel and faucet treat as wrong.
-- An exchange is a run of hits between two players with no gap longer than GAP seconds; after a quiet spell the
-- next hit starts a new one, so an old scuffle never excuses a fresh attack.
--
-- THIS FILE JUDGES NOTHING ON ITS OWN. It does not change karma (the gamemode's guilt library owns that), punish,
-- or hide a replay: "ivi" is still reportable in every case and staff still see every incident. It only stops the
-- killcam's own scoring from treating self-defence as the offence.
--
-- Existing owner: zc_killcam. Extension seams: ZCKillcam_Hit and ZCKillcam_Death from sv_recorder.lua.
-- Consumers: sv_highlight.lua (H.Score, H.Funny), sv_karma.lua (ledger), sv_points.lua (heals, via K.HurtRecently).
if not SERVER then return end
local K = assert(ZCKillcam, "recorder must load first")

K.Intent = K.Intent or {}
local I = K.Intent
I.Version = "20260926.int1"

-- PROVISIONAL(2026-09-26, 20 s covers a firefight including a reload and a chase round a corner, and is short
-- enough that a scuffle two minutes ago does not excuse a fresh attack; ratify-by: 2026-10-26)
local GAP = CreateConVar("zc_killcam_intent_gap", "20", FCVAR_ARCHIVE, "Seconds of quiet after which the next hit between two players starts a new exchange")

-- [attackerUid][victimUid] = {s = start of this exchange, l = last hit, first = attacker struck first}
-- UserIDs, not SteamIDs: bots have none of the latter and are still part of a fight.
I.pairs = I.pairs or {}
-- ["<killerUid>:<victimUid>"] = {why = "defense" | "stopped" | "unprovoked", t = CurTime() of the death}, this round.
I.kills = I.kills or {}
I.stats = I.stats or {defense = 0, stopped = 0, unprovoked = 0}
local stats = I.stats

local function active(rec, now) return rec ~= nil and now - rec.l <= GAP:GetFloat() end

hook.Add("ZB_PreRoundStart", "ZCKillcam.Intent", function()
    I.pairs, I.kills = {}, {}
end)

hook.Add("ZCKillcam_Hit", "ZCKillcam.Intent", function(attacker, victim)
    if not IsValid(attacker) or not IsValid(victim) or attacker == victim then return end
    local au, vu = attacker:UserID(), victim:UserID()
    local now = CurTime()
    local row = I.pairs[au]
    if not row then row = {} I.pairs[au] = row end
    local rec = row[vu]
    if active(rec, now) then
        rec.l = now
        return
    end
    -- A new exchange. The attacker struck first unless the victim was already in an exchange with them.
    local back = I.pairs[vu] and I.pairs[vu][au]
    row[vu] = {s = now, l = now, first = not active(back, now)}
end)

-- The answer for one kill, worked out from the exchanges as they stood when it happened.
function I.Judge(killerUid, victimUid, now)
    now = now or CurTime()
    local mine = I.pairs[killerUid] and I.pairs[killerUid][victimUid]
    local theirs = I.pairs[victimUid]
    if theirs then
        local back = theirs[killerUid]
        if active(back, now) and back.first then return "defense" end
        -- The victim opened an exchange on somebody else that was still going, and it began no later than the
        -- killer's own attack on them: the killer came in to stop it.
        local joined = mine and mine.s or now
        for other, rec in pairs(theirs) do
            if other ~= killerUid and rec.first and active(rec, now) and rec.s <= joined then return "stopped" end
        end
    end
    return "unprovoked"
end

-- Frozen at the moment of death: the ledger, the reel and the faucet all read the same answer, and a hit landed
-- after the fact (a body shot at) cannot change it. Callable from any ZCKillcam_Death listener - hook order is
-- not guaranteed, so sv_karma.lua asks for the answer rather than hoping this listener ran first - and the same
-- death is judged once however many listeners ask.
function K.JudgeDeath(victim, killer, tag)
    if tag ~= "ivi" or not killer or not killer.uid or not IsValid(victim) then return nil end
    local key, now = killer.uid .. ":" .. victim:UserID(), CurTime()
    local got = I.kills[key]
    if got and got.t == now then return got.why end
    local why = I.Judge(killer.uid, victim:UserID(), now)
    I.kills[key] = {why = why, t = now}
    stats[why] = (stats[why] or 0) + 1
    return why
end
hook.Add("ZCKillcam_Death", "ZCKillcam.Intent", function(victim, killer, tag) K.JudgeDeath(victim, killer, tag) end)

-- The recorded answer for an innocent-on-innocent kill this round, or nil when there is none (not a kill, not ivi,
-- or before this file loaded). Callers treat nil as "unknown", never as "guilty".
function K.KillIntent(killerUid, victimUid)
    if not killerUid or not victimUid then return nil end
    local got = I.kills[killerUid .. ":" .. victimUid]
    return got and got.why or nil
end

-- True when `attacker` hit `victim` in the last `within` seconds of this round. The points faucet uses it so a
-- player cannot hurt somebody and then be paid for patching them up.
function K.HurtRecently(attacker, victim, within)
    if not IsValid(attacker) or not IsValid(victim) then return false end
    local rec = I.pairs[attacker:UserID()] and I.pairs[attacker:UserID()][victim:UserID()]
    return rec ~= nil and CurTime() - rec.l <= within
end

concommand.Add("zc_killcam_intent_stats", function(p)
    if IsValid(p) and not p:IsAdmin() then return end
    local line = string.format("[Killcam] intent %s gap=%.0fs | innocent-on-innocent kills: %d unprovoked, %d self-defence, %d stopping an attacker",
        I.Version, GAP:GetFloat(), stats.unprovoked or 0, stats.defense or 0, stats.stopped or 0)
    if IsValid(p) then p:PrintMessage(HUD_PRINTCONSOLE, line) else print(line) end
end)
