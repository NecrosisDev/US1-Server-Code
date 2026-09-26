-- Z-City killcam: the points faucet.
--
-- Owner, 2026-09-22: pay ZPoints from the killcam's own scoring, for combat AND for helping, to every visible
-- contributor rather than only the round's star, and ship it in shadow mode first.
--
-- Existing owner: zc_killcam (H.Score, sv_highlight.lua) scores every burst of kills already and throws all but
-- the round's best away. Extension seam: the ZCKillcam_Burst hook it now publishes, plus ZCity_MedicineUsed from
-- weapon_bandage_sh.lua's other-player heal path. Current consumer: hg.Pointshop, through PS_AddPoints.
--
-- WHY THE KILLCAM'S SCORE AND NOT THE SCOREBOARD'S. H.Score does not measure frags, it measures what the camera
-- could SHOW: a kill through a wall is worth a quarter, a bot is worth about a third, and an innocent killing an
-- innocent in a traitor round is worth a tenth. Those discounts exist to stop the round-end reel celebrating an
-- RDMer, and they do exactly as much good pointed at an economy -- a faucet fed by raw kills pays best for the
-- kill-on-sight play the owner wants less of. Nothing here re-derives any of that; it reads `s.pay`, worked out by
-- the same function with the same weights as the `s.worth` the reel is picked by. The one difference: an UNPROVOKED
-- teamkill pays nothing here, where the reel still gives it a tenth (2026-09-26), and so does a kill that began by
-- knocking down an idle player, whoever they turned out to be. Self-defence, being threatened first and stopping an
-- attacker pay in full (sv_intent.lua), so shooting back is never the expensive choice.
--
-- THIS FILE PAYS NOBODY UNTIL IT IS SWITCHED ON. Default is 1: it does the whole calculation and writes the line
-- to the server log, and calls nothing that touches a balance. That is the house pattern (sv_karma.lua, ChatGuard)
-- and it exists so the rate can be set from real numbers instead of a guess.
if not SERVER then return end
local K = assert(ZCKillcam, "recorder must load first")
assert(K.Highlight and K.Highlight.Score, "sv_highlight.lua must load first")

K.Points = K.Points or {}
local P = K.Points
P.Version = "20260926.pts3"

local H = K.Highlight

-- 0 = off. 1 = work it out and log it, pay nothing. 2 = pay. There is deliberately no mode that pays without
-- logging: the log is how a wrong rate gets noticed.
local mode = CreateConVar("zc_killcam_points", "1", FCVAR_ARCHIVE, "Killcam points: 0 off, 1 log only, 2 pay")
-- PROVISIONAL(2026-09-22, every number here is a first guess and the shadow log exists to replace them;
-- an ordinary clean kill scores ~200, so 40 makes it ~5 ZP, in the same order as the XP faucet's 3-6.
-- ratify-by: 2026-10-22)
local RATE = CreateConVar("zc_killcam_points_rate", "40", FCVAR_ARCHIVE, "Score needed per 1 ZPoint (higher = slower)")
-- 2026-09-26 balance pass (docs/POINTS_BALANCE.md has the working): a heal is worth about one clean kill, not five.
-- At 25 a helpful player out-earned a traitor's whole round from six bandages, and the per-round cap (150) was more
-- than an hour of the playtime faucet in one round. Still shadow numbers: tools/points_shadow_report.py replays the
-- shadow log under any settings, so these are replaced by what the server's own rounds show.
local HEAL = CreateConVar("zc_killcam_points_heal", "6", FCVAR_ARCHIVE, "ZPoints for patching somebody else up")
local CAP = CreateConVar("zc_killcam_points_cap", "40", FCVAR_ARCHIVE, "Most ZPoints one player can earn in one round (0 = uncapped)")
local HEALCAP = CreateConVar("zc_killcam_points_healcap", "4", FCVAR_ARCHIVE, "Most PAID heals one player can bank in a round")
-- The "encouraged to be good" half (owner, 2026-09-26): a small, reliable reward for a traitor round in which you
-- took part and nothing counted against you. It pays for the ordinary good round, which the rest of this file
-- cannot see: no kill, no heal, just played it straight.
local CLEAN = CreateConVar("zc_killcam_points_clean", "3", FCVAR_ARCHIVE, "ZPoints for a traitor round you took part in with nothing counted against you (0 = off)")
local ACTIVE_AFTER = 15 -- seconds into the round a player must still be giving input to count as having taken part
local HEALCD = CreateConVar("zc_killcam_points_healcd", "60", FCVAR_ARCHIVE, "Seconds before the same healer/patient pair pays again")
-- PROVISIONAL(2026-09-26, two minutes is long enough that "shoot a friend, bandage the friend" never pays and short
-- enough that an accident early in the round does not stop a player being paid for helping later; ratify-by: 2026-10-26)
local HEALHURT = CreateConVar("zc_killcam_points_healhurt", "120", FCVAR_ARCHIVE, "A heal does not pay if the healer hurt the patient within this many seconds")

local stats = P.stats or {rounds = 0, bursts = 0, overlaps = 0, heals = 0, healsRefused = 0, paid = 0, players = 0, capped = 0, errors = 0, last = "nothing yet"}
P.stats = stats

-- [steamid64] = {combat = <score>, heal = <ZP>, heals = <count>, name = <callsign>}
local round = P.round or {}
P.round = round
-- ["<healer>/<patient>"] = CurTime() at which that pair may pay again. Cleared every round start.
local healPairs = P.healPairs or {}
P.healPairs = healPairs
-- The end of the last window that was counted. Burst windows reach PRE seconds BEFORE their first kill, so two
-- back-to-back bursts overlap and the events in the overlap would otherwise be paid for twice.
local lastT1 = 0

local function inRound() return zb ~= nil and zb.ROUND_STATE == 1 end
-- [steamid64] = true once something counted against that player this round (an unprovoked kill or conduct)
local marked = P.marked or {}
P.marked = marked
local roundStart = P.roundStart or 0

-- The live player behind a recorder slot, or nil. A slot with no SteamID64 is a bot (sv_highlight's isBot), and
-- an identity whose UserID has been reused belongs to somebody else now -- the same check sv_highlight makes
-- before trusting a live entity.
local function playerFor(who)
    if not who or who.id == nil then return nil end
    local live = Player and Player(who.uid)
    if not IsValid(live) or not live:IsPlayer() then return nil end
    if live:UserID() ~= who.uid then return nil end
    if live:SteamID64() ~= who.id then return nil end
    return live
end

local function row(sid, name)
    local e = round[sid]
    if not e then e = {combat = 0, heal = 0, heals = 0} round[sid] = e end
    if name then e.name = name end
    return e
end

-- ------------------------------------------------------------------------------------- combat
hook.Add("ZCKillcam_Burst", "ZCKillcam.Points", function(by, t0, t1, star, score)
    if mode:GetInt() <= 0 or not inRound() then return end
    stats.bursts = stats.bursts + 1

    -- Clip the window to what has not been counted yet. When the clip bites, the published table covers too much
    -- ground, so the burst is scored again over the narrower window rather than paid for twice.
    local from = math.max(t0, lastT1)
    if from >= t1 then return end
    if from > t0 then
        stats.overlaps = stats.overlaps + 1
        local _, _, _, _, rescored = H.Score(from, t1)
        by = rescored
        if not by then return end
    end
    lastT1 = math.max(lastT1, t1)

    for slot, s in pairs(by) do
        local worth = s.pay
        -- Only ever a number the scorer itself worked out. If a future sv_highlight stops setting it, this pays
        -- nothing rather than guessing with a stale copy of the formula.
        if isnumber(worth) and worth > 0 then
            local who = K.Identity(slot)
            local live = playerFor(who)
            if live then
                row(live:SteamID64(), who.name).combat = row(live:SteamID64()).combat + worth
            end
        end
    end
end)

-- ------------------------------------------------------------------------------------- helping
-- weapon_bandage_sh.lua's SecondaryAttack is the only path that patches up somebody ELSE: it refuses when the
-- target resolves to the user's own character, and `done` is false unless the bandage actually did something.
-- The five medicines override Heal but inherit that caller, so one seam covers the family.
hook.Add("ZCity_MedicineUsed", "ZCKillcam.Points", function(healer, target, healMode, done)
    if mode:GetInt() <= 0 or not done or not inRound() then return end
    if not IsValid(healer) or not healer:IsPlayer() or healer:IsBot() then return end

    -- The patient is often a ragdoll standing in for a downed player (the fake-ragdoll system), so resolve it the
    -- way PostHeal does, through the organism's owner.
    local patient = target
    if IsValid(patient) and not (patient.IsPlayer and patient:IsPlayer()) then
        local org = patient.organism
        patient = org and org.owner or nil
    end
    if not IsValid(patient) or not patient:IsPlayer() or patient == healer then return end

    local hsid, psid = healer:SteamID64(), patient:SteamID64()
    if not hsid or not psid or hsid == psid then return end

    local e = row(hsid, healer.PlayerName and healer:PlayerName() or healer:Nick())

    -- Fixing damage you did yourself is not helping, and without this it is the cheapest farm on the server: wing a
    -- friend, bandage them, repeat. The heal still WORKS - only the payout is withheld - and it is counted, so a
    -- high number reads as somebody trying rather than vanishing.
    if K.HurtRecently and K.HurtRecently(healer, patient, HEALHURT:GetInt()) then
        stats.healsSelfInflicted = (stats.healsSelfInflicted or 0) + 1
        return
    end

    -- Two players taking turns bandaging each other is the obvious way to print money, so a pair pays once per
    -- cooldown and a healer banks only so many in a round. Refusals are counted, not silent: a high number here
    -- is the shape of somebody trying.
    local key = hsid .. "/" .. psid
    if (healPairs[key] or 0) > CurTime() or e.heals >= HEALCAP:GetInt() then
        stats.healsRefused = stats.healsRefused + 1
        return
    end
    healPairs[key] = CurTime() + HEALCD:GetInt()

    e.heals = e.heals + 1
    e.heal = e.heal + HEAL:GetInt()
    stats.heals = stats.heals + 1
end)

-- ------------------------------------------------------------------------------------- paying out
-- What one player earned this round, before the cap. Combat is divided here and nowhere else.
function P.Owed(e)
    local rate = math.max(RATE:GetInt(), 1)
    return math.floor(e.combat / rate) + math.floor(e.heal) + (e.clean or 0)
end

hook.Add("ZCKillcam_Conduct", "ZCKillcam.Points", function(_, offender)
    if IsValid(offender) and offender.SteamID64 and offender:SteamID64() then marked[offender:SteamID64()] = true end
end)
hook.Add("ZCKillcam_Death", "ZCKillcam.Points", function(victim, killer, tag)
    if tag ~= "ivi" or not killer or not killer.id or not K.JudgeDeath then return end
    if K.JudgeDeath(victim, killer, tag) == "unprovoked" then marked[killer.id] = true end
end)

-- Everybody who took part in a traitor round and kept it clean. "Took part" = still giving input ACTIVE_AFTER
-- seconds into the round (sv_intent.lua's activity clock), so a player who loaded in and went AFK is not paid.
local function markClean(traitorRound)
    local amount = CLEAN:GetInt()
    if not traitorRound or amount <= 0 then return end
    local activeAt = K.Intent and K.Intent.active or {}
    for _, p in ipairs(player.GetHumans and player.GetHumans() or player.GetAll()) do
        local sid = IsValid(p) and not p:IsBot() and p:SteamID64() or nil
        if sid and not marked[sid] and (activeAt[p:UserID()] or 0) >= roundStart + ACTIVE_AFTER then
            row(sid, p.PlayerName and p:PlayerName() or p:Nick()).clean = amount
        end
    end
end

local function flush(roundMode, humans)
    stats.rounds = stats.rounds + 1
    local live = mode:GetInt() >= 2
    local cap = CAP:GetInt()
    local lines, paid, people = {}, 0, 0

    for sid, e in pairs(round) do
        local owed = P.Owed(e)
        local capped = false
        if cap > 0 and owed > cap then owed, capped = cap, true stats.capped = stats.capped + 1 end

        if owed > 0 then
            people = people + 1
            paid = paid + owed
            lines[#lines + 1] = string.format("%s %d ZP (combat %d/%d, %d heal%s%s)%s", tostring(e.name or sid), owed,
                math.floor(e.combat), math.max(RATE:GetInt(), 1), e.heals, e.heals == 1 and "" or "s", e.clean and ", clean" or "", capped and " [capped]" or "")

            if live then
                -- The shop refuses a profile that has not loaded, which is the right answer: paying an unloaded
                -- profile is how an absolute write lands on somebody's real balance. Nothing is retried.
                local ply = player.GetBySteamID64 and player.GetBySteamID64(sid) or nil
                if not IsValid(ply) then
                    for _, p in ipairs(player.GetHumans()) do if p:SteamID64() == sid then ply = p break end end
                end
                if IsValid(ply) and ply.PS_AddPoints then
                    local ok, why = ply:PS_AddPoints(owed)
                    if ok then stats.paid = stats.paid + owed stats.players = stats.players + 1
                    else stats.errors = stats.errors + 1 lines[#lines] = lines[#lines] .. " [refused: " .. tostring(why) .. "]" end
                end
            end
        end
    end

    if #lines > 0 then
        stats.last = string.format("%d player%s, %d ZP", people, people == 1 and "" or "s", paid)
        -- mode= and humans= are for tools/points_shadow_report.py: kills are the whole game in tdm/dm and rare for an
        -- innocent in homicide, so the rates are read per mode; humans= counts the players who earned nothing too.
        print(string.format("[Killcam] points %s mode=%s humans=%d: %s | %s", live and "PAID" or "would pay (shadow)", tostring(roundMode or "?"),
            humans or 0, stats.last, table.concat(lines, "; ")))
    else
        stats.last = "nobody earned anything"
    end
end

hook.Add("ZB_EndRound", "ZCKillcam.Points", function()
    if mode:GetInt() <= 0 then return end
    -- Behind the work queue so a busy round-end (the highlight is being cut and packed right now) does not take
    -- the payout's cost on the same tick.
    -- Read now, while CurrentRound() is still this round; the job below may run after it has moved on.
    local current = CurrentRound and CurrentRound()
    local roundMode = istable(current) and current.name or nil
    local humans = #(player.GetHumans and player.GetHumans() or player.GetAll())
    local ok, err = pcall(markClean, K.TraitorRound and K.TraitorRound() or false)
    if not ok then stats.errors = stats.errors + 1 ErrorNoHalt("[Killcam] points clean: " .. tostring(err) .. "\n") end
    K.Work("points.flush", function() flush(roundMode, humans) end, function() stats.errors = stats.errors + 1 end)
end)

hook.Add("ZB_StartRound", "ZCKillcam.Points", function()
    P.round = {} round = P.round
    P.healPairs = {} healPairs = P.healPairs
    P.marked = {} marked = P.marked
    P.roundStart = CurTime() roundStart = P.roundStart
    lastT1 = 0
end)

concommand.Add("zc_killcam_points_stats", function(p)
    if IsValid(p) and not p:IsAdmin() then return end
    local line = string.format("[Killcam] points %s mode=%d rate=%d heal=%d clean=%d cap=%d | rounds=%d bursts=%d overlaps=%d heals=%d refused=%d own-damage=%d capped=%d paid=%d ZP to %d | last: %s",
        P.Version, mode:GetInt(), RATE:GetInt(), HEAL:GetInt(), CLEAN:GetInt(), CAP:GetInt(), stats.rounds, stats.bursts, stats.overlaps,
        stats.heals, stats.healsRefused, stats.healsSelfInflicted or 0, stats.capped, stats.paid, stats.players, stats.last)
    if IsValid(p) then p:PrintMessage(HUD_PRINTCONSOLE, line) else print(line) end
end)

-- Staff: what the round so far would pay, without waiting for it to end.
concommand.Add("zc_killcam_points_pending", function(p)
    if IsValid(p) and not p:IsAdmin() then return end
    local out = {}
    for sid, e in pairs(round) do
        local owed = P.Owed(e)
        if owed > 0 then out[#out + 1] = string.format("%s %d ZP", tostring(e.name or sid), owed) end
    end
    local line = "[Killcam] pending: " .. (#out > 0 and table.concat(out, ", ") or "nobody has earned anything yet")
    if IsValid(p) then p:PrintMessage(HUD_PRINTCONSOLE, line) else print(line) end
end)
