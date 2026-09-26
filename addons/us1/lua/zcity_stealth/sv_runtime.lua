local S=ZCityStealth
local I=ZCityInteractions
if S.Shutdown then S.Shutdown() end
S.Enabled=CreateConVar("zsf_enabled","0",FCVAR_ARCHIVE+FCVAR_REPLICATED,"Enable reviewed stealth gameplay",0,1)
S.TrialUser=CreateConVar("zsf_trial_steamid","",FCVAR_ARCHIVE,"Trial initiators: admin for ULX admin inheritance, SteamID64 for one tester, empty for unrestricted")
S.Sessions={} S.ByActor={}
S.Ready=S.Ready or setmetatable({}, {__mode="k"})
local serial=0
local cooldown=setmetatable({}, {__mode="k"})
local rates=setmetatable({}, {__mode="k"})
function S.Say(p,text) if IsValid(p) and p:IsPlayer() then p:ChatPrint("Stealth: "..text) end end
function S.Token(p) return S.Version..":"..p:GetModel() end
S.TrialGateVersion="20260920.admin1"
function S.TrialAllowed(p)
    return I.TrialIdentityAllowed and I.TrialIdentityAllowed(p,S.TrialUser:GetString()) and I.TrialAllowed(p) or false
end
util.AddNetworkString("zsf_ready")
net.Receive("zsf_ready",function(bits,p)
    if bits>2048 or not IsValid(p) then return end
    local token=net.ReadString()
    if token~=S.Token(p) then return end
    S.Ready[p]=token p:SetNWString("zsf_ready_ack",token)
end)
function S.PlayerAvailable(p,session,airborne,allowCarry,target)
    if not IsValid(p) or not p:IsPlayer() or not p:Alive() then return false,"A living player is required" end
    local o=p.organism
    if not o or o.otrub or IsValid(p.FakeRagdoll) or p:InVehicle() or p:GetMoveType()~=MOVETYPE_WALK
        or p:WaterLevel()>1 or p.SuperCrusher or p.suiciding then return false,"Cannot act in this state" end
    if not airborne and not p:OnGround() then return false,"Stand on solid ground" end
    if S.ByActor[p] and S.ByActor[p]~=session then return false,"Already in an interaction" end
    local shared,sharedReason=I.Available(p,session)
    if not shared then return false,sharedReason end
    local h=ZCityHostage and ZCityHostage.Gameplay
    if h and h.HumanClasses and not h.HumanClasses[p.PlayerClassName or "none"] then return false,"This character cannot use human animations" end
    if h and h.ByPlayer and h.ByPlayer[p] and h.ByPlayer[p]~=session then return false,"Finish the hostage interaction first" end
    if not allowCarry and (IsValid(p:GetNetVar("carryent2")) or IsValid(p:GetNetVar("carryent"))) then return false,"Release the held object first" end
    if not session and p:GetNWString("hg_CustomAnim","")~="" then return false,"Another animation is active" end
    -- A target cannot obtain immunity by withholding a client acknowledgement.
    -- SetClip still verifies both actors against the server's loaded models.
    if not target and not p:IsBot() and S.Ready[p]~=S.Token(p) then return false,"Animation content has not loaded for this player" end
    if not p.PlayCustomAnims then return false,"ZCity animation owner is unavailable" end
    local scale=p:GetModelScale()
    if scale<=0 or scale~=scale or scale==math.huge then return false,"Invalid model scale" end
    return true
end
function S.Armed(p,action,w)
    w=w or p:GetActiveWeapon()
    local kind=S.WeaponKind(p,w)
    return S.WeaponMatches(action,kind) and IsValid(w)
        and I.HandsAvailable(p) and not w.reload and not w.deploy
        and not (w.GetInAttack and w:GetInAttack())
end
function S.Visible(a,v)
    local tr=util.TraceLine({start=a:EyePos(),endpos=v:WorldSpaceCenter(),filter=a,mask=MASK_SOLID})
    return not tr.Hit or tr.Entity==v
end
function S.Target(a)
    local h=ZCityHostage and ZCityHostage.Gameplay
    local range=h and h.TraceReach(a) or 80
    local tr=util.TraceHull({start=a:EyePos(),endpos=a:EyePos()+a:GetAimVector()*math.max(range,180),
        mins=Vector(-5,-5,-5),maxs=Vector(5,5,5),filter=a,mask=MASK_SHOT})
    return tr.Entity
end
function S.Reach(a,v)
    local h=ZCityHostage and ZCityHostage.Gameplay
    return v:IsPlayer() and h and h.Reach(a,v) or 64
end
function S.Rear(a,v)
    local delta=a:GetPos()-v:GetPos() delta.z=0 delta:Normalize()
    return Angle(0,v:EyeAngles().y,0):Forward():Dot(delta)<-.5
end
function S.InApproach(a,v,action)
    if not S.Visible(a,v) then return false end
    local delta=v:GetPos()-a:GetPos()
    if action.above then return delta.z<=-48 and delta.z>=-150 and delta:Length2D()<=160 end
    return delta:LengthSqr()<=S.Reach(a,v)^2
end
-- Cleanup callbacks cannot retain combat input ownership after an error.
local function cleanupCall(label,fn,...)
    local ok,err=pcall(fn,...)
    if not ok then ErrorNoHalt("[ZCityStealth] Cleanup "..label..": "..tostring(err).."\n") end
    return ok
end
local function clearControl(p)
    if S.Input then S.Input[p]=nil end
    p:SetNWString("zsf_mode","") p:SetNWString("zsf_clip","") p:SetNWString("zsf_action","")
    p:SetNWInt("zsf_id",0) p:SetNWEntity("zsf_partner",NULL) p:SetNWFloat("zsf_resist",0)
    p:SetNWBool("zsf_mobile",false) p:SetNWBool("zsf_wire_switch",false)
end
local function resetActor(s,p)
    local successor=S.ByActor[p]
    if successor==s then S.ByActor[p]=nil end
    if successor and successor~=s and not successor.done then return end
    local shared=I.Session(p)
    if shared and shared~=s then return end
    if not IsValid(p) then return end
    local owned=s.poses and s.poses[p]
    local stop=owned and p:IsPlayer() and p:GetNWString("hg_CustomAnim")==owned.sequence
        and p:GetNWFloat("hg_CustomAnimStartTime")==owned.start
    -- Release our network lock before entering any addon/animation callback.
    if p:GetNWInt("zsf_id")==s.id then clearControl(p) end
    if stop then cleanupCall("animation",p.PlayCustomAnims,p,"") end
    local scale=s.scales and s.scales[p]
    if scale then
        s.scales[p]=nil
        if p:IsPlayer() then cleanupCall("scale",I.EndScale,s,p,scale)
        elseif p:GetModelScale()==1 then cleanupCall("body scale",p.SetModelScale,p,scale,0) end
    end
    if p==s.a or s.phase~="attempt" then cooldown[p]=CurTime()+1 end
end
function S.End(s,reason,transfer)
    if not s or s.cleanupComplete or s.cleaning then return end
    s.cleaning=true s.done=true s.endReason=reason or s.endReason
    if S.Sessions[s.id]==s then S.Sessions[s.id]=nil end
    cleanupCall("observer",I.EndObservedControl,s)
    if S.ReleaseBody then cleanupCall("body",S.ReleaseBody,s) end
    if S.ReleaseItem then cleanupCall("item",S.ReleaseItem,s) end
    for _,p in ipairs(s.actors or {}) do cleanupCall("actor",resetActor,s,p) end
    if IsValid(s.originalVictim) then cleanupCall("original victim",resetActor,s,s.originalVictim) end
    if S.ReleaseCollision then cleanupCall("collision",S.ReleaseCollision,s) end
    cleanupCall("reservation",I.Release,s)
    -- Also release legacy/partially recorded claims; never another session's.
    for p,owner in pairs(I.Reservations or {}) do if owner==s then I.Reservations[p]=nil end end
    for p,owner in pairs(S.ByActor) do if owner==s then cleanupCall("remaining actor",resetActor,s,p) end end
    if s.hostile and (s.phase~="attempt" or s.inheritedControl) and not transfer then
        cleanupCall("protection",I.Protect,s.originalVictim or s.v,2)
    end
    if reason then cleanupCall("notice",S.Say,s.a,reason) end
    s.cleaning=nil s.cleanupComplete=true
end
function S.RecoverOrphan(p)
    if not IsValid(p) or not p:IsPlayer() then return false end
    local own=S.ByActor[p]
    if (own and not own.done) or I.Session(p) then return false end
    if own then S.End(own) end
    if I.Session(p) then return false end -- a release callback may hand off control
    if p:GetNWString("zsf_mode","")=="" and p:GetNWInt("zsf_id",0)==0 then return false end
    local clip=S.Assets.clips[p:GetNWString("zsf_clip","")]
    local stop=clip and p:GetNWString("hg_CustomAnim","")==clip.sequence
    clearControl(p)
    if stop then cleanupCall("orphan animation",p.PlayCustomAnims,p,"") end
    return true
end
S.CleanupVersion="20260923.cleanup2"
function S.Normalize(s,p)
    if s.scales[p]==nil then s.scales[p]=p:GetModelScale() end
    I.BeginScale(s,p,s.scales[p],s.actors)
    p:SetModelScale(1,0)
end
function S.SetClip(s,p,name,anchor,mobile,speed)
    local clip=S.Assets.clips[name]
    if not clip then return false end
    if p:IsPlayer() then
        local id,d=p:LookupSequence(clip.sequence)
        if not id or id<0 or not d or d<=0 then return false end
        p:PlayCustomAnims(clip.sequence,false,clip.duration)
        s.poses[p]={sequence=clip.sequence,start=p:GetNWFloat("hg_CustomAnimStartTime")}
    end
    p:SetNWString("zsf_mode",s.phase) p:SetNWString("zsf_clip",name)
    p:SetNWString("zsf_action",s.action.id) p:SetNWInt("zsf_id",s.id)
    p:SetNWBool("zsf_initiator",p==s.a)
    p:SetNWEntity("zsf_partner",p==s.a and s.v or s.a)
    p:SetNWFloat("zsf_start",s.start) p:SetNWFloat("zsf_rate",1) p:SetNWFloat("zsf_yaw",s.yaw)
    p:SetNWFloat("zsf_blend",s.blendDuration or .18)
    p:SetNWVector("zsf_anchor",anchor) p:SetNWVector("zsf_origin",p:GetPos())
    p:SetNWBool("zsf_mobile",mobile or false) p:SetNWFloat("zsf_speed",speed or 0)
    return true
end
function S.PairOffset(name,a,v)
    local data=S.Assets.pairs[name]
    if not data then return end
    local scale=(S.Assets.scales[S.Gender(a)]+S.Assets.scales[S.Gender(v)])/2
    local d=data.offsetUE
    return Vector(d[1],d[2],d[3])*scale
end
function S.Phase(s,name,phase,mobile,speed)
    if s.done then return false end
    local clip=S.Assets.clips[name]
    if not clip then S.End(s,"Missing action clip") return false end
    local oldClip=S.Assets.clips[s.clip]
    local continuing=phase=="loop" and s.phase=="loop" and clip.loop and oldClip and oldClip.loop
    local cycle=continuing and S.Cycle(s.a) or 0
    s.blendDuration=continuing and 0 or .18
    s.phase=phase s.start=CurTime() s.deadline=s.start+clip.duration s.clip=name s.hits={}
    s.contactDistance=nil s.contactApproach=nil s.contactTime=nil s.lastHeadZ=nil
    s.walkCycle=cycle or 0 s.clockRate=nil s.clockSent=nil s.releaseContact=nil
    for _,p in ipairs(s.actors) do
        s.positions[p]=p:GetPos()
        p:SetNWVector("zsf_clock",Vector(s.walkCycle,s.start,0))
    end
    local initial=S.Sample(name,S.Gender(s.a),0) initial:Rotate(Angle(0,s.yaw,0))
    s.anchor=s.a:GetPos()-initial
    if not S.SetClip(s,s.a,name,s.anchor,mobile,speed) then S.End(s,"Animation unavailable") return false end
    if IsValid(s.v) then
        local pair=S.Assets.pairs[name]
        if not pair then S.End(s,"Missing paired animation") return false end
        local offset=S.PairOffset(name,s.a,s.v) offset:Rotate(Angle(0,s.yaw,0))
        s.vAnchor=s.anchor+offset
        if not S.SetClip(s,s.v,pair.victim,s.vAnchor,false,0) then S.End(s,"Victim animation unavailable") return false end
    end
    return true
end
function S.Commit(s)
    if s.done then return end
    local permitted,reason=I.PolicyAllowed(s.a,s.policyIntent,s.v)
    if not permitted then S.End(s,reason) return end
    if s.hostile then
        local allowed,reason=I.HostileAllowed(s.a,s.v,s)
        if not allowed then S.End(s,reason) return end
    end
    local resourceActor=s.action.counter and s.v or s.a
    local stamina=IsValid(resourceActor) and resourceActor.organism and resourceActor.organism.stamina
    if stamina and (stamina[1] or 0)<(s.action.stamina or 8) then S.End(s,"Catch your breath first") return end
    if IsValid(s.v) and not S.InApproach(s.a,s.v,s.action) then S.End(s,"Target evaded the attempt") return end
    for _,p in ipairs(s.actors) do S.Normalize(s,p) end
    if S.AcquireCollision then S.AcquireCollision(s) end
    local entry=s.action.clip
    if s.action.above and s.action.variant and s.id%2==0 then entry=s.action.variant end
    if not S.Preflight(s,entry) then S.End(s,"Not enough clear space for this action") return end
    if s.nativeCarry then
        local hands=s.weapons[s.a]
        if not S.BodyAvailable(s.v,s,s.a) or (s.a:GetNetVar("carryent")~=s.v and s.a:GetNetVar("carryent2")~=s.v) then
            S.End(s,"The original grip changed") return
        end
        -- The successor has reserved both actors and passed geometry before
        -- the native owner relinquishes its grip. Never run both physics drivers.
        if s.a:GetNetVar("carryent")==s.v then hands:SetCarrying() end
        if s.a:GetNetVar("carryent2")==s.v then hg.SetCarryEnt2(s.a) end
        s.nativeCarry=nil
    end
    if s.body and not S.AcquireBody(s) then S.End(s,"Body cannot be moved safely") return end
    if not S.Phase(s,entry,"entry") then return end
    if s.hostile and not s.action.counter then I.StartObservedControl(s,s.action.damage=="choke" and "choke" or "dangerous_melee","danger") end
    if stamina then stamina.subadd=(stamina.subadd or 0)+(s.action.stamina or 8) end
end
-- Read-only preflight shared by the equipment menu and the actual handoff.
function S.CanHostageHandoff(a,v,old,w,preview)
    local g=ZCityHostage and ZCityHostage.Gameplay
    if not g or not g.CanWeaponHandoff or not g.CanWeaponHandoff(old) or old.a~=a or old.v~=v then return false,"Establish a hostage hold first" end
    if not S.Enabled:GetBool() or not S.TrialAllowed(a) or not S.SeamsReady() then return false,"Stealth integration is unavailable" end
    if not IsValid(w) or w:GetOwner()~=a or S.WeaponKind(a,w)~="knife" then return false,"Carry a supported knife" end
    local action=S.Actions.interrogate
    if not S.Armed(a,action,w) then return false,"The knife or your hands are not ready" end
    for _,p in ipairs({a,v}) do
        local ok,why=S.PlayerAvailable(p,old,false,false,p==v)
        if not ok then return false,why end
        if (cooldown[p] or 0)>CurTime() then return false,"Wait for recovery before changing control" end
    end
    local ok,why=I.HostileAllowed(a,v,old,"interrogate")
    if not ok then return false,why end
    if not S.InApproach(a,v,action) or not S.Rear(a,v) then return false,"Keep clear rear access to the held target" end
    local stamina=a.organism.stamina
    if not stamina or (stamina[1] or 0)<(action.stamina or 8) then return false,"Catch your breath first" end
    local entry=action.clip local pair=S.Assets.pairs[entry]
    if not pair then return false,"Paired animation unavailable" end
    for _,row in ipairs({{a,entry},{v,pair.victim}}) do
        local clip=S.Assets.clips[row[2]]
        local id,duration
        if clip then id,duration=row[1]:LookupSequence(clip.sequence) end
        if not id or id<0 or not duration or duration<=0 then return false,"Animation unavailable" end
    end
    if not preview then
        local probe={a=a,v=v,actors={a,v},action=action,phase="attempt",yaw=a:EyeAngles().y}
        if not S.Preflight(probe,entry) then return false,"Not enough clear space for knife control" end
    end
    return true
end
function S.CanSoloHandoff(a,old,wire,dropItem)
    if not old or old.done or old.a~=a or S.ByActor[a]~=old or I.Session(a)~=old or old.phase~="loop"
    -- PROVISIONAL(2026-09-21, the stealth stance and wall cover were removed and were the only
    -- entry states for this transition, so it can no longer succeed; re-home solo fiberwire
    -- readying onto a standing predecessor if the owner still wants it, ratify-by: 2026-10-21)
        or IsValid(old.v) or not old.action or (old.action.kind~="stance" and old.action.kind~="cover") then
        return false,"This action cannot transition here"
    end
    local valid,reason=S.Valid(old)
    if not valid then return false,reason or "Current action is no longer valid" end
    if old.wireHandoff and not wire then return false,"Finish the weapon switch first" end
    if IsValid(old.item) then
        if dropItem~=old.item then return false,"Choose an explicit drop-object action first" end
        return S.CanReleaseItem(old,dropItem)
    elseif dropItem then return false,"Held object changed" end
    return true
end
function S.Begin(a,v,id,predecessor,dropItem,previewEquipment)
    local action=S.Actions[id]
    if not action then return false,"Unknown action" end
    local preview=previewEquipment~=nil
    if preview and (predecessor or not IsValid(previewEquipment) or previewEquipment:GetOwner()~=a) then return false,"Equipment changed" end
    local hostageTransfer=predecessor and predecessor.system=="hostage"
    if hostageTransfer then
        if id~="interrogate" then return false,"This hostage handoff is unavailable" end
        local ok,why=S.CanHostageHandoff(a,v,predecessor,a:GetActiveWeapon())
        if not ok then return false,why end
    elseif predecessor then
        local valid,reason=S.CanSoloHandoff(a,predecessor,false,dropItem)
        if not valid then return false,reason end
        -- Fiberwire still needs an equipment-switch transfer contract.
        if action.kind=="wire" then
            return false,"Release the current action first"
        end
    end
    if not S.Enabled:GetBool() then return false,"Gameplay is disabled during validation" end
    if not S.TrialAllowed(a) then return false,"A controlled tester trial is running" end
    if not S.SeamsReady or not S.SeamsReady() then return false,"Required integration is unavailable" end
    local nativeCarry=action.kind=="body" and IsValid(a) and IsValid(v) and (a:GetNetVar("carryent")==v or a:GetNetVar("carryent2")==v)
    local ok,why=S.PlayerAvailable(a,predecessor,false,nativeCarry)
    if not ok then return false,why end
    ok,why=I.PolicyAllowed(a,id,v)
    if not ok then return false,why end
    if (cooldown[a] or 0)>CurTime() then return false,"Wait a moment" end
    if not S.Armed(a,action,previewEquipment) then
        local w=previewEquipment or a:GetActiveWeapon()
        local unsupported=IsValid(w) and I.UnsupportedWeapons[w:GetClass()]
        if unsupported then return false,unsupported end
        local kind=S.WeaponKind(a,w)
        if S.WeaponMatches(action,kind) then return false,"Your arms or weapon are not ready" end
        return false,"Equip "..(action.weapon=="knife" and "a supported knife" or action.weapon=="hands" and "your hands" or action.weapon=="wire" and "fiberwire" or "hands or a supported knife")
    end
    if action.kind=="wire" then
        if preview then return I.WireEligibility(previewEquipment,v,nil,false,nil,true) end
        return I.StartWire(a,v)
    end
    if action.kind=="native" then
        if preview then return false,"Use the full action menu for disarm" end
        return I.StartDisarmAction(a,v,predecessor,dropItem)
    end
    local paired=action.kind=="takedown" or action.kind=="interrogate" or action.kind=="body"
    local hostile=action.kind=="takedown" or action.kind=="interrogate"
    if hostile then
        ok,why=I.HostileAllowed(a,v,predecessor,id)
        if not ok then return false,why end
        if predecessor and (I.Recovery[I.Receiver(v)] or 0)>CurTime() then return false,"Give the released player space" end
    end
    if paired then
        if not IsValid(v) or v==a then return false,"Look at a nearby target" end
        if action.kind=="body" then
            if not S.BodyAvailable(v,nil,nativeCarry and a) then return false,"An unconscious or dead human body is required; release other players' grips first" end
        else
            ok,why=S.PlayerAvailable(v,hostageTransfer and predecessor or nil,false,false,true)
            if not ok then return false,"Target: "..why end
            if (cooldown[v] or 0)>CurTime() then return false,"Target is recovering from an interaction" end
        end
        if not S.Visible(a,v) then return false,"Target is obstructed" end
        local delta=v:GetPos()-a:GetPos()
        if action.above then
            if delta.z> -48 or delta.z< -150 or delta:Length2D()>160 then return false,"Requires a clear elevated approach" end
        elseif delta:LengthSqr()>S.Reach(a,v)^2 then return false,"Move closer" end
        if action.kind~="body" and not action.above and not S.Rear(a,v) then return false,"Approach from behind" end
    end
    local stamina=a.organism.stamina
    if stamina and (stamina[1] or 0)<(action.stamina or 8) then return false,"Catch your breath first" end
    if preview then
        local pair=S.Assets.pairs[action.clip]
        for _,p in ipairs(paired and {a,v} or {a}) do
            local name=p==a and action.clip or pair and pair.victim
            local clip=name and S.Assets.clips[name]
            if not clip then return false,"Animation unavailable" end
            if p:IsPlayer() then
                local seq,duration=p:LookupSequence(clip.sequence)
                if not seq or seq<0 or not duration or duration<=0 then return false,"Animation unavailable" end
            end
        end
        return true
    end
    serial=serial+1
    local s={id=serial,a=a,v=paired and v or nil,actors={a},poses={},scales={},models={},weapons={},positions={},
        action=action,policyIntent=id,cancel=S.End,phase="attempt",start=CurTime(),deadline=CurTime()+.45,yaw=a:EyeAngles().y,body=action.kind=="body",nativeCarry=nativeCarry,hostile=hostile,resist=0}
    if paired then s.actors[2]=v end
    if predecessor then
        local entry=action.clip
        if action.above and action.variant and s.id%2==0 then entry=action.variant end
        local pair=S.Assets.pairs[entry]
        for _,p in ipairs(s.actors) do
            local name=p==a and entry or pair and pair.victim
            local clip=name and S.Assets.clips[name]
            if not clip then return false,"Animation unavailable" end
            if p:IsPlayer() then
                local sequence,duration=p:LookupSequence(clip.sequence)
                if not sequence or sequence<0 or not duration or duration<=0 then return false,"Animation unavailable" end
            end
        end
        if not S.Preflight(s,entry) then return false,"Not enough clear space for this action" end
    end
    -- Reserve the complete successor before ending the solo pose. Release
    -- callbacks cannot expose the initiator or erase the new reservation.
    if not I.Reserve(s,s.actors,predecessor) then return false,"Already in an interaction" end
    if predecessor then
        -- Lifecycle hooks must see the successor while the old pose releases.
        -- Capture identity now; cleanup callbacks cannot redefine its weapon.
        for _,p in ipairs(s.actors) do
            S.ByActor[p]=s s.models[p]=p:GetModel() s.positions[p]=p:GetPos()
            if p:IsPlayer() then s.weapons[p]=p:GetActiveWeapon() end
        end
        S.Sessions[s.id]=s
    end
    if hostageTransfer then
        s.resist=math.Clamp(predecessor.progress or 0,0,1) s.inheritedControl=true
        for _,p in ipairs(s.actors) do
            S.ByActor[p]=s
            local scale=predecessor.scales[p]
            if scale then s.scales[p]=scale.original;predecessor.scales[p]=nil;I.TransferScale(predecessor,s,p) end
        end
        ZCityHostage.Gameplay.End(predecessor,nil,false,true)
        if s.done then return false,"Handoff interrupted" end
        for _,p in ipairs(s.actors) do
            if not S.PlayerAvailable(p,s,false,false,p==v) or p:GetModel()~=predecessor.models[p]
                or p:GetActiveWeapon()~=predecessor.weapons[p] then
                S.End(s,"Handoff interrupted") return false,"Handoff interrupted"
            end
        end
    elseif predecessor then
        s.scales[a]=predecessor.scales[a] predecessor.scales[a]=nil
        I.TransferScale(predecessor,s,a)
        S.End(predecessor,nil,true)
        if s.done then return false,"Handoff interrupted" end
        local valid,reason=S.Valid(s)
        if not valid then S.End(s,reason or "Handoff interrupted") return false,reason or "Handoff interrupted" end
    end
    for _,p in ipairs(s.actors) do
        S.ByActor[p]=s s.models[p]=p:GetModel() s.positions[p]=p:GetPos()
        if p:IsPlayer() then s.weapons[p]=p:GetActiveWeapon() end
        p:SetNWInt("zsf_id",s.id) p:SetNWString("zsf_mode","attempt") p:SetNWString("zsf_action",id)
        p:SetNWFloat("zsf_resist",s.resist)
        p:SetNWBool("zsf_initiator",p==a) p:SetNWEntity("zsf_partner",p==a and s.v or a)
    end
    S.Sessions[s.id]=s
    if paired and v:IsPlayer() then S.Say(v,"Someone is reaching for you. Move away or fight back! Hold your Use key to resist if caught.") end
    return true
end
function S.Valid(s)
    if s.done or not S.Enabled:GetBool() then return false end
    if not I.PolicyAllowed(s.a,s.phase=="throw" and s.body and "throw" or s.policyIntent,s.originalVictim or s.v) then return false,"Interaction permission changed" end
    if s.hostile and not I.HostileAllowed(s.a,s.originalVictim or s.v,s) then return false,"Interaction permission changed" end
    if s.action.counter and not I.HandsAvailable(s.v) then return false,"Defender lost their grip" end
    for _,p in ipairs(s.actors) do
        if not IsValid(p) or p:GetModel()~=s.models[p] or S.ByActor[p]~=s then return false end
        if s.scales[p] and p:GetModelScale()~=1 then return false end
        if p:IsPlayer() then
            if s.phase~="attempt" and s.positions[p] and p:GetPos():DistToSqr(s.positions[p])>64*64 then return false end
            local available,why=S.PlayerAvailable(p,s,s.action.above and s.phase~="attempt",s.nativeCarry and s.phase=="attempt",p~=s.a)
            if not available then return false,why end
            if p:GetActiveWeapon()~=s.weapons[p] and not (s.wireHandoff and s.wireHandoff.selecting and p==s.a
                and p:GetActiveWeapon()==s.wireHandoff.weapon) then return false,"Weapon changed" end
            local pose=s.poses[p]
            if pose and (p:GetNWString("hg_CustomAnim")~=pose.sequence or p:GetNWFloat("hg_CustomAnimStartTime")~=pose.start) then return false end
        elseif not S.BodyAvailable(p,s,s.nativeCarry and s.a) then return false,"Body is no longer available" end
    end
    if s.wireHandoff then return S.WireHandoffValid(s) end
    return S.Armed(s.a,s.action),"Weapon is not ready"
end
hook.Add("FinishMove","ZCityStealth.AcceptMovement",function(p,mv)
    local s=S.ByActor[p]
    if s and not s.done then
        I.GuardScaleMovement(p,mv)
        if not s.done then s.positions[p]=mv:GetOrigin() end
    end
end)
function S.Shutdown()
    local all={}
    for _,s in pairs(S.Sessions) do all[s]=true end
    for _,s in pairs(S.ByActor) do all[s]=true end
    for s in pairs(all) do S.End(s) end
    for _,p in ipairs(player.GetAll()) do S.RecoverOrphan(p) end
end
include("zcity_stealth/sv_body.lua")
include("zcity_stealth/sv_actions.lua")
include("zcity_stealth/sv_reactions.lua")
include("zcity_stealth/sv_items.lua")
include("zcity_stealth/sv_wire_handoff.lua")
hook.Add("Think","ZCityStealth.Sessions",function()
    local pending={} for _,s in pairs(S.Sessions) do pending[#pending+1]=s end
    for _,s in ipairs(pending) do
        local ok,err=xpcall(function() S.Tick(s) end,debug.traceback)
        if not ok then S.End(s,"Interaction interrupted") ErrorNoHalt("[ZCityStealth] "..tostring(err).."\n") end
    end
end)
function S.OwnContact(s,p,dmg)
    local contact=S.DamageContact
    if contact and not contact.consumed and contact.session==s and contact.target==p
        and dmg.GetDamageCustom and dmg:GetDamageCustom()==contact.marker then
        contact.consumed=true
        return true
    end
    return false
end
hook.Add("PostEntityTakeDamage","ZCityStealth.Interrupt",function(p,dmg,took)
    local s=S.ByActor[p]
    if s and took and dmg:GetDamage()>0 and not S.OwnContact(s,p,dmg) then S.End(s,"Interrupted by injury") end
end)
for _,event in ipairs({"PlayerSpawn","PlayerDisconnected","Fake Up"}) do
    hook.Add(event,"ZCityStealth.Cleanup",function(p) local s=S.ByActor[p] if s then S.End(s) end S.RecoverOrphan(p) end)
end
for _,event in ipairs({"PlayerDeath","PlayerSilentDeath","HG_OnOtrub"}) do
    hook.Add(event,"ZCityStealth.Cleanup",function(p)
        local s=S.ByActor[p]
        if s and s.originalVictim~=p and not S.AwaitRagdoll(s,p) then S.End(s) end
    end)
end
for _,event in ipairs({"PreCleanupMap","ZB_EndRound","ZB_PreRoundStart","ShutDown"}) do hook.Add(event,"ZCityStealth.Cleanup",S.Shutdown) end
cvars.AddChangeCallback("zsf_enabled",function(_,_,value) if tonumber(value)==0 then S.Shutdown() end end,"ZCityStealth.Disable")
function S.RequestAction(p,id,selected,equipment,dropItem)
    if not IsValid(p) or not p:IsPlayer() or (rates[p] or 0)>CurTime() then return end
    rates[p]=CurTime()+.15
    id=tostring(id or "")
    if #id>64 then return end
    local s=S.ByActor[p]
    local ok,why
    local native=I.Session(p)
    if native and native.system=="fiberwire" then
        if p==native.a and id=="release" then native.cancel(native) ok=true
        else ok=false why="The wielder can release the wire; the native grip controls this action" end
    elseif native and native.system=="disarm" then
        if p==native.a and id=="release" then native.cancel(native) ok=true
        else ok=false why="Move away to evade the disarm" end
    elseif s then ok,why=S.SessionAction(s,p,id,selected,equipment,dropItem)
    else ok,why=S.Begin(p,selected~=nil and selected or S.Target(p),id) end
    if not ok and why then S.Say(p,why) end
    return ok,why
end
concommand.Add("zsf_action",function(p,_,args)
    S.RequestAction(p,args[1])
end, nil, "Internal (stealth client): request a stealth action: zsf_action <action>.")
hook.Add("PlayerSay","ZCityStealth.Help",function(p,text)
    if string.Trim(string.lower(text))=="!stealth" then p:ConCommand("zsf_menu") return "" end
end)
