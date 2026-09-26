local J=assert(ZCityGuiltJustice)
local K=assert(ZCityKarmaBounties)
if not K.JusticeLoading then return end -- Only the main module rebuilds its delegates.
function J.Mirror(p,delta)
    local v,a=J.Find(p.life.victimId),J.Find(p.account)
    if p.life.round~=K.RoundKey() or not v or not a then return end
    zb.HarmDoneKarma[v]=zb.HarmDoneKarma[v] or {}
    zb.HarmDoneKarma[v][a]=math.max(0,(zb.HarmDoneKarma[v][a] or 0)+delta)
end
function J.Eligible(a,v,life)
    return J.Assess(a,v,CurrentRound()).scale>0
end
function J.Flush(life)
    if not life or not life.dead or life.ready then return end
    local v=J.Find(life.victimId);local p=life.killer and life.byAccount[life.killer]
    local a=p and J.Find(p.account)
    if p and not life.noSettlement and J.Player(v) and J.Player(a) then
        local value=K.Value(life.deathKarma) or 0
        if value<0 and p.chargeEligible then
            local need=-value*(p.chargeScale or 1)-J.Outstanding(p)
            if need>0 then
                local paid=math.max(0,-J.Change(a,-need))
                p.debits=p.debits+paid;J.Mirror(p,paid)
            elseif need<0 then
                local ok=J.ReturnLoss(p,-need,"settlement")
                if ok then J.Mirror(p,need) end
            end
        elseif value>=0 then
            local outstanding=J.Outstanding(p)
            local ok=J.ReturnLoss(p,outstanding,"settlement")
            if ok then J.Mirror(p,-outstanding) end
            p.bountyFace=math.max(0,value)
            if value>0 and K.BountyEligible(a,v) then
                K.claimed[K.Identity(v)]=true
                p.bountyPaid=math.max(0,J.Change(a,value))
            end
        end
        p.charged=J.Outstanding(p)
        if not ZCityMetaSafety.Locked() and value<0 and a.Karma<=0 and not a:IsAdmin() and not a:IsSuperAdmin()
            and not timer.Exists("simplewaitforkarmadrop"..a:EntIndex()) then
            a:guilt_SetValue(10)
            if ULib and ULib.addBan then ULib.addBan(a:SteamID(),60,"Karma exhausted by friendly kills.",a:Nick(),"System") end
        end
    end
    life.settled=true;life.ready=true;life.expires=CurTime()+45
    if ZCityMetaSafety.Locked() then life.metaHeld=true;life.expires=math.huge end
    for _,pair in pairs(life.byAccount) do
        pair.automaticLoss=J.Outstanding(pair)
        pair.respectEligible=not life.noSettlement and pair.account==life.killer
            and life.victimTraitor and not pair.attackerTraitor
        J.Log("settled",{case=life.justiceId,victim=life.victimId,attacker=pair.account,
            loss=pair.automaticLoss,bounty=pair.bountyPaid,credit=pair.credits,karma=life.deathKarma})
    end
    hook.Run("ZCityGuiltSettlementReady",life)
    if J.Sync then J.Sync(v) end
end
function J.Death(v,a,silent)
    if not K.Active() or not J.Player(v) or K.Excluded(v) then return end
    local life=K.GetLife(v);if life.dead then return end
    life.dead=true;life.deathKarma=K.Karma(v);life.victimTraitor=not not v.isTraitor
    life.kind=K.Kind(CurrentRound());life.deathAt=CurTime()
    local manual=life.suicideAt and CurTime()-life.suicideAt<1
    manual=manual or (life.selfDamageAt and CurTime()-life.selfDamageAt<1)
    local medical=v.organism and v.organism.alive==false
    if a==v then a=nil;if not medical then manual=true end end
    if silent or manual then life.noSettlement=true;a=nil end
    if not J.Player(a) and medical and not life.noSettlement then
        local pending=K.pending[v]
        if pending and pending.tick==engine.TickCount() then a=pending.attacker end
        if not J.Player(a) then
            local best=0
            for source,p in pairs(life.attackers) do
                if J.Player(source) and CurTime()-(p.time or 0)<=120 and (p.contribution or 0)>best then
                    a=source;best=p.contribution
                end
            end
        end
    end
    if J.Player(a) and a~=v and not K.Excluded(a) then
        local existing=life.attackers[a];local p=J.Pair(life,a)
        local hit=J.latest[v]
        local policy=hit and hit.tick==engine.TickCount() and hit.round==life.round and hit.attacker==a and hit.policy
        if policy or not existing then
            policy=policy or J.Assess(a,v,CurrentRound())
            p.policy=policy;p.chargeScale=policy.scale;p.chargeEligible=policy.scale>0
            p.attackerTraitor=policy.attackerTraitor
        end
        life.killer=p.account
    end
    timer.Simple(0,function()J.Flush(life)end)
end
local baseLife,baseObserve,baseCharge=K.GetLife,K.Observe,K.RecordCharge
K.GetLife=function(v)
    local life=baseLife(v);return J.RegisterLife(v,life)
end
K.Observe=function(a,v,info,harm,accepted)
    if K.Active() and J.Player(a) and J.Player(v) and a~=v then
        local life=K.GetLife(v)
        local old=life.byAccount[J.ID(a)]
        if old then life.attackers[a]=old end
    end
    local policy=K.Active() and J.Player(a) and J.Player(v) and a~=v
        and J.PolicyFor(a,v,info,accepted)
    local p=baseObserve(a,v,info,harm,accepted)
    if p then
        p=J.Pair(K.GetLife(v),a);p.policy=policy;p.defending=policy.defending
        p.chargeScale=policy.scale;p.chargeEligible=policy.scale>0
        J.Hostility(a,v,harm,policy)
    end
    return p
end
K.RecordCharge=function(a,v,before,after)
    local life=K.GetLife(v);local p=J.Pair(life,a)
    baseCharge(a,v,before,after)
    if J.Finite(before) and J.Finite(after) then p.debits=p.debits+math.max(0,before-after) end
    p.charged=J.Outstanding(p)
end
K.Change=J.Change
K.Settle=function(v,a) if not v:Alive() then J.Death(v,a,false) end end
hook.Add("PlayerDeath","ZCityKarmaBounties_Settle",function(v,_,a)J.Death(v,a,false)end,-2)
hook.Add("PlayerSilentDeath","ZCityKarmaBounties_NoSilentReward",function(v)J.Death(v,nil,true)end,-2)
hook.Add("PlayerInitialSpawn","ZCityGuiltJustice_Loading",function(p)J.loading[p]=true end,-2)
hook.Add("ZCityKarmaLoaded","ZCityGuiltJustice_Refunds",function(p)timer.Simple(0,function()J.KarmaLoaded(p)end)end)
-- A last-second settlement must consume the old round's claim, not the next round's.
J.claims=J.claims or {}
local refresh=K.RefreshRound
K.RefreshRound=function()
    if K.roundKey then J.claims[K.roundKey]=K.claimed end
    refresh()
    if J.claims[K.roundKey] then K.claimed=J.claims[K.roundKey]
    else J.claims[K.roundKey]=K.claimed end
end
function J.Claims(life)
    local claims=J.claims[life.round]
    if not claims then
        claims=life.round==K.roundKey and K.claimed or {}
        J.claims[life.round]=claims
    end
    return claims
end
local flush=J.Flush
J.Flush=function(life)
    if not life or life.processing or life.failed or life.ready then return end
    local saved=K.claimed;K.claimed=J.Claims(life);life.processing=true
    local ok,err=pcall(flush,life)
    K.claimed=saved;life.processing=nil
    if not ok then life.failed=true;error(err,0) end
end
-- Adopt only unsettled per-life deductions already tracked by the deployed bounty addon.
-- Old cached menu totals are not treated as newly refundable money.
for v,life in pairs(K.lives) do
    if J.Player(v) and v:Alive() and not life.settled and not life.justiceId then
        J.RegisterLife(v,life)
        for a,p in pairs(life.attackers) do
            if J.Player(a) then
                local remaining=zb.HarmDoneKarma[v] and zb.HarmDoneKarma[v][a] or 0
                p.charged=math.min(math.max(0,p.charged or 0),math.max(0,remaining))
                J.Pair(life,a)
            end
        end
    end
end
-- Install after Workshop autoruns; the original virtual path can shadow loose files.
function J.InstallLegacy()
    if not ZCITY_GUILT or not ZCITY_GUILT.DefaultConfig then return false end
    if not (hook.GetTable().HomigradDamage or {}).GuiltReg then return false end
    if J.legacyHandler and net.Receivers.zcity_guilt_action==J.legacyHandler then return true end
    local path="zc_guilt_justice/legacy_server.lua"
    if not file.Exists(path,"LUA") then return false end
    include(path)
    J.legacyHandler=net.Receivers.zcity_guilt_action
    return isfunction(J.legacyHandler)
end
-- The installer returns a boolean status; never return it to the hook dispatcher.
hook.Add("InitPostEntity","ZCityGuiltJustice_Legacy",function()J.InstallLegacy()end)
hook.Add("OnReloaded","ZCityGuiltJustice_Legacy",function()timer.Simple(0,J.InstallLegacy)end)
timer.Create("ZCityGuiltJustice_Legacy",1,0,J.InstallLegacy)

include("zc_guilt_justice/combat_runtime.lua")
