local G = ZCityHostage.Gameplay
local I=ZCityInteractions
if G.Shutdown then G.Shutdown(true) end
G.UsabilityRevision = "20260920.usability1"
G.ScaleRevision = "20260920.scale1"
local C = G.Clips
local enabled = CreateConVar("zch_gameplay_enabled", "0", FCVAR_ARCHIVE + FCVAR_REPLICATED, "Enable the reviewed hostage gameplay candidate", 0, 1)
G.Sessions = {}
G.ByPlayer = {}
G.CollisionState={owners=I.CollisionOwners,separations=I.Collisions}
-- An acknowledged model/version remains valid across a controller-only reload.
G.Ready = G.Ready or setmetatable({}, {__mode="k"})
G.MovementLimits = setmetatable({}, {__mode="k"})
function G.RecordMovementLimit(p,limit)
    if not G.ByPlayer[p] or type(limit)~="number" or limit~=limit then return end
    G.MovementLimits[p]={speed=math.Clamp(limit,0,G.Tuning.speed),time=CurTime()}
end
local function movementLimit(p)
    local sample=G.MovementLimits[p]
    if not sample or CurTime()-sample.time>0.25 then return 0 end
    return sample.speed
end
function G.EscortSpeed(p)
    local s=G.ByPlayer[p]
    return s and s.v and math.min(movementLimit(s.a),movementLimit(s.v)) or 0
end
G.MotionClients=G.MotionClients or setmetatable({}, {__mode="k"})
G.AimClients=G.AimClients or setmetatable({}, {__mode="k"})
util.AddNetworkString("zch_aim_ready")
net.Receive("zch_aim_ready",function(len,p)
    if len>256 or not IsValid(p) then return end
    if net.ReadString()==G.AimRevision then
        G.AimClients[p]=G.AimRevision
        p:SetNWString("zch_aim_ack",G.AimRevision)
    end
end)
util.AddNetworkString("zch_motion_ready")
net.Receive("zch_motion_ready",function(len,p)
    if len>256 or not IsValid(p) then return end
    if net.ReadString()==G.MotionRevision then
        G.MotionClients[p]=G.MotionRevision
        p:SetNWString("zch_motion_ack",G.MotionRevision)
    end
end)
local cooldown, grace, rates, input, postureUntil = {}, {}, {}, {}, {}
local serial = 0

local function say(p, text) if IsValid(p) then p:ChatPrint("Hostage: " .. text) end end
local function standingRoom(p)
    local mins,maxs=p:GetHull()
    local pos=p:GetPos()
    local tr=util.TraceHull({start=pos,endpos=pos,mins=mins,maxs=maxs,filter=p,mask=MASK_PLAYERSOLID_BRUSHONLY})
    return not tr.Hit
end
local function nearGround(p)
    local mins,maxs=p:GetHull()
    local pos=p:GetPos()
    local tr=util.TraceHull({start=pos,endpos=pos-Vector(0,0,18),mins=mins,maxs=maxs,filter=p,mask=MASK_PLAYERSOLID_BRUSHONLY})
    return tr.Hit and not tr.StartSolid and tr.HitNormal.z>0.7
end
local function living(p)
    if not IsValid(p) or not p:IsPlayer() then return false,"not a player" end
    if not p:Alive() then return false,"not alive" end
    if not p.organism then return false,"body state has not loaded yet" end
    if p.organism.otrub then return false,"unconscious" end
    if IsValid(p.FakeRagdoll) or IsValid(p:GetNWEntity("FakeRagdoll")) then return false,"ragdolled; get up first" end
    if p:InVehicle() then return false,"inside a vehicle; exit first" end
    if p:GetMoveType()~=MOVETYPE_WALK then return false,"not in normal walking mode" end
    if p:WaterLevel()>=2 then return false,"swimming; get onto dry ground" end
    -- A hop must not grant immunity: tolerate ground within the snap range (18u).
    if not p:OnGround() and not nearGround(p) then return false,"airborne; wait until grounded" end
    -- Sessions strip IN_DUCK, so a crouched player stands up by himself given headroom.
    if p:Crouching() and not standingRoom(p) then return false,"no room to stand up here" end
    local scale=p:GetModelScale()
    if type(scale)~="number" or scale~=scale or scale<=0 or scale==math.huge then return false,"invalid player model scale" end
    local own=G.ByPlayer[p]
    -- B1 (v2): our own self-aim raises p.suiciding; only a foreign one blocks.
    local selfAim=p.suiciding and own and own.selfAim and own.a==p and G.V2(p)
    if p.SuperCrusher or (p.suiciding and not selfAim) then return false,"another special action is active" end
    if not G.HumanClasses[p.PlayerClassName or "none"] then return false,"unsupported player class" end
    return true
end
local function arms(p)
    local o=p.organism
    return o and not o.larmamputated and not o.rarmamputated
        and (o.larm or 0) < 0.99 and (o.rarm or 0) < 0.99
end
local function pistol(p,w)
    w=w or p:GetActiveWeapon()
    return IsValid(w) and G.IsPistol(w)
        and w.CanUse and w:CanUse() and not w.reload and not w.deploy and arms(p) and not G.Cuffed(p)
end
-- v2 hold grip (AUDIT 4e item 9): R is stripped during a hold, so a reload
-- or sprint read through CanUse must not drop the hostage.
local function holdGrip(s)
    local p=s.a
    if not G.V2(p) then return pistol(p) end
    local w=p:GetActiveWeapon()
    return IsValid(w) and G.IsPistol(w) and not w.deploy and arms(p) and not G.Cuffed(p)
end
local function cuffReady(p)
    local w=p:GetActiveWeapon()
    return IsValid(w) and w:GetClass()=="weapon_handcuffs" and not G.Cuffed(p) and arms(p)
end
local function available(p, existing, label)
    if not enabled:GetBool() then return false, "Gameplay trial is disabled" end
    if ZCityHostageOwnerSeams ~= G.Version or not G.SeamsReady() then return false, "Required ZCity integration patches are not loaded" end
    local valid,reason=living(p)
    if not valid then return false,(label or "You")..": "..reason end
    local id,d=p:LookupSequence(C.holdA)
    if not p.PlayCustomAnims or not id or id<0 or not d or d<=0 then return false, "Animation content is unavailable for this model" end
    if G.ByPlayer[p] and G.ByPlayer[p] ~= existing then return false, "Already in an interaction" end
    local shared,sharedReason=I.Available(p,existing)
    if not shared then return false,sharedReason end
    if IsValid(p:GetNetVar("carryent2")) then return false, "Release the carried object first" end
    if not existing and p:GetNWString("hg_CustomAnim", "") ~= "" then return false, "Another animation is active" end
    return true
end
local function duration(p, seq)
    local id, d=p:LookupSequence(seq)
    if not id or id<0 or not d or d<=0 then return end
    return d
end
local function contact(a,v,kind)
    local d=G.Data.contacts[G.Gender(a)][G.Gender(v)]
    if kind=="cuff" then return Vector(d.cuffX,d.cuffY,0) end
    if kind=="kneeling_execution" then return Vector(28,0,0) end
    -- Local +Y is left. Bring the captive back toward the supporting arm.
    -- The same offset drives collision checks, movement and client following.
    return Vector(d.x-4,d.y+2,0)
end
local function clearPath(p, from, to, pair)
    -- Shared with the predicted client path so kerbs behave the same in both
    -- realms; see G.StepSweep.
    return G.StepSweep(p, from, to, pair)
end
local function supportedGround(p,pos,pair)
    local mins,maxs=p:GetHull()
    local tr=util.TraceHull({start=pos+Vector(0,0,2),endpos=pos-Vector(0,0,8),mins=mins,maxs=maxs,filter=pair,mask=MASK_PLAYERSOLID})
    return tr.Hit and not tr.StartSolid and tr.HitNormal.z>0.7 and (tr.HitWorld or (IsValid(tr.Entity) and tr.Entity:GetMoveType()==MOVETYPE_NONE))
end
-- The formation offset is horizontal; on slopes and stairs the follower must
-- stand on its own ground instead of inheriting the captor's height.
local function groundSnap(p,pos,pair)
    local mins,maxs=p:GetHull()
    local tr=util.TraceHull({start=pos+Vector(0,0,18),endpos=pos-Vector(0,0,18),mins=mins,maxs=maxs,filter=pair,mask=MASK_PLAYERSOLID})
    if tr.Hit and not tr.StartSolid and tr.HitNormal.z>0.7 then return tr.HitPos end
    return pos
end
local function restoreScale(s,p,ragdoll)
    local lease=s.scales and s.scales[p]
    if not lease then return end
    s.scales[p]=nil -- claim before calling the engine; cleanup is idempotent.
    if not IsValid(p) then return end
    -- A newer admin/addon scale change owns the value now. Never overwrite it.
    if p:GetModelScale()~=1 then I.EndScale(s,p,lease.original) return end
    I.EndScale(s,p,lease.original)
    -- Main's Ragdoll_Create notification follows the snapshot/Spawn. Restore
    -- that newly-created visual too; do not rebuild its native physics objects.
    if IsValid(ragdoll) and ragdoll.IsRagdoll and ragdoll:IsRagdoll()
        and ragdoll:GetModel()==lease.model and ragdoll:GetModelScale()==1 and lease.original~=1 then
        ragdoll:SetModelScale(lease.original,0)
    end
end
local function normalizeScale(s,p)
    if s.scales[p] then return end
    s.scales[p]={original=p:GetModelScale(),model=p:GetModel()}
    I.BeginScale(s,p,s.scales[p].original,s.participants)
    if p:GetModelScale()~=1 then p:SetModelScale(1,0) end
end
local function normalizeParticipants(s)
    for _,p in ipairs(s.participants) do normalizeScale(s,p) end
    -- Recheck after normalization. A small model must not grow into an unsafe
    -- movement hull if another owner scales that hull along with its model.
    for _,p in ipairs(s.participants) do
        if not clearPath(p,p:GetPos(),p:GetPos(),s.participants) or not supportedGround(p,p:GetPos(),s.participants) then
            G.End(s,"Not enough space to use the animation at normal size")
            return false
        end
    end
    return true
end
local function visible(a,v)
    local tr=util.TraceLine({start=a:EyePos(),endpos=v:WorldSpaceCenter(),filter=a,mask=MASK_SOLID})
    return not tr.Hit or tr.Entity==v
end
local function target(p, forgivingGrab)
    local reach=G.TraceReach(p)
    local tr=util.TraceLine({start=p:EyePos(),endpos=p:EyePos()+p:GetAimVector()*reach,filter=p,mask=MASK_SHOT})
    if forgivingGrab and not (IsValid(tr.Entity) and tr.Entity:IsPlayer()) then
        -- Small acquisition tolerance only. Admission still checks current
        -- distance, front/rear angle, visibility and both swept player hulls.
        -- Cuffing and deliberate shots retain their exact ray targeting.
        local near=util.TraceHull({start=p:EyePos(),endpos=p:EyePos()+p:GetAimVector()*reach,
            mins=Vector(-6,-6,-6),maxs=Vector(6,6,6),filter=p,mask=MASK_SHOT})
        if not near.StartSolid and not near.AllSolid and IsValid(near.Entity) and near.Entity:IsPlayer()
            and p:GetPos():DistToSqr(near.Entity:GetPos())<=G.Reach(p,near.Entity)^2 and visible(p,near.Entity) then return near.Entity end
    end
    return tr.Entity
end
local function publish(s,p,role)
    p:SetNWBool("zch_motion_v2",s.motionV2 or false)
    p:SetNWBool("zch_aim_v1",s.aimV1 or false)
    p:SetNWString("zch_role",role)
    p:SetNWString("zch_kind",s.kind)
    p:SetNWString("zch_handoff",s.handoff and s.handoff.kind or "")
    p:SetNWString("zch_phase",s.phase)
    p:SetNWInt("zch_session",s.id)
    p:SetNWInt("zch_initiator",s.a:EntIndex())
    p:SetNWFloat("zch_yaw",s.yaw)
    p:SetNWBool("zch_front",s.back==false)
    p:SetNWFloat("zch_phase_start",s.start)
    p:SetNWFloat("zch_phase_end",s.deadline or 0)
    p:SetNWEntity("zch_partner",p==s.a and s.v or s.a)
end
local function pose(s,p,seq)
    local d=duration(p,seq)
    if not d then return false end
    p:PlayCustomAnims(seq,false,d)
    p:SetNWString("zch_sequence",seq)
    s.poses[p]={seq=seq,start=p:GetNWFloat("hg_CustomAnimStartTime")}
    return true
end
local function owns(s,p)
    local t=s.poses[p]
    return t and p:GetNWString("hg_CustomAnim")==t.seq and p:GetNWFloat("hg_CustomAnimStartTime")==t.start
end
local function selectHands(p)
    G.Selecting=p
    p:SelectWeapon("weapon_hands_sh")
    G.Selecting=nil
end
local function newSession(a,v,kind,progress,predecessor)
    serial=serial+1
    local s={id=serial,a=a,v=v,kind=kind,phase="attempt",start=CurTime(),poses={},models={},weapons={},collision={},scales={},progress=progress or 0,participants={a}}
    if v then s.participants[2]=v end
    s.system="hostage" s.cancel=G.End s.policyIntent=kind
    if not I.Reserve(s,s.participants,predecessor) then return end
    if predecessor then
        -- Claim the complete successor before callbacks can acquire either
        -- participant. Transfer scale leases without briefly resizing them.
        for _,p in ipairs(s.participants) do
            G.ByPlayer[p]=s
            if predecessor.scales[p] then
                s.scales[p]=predecessor.scales[p] predecessor.scales[p]=nil
                I.TransferScale(predecessor,s,p)
            end
        end
        G.End(predecessor,nil,false,true)
        if s.done then return end
        for _,p in ipairs(s.participants) do
            if not living(p) then G.End(s,"Interaction interrupted during handoff") return end
        end
    end
    s.motionV2=kind=="hold" and G.MotionClients[a]==G.MotionRevision
    s.aimV1=s.motionV2 and G.AimClients[a]==G.AimRevision
    s.yaw=a:EyeAngles().y
    for _,p in ipairs(s.participants) do
        s.models[p]=p:GetModel() s.weapons[p]=p:GetActiveWeapon()
        G.ByPlayer[p]=s
        publish(s,p,kind=="solo" and "surrender" or "attempt")
    end
    G.Sessions[s.id]=s
    return s
end
-- A failed animation/observer callback must not strand the control owner.
local function cleanupCall(label,fn,...)
    local ok,err=pcall(fn,...)
    if not ok then ErrorNoHalt("[ZCityHostage] Cleanup "..label..": "..tostring(err).."\n") end
    return ok
end
local function clearControl(p)
    input[p]=nil G.MovementLimits[p]=nil
    if not IsValid(p) then return end
    p:SetNWBool("zch_motion_v2",false) p:SetNWFloat("zch_move_limit",0)
    p:SetNWBool("zch_aim_v1",false)
    p:SetNWString("zch_sequence","") p:SetNWString("zch_role","") p:SetNWString("zch_phase","")
    p:SetNWString("zch_kind","") p:SetNWString("zch_handoff","")
    p:SetNWEntity("zch_partner",NULL) p:SetNWInt("zch_session",0) p:SetNWFloat("zch_escape",0)
end
function G.RecoverOrphan(p)
    if not IsValid(p) or G.ByPlayer[p] or I.Session(p) then return false end
    if p:GetNWString("zch_role","")=="" and p:GetNWInt("zch_session",0)==0 then return false end
    local sequence=p:GetNWString("zch_sequence","")
    local ownsAnimation=sequence~="" and p:GetNWString("hg_CustomAnim","")==sequence
    clearControl(p)
    if ownsAnimation then cleanupCall("orphan animation",p.PlayCustomAnims,p,"") end
    return true
end
function G.End(s,reason,escaped,transfer,ragdollContext)
    if not s or s.cleanupComplete or s.ending then return end
    s.ending=true s.done=true
    cleanupCall("self aim",G.ClearSelfAim,s)
    cleanupCall("observer",I.EndObservedControl,s)
    G.Sessions[s.id]=nil
    for _,p in ipairs(s.participants) do
        if G.ByPlayer[p]==s then G.ByPlayer[p]=nil end
        -- A predecessor handoff has already reserved the successor. Clear
        -- only the predecessor's published state, never a newer active pose.
        local published=IsValid(p) and p:GetNWInt("zch_session",0)==s.id
        local successor=G.ByPlayer[p] or I.Session(p)
        if not successor or successor==s or published then
            cleanupCall("controls",clearControl,p)
        end
        if IsValid(p) then
            cleanupCall("animation",function() if owns(s,p) then p:PlayCustomAnims("") end end)
            if p==s.a or (s.phase~="attempt" and not s.reversed) then cooldown[p]=CurTime()+0.75 end
            if reason then cleanupCall("notice",say,p,reason) end
        end
        cleanupCall("scale",restoreScale,s,p,ragdollContext and ragdollContext.player==p and ragdollContext.ragdoll or nil)
    end
    cleanupCall("collision",I.ReleaseCollision,s)
    cleanupCall("reservation",I.Release,s)
    if s.v and IsValid(s.v) and ((s.phase~="attempt" and not s.reversed) or s.inheritedControl) and not transfer then
        grace[s.v]=CurTime()+G.Tuning.grace
        cleanupCall("protection",I.Protect,s.v,G.Tuning.grace)
    elseif s.reversed and IsValid(s.v) and not transfer then
        grace[s.v]=CurTime()+1.5
        cleanupCall("protection",I.Protect,s.v,1.5)
    end
    s.cleanupComplete=true s.ending=nil
end
local function phase(s,name,aseq,vseq,seconds)
    if s.done then return false end
    if (aseq and not duration(s.a,aseq)) or (vseq and not duration(s.v,vseq)) then G.End(s,"Missing animation") return false end
    s.phase=name s.start=CurTime() s.deadline=seconds and s.start+seconds or nil
    for _,p in ipairs(s.participants) do
        publish(s,p,s.kind=="solo" and (G.Cuffed(p) and "restrained" or "surrender") or (p==s.a and "captor" or "victim"))
    end
    if aseq then pose(s,s.a,aseq) end
    if vseq then pose(s,s.v,vseq) end
    if s.kind=="cuff" then I.StartObservedControl(s,"restrict","restrict")
    elseif s.kind~="solo" then I.StartObservedControl(s,"firearm","danger") end
    return true
end
local function freezePair(s)
    for _,p in ipairs(s.participants) do s.collision[p]=true end
    I.AcquireCollision(s,s.participants,s.a,s.v)
    s.offset=contact(s.a,s.v,s.kind)
    s.a:SetNWVector("zch_offset",s.offset)
    s.anchor=s.a:GetPos()
    s.fromV=s.v:GetPos()
    s.positions={[s.a]=s.anchor,[s.v]=s.fromV}
end
local function admittedPair(a,v,kind,intent,equipment)
    if not IsValid(v) or not v:IsPlayer() or a==v then return false,"Aim at a nearby player's upper body" end
    if (grace[v] or 0)>CurTime() then return false,"Give the released player space" end
    local shared,sharedReason=I.HostileAllowed(a,v,nil,intent or kind)
    if not shared then return false,sharedReason end
    local old=G.ByPlayer[v]
    if not v:HasWeapon("weapon_hands_sh") then return false,"Target hands are unavailable" end
    local handoff=kind=="cuff" and old and old.kind=="hold" and old.v==v and old.phase=="hold"
    if old and old.kind~="solo" and not handoff then return false,"Target is already involved" end
    local ok,why=available(a); if not ok then return false,why end
    ok,why=available(v,old,"Target"); if not ok then return false,why end
    if a:GetPos():DistToSqr(v:GetPos())>G.Reach(a,v)^2 or not visible(a,v) then return false,"Get closer with clear reach" end
    local delta=a:GetPos()-v:GetPos() delta.z=0 delta:Normalize()
    local back=Angle(0,v:EyeAngles().y,0):Forward():Dot(delta)<-0.5
    if a:GetAimVector():Dot(-delta)<0.5 then return false,"Face the target" end
    local compliant=handoff or G.Cuffed(v) or (old and old.kind=="solo" and old.phase=="kneeling")
    if kind=="hold" or kind=="kneeling_execution" then
        if not pistol(a,equipment) then return false,"Use a supported pistol with both arms available" end
        if kind=="kneeling_execution" and not back and not compliant then return false,"Approach from behind or obtain surrender" end
        if kind=="kneeling_execution" and not (old and old.phase=="kneeling") then return false,"Target must be kneeling" end
    else
        if not cuffReady(a) then return false,"Equip handcuffs with both arms available" end
        if G.Cuffed(v) then return false,"Target is already handcuffed" end
        if not arms(v) then return false,"Target needs both arms for this cuffing animation" end
        if not compliant and not (intent=="arrest" and back) then return false,intent=="arrest" and "Approach from behind or obtain surrender" or "Target must surrender first" end
        if intent=="arrest" then
            local stamina=a.organism.stamina
            if not stamina or (stamina[1] or 0)<12 then return false,"Catch your breath before attempting an arrest" end
        end
        if not duration(a,C.cuffA) or not duration(v,C.cuffV) then return false,"Cuffing animation is unavailable" end
    end
    local pair={a,v}
    local offset=contact(a,v,kind)
    offset:Rotate(Angle(0,a:EyeAngles().y,0))
    local dest=a:GetPos()+offset
    if not clearPath(v,v:GetPos(),dest,pair) or not supportedGround(a,a:GetPos(),pair) or not supportedGround(v,dest,pair) then return false,"Not enough safe space" end
    return true,nil,old,back
end
function G.CanQuickGrab(a,v,w)
    if not IsValid(w) or w:GetOwner()~=a then return false,"Weapon is unavailable" end
    return admittedPair(a,v,"hold",nil,w)
end
function G.CanStartCuff(a,v,arrest)
    return admittedPair(a,v,"cuff",arrest and "arrest" or nil)
end
-- heldKey (optional): the quick-action token whose key is physically held. The
-- hold IS the grab: no windup, and G.KeyReleased may rewind an unfinished entry.
-- Routes without a key (context menu, zch_action) pass nil and behave as before.
function G.Begin(a,v,kind,intent,heldKey)
    if intent~=nil and not (kind=="cuff" and intent=="arrest") then return false,"Invalid interaction transition" end
    local ok,why,old,back=admittedPair(a,v,kind,intent)
    if not ok then return false,why end
    local progress=old and old.progress or 0
    local s=newSession(a,v,kind,progress,old)
    if not s then return false,"Already in an interaction" end
    s.inheritedControl=old and old.kind~="solo" and (old.phase~="attempt" or old.inheritedControl) or false
    s.policyIntent=intent or kind
    s.wasCompliant=old~=nil or G.Cuffed(v)
    s.back=back s.deadline=CurTime()+(intent=="arrest" and .75 or G.Tuning.windup)
    if heldKey and kind=="hold" then s.heldKey=heldKey s.deadline=CurTime() end -- next Think runs the normal attempt->entry admission
    for _,p in ipairs(s.participants) do publish(s,p,"attempt") p:SetNWFloat("zch_escape",progress) end
    say(v,kind=="cuff" and "Cuffing attempt: move away to evade. Hold your Use key to resist if caught." or (s.heldKey and "You are being grabbed! Hold your Use key to resist." or "Grab attempt! Move away to evade; hold your Use key to resist if caught."))
    return true
end
function G.CuffIntent(a,v) return I.PolicyAllowed(a,"arrest",v) and "arrest" or "cuff" end
function G.StartCuff(a,v) return G.Begin(a,v,"cuff") end
function G.StartArrest(a,v) return G.Begin(a,v,"cuff","arrest") end
function G.StartCuffAction(a,v)
    if G.CuffIntent(a,v)=="arrest" then return G.StartArrest(a,v) end
    return G.StartCuff(a,v)
end
local function solo(p,posture,ordered)
    local old=G.ByPlayer[p]
    if old and old.kind~="solo" then return false,"Release the paired interaction first" end
    local ok,why=available(p,old); if not ok then return false,why end
    if posture=="lie" and not G.Cuffed(p) then return false,"Only available while restrained" end
    local wanted=posture=="lie" and "lying" or "kneeling"
    if old and (old.phase==wanted or (old.phase=="posture_entry" and old.nextPosture==wanted)) then return true end
    if old and (old.phase=="posture_entry" or old.phase=="stand_up") then return false,"Finish changing posture first" end
    if ordered and (postureUntil[p] or 0)>CurTime() then return false,"Give them time to change posture" end
    if not p:HasWeapon("weapon_hands_sh") then return false,"Hands weapon is unavailable" end
    local from=old and old.phase
    local seq=posture=="lie" and (from=="kneeling" and C.kneelToLie or C.lieIn)
        or (G.Cuffed(p) and C.kneelIn or C.surrenderIn)
    if not duration(p,seq) then return false,"Posture animation unavailable for this model" end
    -- Transfer posture leases without restoring scale between poses.
    selectHands(p)
    local s=newSession(p,nil,"solo",nil,old)
    if not s then return false,"Already in an interaction" end
    if not normalizeParticipants(s) then return false,"Not enough safe space at normal size" end
    s.weapons[p]=p:GetActiveWeapon()
    s.anchor=p:GetPos() s.positions={[p]=s.anchor}
    s.cuffed=G.Cuffed(p)
    s.nextPosture=posture=="lie" and "lying" or "kneeling"
    phase(s,"posture_entry",seq,nil,duration(p,seq) or 0)
    if ordered then postureUntil[p]=(s.deadline or CurTime())+3 end
    return true
end
function G.CaptureInput(p,cmd)
    local previous=input[p]
    local release=cmd:KeyDown(IN_RELOAD)
    input[p]={forward=cmd:GetForwardMove(),side=cmd:GetSideMove(),yaw=cmd:GetViewAngles().y,pitch=cmd:GetViewAngles().p,time=CurTime(),struggle=cmd:KeyDown(IN_USE),release=release}
    local s=G.ByPlayer[p]
    if release and previous and not previous.release and s and s.a==p then
        -- v2: R never lets go of an established hold; release is a held-Use danger row.
        if G.V2(p) and s.kind=="hold" and s.phase~="attempt" then return true end
        G.Release(p)
        return true
    end
end
local function reposition(s,dt,commandOrigin)
    if not s.v then return true end
    local pair=s.participants
    local i=input[s.a]
    local predicted=s.motionV2 and s.phase=="hold"
    local v2=G.V2(s.a)
    if predicted then
        local limit=G.EscortSpeed(s.a)
        if not v2 or not s.nwLimit or math.abs(limit-s.nwLimit)>=1 or (limit==0)~=(s.nwLimit==0) then
            s.nwLimit=limit s.a:SetNWFloat("zch_move_limit",limit)
        end
    end
    local nextYaw=s.yaw
    local shift=Vector(0,0,0)
    s.motion=shift
    if s.phase=="hold" and i and CurTime()-i.time<0.25 then
        nextYaw=math.ApproachAngle(s.yaw,i.yaw,(predicted and 180 or 60)*dt)
        local ang=Angle(0,nextYaw,0)
        local f=math.Clamp(i.forward/200,-1,1) local r=math.Clamp(i.side/200,-1,1)
        local move=ang:Forward()*f+ang:Right()*r
        if move:LengthSqr()>1 then move:Normalize() end
        local cap=math.min(G.Tuning.speed,movementLimit(s.a),movementLimit(s.v))
        if not predicted then shift=move*cap*dt end
    end
    local a=predicted and (commandOrigin or s.a:GetPos()) or s.anchor+shift
    if predicted then shift=a-s.anchor end
    local off=Vector(s.offset.x,s.offset.y,0) off:Rotate(Angle(0,nextYaw,0))
    local v=a+off
    if predicted then
        -- Sweep short pieces of the rotation arc instead of cutting the
        -- follower through a corner along a single chord.
        local delta=math.AngleDifference(nextYaw,s.yaw)
        local steps=math.max(1,math.ceil(math.abs(delta)/5))
        local previous=s.v:GetPos()
        for step=1,steps do
            local offset=Vector(s.offset.x,s.offset.y,0)
            offset:Rotate(Angle(0,s.yaw+delta*step/steps,0))
            local dest=a+offset
            if not G.ClearEscortPath(s.v,previous,dest,pair,v2) then
                -- A turn may fail while translation along the old formation
                -- remains safe. Never undo the captor's predicted movement.
                nextYaw=s.yaw
                offset=Vector(s.offset.x,s.offset.y,0) offset:Rotate(Angle(0,nextYaw,0))
                v=a+offset
                break
            end
            previous=dest
        end
    end
    v=groundSnap(s.v,v,pair)
    if s.phase=="entry" or s.phase=="cuffing" or (s.phase=="execute" and s.kind=="kneeling_execution") then v=LerpVector(math.Clamp((CurTime()-s.start)/0.5,0,1),s.fromV,v)
    elseif s.phase=="entry_reverse" then v=LerpVector(math.Clamp((s.deadline-CurTime())/0.5,0,1),s.fromV,v) end
    local blocked
    if v2 then
        -- The predicate the captor's Move already used; a block stops the pair.
        blocked=not G.ClearEscortPath(s.a,s.a:GetPos(),a,pair,true) or not G.ClearEscortPath(s.v,s.v:GetPos(),v,pair,true)
    else
        blocked=not clearPath(s.a,s.a:GetPos(),a,pair) or not clearPath(s.v,s.v:GetPos(),v,pair)
            or not supportedGround(s.a,a,pair) or not supportedGround(s.v,v,pair)
    end
    if blocked then
        s.blocked=s.blocked or CurTime()
        if CurTime()-s.blocked>(v2 and G.Tuning.blockedV2 or 0.75) then G.End(s,"Hold released: obstructed") end
        return false
    end
    s.blocked=nil s.yaw=nextYaw s.anchor=a
    s.motion=shift
    s.positions[s.a]=a s.positions[s.v]=v
    if not predicted then s.a:SetPos(a) end
    s.v:SetPos(v)
    if not v2 or not s.nwYaw or math.abs(math.AngleDifference(s.yaw,s.nwYaw))>=0.25 then
        s.nwYaw=s.yaw
        for _,p in ipairs(pair) do p:SetNWFloat("zch_yaw",s.yaw) end
    end
    return true
end
-- Aiming at yourself is not a pose change alone: it enters ZCity's own suicide
-- state, so its existing owner supplies the timer, the FOV effect and the
-- outcome. hg.CanSuicide (homigrad/sh_utility.lua) gates it and the weapon
-- base's suicide_time machine (homigrad_base/shared.lua) runs it. We own only
-- the mode->flag mapping and never the death itself. The latch means we clear
-- only what we set, so a player who used the console command keeps their state.
local function stepSelfAim(s)
    local p=s.a
    if not IsValid(p) then return end
    local aiming=G.AimMode(p,p:GetActiveWeapon())=="self"
        and (not hg or not hg.CanSuicide or hg.CanSuicide(p))
    if G.V2(p) then
        -- B14: the host cleared our flag (deploy, CanSuicide). Accept that until
        -- the captor looks up again instead of re-raising it every tick.
        if s.selfAim and not p.suiciding then s.selfAim=nil s.selfAimRefused=true end
        if not aiming then s.selfAimRefused=nil elseif s.selfAimRefused then aiming=false end
    end
    if aiming and not s.selfAim then s.selfAim=true p.suiciding=true
    elseif not aiming and s.selfAim then s.selfAim=nil p.suiciding=false end
end
function G.ClearSelfAim(s)
    if s and s.selfAim and IsValid(s.a) then s.a.suiciding=false end
    if s then s.selfAim=nil end
end
local function chooseHold(s,dt)
    local i=input[s.a] or {}
    local move=s.motion or Vector(0,0,0)
    local speed=dt>0 and move:Length2D()/dt or 0
    local facing=Angle(0,s.yaw,0)
    local f,r=move:Dot(facing:Forward()),move:Dot(facing:Right())
    if s.motionV2 then
        -- Smooth only the gait, never the controls. Batched user commands must
        -- not alternate the idle/walk sequence at the server Think frequency.
        local moving=i.time and CurTime()-i.time<0.25 and (math.abs(i.forward or 0)+math.abs(i.side or 0)>0)
        if moving then
            -- A linear approach hits zero on every empty Think between
            -- batched commands. Low-pass displacement instead, independent
            -- of frame rate; releasing movement keys still stops immediately.
            s.animSpeed=(s.animSpeed or 0)+(speed-(s.animSpeed or 0))*(1-math.exp(-dt/0.1))
        else s.animSpeed=0 end
        speed=s.animSpeed
        if move:LengthSqr()>0.001 then s.animDirection=move end
        local direction=s.animDirection or move
        f,r=direction:Dot(facing:Forward()),direction:Dot(facing:Right())
        if s.walkAxis=="f" and math.abs(r)<math.abs(f)*1.2 then r=0 end
        if s.walkAxis=="r" and math.abs(f)<math.abs(r)*1.2 then f=0 end
    end
    local suffix
    if speed>1 then
        suffix=math.abs(f)>=math.abs(r) and (f>0 and "walkforward" or "walkback") or (r>0 and "walkright" or "walkleft")
        s.walkAxis=math.abs(f)>=math.abs(r) and "f" or "r"
    end
    -- v2 idles on the authored loop; the aim-space blend replaced it within a tick.
    local v2=G.V2(s.a)
    local sa=suffix and "zcg_paired_pistol_grabhostage_"..suffix.."_att" or (v2 and C.holdA or "zcg_aim_att")
    local sv=suffix and "zcg_paired_pistol_grabhostage_"..suffix.."_vic" or (v2 and C.holdV or "zcg_aim_vic")
    local changed=not s.poses[s.a] or s.poses[s.a].seq~=sa
    if changed then pose(s,s.a,sa) pose(s,s.v,sv) end
    local rate=suffix and math.Clamp(speed/G.Tuning.speed,0,1) or 0
    s.walkCycle=((s.walkCycle or 0)+dt*rate)%1
    if changed or math.abs(rate-(s.walkRate or -1))>0.01 then
        s.walkRate=rate
        for _,p in ipairs(s.participants) do
            p:SetNWFloat("zch_walk_cycle",s.walkCycle)
            p:SetNWFloat("zch_walk_time",CurTime())
            p:SetNWFloat("zch_walk_rate",rate)
        end
    end
    local aim=G.AimPoseAngles(s.a,Angle(i.pitch or 0,i.yaw or s.yaw,0))
    local yaw=math.Clamp(math.AngleDifference(aim.y,s.yaw)/50,-1,1)
    local pitch=math.Clamp(-aim.p/35,-1,1)
    for _,p in ipairs(s.participants) do p:SetPoseParameter("zcg_yaw",yaw) p:SetPoseParameter("zcg_pitch",pitch) end
end
local function attemptStillValid(s)
    local a,v=s.a,s.v
    if not I.HostileAllowed(a,v,s) then return false end
    if a:GetPos():DistToSqr(v:GetPos())>G.Reach(a,v)^2 or not visible(a,v) then return false end
    local d=a:GetPos()-v:GetPos() d.z=0 d:Normalize()
    if a:GetAimVector():Dot(-d)<0.5 then return false end
    if s.back and not s.wasCompliant and not G.Cuffed(v) then
        if Angle(0,v:EyeAngles().y,0):Forward():Dot(d)>=-0.5 then return false end
    end
    return true
end
function G.Release(p)
    local s=G.ByPlayer[p]
    if not s then return false,"No interaction" end
    if s.phase=="release" or s.phase=="stand_up" or s.phase=="entry_reverse" then return true end
    if s.v and p~=s.a then return false,"Struggle to escape" end
    if s.phase=="attempt" then G.End(s,"Attempt canceled") return true end
    if s.kind=="solo" then
        if s.phase=="posture_entry" then return false,"Finish changing posture first" end
        if s.phase=="standing" then G.End(s) return true end
        local seq=s.phase=="lying" and C.lieOut or (G.Cuffed(p) and C.kneelOut or C.surrenderOut)
        phase(s,"stand_up",seq,nil,duration(p,seq) or 0)
        postureUntil[p]=(s.deadline or CurTime())+5
    else
        phase(s,"release",C.exitA,C.exitV,math.max(duration(s.a,C.exitA) or 0,duration(s.v,C.exitV) or 0))
    end
    return true
end
-- The quick-action key came up. Only an unfinished, key-held grab entry rewinds;
-- an established hold (or any session started without a key) is unaffected.
function G.KeyReleased(p,token)
    local s=G.ByPlayer[p]
    if not s or s.done or s.a~=p or not s.heldKey or s.heldKey~=token then return false end
    s.heldKey=nil
    if s.phase=="attempt" then G.End(s,"Attempt canceled") return true end
    if s.phase~="entry" or not s.deadline or CurTime()>=s.deadline then return false end
    -- Mirror: rewind for exactly as long as the entry ran (never longer than the
    -- clip). G.Cycle and reposition() derive cycle and position from this clock.
    local spent=math.Clamp(CurTime()-s.start,0,s.deadline-s.start)
    s.phase="entry_reverse" s.start=CurTime() s.deadline=s.start+spent
    publish(s,s.a,"captor") publish(s,s.v,"victim")
    return true
end
function G.RestraintChanged(p)
    local s=G.ByPlayer[p]
    if not s or s.kind~="solo" then return end -- removing cuffs does not release a separate grip
    if not living(p) then G.End(s,"Restraint posture interrupted") return end
    s.cuffed=G.Cuffed(p)
    if not s.cuffed then
        if s.phase=="standing" then G.End(s) return end
        local seq=(s.phase=="lying" or s.nextPosture=="lying") and C.uncuffGetUp or C.surrenderOut
        phase(s,"stand_up",seq,nil,duration(p,seq) or 0)
    elseif s.phase=="kneeling" then
        s.nextPosture="kneeling"
        phase(s,"posture_entry",C.surrenderToCuffed,nil,duration(p,C.surrenderToCuffed) or 0)
    end
end
local function fireAtVictim(s)
    if s.shot then return end
    s.shot=true -- claim before firing: weapon damage may re-enter cleanup synchronously.
    local w=s.weapons[s.a]
    if not IsValid(w) or s.a:GetActiveWeapon()~=w or not pistol(s.a) or w:Clip1()<=0 then G.End(s,"Unable to fire") return end
    local before=w:Clip1()
    G.Firing=s.a
    local ok,err=xpcall(function() w:PrimaryAttack(true) end,debug.traceback)
    G.Firing=nil
    if not ok then ErrorNoHalt("[ZCityHostage] "..tostring(err).."\n") end
    if not s.done then G.End(s,(ok and w:Clip1()<before) and "Shot fired; hold released" or "Shot did not fire") end
end
function G.Execution(p,selected)
    local s=G.ByPlayer[p]
    if not s then return G.Begin(p,selected~=nil and selected or target(p),"kneeling_execution") end
    if s.a~=p or s.kind~="hold" or s.phase~="hold" then return false,"First establish a hostage hold" end
    local allowed,why=I.PolicyAllowed(p,"execution",s.v)
    if not allowed then return false,why end
    local w=s.weapons[p]
    if not pistol(p) or w:Clip1()<=0 then return false,"A ready loaded pistol is required" end
    -- Keep the living victim's hold pose; death remains the normal damage/ragdoll owner's decision.
    s.phase="execute" s.policyIntent="execution" s.start=CurTime() s.deadline=CurTime()+2
    publish(s,s.a,"captor") publish(s,s.v,"victim")
    say(s.v,"Captor is preparing to shoot. Struggle or get help!")
    return true
end
local function validSession(s)
    if s.done or not enabled:GetBool() then return false end
    if s.kind~="solo" and not I.HostileAllowed(s.a,s.v,s) then return false end
    for _,p in ipairs(s.participants) do
        local switching=s.phase=="handoff" and s.handoff and p==s.a
            and (p:GetActiveWeapon()==s.handoff.previous or p:GetActiveWeapon()==s.handoff.weapon)
        local w=p:GetActiveWeapon()
        local restraintSwitch=s.kind=="solo" and (G.Cuffed(p) or s.phase=="stand_up") and IsValid(w)
            and (w:GetClass()=="weapon_hands_sh" or w:GetClass()=="weapon_handcuffs_key")
        if not living(p) or p:GetModel()~=s.models[p] or (w~=s.weapons[p] and not switching and not restraintSwitch)
            or (s.poses[p] and not owns(s,p)) then return false end
        if s.scales[p] and p:GetModelScale()~=1 then return false end
        local drift=(p==s.a and s.motionV2 and s.phase=="hold" and G.V2(s.a)) and 96 or 32
        if s.positions and s.positions[p] and IsValid(p) and p:GetPos():DistToSqr(s.positions[p])>drift*drift then return false end
    end
    return true
end
function G.CanWeaponHandoff(s)
    return s and not s.done and s.kind=="hold" and (s.phase=="hold" or s.phase=="handoff")
        and G.ByPlayer[s.a]==s and G.ByPlayer[s.v]==s and I.Session(s.a)==s and I.Session(s.v)==s
        and validSession(s)
end
function G.PublishHandoff(s)
    for _,p in ipairs(s.participants) do publish(s,p,p==s.a and "captor" or "victim") end
end
local function stepSession(s,now)
    local dt=math.Clamp(now-(s.last or now),0,0.1) s.last=now
    if s.kind=="solo" and s.cuffed~=G.Cuffed(s.a) then G.RestraintChanged(s.a) end
    local valid=validSession(s)
    if not valid then G.End(s,"Interaction interrupted")
    elseif s.kind=="cuff" and (not cuffReady(s.a) or not arms(s.v)) then G.End(s,"Cuffing interrupted: arms or equipment unavailable")
    elseif s.kind~="solo" and s.kind~="cuff" and s.phase~="handoff" and not holdGrip(s) then G.End(s,"Grip lost")
    elseif s.phase=="attempt" then
        if not attemptStillValid(s) then G.End(s,"Grab evaded",true)
        elseif now>=s.deadline and normalizeParticipants(s) then
            if s.policyIntent=="arrest" then
                local stamina=s.a.organism and s.a.organism.stamina
                if not stamina or (stamina[1] or 0)<12 then G.End(s,"Arrest interrupted: exhausted")
                else stamina.subadd=(stamina.subadd or 0)+12 end
            end
            if not s.done then
                freezePair(s)
                selectHands(s.v) s.weapons[s.v]=s.v:GetActiveWeapon()
                local ca=s.kind=="kneeling_execution" and C.executeA or (s.kind=="cuff" and C.cuffA or (s.back and C.rearA or C.frontA))
                local cv=s.kind=="kneeling_execution" and (G.Cuffed(s.v) and C.kneel or C.surrender) or (s.kind=="cuff" and C.cuffV or (s.back and C.rearV or C.frontV))
                phase(s,s.kind=="kneeling_execution" and "execute" or (s.kind=="cuff" and "cuffing" or "entry"),ca,cv,math.max(duration(s.a,ca) or 0,duration(s.v,cv) or 0))
            end
        end
    else
        I.StepObservedControl(s)
        if s.v then
            reposition(s,dt)
            -- Command-time following already consumed this displacement
            -- from the anchor. Keep it for the gait's Think-time sample.
            if s.motionV2 and s.phase=="hold" then s.motion=s.motion+(s.commandMotion or vector_origin) end
            s.commandMotion=nil
        end
        if not s.done and s.v then
            local vi=input[s.v]
            local resisting=(vi and now-vi.time<0.25 and vi.struggle) or (s.struggleUntil or 0)>now
            if resisting then
                local seconds=G.EscapeSeconds(G.Cuffed(s.v),G.V2(s.a))
                local stamina=s.v.organism and s.v.organism.stamina
                local scale=stamina and math.Clamp((stamina[1] or 0)/math.max(stamina.max or 180,1),0.25,1) or 1
                s.progress=math.min(1,s.progress+dt/seconds*scale)
                -- dt is capped above: bound our contribution, never truncate
                -- exertion already queued by the native stamina owners.
                if stamina then stamina.subadd=(stamina.subadd or 0)+dt*2 end
            else s.progress=math.max(0,s.progress-dt*0.06) end
            -- v2 publishes whole-percent steps, not every decay tick.
            if not G.V2(s.a) or not s.nwEscape or math.abs(s.progress-s.nwEscape)>=0.01 or (s.progress==0)~=(s.nwEscape==0) then
                s.nwEscape=s.progress
                s.v:SetNWFloat("zch_escape",s.progress) s.a:SetNWFloat("zch_escape",s.progress)
            end
            if s.progress>=1 then G.End(s,"Victim escaped",true) end
        end
        if not s.done then
            if s.phase=="handoff" then G.StepControlHandoff(s)
            elseif s.phase=="hold" then stepSelfAim(s) chooseHold(s,dt)
            elseif s.phase=="execute" then
                local w=s.weapons[s.a]
                local head=G.ExecutionTarget(s.a)
                local _,pos,ang
                if IsValid(w) and w.GetTrace then _,pos,ang=w:GetTrace(true) end
                local clear=head and pos and util.TraceLine({start=pos,endpos=head,filter={s.a,w},mask=MASK_SHOT})
                local aligned=head and pos and ang and ang:Forward():Dot((head-pos):GetNormalized())>0.985
                if now-s.start>=0.6 and aligned and clear and (not clear.Hit or clear.Entity==s.v) then fireAtVictim(s)
                elseif now>=s.deadline then G.End(s,"Shot canceled: no clear alignment") end
            elseif s.deadline and now>=s.deadline then
                if s.phase=="entry" then s.heldKey=nil phase(s,"hold",C.holdA,C.holdV)
                elseif s.phase=="entry_reverse" then s.reversed=true G.End(s)
                elseif s.phase=="release" then G.End(s)
                elseif s.phase=="cuffing" then
                    local w=s.weapons[s.a]
                    -- Existing Tie owns item consumption, netvars and organism.handcuffed.
                    G.Committing=s
                    local ok,err=xpcall(function()
                        if cuffReady(s.a) then w:Tie({Entity=s.v}) end
                    end,debug.traceback)
                    G.Committing=nil G.Selecting=nil
                    if not ok then ErrorNoHalt("[ZCityHostage] "..tostring(err).."\n") end
                    local v=s.v G.End(s)
                    if ok and G.Cuffed(v) then solo(v,"kneel") end
                elseif s.phase=="posture_entry" then
                    phase(s,s.nextPosture,s.nextPosture=="lying" and C.lie or (G.Cuffed(s.a) and C.kneel or C.surrender))
                elseif s.phase=="stand_up" then
                    if G.Cuffed(s.a) then phase(s,"standing",C.standing) s.positions=nil
                    else G.End(s) end
                end
            elseif s.kind=="solo" and s.phase=="standing" then
                if not G.Cuffed(s.a) then G.End(s)
                else
                    local speed=s.a:GetVelocity():Length2D()
                    local backward=s.a:GetVelocity():Dot(s.a:EyeAngles():Forward())<0
                    local seq=speed>5 and ("zcg_hostage_handcuff_"..(speed>80 and "run_" or "walk_")..(backward and "back" or "forward")) or C.standing
                    if not s.poses[s.a] or s.poses[s.a].seq~=seq then pose(s,s.a,seq) end
                end
            end
        end
    end
end
hook.Add("Think","ZCityHostage.Sessions",function()
    local now=CurTime()
    if not next(G.Sessions) then return end
    local pending={}
    for _,s in pairs(G.Sessions) do pending[#pending+1]=s end
    for _,s in ipairs(pending) do
        -- B10: one failing session must not stall every other hold.
        local ok,err=xpcall(stepSession,debug.traceback,s,now)
        if not ok then
            ErrorNoHalt("[ZCityHostage] session "..tostring(s.id)..": "..tostring(err).."\n")
            cleanupCall("failed session",G.End,s,"Interaction interrupted")
        end
    end
end)
hook.Add("FinishMove","ZCityHostage.Anchors",function(p,mv)
    local s=G.ByPlayer[p]
    if s then I.GuardScaleMovement(p,mv) if s.done then return end end
    if s and s.motionV2 and s.phase=="hold" and s.a==p then
        local v2=G.V2(p)
        local drift=mv:GetOrigin():DistToSqr(s.anchor)
        if not validSession(s) or not holdGrip(s) or drift>(v2 and 96*96 or 32*32) then
            G.End(s,"Interaction interrupted") return
        end
        -- v2: a stale anchor re-anchors on the accepted origin instead of releasing.
        if v2 and drift>32*32 then s.anchor=mv:GetOrigin() s.positions[p]=s.anchor end
        -- Follow the accepted command origin now, not on the next Think.
        -- The captor's entity origin is still committed by engine movement.
        if reposition(s,0,mv:GetOrigin()) then
            s.commandMotion=(s.commandMotion or vector_origin)+s.motion
        end
        return
    end
    if s and s.positions and s.positions[p] and s.phase~="attempt" then mv:SetOrigin(s.positions[p]) mv:SetVelocity(Vector(0,0,0)) end
end)
hook.Add("PostEntityTakeDamage","ZCityHostage.Damage",function(p,dmg,took)
    local s=G.ByPlayer[p]
    if not took or not s or dmg:GetDamage()<=0 then return end
    if s.phase=="attempt" or s.phase=="handoff" or s.kind=="solo" or s.kind=="cuff" then G.End(s,"Interrupted by injury") return end
    if p==s.a then
        if CurTime()-(s.damageTime or 0)>0.5 then s.damage=0 end
        s.damageTime=CurTime() s.damage=(s.damage or 0)+dmg:GetDamage()
        if s.damage>=10 then G.End(s,"Grip broken by injury",true) end
    end
end)
for _,event in ipairs({"PlayerDeath","PlayerSpawn","PlayerDisconnected","Fake","Ragdoll_Create"}) do
    hook.Add(event,"ZCityHostage.SessionCleanup",function(p,ragdoll)
        if event=="PlayerSpawn" and OverrideSpawn then return end -- FakeUp's get-up Spawn is the same life
        local context=(event=="Fake" or event=="Ragdoll_Create") and {player=p,ragdoll=ragdoll} or nil
        G.End(G.ByPlayer[p],nil,nil,nil,context) input[p]=nil cooldown[p]=nil rates[p]=nil
        G.RecoverOrphan(p)
        if event=="PlayerDeath" or event=="PlayerSpawn" or event=="PlayerDisconnected" then grace[p]=nil postureUntil[p]=nil end
        if event=="PlayerDisconnected" then G.Ready[p]=nil end
    end)
end
local function stopAll(preserveSeparation)
    for _,s in pairs(G.Sessions) do G.End(s) end
    for _,p in ipairs(player.GetAll()) do G.RecoverOrphan(p) end
    if not preserveSeparation then
        local all={} for s in pairs(I.Collisions) do if s.system=="hostage" then all[#all+1]=s end end
        for _,s in ipairs(all) do I.ReleaseCollision(s,true) end
    end
end
G.Shutdown=stopAll
for _,event in ipairs({"ZB_EndRound","ZB_PreRoundStart","PreCleanupMap","ShutDown"}) do
    hook.Add(event,"ZCityHostage.ClearAll",function() stopAll(event~="PreCleanupMap" and event~="ShutDown") end)
end
cvars.AddChangeCallback("zch_gameplay_enabled",function(_,_,v) if tonumber(v)~=1 then stopAll(true) end end,"ZCityHostage.Disable")
concommand.Add("zch_ready",function(p,_,args)
    if IsValid(p) and p:IsPlayer() and args[1]==G.Version then
        local token=G.ReadyToken(p)
        G.Ready[p]=token
        if p:GetNWString("zch_ready_ack")~=token then p:SetNWString("zch_ready_ack",token) end
    end
end)
function G.RequestAction(p,action,arg,selected,equipment,heldKey)
    if not IsValid(p) or not p:IsPlayer() then return end
    if type(action)~="string" or #action>16 then return end
    if not enabled:GetBool() then return end
    if hg.SpecDM and (hg.SpecDM.Entity(p) or hg.SpecDM.Entity(selected)) then return false,"World interactions are unavailable in SpecDM" end
    local now=CurTime()
    if (rates[p] or 0)>now then return end
    rates[p]=now+0.1
    local s=G.ByPlayer[p]
    if action=="struggle" then
        if s and s.v==p then s.struggleUntil=arg=="1" and now+0.5 or 0 end
        return
    end
    if (cooldown[p] or 0)>now and not s then return end
    local ok,why
    if action=="release" or action=="stand" then ok,why=G.Release(p)
    elseif action=="grab" then ok,why=G.Begin(p,selected~=nil and selected or target(p,true),"hold",nil,heldKey)
    elseif action=="cuff" then ok,why=G.StartCuff(p,selected~=nil and selected or target(p))
    elseif action=="arrest" then ok,why=G.StartArrest(p,selected~=nil and selected or target(p))
    elseif action=="knife_hold" then ok,why=G.StartKnifeHandoff(p,equipment)
    elseif action=="wire_hold" then ok,why=G.StartWireHandoff(p,equipment)
    elseif action=="uncuff" or action=="unlock_self" then
        local w=p:GetActiveWeapon()
        if not IsValid(w) or w:GetClass()~="weapon_handcuffs_key" or not w.UnTie then ok,why=false,"Equip a cuff key"
        else ok,why=w:UnTie(action=="unlock_self" and p or selected) end
    elseif action=="surrender" or action=="kneel" then ok,why=solo(p,"kneel")
    elseif action=="lie" then ok,why=solo(p,"lie")
    elseif action=="execute" then
        local v=s and s.v or (selected~=nil and selected or target(p))
        if arg and arg~="" and (not IsValid(v) or tonumber(arg)~=v:EntIndex()) then ok,why=false,"Target changed; shot canceled"
        elseif selected~=nil and v~=selected then ok,why=false,"Target changed; shot canceled"
        else ok,why=G.Execution(p,selected) end
    elseif action=="order_kneel" or action=="order_lie" then
        local v=selected~=nil and selected or target(p)
        if not I.Available(p) or s or G.Cuffed(p) or not arms(p) then ok,why=false,"Free your hands before positioning someone"
        elseif not living(p) or not IsValid(v) or not v:IsPlayer() or v==p or p:GetPos():DistToSqr(v:GetPos())>G.Reach(p,v)^2 or not visible(p,v) then
            ok,why=false,"Get within clear reach"
        elseif not I.HostileAllowed(p,v,nil,"posture") then ok,why=false,"Control is not available now"
        elseif G.Cuffed(v) then ok,why=solo(v,action=="order_lie" and "lie" or "kneel",true)
        elseif (postureUntil[v] or 0)>now then ok,why=false,"Give them time to respond"
        else postureUntil[v]=now+5 say(v,p:Nick().." asks you to kneel. Hold Use while looking at empty space, then choose Surrender if you agree.") ok=true end
    else return end
    if not ok then say(p,why or "Unavailable") end
    return ok,why
end
concommand.Add("zch_action",function(p,_,args)
    G.RequestAction(p,args[1],args[2])
end)
include("zcity_hostage/sv_handoff.lua")
