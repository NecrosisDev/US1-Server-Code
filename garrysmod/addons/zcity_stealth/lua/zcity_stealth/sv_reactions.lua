local S=ZCityStealth
local pending=setmetatable({}, {__mode="k"})
local reactionSerial=-1
function S.IsPoisonCollapse(p)
    local org=IsValid(p) and p.organism
    return org and ((org.tranquilizer or 0)>0 or (org.poison4 or 0)>0)
        and (org.otrub or org.needfake or (org.consciousness or 1)<.4)
end
function S.AdoptRagdoll(s,p,rag)
    if s.done or s.v~=p or not IsValid(rag) or not rag:IsRagdoll() then return false end
    local name=p:GetNWString("zsf_clip")
    if not S.Assets.clips[name] then return false end
    if not ZCityInteractions.Reserve(s,{rag}) then S.End(s,"Body is already controlled") return false end
    s.awaitingBody=nil
    s.originalVictim=p s.v=rag s.body=true s.actors[2]=rag
    s.a:SetNWEntity("zsf_partner",rag)
    S.ByActor[rag]=s s.models[rag]=rag:GetModel()
    s.scales[rag]=s.scales[p] or rag:GetModelScale()
    rag:SetModelScale(1,0)
    if not S.AcquireBody(s) then S.End(s,"Ragdoll handoff interrupted") return false end
    -- Native damage owns death/unconsciousness and weapon drops. Continue the
    -- remaining authored body motion using that exact ragdoll, never a clone.
    if not S.SetClip(s,rag,name,s.vAnchor,false,0) then S.End(s) return false end
    rag:SetNWFloat("zsf_start",s.start)
    S.AcquireCollision(s)
    return true
end
function S.AwaitRagdoll(s,p)
    if s.done or s.v~=p or s.phase=="attempt" or s.phase=="release" or s.phase=="settle" then return false end
    if not s.awaitingBody then s.awaitingBody={player=p,deadline=CurTime()+.25} end
    return true
end
hook.Add("Ragdoll_Create","ZCityStealth.Handoff",function(p,rag)
    local s=S.ByActor[p]
    if s then
        if p==s.v and s.phase~="attempt" then S.AdoptRagdoll(s,p,rag)
        elseif p==s.a then S.End(s,"Attacker incapacitated") end
    elseif (pending[p] and CurTime()-pending[p]<.5) or S.IsPoisonCollapse(p) then
        pending[p]=nil
        S.StartPoisonReaction(p,rag)
    end
end)
hook.Add("HG_OnOtrub","ZCityStealth.PoisonReaction",function(p)
    if not S.Enabled:GetBool() or S.ByActor[p] or not IsValid(p) or IsValid(p.FakeRagdoll) then return end
    local org=p.organism
    if org and ((org.tranquilizer or 0)>0 or (org.poison4 or 0)>0) then pending[p]=CurTime() end
end)
function S.StartPoisonReaction(p,body)
    if not IsValid(body) or S.ByActor[body] or not S.Enabled:GetBool() or not S.TrialAllowed(p) or not S.IsPoisonCollapse(p) then return end
    reactionSerial=reactionSerial-1
    local name="Standing_Idle_PoisonedKnockOut"
    local start=S.Sample(name,S.Gender(body),0)
    local yaw=p:EyeAngles().y start:Rotate(Angle(0,yaw,0))
    local s={id=reactionSerial,a=body,v=body,actors={body},models={[body]=body:GetModel()},scales={},poses={},positions={},
        action={id="poison_reaction",kind="reaction"},phase="reaction",start=CurTime(),deadline=CurTime()+S.Assets.clips[name].duration,
        yaw=yaw,body=true,reaction=true,sourcePlayer=p,clip=name,hits={}}
    s.anchor=p:GetPos()-start s.vAnchor=s.anchor
    if not ZCityInteractions.Reserve(s,{body}) then return end
    S.ByActor[body]=s S.Sessions[s.id]=s
    S.Normalize(s,body)
    if not S.AcquireBody(s) or not S.SetClip(s,body,name,s.anchor,false,0) then S.End(s) end
end
function S.TickReaction(s)
    if s.done then return end
    if not S.Enabled:GetBool() or not IsValid(s.v) or s.v:GetModel()~=s.models[s.v] or s.v:GetModelScale()~=1
        or not S.BodyAvailable(s.v,s) or CurTime()>=s.deadline then S.End(s) return end
    local now=CurTime() local dt=math.Clamp(now-(s.last or now),0,.1) s.last=now
    if not S.DriveBody(s,dt) then S.End(s) end
end
