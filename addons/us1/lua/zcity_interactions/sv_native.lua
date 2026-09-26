local I=ZCityInteractions
I.NativeSessions=I.NativeSessions or {}
I.WireBreathing=I.WireBreathing or setmetatable({}, {__mode="k"})
function I.CanNativeCarry(a,target,own)
    if not IsValid(a) or not IsValid(target) then return false end
    if not I.Available(a,own) or not I.Available(target,own) then return false end
    local owner=I.Receiver(target)
    if (IsValid(owner) and not I.Available(owner,own)) or target.StrangleLocked then return false end
    for _,p in ipairs(player.GetAll()) do
        if p~=a and (p:GetNetVar("carryent")==target or p:GetNetVar("carryent2")==target) then return false end
    end
    return true
end
function I.NativeCarryReleased(target)
    local p=I.Receiver(target)
    if IsValid(p) and p:IsPlayer() then I.Protect(p,2) end
end
function I.HurtGrabAllowed(a,v)
    if not IsValid(a) or not IsValid(v) or not I.HandsAvailable(a) or a.organism.otrub
        or IsValid(a.FakeRagdoll) or a:InVehicle() then return false end
    if not I.HostileAllowed(a,v,nil,"hurt_grab") or not I.CanNativeCarry(a,v) then return false end
    local target=IsValid(v.FakeRagdoll) and v.FakeRagdoll or v
    if not I.CanNativeCarry(a,target) or a:GetPos():DistToSqr(target:GetPos())>75*75 then return false end
    local trace=util.TraceLine({start=a:EyePos(),endpos=target:WorldSpaceCenter(),filter=a,mask=MASK_SOLID})
    return not trace.Hit or trace.Entity==target or trace.Entity==v
end
local function wireActor(a,w,preview)
    return IsValid(a) and a:IsPlayer() and a:Alive() and I.HandsAvailable(a)
        and not a.organism.otrub and not IsValid(a.FakeRagdoll) and not a:InVehicle()
        and a:GetMoveType()==MOVETYPE_WALK and a:WaterLevel()<=1
        and IsValid(w) and (preview or a:GetActiveWeapon()==w) and w:GetOwner()==a
end
function I.WireEligibility(w,target,predecessor,preview,dropItem,equipmentPreview)
    if not hg.organism or hg.organism.InteractionWireBreathingVersion~="20260920.wirebreath1" then
        return false,"Fiberwire breathing integration is not ready"
    end
    if not IsValid(w) then return false,"Equip native fiberwire" end
    local a=w:GetOwner() local v=I.Receiver(target)
    local solo=predecessor and predecessor.system~="hostage"
    if predecessor then
        local g=ZCityHostage and ZCityHostage.Gameplay
        local stealth=ZCityStealth
        if solo then
            if not stealth or not stealth.CanSoloHandoff(a,predecessor,true,preview and dropItem or nil)
                or (not preview and (not predecessor.wireHandoff or predecessor.wireHandoff.target~=target
                    or predecessor.wireHandoff.weapon~=w)) then return false,"The original stance changed" end
            if (I.Recovery[v] or 0)>CurTime() then return false,"Give the released player space" end
        elseif not g or not g.CanWeaponHandoff(predecessor) or predecessor.a~=a or predecessor.v~=target
            or (not preview and (predecessor.phase~="handoff" or not predecessor.handoff or predecessor.handoff.weapon~=w)) then
            return false,"The original hostage grip changed"
        end
    elseif preview then return false,"A current hostage grip is required" end
    if not wireActor(a,w,preview or equipmentPreview) or not IsValid(v) or not v:IsPlayer() or not v:Alive() or a==v then return false,"Cannot use fiberwire in this state" end
    local allowed,why=I.HostileAllowed(a,v,predecessor,"fiberwire")
    if not allowed then return false,why end
    if not I.Available(v,predecessor) or not I.CanNativeCarry(a,target,predecessor) then return false,"Target is already controlled" end
    if IsValid(v.FakeRagdoll) and not I.CanNativeCarry(a,v.FakeRagdoll,predecessor) then return false,"Release the other grip first" end
    local stamina=a.organism.stamina
    if not stamina or (stamina[1] or 0)<50 then return false,"Fiberwire requires 50 stamina" end
    local delta=target:GetPos()-a:GetPos()
    if delta:LengthSqr()>100*100 then return false,"Move within reach of the target" end
    local facing=Angle(0,v:EyeAngles().y,0):Forward()
    local approach=a:GetPos()-target:GetPos() approach.z=0 approach:Normalize()
    if not IsValid(v.FakeRagdoll) and facing:Dot(approach)>=-.5 then return false,"Keep clear rear access to the target" end
    local trace=util.TraceLine({start=a:EyePos(),endpos=target:WorldSpaceCenter(),filter=a,mask=MASK_SOLID})
    if trace.Hit and trace.Entity~=target and trace.Entity~=v then return false,"Target is obstructed" end
    return true
end
function I.CanWireHandoff(a,target,old,w,dropItem)
    if not IsValid(w) or w:GetOwner()~=a or w:GetClass()~="weapon_zc_fiberwire_standalone" or not w.InteractionStart then return false,"Carry fiberwire with the native adapter" end
    local stealth=ZCityStealth
    if not stealth or not stealth.Enabled:GetBool() or not stealth.TrialAllowed(a) or not stealth.SeamsReady() then return false,"Stealth integration is unavailable" end
    return I.WireEligibility(w,target,old,true,dropItem)
end
function I.PrepareWire(w,target,stop,predecessor)
    if not I.WireEligibility(w,target,predecessor) then return false end
    local a=w:GetOwner() local v=I.Receiver(target)
    local s={system="fiberwire",policyIntent="fiberwire",a=a,v=v,weapon=w,phase="hold",hostile=true,organism=v.organism,previousBody=v.FakeRagdoll,
        cancel=function(session)
            if session.ending then return end
            session.ending=true
            -- Fake can create its native body before a later callback throws.
            -- Claim only that newly created, still-unowned body for restoring
            -- inherited scale; never resize another controller's body.
            local rag=IsValid(session.v) and session.v.FakeRagdoll
            if session.scales and not session.body and IsValid(rag) and rag~=session.previousBody
                and rag:IsRagdoll() and I.Receiver(rag)==session.v and I.Reserve(session,{rag}) then
                session.body=rag session.bodyModel=rag:GetModel()
            end
            local ok,err=xpcall(stop,debug.traceback)
            I.WireEnded(w)
            if not ok then ErrorNoHalt("[ZCityInteractions] Wire cleanup failed: "..tostring(err).."\n") end
        end}
    local actors={a,v} if target~=v then actors[#actors+1]=target end
    s.actors=actors
    if not I.Reserve(s,actors,predecessor) then return false end
    I.NativeSessions[w]=s
    if predecessor then
        s.scales={} s.resistance=math.Clamp(predecessor.progress or 0,0,1)
        for _,p in ipairs({a,v}) do
            local saved=predecessor.scales[p]
            if saved then
                s.scales[p]=type(saved)=="number" and {original=saved,model=predecessor.models[p]} or saved
                predecessor.scales[p]=nil I.TransferScale(predecessor,s,p)
            end
        end
        if predecessor.system=="hostage" then ZCityHostage.Gameplay.End(predecessor,nil,false,true)
        else ZCityStealth.End(predecessor,nil,true) end
        if s.done then return false end
        if not wireActor(a,w) or not IsValid(v) or not v:Alive() or v.organism~=s.organism
            or v.organism.otrub or not I.HostileAllowed(a,v,s,"fiberwire") then s.cancel(s) return false end
        for p,saved in pairs(s.scales) do
            if p:GetModelScale()~=1 or p:GetModel()~=saved.model then s.cancel(s) return false end
        end
    end
    return true
end
function I.AttachWire(w,rag)
    local s=I.NativeSessions[w]
    if not s or s.done or not IsValid(rag) or not rag:IsRagdoll() or I.Receiver(rag)~=s.v or not I.Reserve(s,{rag}) then I.WireEnded(w) return false end
    s.body=rag
    I.WireBreathing[s.organism]=s
    s.actors[#s.actors+1]=rag s.bodyModel=rag:GetModel()
    s.resistance=s.resistance or 0 s.last=CurTime()
    for _,p in ipairs({s.a,s.v}) do
        p:SetNWString("zci_native","fiberwire") p:SetNWBool("zci_native_initiator",p==s.a)
        p:SetNWEntity("zci_native_partner",p==s.a and s.v or s.a) p:SetNWFloat("zci_native_resist",s.resistance)
    end
    return true
end
function I.WireEnded(w)
    local s=I.NativeSessions[w]
    if not s then return end
    s.done=true I.NativeSessions[w]=nil
    if I.WireBreathing[s.organism]==s then I.WireBreathing[s.organism]=nil end
    for _,p in ipairs({s.a,s.v}) do
        if IsValid(p) and p:GetNWEntity("zci_native_partner")== (p==s.a and s.v or s.a) then
            p:SetNWString("zci_native","") p:SetNWEntity("zci_native_partner",NULL) p:SetNWFloat("zci_native_resist",0)
        end
    end
    local scales=s.scales or {};s.scales=nil
    for p,saved in pairs(scales) do
        local unchanged=IsValid(p) and p:GetModelScale()==1
        I.EndScale(s,p,saved.original)
        if p==s.v and unchanged and IsValid(s.body) and s.body:GetModel()==s.bodyModel and s.body:GetModelScale()==1 then
            s.body:SetModelScale(saved.original,0)
        end
    end
    I.Release(s) I.Protect(s.v,2)
end
function I.WireValid(w)
    local s=I.NativeSessions[w]
    if not s then return false end
    for p,saved in pairs(s.scales or {}) do
        if not IsValid(p) or p:GetModelScale()~=1 or p:GetModel()~=saved.model then return false end
    end
    return wireActor(s.a,w) and IsValid(s.v) and s.v:Alive() and s.v.organism==s.organism
        and IsValid(s.body) and w.StrangleRag==s.body and s.body.Strangler==s.a
        and s.body.StrangleLocked and s.a:GetPos():DistToSqr(s.body:GetPos())<160*160
        and I.HostileAllowed(s.a,s.v,s)
end
-- The lungs owner queries the current grip; no temporary write to a medical
-- regeneration value can overwrite a concurrent poison or treatment.
function I.BreathingWire(org)
    local s=I.WireBreathing[org]
    if s and not s.done and s.organism==org and I.NativeSessions[s.weapon]==s
        and IsValid(s.weapon) and s.weapon:GetStrangling() and I.WireValid(s.weapon) then
        return s.weapon
    end
end
-- Contextual invocation enters the weapon's native start path. The weapon
-- owns physics, stamina, oxygen suppression, effects and justice wrappers.
function I.StartWire(a,target,predecessor)
    local w=IsValid(a) and a:GetActiveWeapon()
    if not IsValid(w) or w:GetClass()~="weapon_zc_fiberwire_standalone" or not w.InteractionStart then
        return false,"Equip fiberwire with the native interaction adapter"
    end
    if I.NativeSessions[w] then return false,"Already controlling a target" end
    local ok,accepted,reason=pcall(w.InteractionStart,w,target,predecessor)
    if not ok or not accepted then
        local s=I.NativeSessions[w];if s then s.cancel(s) end
        if not ok then ErrorNoHalt("[Interactions] Fiberwire start failed: "..tostring(accepted).."\n") end
        return false,ok and reason or "Fiberwire start was interrupted"
    end
    return true,reason
end
hook.Add("PostEntityTakeDamage","ZCityInteractions.NativeInjury",function(p,dmg,took)
    local s=I.Session(p)
    if s and s.system=="fiberwire" and took and dmg:GetDamage()>0 and dmg:GetInflictor()~=s.weapon then s.cancel(s) end
end)
hook.Add("Think","ZCityInteractions.NativeLifetimes",function()
    for w,s in pairs(I.NativeSessions) do
        if not IsValid(w) or not I.WireValid(w) then s.cancel(s)
        else
            local now=CurTime() local dt=math.Clamp(now-(s.last or now),0,.1) s.last=now
            local resisting=(s.resistUntil or 0)>now and not s.v.organism.otrub and I.HandsAvailable(s.v)
            s.resistance=math.Clamp((s.resistance or 0)+dt*(resisting and .25 or -.1),0,1)
            s.a:SetNWFloat("zci_native_resist",s.resistance) s.v:SetNWFloat("zci_native_resist",s.resistance)
            if s.resistance>=1 then s.cancel(s) end
        end
    end
end)
hook.Add("StartCommand","ZCityInteractions.NativeResistance",function(p,cmd)
    local s=I.Session(p)
    if s and s.system=="fiberwire" and p==s.v then s.resistUntil=cmd:KeyDown(IN_USE) and CurTime()+.25 or 0 end
end)
for _,event in ipairs({"PlayerSpawn","PlayerDisconnected","PlayerDeath","PlayerSilentDeath"}) do
    hook.Add(event,"ZCityInteractions.NativeLife",function(p)
        if event=="PlayerSpawn" and OverrideSpawn then return end
        local s=I.Session(p) if s and s.system=="fiberwire" then s.cancel(s) end
    end)
end
for _,event in ipairs({"PreCleanupMap","ZB_EndRound","ZB_PreRoundStart","ShutDown"}) do
    hook.Add(event,"ZCityInteractions.NativeRound",function()
        local pending={} for _,s in pairs(I.NativeSessions) do pending[#pending+1]=s end
        for _,s in ipairs(pending) do s.cancel(s) end
    end)
end
