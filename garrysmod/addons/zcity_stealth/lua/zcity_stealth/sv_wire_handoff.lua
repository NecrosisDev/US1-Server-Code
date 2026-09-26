local S=ZCityStealth
local I=ZCityInteractions

function S.SoloWireStatus(a,target,w,dropItem)
    local old=S.ByActor[a]
    local ok,why=S.CanSoloHandoff(a,old,false,dropItem)
    if not ok then return false,why end
    return I.CanWireHandoff(a,target,old,w,dropItem)
end

function S.SoloWireSwitchAllowed(a,w)
    local old=S.ByActor[a] local h=old and old.wireHandoff
    return old and not old.done and old.a==a and h and h.selecting and h.weapon==w
        and IsValid(w) and w:GetOwner()==a
end

function S.WireHandoffValid(old)
    local h=old.wireHandoff local a=old.a
    if not h or not IsValid(h.weapon) or h.weapon:GetOwner()~=a
        or h.weapon:GetClass()~="weapon_zc_fiberwire_standalone" or not h.weapon.InteractionStart
        or not I.HandsAvailable(a) or a.organism~=h.organism
        or not S.TrialAllowed(a) or not S.SeamsReady() then return false,"Fiberwire handoff interrupted" end
    local active=a:GetActiveWeapon()
    if active~=h.weapon and not (h.selecting and active==h.previous) then return false,"Weapon changed" end
    local v=h.receiver
    if not IsValid(h.target) or h.target:GetCreationID()~=h.creation or not IsValid(v) or not v:Alive()
        or I.Receiver(h.target)~=v or v.organism~=h.targetOrganism
        or (I.PolicyLives[v] or 0)~=h.life or I.PolicyRound~=h.round then return false,"Target changed" end
    return I.HostileAllowed(a,v,old,"fiberwire")
end

function S.StartSoloWireHandoff(a,target,equipment,dropItem)
    local g=ZCityHostage and ZCityHostage.Gameplay
    local w=equipment or (g and g.ControlWire(a))
    local ok,why=S.SoloWireStatus(a,target,w,dropItem)
    if not ok then return false,why end
    local old=S.ByActor[a] local receiver=I.Receiver(target)
    -- The explicitly labeled drop happens before selecting a two-hand item.
    -- A native selection veto keeps the stance, but does not reclaim the prop.
    if dropItem then
        S.ReleaseItem(old)
        if old.done or not S.CanSoloHandoff(a,old) then return false,"Object release interrupted the stance" end
        ok,why=S.SoloWireStatus(a,target,w)
        if not ok then return false,why end
    end
    local h={weapon=w,previous=a:GetActiveWeapon(),target=target,receiver=receiver,
        creation=target:GetCreationID(),life=I.PolicyLives[receiver] or 0,round=I.PolicyRound,
        organism=a.organism,targetOrganism=receiver.organism,readyAt=CurTime()+.4,deadline=CurTime()+2,selecting=true,
        speed=a:GetNWFloat("zsf_speed",0)}
    old.wireHandoff=h
    a:SetNWBool("zsf_wire_switch",true) a:SetNWFloat("zsf_speed",0)
    local called,err=pcall(a.SelectWeapon,a,w:GetClass())
    h.selecting=nil
    if old.done then return false,"Handoff interrupted" end
    if not called or a:GetActiveWeapon()~=w then
        if a:GetActiveWeapon()==h.previous then
            old.wireHandoff=nil a:SetNWBool("zsf_wire_switch",false) a:SetNWFloat("zsf_speed",h.speed)
        else S.End(old,"Weapon switch interrupted the stance") end
        if not called then ErrorNoHalt("[Interactions] Wire selection failed: "..tostring(err).."\n") end
        return false,"Weapon switch was refused"
    end
    old.weapons[a]=w
    return true
end

function S.StepSoloWireHandoff(old)
    local h=old.wireHandoff
    if CurTime()>=h.deadline then S.End(old,"Fiberwire was not ready; stance released") return end
    if CurTime()<h.readyAt or not S.Armed(old.a,S.Actions.fiberwire) then return end
    local ok,why=I.StartWire(old.a,h.target,old)
    if not ok and not old.done then S.End(old,why or "Fiberwire handoff interrupted") end
end
