if not SERVER then return end
ZCObserverServer = ZCObserverServer or {}
local O = ZCObserverServer
O.Version = "20260926.observer2"
local mode = CreateConVar("zc_observer_mode", "2", FCVAR_ARCHIVE, "Afterlife: 0 staged/off, 1 owner preview, 2 public", 0, 2)
local owner = "76561198011536179"
local histories = setmetatable({}, {__mode="k"})
local lives = setmetatable({}, {__mode="k"})
local debriefs = setmetatable({}, {__mode="k"}) -- player -> {snapshot, life, round, gen}: this death's, for a re-send
local serial = 0
local generation = 0
util.AddNetworkString("ZCObserverSnapshot")

local function human(ply)
    return IsValid(ply) and ply:IsPlayer() and not ply:IsBot()
end
-- zc_observer_mode gates the SPECTATING tools (the dock, the ESP, the legacy HUD hooks below). A player's own death
-- debrief is their own data: the GoobOS death panel shows it whatever the mode (UI cohesion U1, 2026-09-26).
local function allowed(ply)
    return human(ply) and (mode:GetInt() == 2 or (mode:GetInt() == 1 and ply:SteamID64() == owner))
end
local function clean(value, limit)
    return tostring(value or ""):gsub("[%c]", " "):sub(1, limit or 80)
end
local function finite(value, maximum)
    value = tonumber(value) or 0
    if value ~= value or value == math.huge or value == -math.huge then return 0 end
    return math.Clamp(value, 0, maximum)
end
local function roundId() return math.floor(zb and zb.ROUND_START or 0) end
local function send(ply, snapshot)
    if not human(ply) then return end
    local data = util.TableToJSON(snapshot)
    if not data or #data > 24000 then return end
    net.Start("ZCObserverSnapshot")
    net.WriteUInt(#data, 16); net.WriteData(data, #data)
    net.Send(ply)
end

-- What kind of harm a hit was, for the death panel's cause line ("Shot", "Fall", ...). nil when the type says nothing.
local function kindOf(d)
    if d:IsFallDamage() then return "fall" end
    if d:IsExplosionDamage() then return "explosion" end
    if d:IsBulletDamage() or d:IsDamageType(DMG_BUCKSHOT) then return "bullet" end
    if d:IsDamageType(DMG_SLASH) then return "slash" end
    if d:IsDamageType(DMG_BURN) or d:IsDamageType(DMG_SLOWBURN) then return "burn" end
    if d:IsDamageType(DMG_DROWN) then return "drown" end
    if d:IsDamageType(DMG_CLUB) or d:IsDamageType(DMG_CRUSH) then return "blunt" end
    return nil
end

-- Personal injury history only; no global kill feed or role information.
hook.Add("HomigradDamage", "ZCObserver.Injury", function(victim, damage, hitgroup, body, harm)
    if IsValid(victim) and not victim:IsPlayer() and hg and hg.RagdollOwner then victim = hg.RagdollOwner(victim) end
    if not human(victim) or not victim:Alive() then return end
    local list = histories[victim] or {}; histories[victim] = list
    local attacker = damage:GetAttacker()
    local inflictor = damage:GetInflictor()
    local weapon = IsValid(inflictor) and not inflictor:IsPlayer() and inflictor:GetClass() or ""
    if weapon == "" and IsValid(attacker) and attacker:IsPlayer() then
        local held = attacker:GetActiveWeapon()
        if IsValid(held) then weapon = held:GetClass() end
    end
    list[#list+1] = {
        at=CurTime(), name=clean(IsValid(attacker) and attacker:IsPlayer() and attacker:Nick() or "Environment"),
        sid=IsValid(attacker) and attacker:IsPlayer() and clean(attacker:SteamID64(),20) or "",
        weapon=clean(weapon,64), group=math.floor(finite(hitgroup,16)), harm=finite(harm,10000),
    }
    local ok, kind = pcall(kindOf, damage)
    if ok and kind then list[#list].kind = kind end
    while #list > 24 do table.remove(list,1) end
end)

hook.Add("PlayerDeath", "ZCObserver.Debrief", function(victim, inflictor, attacker)
    if not human(victim) then return end
    serial = (serial + 1) % 4294967295
    local org = victim.organism or {}
    local now = CurTime()
    local snapshot = {
        serial=serial, map=game.GetMap(), round=roundId(), at=now,
        cause=IsValid(inflictor) and clean(inflictor:GetClass(),64) or "unknown",
        engineAttacker=IsValid(attacker) and attacker:IsPlayer() and clean(attacker:Nick()) or "Environment / unresolved",
        selfInflicted=attacker==victim,
        condition={blood=finite(org.blood,20000), pain=finite(org.pain,100000), pulse=finite(org.pulse,1000)},
        injuries={},
    }
    for _, hit in ipairs(histories[victim] or {}) do
        if now-hit.at <= 120 then
            local copy=table.Copy(hit); copy.ago=math.max(0,now-hit.at); copy.at=nil
            snapshot.injuries[#snapshot.injuries+1]=copy
        end
    end
    histories[victim]=nil
    -- Send after the engine's death state; never deliver an old death over a respawn.
    local uid=victim:UserID(); local epoch=snapshot.round; local life=lives[victim]; local gen=generation
    debriefs[victim]={snapshot=snapshot, life=life, round=epoch, gen=gen}
    timer.Simple(0,function()
        if IsValid(victim) and victim:UserID()==uid and not victim:Alive() and roundId()==epoch and lives[victim]==life and generation==gen then send(victim,snapshot) end
    end)
end)
hook.Add("PlayerSpawn", "ZCObserver.Spawn", function(ply)
    histories[ply]=nil
    debriefs[ply]=nil
    lives[ply]=(lives[ply] or 0)+1
    send(ply,{clear=true,round=roundId()})
end)
hook.Add("PlayerDisconnected", "ZCObserver.Gone", function(ply) histories[ply]=nil; lives[ply]=nil; debriefs[ply]=nil end)
hook.Add("ZB_PreRoundStart", "ZCObserver.Round", function()
    generation=generation+1
    histories=setmetatable({}, {__mode="k"})
    lives=setmetatable({}, {__mode="k"})
    debriefs=setmetatable({}, {__mode="k"})
    for _,ply in ipairs(player.GetHumans()) do send(ply,{clear=true,round=roundId()}) end
end)

-- The death panel asks for this death's debrief when it opens without one (the push above can land before the client
-- is listening). No payload; the reply is the same ZCObserverSnapshot, only for the asker's own current death.
local function resend(_, ply)
    local d=debriefs[ply]
    if d and not ply:Alive() and d.life==lives[ply] and d.round==roundId() and d.gen==generation then send(ply,d.snapshot) end
end
if US1 and US1.Net and US1.Net.Receive then
    US1.Net.Receive("ZCObserverDebriefRequest", {maxBits = 8, rate = 1}, resend)
else
    util.AddNetworkString("ZCObserverDebriefRequest")
    local asked=setmetatable({}, {__mode="k"})
    net.Receive("ZCObserverDebriefRequest", function(len, ply)
        if not human(ply) or len > 8 or (asked[ply] or 0) > RealTime() then return end
        asked[ply]=RealTime()+1
        resend(len, ply)
    end)
end

-- Exact legacy hooks only. Preview leaves other players' existing HUD untouched.
local legacy = {
    {"ZB_PreRoundStart","PAT_SpectatorAssist_ResetTimeline"},
    {"PlayerInitialSpawn","PAT_SpectatorAssist_SyncOnJoin"},
    {"PlayerDeath","PAT_SpectatorAssist_RecordDeath"},
    {"PlayerDeathThink","PAT_SpectatorAssist_VitalsSync"},
}
O.Legacy = O.Legacy or {}
local function configure()
    for _,p in ipairs(player.GetHumans()) do p:SetNWBool("ZCObserverEnabled",allowed(p)) end
    for _,item in ipairs(legacy) do
        local event,id=item[1],item[2]
        local fn=(hook.GetTable()[event] or {})[id]
        if mode:GetInt()==2 then
            if fn then O.Legacy[id]=fn; hook.Remove(event,id) end
        elseif O.Legacy[id] and not fn then hook.Add(event,id,O.Legacy[id]) end
    end
end
hook.Add("PlayerInitialSpawn","ZCObserver.Join",function(ply)
    timer.Simple(2,function() if IsValid(ply) then ply:SetNWBool("ZCObserverEnabled",allowed(ply)) end end)
end)
hook.Add("InitPostEntity","ZCObserver.LegacyOwnership",configure)
cvars.AddChangeCallback("zc_observer_mode",function() configure() end,"ZCObserver.Mode")
configure()
