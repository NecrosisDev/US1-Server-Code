-- Loaded once by the main bounty module, after its native delegates are defined.
local J,K=assert(ZCityGuiltJustice),assert(ZCityKarmaBounties)
if not K.JusticeLoading then return end
local harmCharge=K.HarmCharge
K.HarmCharge=function(a,v,harm,oldGuilt,multiplier)
    if not K.Active() then return harmCharge(a,v,harm,oldGuilt,multiplier) end
    local life=K.GetLife(v);local pair=life.attackers[a]
    if not pair then return 0,0 end
    local policy=pair.policy or J.Assess(a,v,CurrentRound())
    pair.chargeScale=policy.scale
    pair.chargeEligible=policy.scale>0 and multiplier~=0
    if not pair.chargeEligible or life.settled or not v:Alive() then return 0,0 end
    local value=K.Value(K.Karma(v))
    if not value then return nil end
    if value>=0 then return 0,0 end
    local before=pair.harm or 0
    pair.harm=math.min(10,before+math.max(0,J.Finite(harm) and harm or 0))
    local charge=math.min(-value*(pair.harm-before)/10,math.max(0,-value-pair.charged))
    -- The native handler / creature bridge applies the captured retaliation scale once.
    return charge,oldGuilt
end
local beginPill=K.BeginPill
K.BeginPill=function(v,info)
    local c=beginPill(v,info)
    if c then c.policy=J.PolicyFor(c.a,v,info,true) end
    return c
end
K.EndPill=function(c,info,loss,killed)
    if not c or not J.Finite(loss) or loss<=0 then return end
    local a,v=c.a,c.v
    if not J.Player(a) or not J.Player(v) then return end
    local harm=math.min(10,loss/c.maximum*10)
    local pair=K.Observe(a,v,info,harm,true);if not pair then return end
    local policy=c.policy or pair.policy or J.Assess(a,v,CurrentRound())
    pair.policy=policy;pair.chargeScale=policy.scale;pair.chargeEligible=policy.scale>0
    if policy.scale>0 then
        zb.GuiltTable[v]=zb.GuiltTable[v] or {};zb.GuiltTable[a]=zb.GuiltTable[a] or {}
        local cost,guilt=K.HarmCharge(a,v,harm,harm*6,1)
        if cost and cost>0 then
            local before=J.Balance(a);K.Change(a,-cost*policy.scale)
            K.RecordCharge(a,v,before,J.Balance(a));K.RefundLedger(a,v,J.Balance(a)-before)
            a.Guilt=(a.Guilt or 0)+guilt
            zb.GuiltTable[a][v]=math.Clamp((zb.GuiltTable[a][v] or 0)+guilt,0,200)
        end
    end
    -- Unmorphing alone is not a kill and cannot claim a bounty.
    if killed and not v:Alive() then K.Settle(v,a) end
end
