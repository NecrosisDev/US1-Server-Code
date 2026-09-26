local S=ZCityStealth
local I=ZCityInteractions
function S.CanReleaseItem(s,item)
    if not IsValid(item) or s.item~=item or S.ByActor[item]~=s or I.Session(item)~=s
        or not IsValid(s.itemPhys) or item:GetPhysicsObject()~=s.itemPhys or not s.itemPhys:IsMotionEnabled()
        or constraint.HasConstraints(item) then return false,"Held object changed; release it first" end
    for _,p in ipairs(player.GetAll()) do
        if p:GetNetVar("carryent")==item or p:GetNetVar("carryent2")==item then return false,"Another grip owns the object" end
    end
    return true
end
function S.AcquireItem(s)
    local w=s.weapons[s.a]
    local item=IsValid(w) and w.GetCarrying and w:GetCarrying()
    if not IsValid(item) then
        return not IsValid(s.a:GetNetVar("carryent")) and not IsValid(s.a:GetNetVar("carryent2"))
    end
    local phys=item:GetPhysicsObject()
    if item:IsRagdoll() or item:GetMoveType()~=MOVETYPE_VPHYSICS or not IsValid(phys) or not phys:IsMotionEnabled()
        or phys:GetMass()>10 or constraint.HasConstraints(item) or S.ByActor[item] then return false end
    if s.a:GetNetVar("carryent")~=item then return false end
    if not ZCityInteractions.Reserve(s,{item}) then return false end
    s.item=item s.itemPhys=phys S.ByActor[item]=s
    w:SetCarrying()
    return true
end
function S.ReleaseItem(s)
    if not s.item then return end
    local item,phys=s.item,s.itemPhys
    s.item=nil s.itemPhys=nil
    if S.ByActor[item]==s then S.ByActor[item]=nil end
    if I.Reservations[item]==s then I.Reservations[item]=nil end
    if s.reserved then s.reserved[item]=nil end
    if IsValid(phys) then phys:Wake() end
end
function S.DriveItem(s,dt)
    local phys=s.itemPhys
    if not IsValid(s.item) or not IsValid(phys) or not IsValid(s.a) then return false end
    if S.ByActor[s.item]~=s or constraint.HasConstraints(s.item) or not phys:IsMotionEnabled() then return false end
    for _,p in ipairs(player.GetAll()) do
        if p:GetNetVar("carryent")==s.item or p:GetNetVar("carryent2")==s.item then return false end
    end
    local b=s.a:LookupBone("ValveBiped.Bip01_L_Hand") local m=b and s.a:GetBoneMatrix(b)
    if not m then return false end
    local target=m:GetTranslation()
    local tr=util.TraceHull({start=phys:GetPos(),endpos=target,mins=s.item:OBBMins(),maxs=s.item:OBBMaxs(),filter={s.a,s.item},mask=MASK_SOLID})
    if tr.Hit or tr.StartSolid or tr.AllSolid then return false end
    phys:ComputeShadowControl({secondstoarrive=.05,pos=target,angle=m:GetAngles(),maxangular=600,maxangulardamp=800,
        maxspeed=350,maxspeeddamp=700,dampfactor=.8,teleportdistance=0,deltatime=dt})
    phys:Wake()
    return true
end
function S.ThrowItem(s,velocity)
    local phys=s.itemPhys
    if not IsValid(phys) then return end
    if IsValid(s.a) then s.item:SetPhysicsAttacker(s.a,15) end
    S.ReleaseItem(s)
    -- Continue the evaluated hand velocity; no second end-of-clip impulse.
    phys:SetVelocity(velocity)
end
function S.UpdateThrow(s,dt)
    if dt<=0 or s.bodyReleased or (not s.body and not s.item) then return end
    local elapsed=CurTime()-s.start
    local hand=S.BonePose(s.clip,S.Gender(s.a),s.body and "ValveBiped.Bip01_R_Hand" or "ValveBiped.Bip01_L_Hand",elapsed)
    if not hand then return end
    hand:Rotate(Angle(0,s.yaw,0))
    hand=hand+(S.PoseOrigin(s.a,CurTime()) or s.a:GetPos())
    if s.body then
        local pelvis=S.BonePose(s.v:GetNWString("zsf_clip"),S.Gender(s.v),"ValveBiped.Bip01_Pelvis",elapsed)
        if not pelvis then return end
        pelvis:Rotate(Angle(0,s.yaw,0))
        pelvis=pelvis+(S.PoseOrigin(s.v,CurTime()) or s.v:GetPos())
        local distance=hand:Distance(pelvis)
        local old=s.releaseContact or distance
        if distance<30 then s.throwHeld=true end
        if s.throwHeld and distance>30 and distance>old then
            if IsValid(s.a) then s.v:SetPhysicsAttacker(s.a,15) end
            s.bodyReleased=true S.ReleaseBody(s)
        end
        s.releaseContact=distance
    else
        local velocity=s.throwHand and (hand-s.throwHand)/dt or vector_origin
        local speed=velocity:Length()
        -- Release just after the forward hand-speed peak, while the arm is
        -- extended. The source pack has no notify markers to copy.
        local reach=(hand-s.a:WorldSpaceCenter()):Dot(Angle(0,s.yaw,0):Forward())
        if s.throwSpeed and s.throwSpeed>300 and speed<s.throwSpeed and reach>40 then
            local carried=s.throwVelocity or velocity
            if carried:Length()>650 then carried=carried:GetNormalized()*650 end
            S.ThrowItem(s,carried)
        end
        s.throwHand=hand s.throwSpeed=speed s.throwVelocity=velocity
    end
end
