-- Z-City killcam: the per-life timeline - the karma ledger, made transparent to the player it is about.
--
-- Owner, 2026-09-26: "Transparent karma ledger, per-life, per-player, logging incidents along a timeline." The
-- scoring in sv_intent.lua / sv_karma.lua decides what counts; this file shows a player, for each of their lives,
-- everything that was logged about them and whether it counted - "You held a gun on Bob (flag: only counts if a
-- fight follows)", "Bob fought back - counts as baiting", "You killed Bob in self-defence (doesn't count)". A player
-- who can see WHY something counted can change what they do; one who only sees a number going down just leaves.
--
-- Sources: ZCKillcam_Incident (sv_intent.lua: flags, trips, first contact, ambushes, searches, kills with their
-- verdict) and ZCity_MedicineUsed (heals - the good acts get a line too). A life starts at a real spawn and ends at
-- death, at round end (survived) or on leaving. The last KEEP_LIVES are kept per player on disk.
--
-- ROLE PRIVACY. A verdict can reveal a role: "you killed a traitor", or a victim told their killer's teamkill was
-- counted (so the killer was innocent). While the round those lives belong to is still running in a traitor mode
-- (ZCityMetaSafety.Locked - the same lock the guilt review uses), every event is sent in its SAFE form: what
-- happened, without the verdict. The full text is sent once the round is over. The death panel therefore shows the
-- safe form; the Karma app (!karma) shows the full one after the round.
--
-- Who sees it: zc_killcam_timeline 0 off, 1 the tester only (zc_killcam_timeline_tester), 2 everyone - the house
-- pattern for a new player-facing surface. A player is only ever sent their OWN lives. Staff read anyone's with
-- zc_killcam_timeline <name | SteamID64> in console.
--
-- Existing owner: zc_killcam. Consumers: sv_life.lua (h2h.timeline for the GoobOS death panel, which reserved that
-- field for exactly this), zc_goobos/karma.lua (the Karma app) through net "zckc_timeline".
if not SERVER then return end
local K = assert(ZCKillcam, "recorder must load first")

K.Timeline = K.Timeline or {}
local TL = K.Timeline
TL.Version = "20260926.tl1"

-- Created in autorun/zc_goobos_apps.lua too (replicated, so the phone can hide the app); whichever runs first wins.
local MODE = GetConVar("zc_killcam_timeline") or CreateConVar("zc_killcam_timeline", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Per-life karma timeline for players: 0 off, 1 tester only, 2 everyone")
local TESTER = GetConVar("zc_killcam_timeline_tester") or CreateConVar("zc_killcam_timeline_tester", "76561198011536179", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "SteamID64 that sees the karma timeline while zc_killcam_timeline is 1")
local KEEP_LIVES, MAX_EVENTS = 8, 48
local DIR = K.Root .. "/timeline"

function TL.Allowed(p)
    if not IsValid(p) or p:IsBot() then return false end
    local mode = MODE:GetInt()
    return mode >= 2 or (mode == 1 and p:SteamID64() == string.Trim(TESTER:GetString()))
end

TL.live = TL.live or {}   -- [uid] = the life being lived
TL.lives = TL.lives or {} -- [sid] = frozen lives, newest first
TL.round = TL.round or 0  -- serial of the current round, stamped on every life
TL.stats = TL.stats or {lives = 0, events = 0, sent = 0, denied = 0, errors = 0}
local stats = TL.stats

local function locked()
    local M = rawget(_G, "ZCityMetaSafety")
    if M and isfunction(M.Locked) then
        local ok, v = pcall(M.Locked)
        if ok then return v == true end
    end
    return zb ~= nil and zb.ROUND_STATE == 1 and K.TraitorRound ~= nil and K.TraitorRound()
end

local function conductWeight()
    local cv = GetConVar("zc_killcam_karma_conduct")
    return cv and cv:GetFloat() or 0.5
end

-- ------------------------------------------------------------------------------------- persistence
local function fileFor(sid) return DIR .. "/" .. sid .. ".json" end
local function load(sid)
    local got = TL.lives[sid]
    if got then return got end
    got = {}
    local raw = file.Read(fileFor(sid), "DATA")
    if isstring(raw) then
        local t = util.JSONToTable(raw)
        if istable(t) then got = t end
    end
    TL.lives[sid] = got
    return got
end
local function save(sid)
    local list = TL.lives[sid]
    if not list then return end
    local write = function()
        file.CreateDir(DIR)
        file.Write(fileFor(sid), util.TableToJSON(list))
    end
    -- Off the death tick: the killcam's own work queue if it is there, else straight away (a small file).
    if K.Work then K.Work("timeline.save", function() write() end, function() stats.errors = stats.errors + 1 end) else write() end
end

-- ------------------------------------------------------------------------------------- lives
local function begin(p)
    if not IsValid(p) or p:IsBot() then return end
    local sid = p:SteamID64()
    if not sid then return end
    local mode = CurrentRound and CurrentRound()
    TL.live[p:UserID()] = {sid = sid, name = K.DisplayName and K.DisplayName(p) or p:Nick(), start = CurTime(), at = os.time(),
        map = game.GetMap(), mode = istable(mode) and mode.name or nil, round = TL.round, events = {}}
    timer.Simple(0, function()
        local life = IsValid(p) and TL.live[p:UserID()]
        if life and K.LiveKarma then life.karma0 = K.LiveKarma(sid) end
    end)
end

local function freeze(p, uid, how, by)
    local life = TL.live[uid]
    if not life then return end
    TL.live[uid] = nil
    life.span = math.max(CurTime() - life.start, 0)
    life.ended = how -- "died" | "survived" | "left"
    life.by = by
    if K.LiveKarma then life.karma1 = K.LiveKarma(life.sid) end
    life.start = nil
    local list = load(life.sid)
    table.insert(list, 1, life)
    while #list > KEEP_LIVES do table.remove(list) end
    stats.lives = stats.lives + 1
    save(life.sid)
    return life
end

hook.Add("ZB_StartRound", "ZCKillcam.Timeline", function() TL.round = TL.round + 1 end)
hook.Add("PlayerSpawn", "ZCKillcam.Timeline", function(p)
    if OverrideSpawn then return end -- a ragdoll get-up re-spawns mid-life (sv_tier_0.lua); that is not a new life
    if not IsValid(p) then return end
    freeze(p, p:UserID(), "survived") -- a life nobody closed (respawn modes, or a missed round end)
    begin(p)
end)
-- After the recorder's own death listener has run (and with it the kill verdict), not before it.
hook.Add("PlayerDeath", "ZCKillcam.Timeline", function(p, _, attacker)
    if not IsValid(p) then return end
    local uid = p:UserID()
    local by = IsValid(attacker) and attacker:IsPlayer() and attacker ~= p and (K.DisplayName and K.DisplayName(attacker) or attacker:Nick()) or nil
    timer.Simple(0, function() freeze(p, uid, "died", by) end)
end)
hook.Add("ZB_EndRound", "ZCKillcam.Timeline", function()
    for _, p in ipairs(player.GetHumans and player.GetHumans() or player.GetAll()) do
        if IsValid(p) and p:Alive() then freeze(p, p:UserID(), "survived") end
    end
end)
hook.Add("PlayerDisconnected", "ZCKillcam.Timeline", function(p) freeze(p, p:UserID(), "left") end)

-- ------------------------------------------------------------------------------------- events
-- `e` = {kind = colour/axis bucket for the death panel, mine = the player did it, text, tag, w = weight toward the
-- ledger's rate when it counts, safe = {text, tag} to show while the round is locked (nil = nothing to hide)}.
local function push(uid, e)
    local life = uid and TL.live[uid]
    if not life then return end
    e.t = math.floor((CurTime() - life.start) * 10 + 0.5) / 10
    local list = life.events
    if #list >= MAX_EVENTS then
        -- Full: the oldest flag or first-contact line makes room. Kills, trips, ambushes and heals are kept.
        local drop = 1
        for i, old in ipairs(list) do if old.kind == "flag" or old.kind == "other" or old.kind == "taken" then drop = i break end end
        table.remove(list, drop)
    end
    list[#list + 1] = e
    stats.events = stats.events + 1
end
TL.Push = push

local PROV = {aim = {"held a gun on", "you held a gun on them"}, melee = {"squared up to", "you squared up to them"},
    loot = {"broke the box being looted by", "you broke the box they were looting"}}
local PROV_THEM = {aim = "held a gun on you", melee = "squared up to you", loot = "broke the box you were looting"}
local TRIP_NAME = {aim = "baiting", melee = "baiting", loot = "loot theft"}
local FLAG_TAG = "flag - only counts if a fight follows"

-- Only between players who could be in the wrong with each other: anybody in a traitor round (sides are hidden),
-- teammates elsewhere. A flag or a fight between enemies in a team mode is the game, not an incident.
local function relevant(a, b)
    if K.TraitorRound and K.TraitorRound() then return true end
    local pa, pb = a and Player(a.uid), b and Player(b.uid)
    return IsValid(pa) and IsValid(pb) and pa:Team() == pb:Team()
end

local handlers = {}
handlers.flag = function(a, b, info)
    if not relevant(a, b) then return end
    local verb = PROV[info.kind] or PROV.aim
    if info.justified then
        push(a.uid, {kind = "flag", mine = true, text = "You " .. verb[1] .. " " .. b.name .. " while they were attacking or threatening someone", tag = "no effect - covering"})
        push(b.uid, {kind = "flag", text = a.name .. " " .. (PROV_THEM[info.kind] or "") .. " while you were attacking or threatening someone", tag = "no effect"})
    else
        push(a.uid, {kind = "flag", mine = true, text = "You " .. verb[1] .. " " .. b.name, tag = FLAG_TAG})
        push(b.uid, {kind = "flag", text = a.name .. " " .. (PROV_THEM[info.kind] or ""), tag = "flag on them - if you fight back, it's on them"})
    end
end
handlers.trip = function(a, b, info) -- a provoked, b was the target
    local what = TRIP_NAME[info.kind] or "provoking"
    local w = info.counts and conductWeight() or nil
    local counts = info.counts and string.format("counts as %s (%.1f)", what, w) or "logged - does not count in this mode"
    if info.how == "followed" then
        push(a.uid, {kind = "bad", mine = true, text = "You attacked " .. b.name .. " after breaking the box they were looting", tag = counts, w = w,
            safe = {text = "You attacked " .. b.name .. " after breaking the box they were looting", tag = "verdict at round end"}})
        push(b.uid, {kind = "taken", text = a.name .. " attacked you after breaking the box you were looting", tag = "on them"})
        return
    end
    push(a.uid, {kind = "bad", mine = true, text = b.name .. " fought back after " .. (PROV[info.kind] or PROV.aim)[2], tag = counts, w = w,
        safe = {text = b.name .. " fought back after " .. (PROV[info.kind] or PROV.aim)[2], tag = "verdict at round end"}})
    push(b.uid, {kind = "dealt", mine = true, text = "You fought back after " .. a.name .. " " .. (PROV_THEM[info.kind] or "provoked you"), tag = "provoked - doesn't count against you"})
end
handlers.fight = function(a, b, info)
    if not relevant(a, b) then return end
    local shot = info.how == "shot"
    if info.first then
        push(a.uid, {kind = "other", mine = true, text = shot and ("You fired at " .. b.name .. " first (missed)") or ("You attacked " .. b.name .. " first"),
            tag = "you started this fight"})
        push(b.uid, {kind = "taken", text = shot and (a.name .. " fired at you first (missed)") or (a.name .. " attacked you first"), tag = "they started this fight"})
    else
        push(a.uid, {kind = "dealt", mine = true, text = "You fought back against " .. b.name, tag = info.provoked and "provoked" or "they started it"})
        push(b.uid, {kind = "taken", text = a.name .. " fought back", tag = info.provoked and "you provoked them" or "you started it"})
    end
end
handlers.ambush = function(a, b, info)
    local w = info.counts and conductWeight() or nil
    push(a.uid, {kind = "bad", mine = true, text = "You hit " .. b.name .. " while they were idle", w = w,
        tag = info.counts and string.format("counts as an ambush (%.1f)", w) or "logged", safe = {text = "You hit " .. b.name .. " while they were idle", tag = "verdict at round end"}})
    push(b.uid, {kind = "taken", text = a.name .. " hit you while you were idle", tag = "ambush - on them"})
end
handlers.search = function(a, b)
    push(a.uid, {kind = "bad", mine = true, text = "You searched " .. b.name .. " after knocking them down", tag = "part of the ambush"})
    push(b.uid, {kind = "taken", text = a.name .. " searched you after knocking you down", tag = "part of the ambush"})
end
local KILL_TEXT = {
    unprovoked = {"You killed %s - you started it", "counts as a bad act (1.0)", 1},
    defense = {"You killed %s in self-defence - they attacked first", "doesn't count"},
    threatened = {"You killed %s - they held a gun on you / squared up first", "doesn't count"},
    provoked = {"You killed %s - they broke the box you were looting", "doesn't count"},
    stopped = {"You killed %s while they were attacking someone", "doesn't count - you stopped them"},
}
local DIED_TEXT = {
    unprovoked = "they started it - counted against them",
    defense = "you attacked them first",
    threatened = "you held a gun on them / squared up first",
    provoked = "you broke the box they were looting",
    stopped = "you were attacking someone - they stopped you",
}
handlers.kill = function(a, b, info)
    local tag, why = info.tag, info.why
    local safeA = {text = "You killed " .. b.name, tag = "verdict at round end"}
    if tag == "ivi" and why and KILL_TEXT[why] then
        local k = KILL_TEXT[why]
        push(a.uid, {kind = k[3] and "bad" or "kill", mine = true, text = string.format(k[1], b.name), tag = k[2], w = k[3], safe = safeA})
        push(b.uid, {kind = "death", text = "Killed by " .. a.name .. " - " .. DIED_TEXT[why], safe = {text = "Killed by " .. a.name}})
    elseif tag == "t_killed" then
        push(a.uid, {kind = info.ambush and "bad" or "kill", mine = true, safe = safeA,
            text = info.ambush and ("You killed " .. b.name .. ", a traitor - found by an ambush") or ("You killed " .. b.name .. ", a traitor"),
            tag = info.ambush and "no credit" or "good kill"})
        push(b.uid, {kind = "death", text = "Killed by " .. a.name, safe = {text = "Killed by " .. a.name}})
    else
        push(a.uid, {kind = "kill", mine = true, text = "You killed " .. b.name, safe = safeA})
        push(b.uid, {kind = "death", text = "Killed by " .. a.name})
    end
end

hook.Add("ZCKillcam_Incident", "ZCKillcam.Timeline", function(kind, a, b, info)
    if MODE:GetInt() <= 0 or not a or not b then return end
    local fn = handlers[kind]
    if not fn then return end
    local ok, err = pcall(fn, a, b, info or {})
    if not ok then stats.errors = stats.errors + 1 TL.lastError = tostring(err) end
end)

-- Helping is logged too: a line in green is as much the point as a line in red.
hook.Add("ZCity_MedicineUsed", "ZCKillcam.Timeline", function(healer, target, _, done)
    if MODE:GetInt() <= 0 or not done or not IsValid(healer) or not healer:IsPlayer() then return end
    local patient = target
    if IsValid(patient) and not (patient.IsPlayer and patient:IsPlayer()) then
        local org = patient.organism
        patient = org and org.owner or nil
    end
    if not IsValid(patient) or not patient:IsPlayer() or patient == healer then return end
    local hn, pn = K.DisplayName and K.DisplayName(healer) or healer:Nick(), K.DisplayName and K.DisplayName(patient) or patient:Nick()
    push(healer:UserID(), {kind = "heal", mine = true, text = "You patched up " .. pn, tag = "helping"})
    push(patient:UserID(), {kind = "heal", text = hn .. " patched you up", tag = "helped"})
end)

-- ------------------------------------------------------------------------------------- reading
-- A life as it may be shown right now: every event in its safe form while its round is still locked.
function TL.View(life)
    local hide = life.round == TL.round and locked()
    local out = {}
    for i, e in ipairs(life.events or {}) do
        local s = hide and e.safe or nil
        out[i] = {t = e.t, kind = e.kind, mine = e.mine, text = s and s.text or e.text, tag = s and s.tag or e.tag, w = (not s) and e.w or nil}
    end
    return {at = life.at, map = life.map, mode = life.mode, span = life.span, ended = life.ended, by = life.by,
        karma0 = life.karma0, karma1 = life.karma1, events = out, held = hide or nil}
end

-- For sv_life.lua: the life that just ended in this death, as the death panel may show it.
function K.LifeTimeline(sid, p)
    if not sid or MODE:GetInt() <= 0 or not TL.Allowed(p) then return nil end
    local life = load(sid)[1]
    if not life or life.ended ~= "died" or os.time() - (life.at + (life.span or 0)) > 30 then return nil end
    return TL.View(life)
end

-- ------------------------------------------------------------------------------------- the Karma app
util.AddNetworkString("zckc_timeline")
local nextAsk = {}
net.Receive("zckc_timeline", function(_, p)
    if not IsValid(p) then return end
    local now = CurTime()
    if (nextAsk[p] or 0) > now then return end
    nextAsk[p] = now + 1
    local allowed = TL.Allowed(p)
    local out = {v = 1, allowed = allowed, lives = {}}
    if allowed then
        local sid = p:SteamID64()
        for i, life in ipairs(load(sid)) do out.lives[i] = TL.View(life) end
        -- The live one too, so a player can check what has been logged so far - in its safe form if locked.
        local current = TL.live[p:UserID()]
        if current then
            local view = TL.View({events = current.events, round = current.round, at = current.at, map = current.map, mode = current.mode, karma0 = current.karma0})
            view.span, view.ended = CurTime() - current.start, "alive"
            out.current = view
        end
        -- The player's own row of the staff ledger (sv_karma.lua), when that is recording: nothing staff can see
        -- about a player's conduct is hidden from that player.
        if K.KarmaRate and K.Karma and K.Karma.ledger and K.Karma.ledger[sid] then
            local e = K.Karma.ledger[sid]
            local rate = K.KarmaRate(sid)
            local floor = GetConVar("zc_killcam_karma_rate")
            local rounds = GetConVar("zc_killcam_karma_rounds")
            out.ledger = {rate = rate, floor = floor and floor:GetFloat() or nil, rounds = e.r, need = rounds and rounds:GetInt() or nil,
                unprovoked = e.b, contested = e.d or 0, forgiven = e.fg or 0, traitors = e.g, ambush = e.xa or 0, bait = e.xb or 0, loot = e.xl or 0,
                conduct = conductWeight(), karma = K.LiveKarma and K.LiveKarma(sid) or nil}
        end
        stats.sent = stats.sent + 1
    else
        stats.denied = stats.denied + 1
    end
    local json = util.TableToJSON(out) or "{}"
    local data = util.Compress(json) or ""
    if #data > 60000 then data = util.Compress(util.TableToJSON({v = 1, allowed = allowed, lives = {}, tooBig = true})) or "" end
    net.Start("zckc_timeline")
    net.WriteUInt(#data, 16)
    net.WriteData(data, #data)
    net.Send(p)
end)
hook.Add("PlayerDisconnected", "ZCKillcam.TimelineAsk", function(p) nextAsk[p] = nil end)

-- ------------------------------------------------------------------------------------- staff
concommand.Add("zc_killcam_timeline", function(p, _, args)
    if IsValid(p) and not (K.IsOperator and K.IsOperator(p)) then return end
    local function say(text) if IsValid(p) then p:PrintMessage(HUD_PRINTCONSOLE, text) else print(text) end end
    local text = string.Trim(table.concat(args, " "))
    if text == "" then
        return say(string.format("[Killcam] timeline %s mode=%d | lives %d, events %d, app sends %d (%d refused), errors %d%s | give a name or SteamID64",
            TL.Version, MODE:GetInt(), stats.lives, stats.events, stats.sent, stats.denied, stats.errors, TL.lastError and (" (" .. TL.lastError .. ")") or ""))
    end
    local sid = text:match("^%d+$") and text or nil
    if not sid then
        local needle = string.lower(text)
        for _, q in ipairs(player.GetHumans and player.GetHumans() or player.GetAll()) do
            if string.find(string.lower(q:Nick()), needle, 1, true) then sid = q:SteamID64() break end
        end
    end
    if not sid then return say("[Killcam] nobody online matches '" .. text .. "' (a SteamID64 works for anyone)") end
    local list = load(sid)
    if #list == 0 then return say("[Killcam] no lives recorded for " .. sid) end
    for _, life in ipairs(list) do
        say(string.format("-- %s  %s %s  %s after %ds  karma %s -> %s", os.date("%Y-%m-%d %H:%M", life.at or 0), life.map or "?", life.mode or "",
            life.ended or "?", math.floor(life.span or 0), tostring(life.karma0 or "?"), tostring(life.karma1 or "?")))
        for _, e in ipairs(life.events or {}) do
            say(string.format("   %5.1fs  %s%s", e.t or 0, e.text or "", e.tag and ("  [" .. e.tag .. "]") or ""))
        end
    end
end)
