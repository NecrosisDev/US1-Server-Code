-- Personality-driven social events. No combat state is authored here.
if not SERVER then return end
local D = hg.botdriver
local S = D.social or { epoch = 0 }
D.social = S
S.epoch = S.epoch + 1
S.peers = S.peers or setmetatable({}, {__mode = "k"})
S.bots = S.bots or setmetatable({}, {__mode = "k"})
S.lives = S.lives or setmetatable({}, {__mode = "k"})
S.lastPM = S.lastPM or -math.huge
S.sent = S.sent or 0
S.lastAmbient = S.lastAmbient or -math.huge
S.roundOpenedAt = S.roundOpenedAt or CurTime()
S.roleSaid = S.roleSaid or setmetatable({}, {__mode = "k"})
local cv = GetConVar("zc_bots_chatter")
local cvPM = GetConVar("zc_bots_social_pm") or CreateConVar("zc_bots_social_pm", "1", FCVAR_ARCHIVE, "Bot private compliments and replies", 0, 1)

local function enabled(bot)
    return cv and cv:GetBool() and D.Enabled() and IsValid(bot) and bot:IsPlayer()
        and bot:IsBot() and bot.zcBot and not bot.zcBotBenched
end
local function spectator(p)
    return not p:Alive() or p:Team() == TEAM_SPECTATOR
end
local function human(p)
    return IsValid(p) and p:IsPlayer() and not p:IsBot()
end
local function state(store, p)
    store[p] = store[p] or {at = -math.huge, count = 0, unsolicited = 0, recent = {}}
    return store[p]
end
local function pick(event, personality, history, sameContext)
    local bank = D.socialLines[event]
    if not bank then return end
    local primary = bank[personality.archetype] or bank.default
    local alternate = bank.default ~= primary and bank.default or nil
    -- WS-chat-realism (C3): a repeated same-context PM within 3 minutes
    -- prefers the OTHER pool first, so the same event doesn't always answer
    -- from the same bank twice in a row.
    local pool = (sameContext and alternate) or primary
    local choices = {}
    for _, line in ipairs(pool) do
        if not table.HasValue(history, line) then choices[#choices + 1] = line end
    end
    if #choices == 0 and pool ~= primary then
        for _, line in ipairs(primary) do
            if not table.HasValue(history, line) then choices[#choices + 1] = line end
        end
    end
    if #choices == 0 then choices = bank.default end
    return choices[math.random(#choices)]
end
local function cancel(p)
    if not IsValid(p) then return end
    timer.Remove("zc_bots_social_pm_" .. p:EntIndex())
    timer.Remove("zc_bots_social_banter_" .. p:EntIndex())
    local b = S.bots[p]
    if b then b.pending = nil end
    S.lives[p] = (S.lives[p] or 0) + 1
end

-- Bounded queue: one pending line per bot, six received lines per human per
-- round, at most one unsolicited compliment every three minutes, and no instant pile-on.
function S.QueuePM(bot, recipient, event, unsolicited)
    if not enabled(bot) or not cvPM:GetBool() or not human(recipient) or recipient.zcBotPMOff
        or not ZCChatPM or not ZCChatPM.SendBot then return false end
    local now = CurTime()
    local b, p = state(S.bots, bot), state(S.peers, recipient)
    if b.pending or now - b.at < 20 or now - p.at < 18 or now - S.lastPM < 2
        or p.count >= 6 or (unsolicited and (p.unsolicited >= 1 or now - (p.lastUnsolicited or -math.huge) < 180)) then return false end
    local delay
    if D.chat and D.chat.ReplyDelay then
        delay = D.chat.ReplyDelay(bot, "pm")
        if not delay then return false end
    else
        delay = math.Rand(3, 6)
    end
    local sameContext = p.lastEvent == event and now - (p.lastEventAt or -math.huge) < 180
    local line = pick(event, D.GetPersonality(bot), p.recent, sameContext)
    if not line then return false end
    p.lastEvent, p.lastEventAt = event, now
    b.pending, b.at, p.at, S.lastPM = true, now, now, now
    p.count = p.count + 1
    if unsolicited then p.unsolicited = p.unsolicited + 1; p.lastUnsolicited = now end
    p.recent[#p.recent + 1] = line
    if #p.recent > 8 then table.remove(p.recent, 1) end
    local epoch, botLife, humanLife = S.epoch, S.lives[bot], S.lives[recipient]
    local botAlive, humanAlive = bot:Alive(), recipient:Alive()
    local function valid()
        return epoch == S.epoch and enabled(bot) and human(recipient) and cvPM:GetBool()
            and not recipient.zcBotPMOff and S.lives[bot] == botLife and S.lives[recipient] == humanLife
            and bot:Alive() == botAlive and recipient:Alive() == humanAlive
    end
    local attempts = 0
    local function deliver()
        if not valid() then b.pending = nil return end
        attempts = attempts + 1
        local brain = D.brains[bot]
        local queued = not (brain and IsValid(brain.target)) and D.chatTyping.SendWithTyping(bot, line, function(speaker, text)
            b.pending = nil
            if valid() and ZCChatPM and ZCChatPM.SendBot and ZCChatPM.SendBot(speaker, recipient, text) then
                S.sent = S.sent + 1
            end
        end, true)
        if not queued and attempts < 3 then
            timer.Create("zc_bots_social_pm_" .. bot:EntIndex(), 4, 1, deliver)
        elseif not queued then b.pending = nil end
    end
    timer.Create("zc_bots_social_pm_" .. bot:EntIndex(), delay, 1, deliver)
    -- Typing may be interrupted by combat without invoking its callback.
    -- A later request may release this reservation after the bounded timeout.
    b.expires = now + 24
    return true
end

function S.ReplyEvent(text)
    text = string.Trim(string.lower(text))
    local function word(w) return text:find("%f[%a]" .. w .. "%f[%A]") ~= nil end
    -- Intent only; never echo private content or answer tactical questions.
    if word("idiot") or word("trash") or word("hate") or word("cheater") then return "pm_salt" end
    if word("sorry") or text:find("my bad",1,true) then return "pm_apology" end
    if word("thanks") or word("ty") or word("nice") or word("gg") or text:find("good shot",1,true) then return "pm_kind" end
    if #text < 32 and (word("hi") or word("hey") or word("hello") or word("yo") or word("sup")) then return "pm_greeting" end
    if text:find("?",1,true) or word("where") or word("who") or word("why") or word("how") then return "pm_question" end
    return "pm_reply"
end
hook.Add("ZCChatPMDelivered", "zc_bots_social_reply", function(sender, target, text)
    if not human(sender) or not enabled(target) then return end
    local p = state(S.peers, sender)
    local now = CurTime()
    if p.silentUntil and now < p.silentUntil then return end

    p.pmTimes = p.pmTimes or {}
    local times = p.pmTimes
    local i = 1
    while i <= #times do
        if now - times[i] > 60 then table.remove(times, i) else i = i + 1 end
    end
    times[#times + 1] = now

    -- WS-chat-realism (C3): 3+ PMs in 60s to a bot that is actually alive
    -- gets one pm_busy line, then 90s of silence toward that human.
    if #times >= 3 and target:Alive() then
        p.silentUntil = now + 90
        S.QueuePM(target, sender, "pm_busy", false)
        return
    end

    S.QueuePM(target, sender, S.ReplyEvent(text), false)
end)
concommand.Add("zc_bot_pm", function(p, _, args)
    if not human(p) then return end
    p.zcBotPMOff = args[1] == "0"
    p:ChatPrint(p.zcBotPMOff and "Bot private messages disabled for this session." or "Bot private messages enabled.")
end, nil, "Bot private messages for this session: zc_bot_pm 0 turns them off, zc_bot_pm 1 back on.")

local teamModes = {tdm=true,gwars=true,cstrike=true,hl2dm=true,criresp=true,coop=true,defense=true,riot=true,["Cops/Gangsters"]=true}
function S.NiceKill(victim, attacker, inflictor)
    local mode = zb and (zb.CROUND_MAIN or zb.CROUND)
    if teamModes[mode] and not D.IsFFA() and D.TeamOf(victim) == D.TeamOf(attacker) then return false end
    if victim.LastHitGroup and victim:LastHitGroup() == HITGROUP_HEAD then return true end
    if victim:GetPos():DistToSqr(attacker:GetPos()) >= 1000 * 1000 or attacker:Health() <= 25 then return true end
    local w = IsValid(inflictor) and inflictor ~= attacker and inflictor or attacker:GetActiveWeapon()
    local class = IsValid(w) and w:GetClass() or ""
    return class:find("knife",1,true) ~= nil or class:find("melee",1,true) ~= nil or class == "weapon_hands_sh"
end
hook.Add("PlayerDeath", "zc_bots_social_kill", function(victim, inflictor, attacker)
    if not IsValid(victim) or not victim:IsPlayer() then return end
    cancel(victim)
    if not IsValid(attacker) or not attacker:IsPlayer() or victim == attacker then return end
    local bot, peer, event
    if enabled(victim) and human(attacker) then bot, peer, event = victim, attacker, "pm_lost"
    elseif enabled(attacker) and human(victim) then bot, peer, event = attacker, victim, "pm_won"
    else return end
    if not S.NiceKill(victim,attacker,inflictor) then return end
    local p = D.GetPersonality(bot)
    if math.random() < .10 + (p.sportsmanship or .5) * .12 then S.QueuePM(bot,peer,event,true) end
end)

-- Only public roles get distinctive public lines. All Homicide alignments
-- use exactly the same bank: repeated dialogue cannot become a role detector.
function S.RoleEvent(bot)
    local mode = zb and (zb.CROUND_MAIN or zb.CROUND)
    if D.homicide and D.homicide.Active() then return "role_homicide" end
    if mode == "criresp" then return bot:Team() == 0 and "role_police" or "role_criminal" end
    if mode == "Cops/Gangsters" then return bot:Team() == 1 and "role_police" or "role_criminal" end
    if mode == "gwars" then return "role_gang" end
    if mode == "defense" or mode == "coop" then return "role_defense" end
    return "role_fighter"
end
function S.LiveEvent(bot, b)
    if bot:Health() <= 40 then return "live_hurt" end
    if IsValid(b.doorTarget) or IsValid(b.doorBreachDoor) then return "live_door" end
    if b.medicPatient and IsValid(b.medicPatient) then return "role_medic" end
    if b.heardAt and CurTime() - b.heardAt < 10 then return "live_heard" end
    if not S.roleSaid[bot] and CurTime() - S.roundOpenedAt < 60 then return S.RoleEvent(bot) end
    return nil
end
local function hasSpectator()
    for _, p in ipairs(player.GetHumans()) do if spectator(p) then return true end end
    return false
end
local function banterReply(speaker)
    local epoch = S.epoch
    for other, b in RandomPairs(D.brains) do
        if other ~= speaker and enabled(other) and spectator(other) then
            timer.Create("zc_bots_social_banter_" .. other:EntIndex(), math.Rand(7, 11), 1, function()
                if epoch ~= S.epoch or not enabled(other) or not spectator(other) or not enabled(speaker)
                    or not spectator(speaker) or not hasSpectator() then return end
                D.ChatterSpeak(other,b,"spec_reply",nil,.95,false,{spectatorOnly=true,validate=spectator})
            end)
            break
        end
    end
end
timer.Create("zc_bots_social_ambient", 10, 0, function()
    for _, b in pairs(S.bots) do if b.pending and CurTime() > (b.expires or 0) then b.pending = nil end end
    if not cv or not cv:GetBool() or not D.Enabled() or #player.GetHumans() == 0 then return end
    if CurTime() - S.lastAmbient < 55 then return end
    for bot, b in RandomPairs(D.brains) do
        if enabled(bot) then
            if spectator(bot) and hasSpectator() then
                if D.ChatterSpeak(bot,b,"spec_open",nil,.24,false,{spectatorOnly=true,validate=spectator,after=banterReply}) then S.lastAmbient = CurTime() break end
            elseif bot:Alive() and D.RoundAllowsCombat() and not IsValid(b.target) then
                local event = S.LiveEvent(bot,b)
                -- WS-chat-realism (C1): the round-open role/ambient line is a
                -- "roundstart" moment -- at most one bot server-wide gets to
                -- say one within a 90s window of round open.
                local isRoleEvent = event and event:sub(1,5) == "role_"
                local momentOK = not isRoleEvent or not D.chat or not D.chat.MomentAllowed
                    or D.chat.MomentAllowed("roundstart", 1, 90)
                if event and momentOK and D.ChatterSpeak(bot,b,event,nil,.16,true,{after=function()
                    if event:sub(1,5) == "role_" then S.roleSaid[bot] = true end
                end,validate=function(p)
                    return D.RoundAllowsCombat() and not spectator(p) and not IsValid(b.target) and S.LiveEvent(p,b)==event
                end}) then S.lastAmbient = CurTime() break end
            end
        end
    end
end)

hook.Add("PlayerSpawn", "zc_bots_social_spawn", cancel)
hook.Add("PlayerDisconnected", "zc_bots_social_disconnect", function(p)
    cancel(p)
    S.peers[p], S.bots[p], S.lives[p] = nil, nil, nil
end)
local function reset()
    S.epoch = S.epoch + 1
    S.roundOpenedAt = CurTime()
    S.roleSaid = setmetatable({}, {__mode = "k"})
    for _, p in ipairs(player.GetAll()) do cancel(p) end
    for _, p in pairs(S.peers) do p.count, p.unsolicited = 0, 0 end
end
hook.Add("ZB_EndRound", "zc_bots_social_end", reset)
hook.Add("ZB_PreRoundStart", "zc_bots_social_round", reset)
hook.Add("ZB_StartRound", "zc_bots_social_open", function() S.roundOpenedAt = CurTime() end)
for _, p in ipairs(player.GetAll()) do cancel(p) end
