-- Goob's ZCity: modest, server-authoritative friendly-fire brain feedback.
-- TDM-family allies take 75% incoming damage; every other mode gets no added reduction.
if not SERVER then return end
ZCityFFBrain = ZCityFFBrain or {}
local F = ZCityFFBrain
F.Version = "20260916.2"
F.states = F.states or setmetatable({}, { __mode = "k" })
F.events = setmetatable({}, { __mode = "k" })
F.Settings = { grace = 20, decay = 2, decayDelay = 3, scale = 0.0005,
    burstTime = 0.5, burstCap = 0.0175, lifeCap = 0.10, absoluteCap = 0.125,
    victimScale = 1, tdmVictimScale = 0.75, unarmed = 0.25, other = 0.75, bullet = 1.25, blast = 1.50, hitCap = 100 }
local enabled = CreateConVar("zc_ff_brain_enabled", "1", FCVAR_ARCHIVE,
    "Reflect repeated friendly fire as modest brain injury", 0, 1)
local grace = CreateConVar("zc_ff_brain_grace", "20", FCVAR_ARCHIVE,
    "Weighted friendly damage forgiven before brain injury", 0, 100)
local scale = CreateConVar("zc_ff_brain_scale", "1", FCVAR_ARCHIVE,
    "Brain injury multiplier (hard safety caps still apply)", 0, 2)
local teamModes = { tdm = true, cstrike = true, hl2dm = true, gwars = true,
    criresp = true, wildcard = true, riot = true, uncontainedriot = true,
    coop = true, defense = true }
local hands = { weapon_hands_sh = true, weapon_hg_coolhands = true, weapon_fists = true }
local function finite(n) return isnumber(n) and n == n and math.abs(n) < math.huge end
local function playerEntity(e) return IsValid(e) and e:IsPlayer() end
function F.AdminImmune(p)
    return playerEntity(p) and (p:IsAdmin() or p:IsSuperAdmin())
end
function F.PlayerBody(e)
    if playerEntity(e) then return e end
    if not IsValid(e) then return end
    local p = hg and hg.RagdollOwner and hg.RagdollOwner(e)
    if playerEntity(p) and p:Alive() and p.FakeRagdoll == e then return p end
end
function F.Attacker(info)
    local a = info:GetAttacker()
    if playerEntity(a) then return a end
    local p = F.PlayerBody(a)
    if p then return p end
    for _, e in ipairs({ a, info:GetInflictor() }) do
        if IsValid(e) then
            for _, owner in pairs({ e:GetOwner(), e.Owner, e.owner, e.HBOWNER,
                e.GetDriver and e:GetDriver(), e.GetPhysicsAttacker and e:GetPhysicsAttacker(10) }) do
                if playerEntity(owner) then return owner end
            end
        end
    end
end
function F.ModeKind(mode)
    if ZCityKarmaBounties and ZCityKarmaBounties.Kind then
        local kind=ZCityKarmaBounties.Kind(mode)
        return kind=="homicide" and "innocent" or kind
    end
    local seen = {}
    for depth = 1, 12 do
        if not istable(mode) or seen[mode] then return end
        seen[mode] = true
        if mode.name == "hmcd" or mode.name == "fear" then return "innocent" end
        if teamModes[mode.name] then return "team" end
        mode = zb and zb.modes and zb.modes[mode.base]
    end
end
function F.Friendly(a, v)
    if not playerEntity(a) or not playerEntity(v) or a == v or not a:Alive() then return false end
    if not zb or zb.ROUND_STATE ~= 1 or not isfunction(CurrentRound) then return false end
    for _, p in ipairs({ a, v }) do
        if p:Team() == TEAM_SPECTATOR or p:Team() == TEAM_UNASSIGNED then return false end
    end
    local kind = F.ModeKind(CurrentRound())
    if kind == "innocent" then return (not not a.isTraitor) == (not not v.isTraitor) end
    return kind == "team" and a:Team() == v:Team()
end
function F.Weight(info)
    local s = F.Settings
    if info:IsDamageType(DMG_BLAST) then return s.blast end
    if info:IsDamageType(DMG_BULLET + DMG_BUCKSHOT + DMG_SNIPER) then return s.bullet end
    local inf = info:GetInflictor()
    if IsValid(inf) and hands[inf:GetClass()] and info:IsDamageType(DMG_CLUB) then return s.unarmed end
    return s.other
end
function F.Capture(v, info, creatureHit)
    if not enabled:GetBool() or not playerEntity(v) or not v:Alive() then return end
    local a, amount = F.Attacker(info), info:GetDamage()
    if not F.Friendly(a, v) or not finite(amount) or amount <= 0 then return end
    if v.organism and (v.organism.alive == false or (v.organism.godmode and not creatureHit)) then return end
    local J=ZCityGuiltJustice
    local policy=J and J.Assess and J.Assess(a,v,CurrentRound())
    if policy then J.Remember(a,v,policy) end
    return { attacker = a, victim = v, policy=policy, feedbackScale=policy and policy.scale or 0,
        damage = math.min(amount, F.Settings.hitCap),
        weight = F.Weight(info), multiplier = (F.ModeKind(CurrentRound()) == "innocent" and a.isTraitor and v.isTraitor) and 2 or 1,
        round = zb.ROUND_START, mode = CurrentRound(), time = CurTime() }
end
function F.Event(v, info, creatureHit)
    local context = F.nativeContexts and F.nativeContexts[v]
    if context and context.attacker == F.Attacker(info) then return context end
    local tick = engine.TickCount()
    if F.eventTick ~= tick then F.events = setmetatable({}, { __mode = "k" }); F.eventTick = tick end
    F.events[info] = F.events[info] or {}
    local row = F.events[info][v]
    if not row then row = F.Capture(v, info, creatureHit); F.events[info][v] = row end
    return row
end
function F.Apply(row, amount)
    if not row or row.counted then return end
    row.counted = true
    if F.AdminImmune(row.attacker) then F.states[row.attacker]=nil;return 0 end
    if not row.feedbackScale or row.feedbackScale <= 0 then return 0 end
    local a, s, now = row.attacker, F.Settings, CurTime()
    if not enabled:GetBool() or not playerEntity(a) or not a:Alive() then return end
    if not zb or zb.ROUND_STATE ~= 1 or zb.ROUND_START ~= row.round or CurrentRound() ~= row.mode then return end
    local org = a.organism
    if not istable(org) or not finite(org.brain) or org.alive == false then return end
    local state = F.states[a]
    if not state or state.org ~= org then
        state = { org = org, score = 0, last = now, added = 0, burst = now, used = 0 }
        F.states[a] = state
    end
    local before = math.max(0, state.score - math.max(0, now - state.last - s.decayDelay) * s.decay)
    local damage = finite(amount) and math.min(math.max(amount, 0), row.damage) or row.damage
    local score = before + damage * row.weight
    local excess = math.max(0, score - grace:GetFloat()) - math.max(0, before - grace:GetFloat())
    state.score, state.last = math.min(score, 250), now
    if now - state.burst >= s.burstTime then state.burst, state.used = now, 0 end
    local add = math.max(0, math.min(excess * s.scale * scale:GetFloat() * (row.multiplier or 1) * row.feedbackScale,
        s.burstCap * (row.multiplier or 1) - state.used, s.lifeCap - state.added, s.absoluteCap - org.brain))
    if add <= 0 then return 0 end
    if ZCityMetaSafety and ZCityMetaSafety.Locked() then
        add=ZCityMetaSafety.QueueBrain(a,add)
        state.added,state.used=state.added+add,state.used+add
        return add
    end
    -- Direct organ change: no synthetic gunshot, shock, skull damage, or reflection recursion.
    org.brain = org.brain + add
    state.added, state.used = state.added + add, state.used + add
    F.QueueSync(a, org)
    return add
end
function F.OnPre(v, info, hitgroup, body)
    v = F.PlayerBody(v) or F.PlayerBody(body)
    if v then F.Reduce(F.Event(v, info), info) end
end
function F.OnHarm(v, info, hitgroup, body, harm)
    v = F.PlayerBody(v) or F.PlayerBody(body)
    if not v or not finite(harm) or harm <= 0 then return end
    F.Apply(F.Event(v, info))
end
function F.OnPost(ent, info, tookDamage)
    local v = F.PlayerBody(ent)
    if not v then return end
    local recent = F.recent and F.recent[v]
    if F.recent then F.recent[v] = nil end
    if not tookDamage then return end
    local row = recent and recent.tick == engine.TickCount()
        and recent.row.attacker == F.Attacker(info) and recent.row or F.Event(v, info)
    F.Apply(row, info:GetDamage() / (row and row.retained or 1))
end
hook.Add("PreHomigradDamage", "ZCityFFBrain_Capture", F.OnPre)
hook.Add("HomigradDamage", "ZCityFFBrain_Harm", F.OnHarm)
-- Keep one damage transaction through player-to-ragdoll forwarding. Engine
-- callbacks can wrap the same C++ damage record in different Lua userdata.
F.nativeContexts = F.nativeContexts or setmetatable({}, {__mode="k"})
F.recent = F.recent or setmetatable({}, {__mode="k"})
function F.InstallNativeBridge()
    local t=hook.GetTable().EntityTakeDamage
    local current=t and t["homigrad-damage"]
    if not isfunction(current) then return end
    local old=F.nativeBridge
    local c=ZCityPillCompat
    local outer=c and c.wraps and c.wraps[t] and c.wraps[t]["homigrad-damage"]
    if old and (current==old.wrapper
        or (outer and current==outer.wrapper and outer.original==old.wrapper)) then old.version=F.Version;return end
    local previous=old and current==old.wrapper and old.original or current
    local function packed(...) return {n=select("#",...),...} end
    local wrapper=function(ent,info,...)
        local v=F.PlayerBody(ent)
        if not v then return previous(ent,info,...) end
        local parent=F.nativeContexts[v]
        local row=F.Event(v,info)
        if row then F.nativeContexts[v]=row end
        local args=packed(...)
        local result=packed(pcall(previous,ent,info,unpack(args,1,args.n)))
        F.nativeContexts[v]=parent
        if not result[1] then error(result[2],0) end
        return unpack(result,2,result.n)
    end
    F.nativeBridge={original=previous,wrapper=wrapper,version=F.Version}
    hook.Add("EntityTakeDamage","homigrad-damage",wrapper)
end

-- Modify incoming magnitude once, then let the native damage pipeline continue.
function F.VictimScale(mode)
    if ZCityKarmaBounties and ZCityKarmaBounties.Kind(mode)=="homicide" then return 1 end
    local seen={}
    for _=1,12 do
        if not istable(mode) or seen[mode] then return F.Settings.victimScale end
        seen[mode]=true
        if mode.name=="tdm" or mode.base=="tdm" then return F.Settings.tdmVictimScale end
        mode=zb and zb.modes and zb.modes[mode.base]
    end
    return F.Settings.victimScale
end
function F.Reduce(row, info)
    if not row or row.reduced then return end
    row.reduced = true
    row.retained = F.VictimScale(row.mode)
    if row.retained ~= 1 then info:ScaleDamage(row.retained) end
end
function F.OnIncoming(ent, info)
    local v = F.PlayerBody(ent)
    if not v then return end
    -- A hidden morph carrier is not a second valid damage target.
    local c = ZCityPillCompat
    if c and c.IsCarrier and c.IsCarrier(v) then return end
    local row = F.Event(v, info)
    F.Reduce(row, info)
    if row then F.recent[v] = {row=row,tick=engine.TickCount()} end
    -- Deliberately no boolean return: this addon never blocks the hit.
end
function F.InstallDamagePriority()
    F.InstallNativeBridge()
    if not hook.GetULibTable then return end
    local name = "ZCityFFBrain_Capture"
    local current = (hook.GetTable().EntityTakeDamage or {})[name]
    local all = hook.GetULibTable().EntityTakeDamage
    local high = all and all[-1] and all[-1][name]
    -- Pill compatibility can wrap/re-register callbacks. Preserve its wrapper
    -- while restoring high priority; monitor priority would swallow its block.
    if current and (not high or high.fn ~= current) then
        hook.Add("EntityTakeDamage", name, current, -1)
    end
end
hook.Add("EntityTakeDamage", "ZCityFFBrain_Capture", F.OnIncoming, -1)
hook.Add("InitPostEntity", "ZCityFFBrain_Priority", F.InstallDamagePriority)
timer.Create("ZCityFFBrain_Priority", 0.25, 0, F.InstallDamagePriority)

hook.Add("PostEntityTakeDamage", "ZCityFFBrain_Fallback", F.OnPost)
function F.InstallPillBridge()
    local c = ZCityPillCompat
    if not c or not isfunction(c.Damage) or not isfunction(c.Body) then return end
    local old = F.pillBridge
    if old and c.Damage == old.wrapper and old.version == F.Version then return end
    local previous = old and c.Damage == old.wrapper and old.original or c.Damage
    local wrapper = function(ent, info)
        local morph, v = c.Body(ent)
        local row = v and F.Event(v, info, true)
        local hp, state = v and v:Health(), v and c.states[v]
        local bounty = ZCityKarmaBounties and v and ZCityKarmaBounties.BeginPill(v, info)
        F.Reduce(row, info)
        local result = previous(ent, info)
        if v then
            local killed = not v:Alive() or (state and state.dying) or morph.dead
            local loss = killed and hp or math.max(0, hp - v:Health())
            if row and loss > 0 then F.Apply(row, loss / (row.retained or 1)) end
            if bounty then ZCityKarmaBounties.EndPill(bounty, info, loss, killed) end
        end
        return result
    end
    F.pillBridge = { original = previous, wrapper = wrapper, version = F.Version }
    c.Damage = wrapper
end
hook.Add("InitPostEntity", "ZCityFFBrain_Pills", F.InstallPillBridge)
timer.Create("ZCityFFBrain_Pills", 1, 0, F.InstallPillBridge)
F.InstallPillBridge()
-- Low-karma injury is time-based, not an extra hit or a change to karma itself.
local karmaEnabled = CreateConVar("zc_karma_brain_enabled", "1", FCVAR_ARCHIVE,
    "Gradually add mild brain injury below 10 karma during active rounds", 0, 1)
local karmaScale = CreateConVar("zc_karma_brain_scale", "1", FCVAR_ARCHIVE,
    "Low-karma injury rate multiplier; total injury safety caps remain", 0, 2)
F.sync = F.sync or setmetatable({}, { __mode = "k" })
function F.QueueSync(ply, org)
    if F.sync[ply] == org then return end
    F.sync[ply] = org
    timer.Simple(0.1, function()
        if F.sync[ply] ~= org then return end
        F.sync[ply] = nil
        if not playerEntity(ply) or not ply:Alive() or ply.organism ~= org then return end
        ply.fullsend = true
        if hg and isfunction(hg.send_organism) then hg.send_organism(org, ply) end
    end)
end
function F.KarmaRate(karma)
    if not finite(karma) or karma >= 10 then return 0 end
    local deficit = (50 - math.Clamp(karma, 0, 50)) / 25
    local rate = 0.00025 + 0.00075 * deficit
    return rate * 2
end
function F.KarmaStep(ply, elapsed)
    if not karmaEnabled:GetBool() or not zb or zb.ROUND_STATE ~= 1 then return 0 end
    if not playerEntity(ply) or not ply:Alive() or ply:Team() == TEAM_SPECTATOR
        or ply:Team() == TEAM_UNASSIGNED then return 0 end
    local org = ply.organism
    if not istable(org) or org.alive == false or not finite(org.brain) then return 0 end
    local karma = ZCityMetaSafety and ZCityMetaSafety.Public(ply) or ply.Karma
    if not finite(karma) and isfunction(ply.guilt_GetValue) then karma = ply:guilt_GetValue() end
    local rate = F.KarmaRate(karma)
    if rate <= 0 or not finite(elapsed) or elapsed <= 0 then return 0 end
    local add = math.max(0, math.min(rate * math.min(elapsed, 2) * karmaScale:GetFloat(), F.Settings.absoluteCap - org.brain))
    if add <= 0 then return 0 end
    org.brain = org.brain + add
    F.QueueSync(ply, org)
    return add
end
F.karmaLast = CurTime()
function F.KarmaTick()
    local now = CurTime()
    local dt = math.Clamp(now - (F.karmaLast or now), 0, 2)
    F.karmaLast = now -- Do not charge for hibernation, death, or a paused round.
    for _, ply in ipairs(player.GetAll()) do F.KarmaStep(ply, dt) end
end
timer.Create("ZCityFFBrain_Karma", 1, 0, F.KarmaTick)

function F.ResetPlayer(ply)
    F.states[ply] = nil
    if F.recent then F.recent[ply] = nil end
    if F.sync then F.sync[ply] = nil end
    if F.karmaNotices then F.karmaNotices[ply] = nil end
end
function F.ResetRound()
    F.states = setmetatable({}, { __mode = "k" })
    F.events = setmetatable({}, { __mode = "k" })
    F.karmaLast = CurTime()
    F.recent = setmetatable({}, {__mode="k"})
end
hook.Add("PlayerSpawn", "ZCityFFBrain_Reset", function(ply)
    if OverrideSpawn then return end
    if ZCityPillCompat and IsValid(ZCityPillCompat.Morph(ply)) then return end
    F.ResetPlayer(ply)
end)
hook.Add("Org Clear", "ZCityFFBrain_Reset", function(org)
    for ply, state in pairs(F.states) do if state.org == org then F.ResetPlayer(ply) end end
end)
hook.Add("PostPlayerDeath", "ZCityFFBrain_Reset", F.ResetPlayer)
hook.Add("PlayerDisconnected", "ZCityFFBrain_Reset", F.ResetPlayer)
hook.Add("ZB_PreRoundStart", "ZCityFFBrain_Reset", F.ResetRound)
hook.Add("ZB_EndRound", "ZCityFFBrain_Reset", F.ResetRound)
hook.Add("PostCleanupMap", "ZCityFFBrain_Reset", F.ResetRound)
concommand.Add("zc_ff_brain_status", function(ply)
    if IsValid(ply) and not ply:IsAdmin() then return end
    local mode = isfunction(CurrentRound) and CurrentRound()
    print("[ZCityFFBrain]", F.Version, "enabled", enabled:GetBool(),
        "mode", mode and mode.name, "kind", F.ModeKind(mode), "grace", grace:GetFloat(), "victimScale", F.VictimScale(mode),
        "karmaEnabled", karmaEnabled:GetBool(), "karmaScale", karmaScale:GetFloat())
end, nil, "Admin: print friendly-fire brain settings for the current mode.")
-- Normal loads are silent; errors and requested status output are preserved.

F.InstallDamagePriority()

for p in pairs(F.states) do if F.AdminImmune(p) then F.states[p]=nil end end
