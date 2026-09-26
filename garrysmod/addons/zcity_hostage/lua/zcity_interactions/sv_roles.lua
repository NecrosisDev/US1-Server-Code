local I=ZCityInteractions
I.DisarmSessions=I.DisarmSessions or setmetatable({}, {__mode="k"})
I.DisarmFollowups=I.DisarmFollowups or setmetatable({}, {__mode="k"})
local function ready(a)
    local w=IsValid(a) and a:GetActiveWeapon()
    return IsValid(a) and a:Alive() and I.HandsAvailable(a) and not a.organism.otrub
        and not IsValid(a.FakeRagdoll) and not a:InVehicle() and IsValid(w)
        and w:GetClass()=="weapon_hands_sh" and not IsValid(a:GetNetVar("carryent")) and not IsValid(a:GetNetVar("carryent2"))
end
function I.DisarmValid(s,predecessor)
    if not s or s.done or not ready(s.a) or not IsValid(s.v) or not s.v:Alive() then return false end
    if s.a:GetActiveWeapon()~=s.weapon or s.v:GetActiveWeapon()~=s.targetWeapon then return false end
    if s.scale and (s.a:GetModelScale()~=1 or s.a:GetModel()~=s.model or s.a.organism~=s.organism) then return false end
    if not I.HostileAllowed(s.a,s.v,predecessor or s,"disarm") then return false end
    local body=IsValid(s.v.FakeRagdoll) and s.v.FakeRagdoll or s.v
    if body~=s.targetBody or not I.Available(body,s) then return false end
    if s.a:GetPos():DistToSqr(body:GetPos())>90*90 then return false end
    local trace=util.TraceLine({start=s.a:EyePos(),endpos=body:WorldSpaceCenter(),filter=s.a,mask=MASK_SOLID})
    return not trace.Hit or trace.Entity==body
end
function I.BeginDisarm(a,v,mode,contextual,predecessor,dropItem)
    if I.DisarmSessions[a] or not ready(a) or not IsValid(v) or v==a or not v:IsPlayer() or not v:Alive() then return false end
    local stealth=ZCityStealth
    if predecessor and (not contextual or not stealth or not stealth.CanSoloHandoff(a,predecessor,false,dropItem)) then return false end
    local targetWeapon=v:GetActiveWeapon()
    if not IsValid(targetWeapon) or targetWeapon.NoDrop or targetWeapon:GetClass()=="weapon_hands_sh" then return false end
    if not I.HostileAllowed(a,v,predecessor,"disarm") or not I.Available(v) or (I.Recovery[v] or 0)>CurTime() then return false end
    local stamina=a.organism.stamina
    if not stamina or (stamina[1] or 0)<8 then return false end
    local body=IsValid(v.FakeRagdoll) and v.FakeRagdoll or v
    local s={a=a,v=v,weapon=a:GetActiveWeapon(),targetWeapon=targetWeapon,targetBody=body,mode=mode,
        system="disarm",phase="attempt",policyIntent="disarm",contextual=contextual==true,start=CurTime(),
        cancel=function(session)
            if session.done or session.ending then return end
            session.ending=true
            local ok,err=pcall(mode.StopDisarmingOther,a)
            I.EndDisarm(a)
            if not ok then ErrorNoHalt("[Interactions] Disarm cleanup failed: "..tostring(err).."\n") end
        end}
    if not I.DisarmValid(s,predecessor) or not mode.CanPlayerDisarmOther(a,body) or not mode.CanPlayerDisarmOtherPly(a,v) then return false end
    local actors={a,v} if body~=v then actors[#actors+1]=body end
    s.actors=actors
    if not I.Reserve(s,actors,predecessor) then return false end
    I.DisarmSessions[a]=s I.DisarmFollowups[a]=nil
    if predecessor then
        s.scale=predecessor.scales[a] s.model=predecessor.models[a] s.organism=a.organism
        predecessor.scales[a]=nil I.TransferScale(predecessor,s,a)
        stealth.End(predecessor,nil,true)
        if s.done then return false end
        if not I.DisarmValid(s) then s.cancel(s) return false end
    end
    for _,p in ipairs({a,v}) do
        p:SetNWString("zci_native","disarm") p:SetNWBool("zci_native_initiator",p==a)
        p:SetNWEntity("zci_native_partner",p==a and v or a)
    end
    return true
end
function I.EndDisarm(a)
    local s=I.DisarmSessions[a]
    if not s then return end
    s.done=true I.DisarmSessions[a]=nil
    for _,p in ipairs({s.a,s.v}) do
        if IsValid(p) and p:GetNWString("zci_native")=="disarm" then
            p:SetNWString("zci_native","") p:SetNWEntity("zci_native_partner",NULL)
        end
    end
    if s.scale then local original=s.scale;s.scale=nil;I.EndScale(s,a,original) end
    I.Release(s) I.Protect(s.v,2)
end
function I.CommitDisarm(a,v)
    local s=I.DisarmSessions[a]
    if not s or s.v~=v or s.committed or CurTime()-s.start<.45 or not I.DisarmValid(s) then return false end
    local stamina=a.organism.stamina
    if not stamina or (stamina[1] or 0)<8 then s.cancel(s) return false end
    s.committed=true s.phase="commit" stamina.subadd=(stamina.subadd or 0)+8
    I.DisarmFollowups[a]={v=v,life=I.PolicyLives[v] or 0,actorLife=I.PolicyLives[a] or 0,round=I.PolicyRound,at=CurTime()}
    return true
end
function I.DisarmFollowupAllowed(a,v)
    local row=I.DisarmFollowups[a]
    return row and row.v==v and row.round==I.PolicyRound and row.life==(I.PolicyLives[v] or 0)
        and row.actorLife==(I.PolicyLives[a] or 0) and CurTime()-row.at<.2 and ready(a)
        and I.Available(a) and I.Available(v) and I.PolicyAllowed(a,"disarm",v)
end
function I.StartDisarmAction(a,v,predecessor,dropItem)
    local mode,name=I.PolicyContext()
    if name~="hmcd" or not mode.StartDisarmingOther then return false,"The native disarm ability is unavailable" end
    if I.DisarmSessions[a] then return false,"Already controlling a target" end
    local ok,err=pcall(mode.StartDisarmingOther,a,v,true,predecessor,dropItem)
    if not ok then
        local s=I.DisarmSessions[a];if s then s.cancel(s) end
        ErrorNoHalt("[Interactions] Disarm start failed: "..tostring(err).."\n")
        return false,"Disarm was interrupted"
    end
    return I.DisarmSessions[a]~=nil,"Disarm requires free hands, a nearby armed target and sufficient stamina"
end
hook.Add("Think","ZCityInteractions.DisarmLifetimes",function()
    for a,s in pairs(I.DisarmSessions) do
        if not I.DisarmValid(s) or CurTime()-s.start>2 or not a.Ability_Disarm then s.cancel(s)
        elseif s.contextual then
            local ok,err=xpcall(function() s.mode.ContinueDisarmingOther(a) end,debug.traceback)
            if not ok then s.cancel(s) ErrorNoHalt("[ZCityInteractions] Disarm interrupted: "..tostring(err).."\n") end
        end
    end
end)
hook.Add("PostEntityTakeDamage","ZCityInteractions.DisarmInjury",function(p,dmg,took)
    local s=I.Session(p)
    if s and s.system=="disarm" and not s.committed and took and dmg:GetDamage()>0 then s.cancel(s) end
end)
hook.Add("StartCommand","ZCityInteractions.DisarmCancel",function(p,cmd)
    local s=I.DisarmSessions[p]
    if s and s.contextual and cmd:KeyDown(IN_RELOAD) then s.cancel(s) end
end)
for _,event in ipairs({"PlayerSpawn","PlayerDisconnected","PlayerDeath","PlayerSilentDeath"}) do
    hook.Add(event,"ZCityInteractions.DisarmLife",function(p)
        if event=="PlayerSpawn" and OverrideSpawn then return end
        local s=I.Session(p) if s and s.system=="disarm" then s.cancel(s) end
        I.DisarmFollowups[p]=nil
    end)
end
for _,event in ipairs({"PreCleanupMap","ZB_EndRound","ZB_PreRoundStart","ShutDown"}) do
    hook.Add(event,"ZCityInteractions.DisarmRound",function()
        local all={} for _,s in pairs(I.DisarmSessions) do all[#all+1]=s end
        for _,s in ipairs(all) do s.cancel(s) end
        I.DisarmFollowups=setmetatable({}, {__mode="k"})
    end)
end
