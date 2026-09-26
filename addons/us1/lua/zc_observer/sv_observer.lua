if not SERVER then return end
ZCObserverServer = ZCObserverServer or {}
local O = ZCObserverServer
O.Version = "20260922.observer1"
local mode = CreateConVar("zc_observer_mode", "2", FCVAR_ARCHIVE, "Afterlife: 0 staged/off, 1 owner preview, 2 public", 0, 2)
local owner = "76561198011536179"
local histories = setmetatable({}, {__mode="k"})
local lives = setmetatable({}, {__mode="k"})
local serial = 0
local generation = 0
util.AddNetworkString("ZCObserverSnapshot")

local function allowed(ply)
    return IsValid(ply) and ply:IsPlayer() and not ply:IsBot()
        and (mode:GetInt() == 2 or (mode:GetInt() == 1 and ply:SteamID64() == owner))
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
    if not allowed(ply) then return end
    local data = util.TableToJSON(snapshot)
    if not data or #data > 24000 then return end
    net.Start("ZCObserverSnapshot")
    net.WriteUInt(#data, 16); net.WriteData(data, #data)
    net.Send(ply)
end

-- Personal injury history only; no global kill feed or role information.
hook.Add("HomigradDamage", "ZCObserver.Injury", function(victim, damage, hitgroup, body, harm)
    if IsValid(victim) and not victim:IsPlayer() and hg and hg.RagdollOwner then victim = hg.RagdollOwner(victim) end
    if not allowed(victim) or not victim:Alive() then return end
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
    while #list > 24 do table.remove(list,1) end
end)

hook.Add("PlayerDeath", "ZCObserver.Debrief", function(victim, inflictor, attacker)
    if not allowed(victim) then return end
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
    timer.Simple(0,function()
        if IsValid(victim) and victim:UserID()==uid and not victim:Alive() and roundId()==epoch and lives[victim]==life and generation==gen then send(victim,snapshot) end
    end)
end)
hook.Add("PlayerSpawn", "ZCObserver.Spawn", function(ply)
    histories[ply]=nil
    lives[ply]=(lives[ply] or 0)+1
    if allowed(ply) then send(ply,{clear=true,round=roundId()}) end
end)
hook.Add("PlayerDisconnected", "ZCObserver.Gone", function(ply) histories[ply]=nil; lives[ply]=nil end)
hook.Add("ZB_PreRoundStart", "ZCObserver.Round", function()
    generation=generation+1
    histories=setmetatable({}, {__mode="k"})
    lives=setmetatable({}, {__mode="k"})
    for _,ply in ipairs(player.GetHumans()) do if allowed(ply) then send(ply,{clear=true,round=roundId()}) end end
end)

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
