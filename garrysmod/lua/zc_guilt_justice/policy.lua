-- Shared server-side combat eligibility. Bounty price is deliberately not a defence test.
local J=assert(ZCityGuiltJustice)
J.PolicyVersion="20260915.1"
J.latest=J.latest or setmetatable({},{__mode="k"})
function J.Allied(a,v,mode,attackTeam)
    if not J.Player(a) or not J.Player(v) or a==v then return false end
    local kind=ZCityKarmaBounties.Kind(mode)
    if kind=="homicide" then return (not not a.isTraitor)==(not not v.isTraitor),kind end
    return kind=="team" and (attackTeam or a:Team())==v:Team(),kind
end
function J.Defending(a,v)
    local K=ZCityKarmaBounties
    if not J.Player(a) or not J.Player(v) or not K.Active() then return false end
    local row=J.hostility[J.ID(a)]
    row=row and row[J.ID(v)]
    return row~=nil and row.round==K.RoundKey() and row.untilTime>=CurTime()
        and row.targetLife==K.GetLife(a).justiceId
        and row.sourceLife==K.GetLife(v).justiceId
end
function J.Assess(a,v,mode,attackTeam)
    local p={allied=false,scale=0,reason="invalid",defending=false}
    if not J.Player(a) or not J.Player(v) or a==v then return p end
    if a:Team()>=1000 or v:Team()>=1000 then return p end
    if not zb or zb.ROUND_STATE~=1 then p.reason="inactive";return p end
    mode=mode or CurrentRound()
    local K=ZCityKarmaBounties
    p.allied,p.kind=J.Allied(a,v,mode,attackTeam)
    p.attackerTraitor,p.victimTraitor=not not a.isTraitor,not not v.isTraitor
    p.force=isfunction(zb.IsForce) and zb.IsForce(a) or false
    local protected=p.allied or (p.kind=="homicide" and p.force and v.isTraitor and not a.isTraitor)
    if not protected then p.reason="enemy";return p end
    if mode.GuiltDisabled or (GetConVar("zb_dev") and GetConVar("zb_dev"):GetBool())
        or K.Excluded(a) or K.Excluded(v) then p.reason="mode_exempt";return p end
    if J.Defending(a,v) then p.reason="self_defence";p.defending=true;return p end
    local ret=zb.GuiltTable and zb.GuiltTable[v] and zb.GuiltTable[v][a] or 0
    ret=J.Finite(ret) and math.Clamp(ret,0,1) or 0
    p.nativeRetaliation=ret
    if ret>=1 then p.reason="native_retaliation";p.defending=true;return p end
    if J.Finite(v.Guilt) and v.Guilt>1 and not p.force then
        p.reason="guilty_target";p.defending=true;return p
    end
    if a.IsBerserk and a:IsBerserk() then p.reason="berserk";return p end
    if isfunction(mode.GuiltCheck) then
        local ok,mul=pcall(mode.GuiltCheck,a,v,0,0,0)
        if not ok or mul==0 then p.reason="mode_rule";return p end
    end
    p.scale=1-ret;p.reason="friendly"
    return p
end
function J.Remember(a,v,policy)
    J.latest[v]={attacker=a,tick=engine.TickCount(),round=ZCityKarmaBounties.RoundKey(),policy=policy}
end
function J.PolicyFor(a,v,info,creatureHit)
    local F=ZCityFFBrain
    local row=F and F.Event and F.Event(v,info,creatureHit)
    local policy=row and row.attacker==a and row.policy
    if not policy then policy=J.Assess(a,v,CurrentRound()) end
    J.Remember(a,v,policy)
    return policy
end
function J.Hostility(a,v,harm,policy)
    if not J.Finite(harm) or harm<=0 then return end
    policy=policy or J.Assess(a,v,CurrentRound())
    if not policy.allied or policy.defending or policy.reason=="mode_exempt" then return end
    local K=ZCityKarmaBounties
    local id=J.ID(v);J.hostility[id]=J.hostility[id] or {}
    J.hostility[id][J.ID(a)]={round=K.RoundKey(),untilTime=CurTime()+12,
        targetLife=K.GetLife(v).justiceId,sourceLife=K.GetLife(a).justiceId}
end
function J.ClearCombatLife(p)
    if not J.Player(p) then return end
    J.latest[p]=nil
    local id=J.ID(p);J.hostility[id]=nil
    for _,row in pairs(J.hostility) do row[id]=nil end
    if zb and zb.GuiltTable then
        zb.GuiltTable[p]=nil
        for _,row in pairs(zb.GuiltTable) do if istable(row) then row[p]=nil end end
    end
end
hook.Add("PlayerSpawn","ZCityGuiltJustice_CombatLife",function(p)
    if OverrideSpawn or (ZCityPillCompat and IsValid(ZCityPillCompat.Morph(p))) then return end
    J.ClearCombatLife(p)
end)
hook.Add("PlayerDisconnected","ZCityGuiltJustice_CombatLife",J.ClearCombatLife)
