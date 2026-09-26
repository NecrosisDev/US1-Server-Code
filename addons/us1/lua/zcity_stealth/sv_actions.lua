local S=ZCityStealth
local contactSerial=0
local function ground(p,pos,filter)
    local lo,hi=p:GetHull()
    local tr=util.TraceHull({start=pos+Vector(0,0,3),endpos=pos-Vector(0,0,10),mins=lo,maxs=hi,filter=filter,mask=MASK_PLAYERSOLID})
    return tr.Hit and not tr.StartSolid and tr.HitNormal.z>.7 and (tr.HitWorld or (IsValid(tr.Entity) and tr.Entity:GetMoveType()==MOVETYPE_NONE))
end
function S.Preflight(s,name)
    local clip=S.Assets.clips[name] local pair=S.Assets.pairs[name]
    if not clip then return false end
    local facing=Angle(0,s.yaw,0)
    local initial=S.Sample(name,S.Gender(s.a),0) initial:Rotate(facing)
    local anchor=s.a:GetPos()-initial
    for _,p in ipairs(s.actors) do
        local n=p==s.a and name or pair and pair.victim
        if not n then return false end
        local offset=p==s.a and vector_origin or S.PairOffset(name,s.a,p)
        offset=Vector(offset.x,offset.y,offset.z) offset:Rotate(facing)
        local previous=p:GetPos()
        for frame=0,S.Assets.clips[n].frames-1 do
            local t=frame/S.Assets.clips[n].fps
            local v=S.Sample(n,S.Gender(p),t) v:Rotate(facing)
            local pos=anchor+offset+v
            if frame==0 and s.phase=="attempt" and s.action.above and p~=s.a and previous:DistToSqr(pos)>24*24 then return false end
            if p:IsPlayer() then
                if not S.PathClear(p,previous,pos,s.actors) then return false end
                if not s.action.above and not ground(p,pos,s.actors) then return false end
            else
                local tr=util.TraceHull({start=previous,endpos=pos,mins=Vector(-6,-6,0),maxs=Vector(6,6,12),filter=s.actors,mask=MASK_PLAYERSOLID})
                if tr.Hit or tr.StartSolid or tr.AllSolid then return false end
            end
            previous=pos
        end
        if p:IsPlayer() and not ground(p,previous,s.actors) then return false end
    end
    return true
end
local function bone(p,name)
    local id=p:LookupBone("ValveBiped.Bip01_"..name)
    local matrix=id and p:GetBoneMatrix(id)
    return matrix and matrix:GetTranslation()
end
local function damage(s,target,pos,amount,kind,attacker,contactFrom)
    if s.done or not IsValid(target) or not IsValid(s.a) or not IsValid(s.weapons[s.a]) then return end
    local info=DamageInfo()
    attacker=attacker or s.a
    info:SetAttacker(attacker) info:SetInflictor(s.weapons[attacker] or s.weapons[s.a]) info:SetDamage(amount)
    info:SetDamageType(kind) info:SetDamagePosition(pos)
    local direction=pos-(contactFrom or attacker:WorldSpaceCenter())
    if direction:LengthSqr()<.001 then return end
    info:SetDamageForce(direction:GetNormalized()*amount*20)
    -- Source copies DamageInfo userdata. DamageCustom survives that copy;
    -- stay below 2^24 because its native Lua binding loses larger integers.
    contactSerial=contactSerial%8388607+1
    local marker=8388608+contactSerial
    info:SetDamageCustom(marker)
    local previous,previousContact=S.Damaging,S.DamageContact
    S.Damaging=s S.DamageContact={session=s,target=target,marker=marker}
    local ok,err=xpcall(function()
      ZCityInteractions.WithObservedDamage(s,attacker,target,function()
        if s.action.weapon=="knife" then
            ZCityInteractions.WithKnifeProfile(s.weapons[s.a],function() target:TakeDamageInfo(info) end)
        else target:TakeDamageInfo(info) end
      end)
    end,debug.traceback)
    S.Damaging=previous S.DamageContact=previousContact
    if not ok then error(err) end
end
function S.Contact(s,dt)
    if s.done or s.awaitingBody or not IsValid(s.v) or (s.body and not s.originalVictim) or (s.phase~="entry" and s.phase~="finish") then return end
    local action=s.action
    if action.kind~="takedown" and s.phase~="finish" then return end
    local target=bone(s.v,"Neck1")
    if not target then return end
    local hand=bone(s.a,"R_Hand")
    if action.counter then hand=bone(s.v,"R_Hand") target=bone(s.a,"Head1") or target end
    if action.contact=="foot_head" then
        local left,right=bone(s.a,"L_Foot"),bone(s.a,"R_Foot")
        target=bone(s.v,"Head1") or target
        hand=left and right and (left:DistToSqr(target)<right:DistToSqr(target) and left or right) or right
    elseif action.contact=="torso_neck" and not s.hits[2] then target=bone(s.v,"Spine1") or target
    elseif action.contact=="torso" then target=bone(s.v,"Spine4") or target
    elseif action.contact=="leg_neck" and not s.hits[1] then target=bone(s.v,"R_Thigh") or target end
    if not hand then return end
    local distance=hand:Distance(target)
    local clear=util.TraceLine({start=hand,endpos=target,filter={s.a,s.weapons[s.a]},mask=MASK_SHOT})
    local radius=action.weapon=="knife" and 18 or 12
    local touching=distance<radius and (not clear.Hit or clear.Entity==s.v)
    if action.damage=="choke" then
        hand=bone(s.a,"L_Hand") or hand
        local elbow=bone(s.a,"L_Forearm")
        if elbow then
            local arm=hand-elbow
            local closest=elbow+arm*math.Clamp((target-elbow):Dot(arm)/math.max(arm:LengthSqr(),.001),0,1)
            local trace=util.TraceLine({start=closest,endpos=target,filter={s.a,s.weapons[s.a]},mask=MASK_SHOT})
            touching=closest:Distance(target)<12 and (not trace.Hit or trace.Entity==s.v)
        end
        local victim=IsValid(s.originalVictim) and s.originalVictim or s.v
        local org=victim.organism
        -- Native lungs consume/reset this input and own breathing, oxygen,
        -- collapse and recovery. Do not add a second oxygen drain or invent
        -- a scalar audit channel for org.o2's nested state.
        if touching and org then ZCityInteractions.ObserveChokeInput(s,org);org.choking=true end
        return
    end
    -- Contact is detected at the local minimum following an approaching
    -- strike. It must come from the actual evaluated pose, not a clip timer.
    local fresh=not s.contactTime or CurTime()-s.contactTime<=.1
    local old=fresh and s.contactDistance or nil
    old=old or distance
    local closing=old-distance
    -- A server tick can straddle the closest approach. Retain the previous
    -- verified contact for that one departing sample, never through a wall.
    local unobstructed=not clear.Hit or clear.Entity==s.v
    if not fresh or (action.contact~="head_floor" and (not unobstructed or distance>=radius+6)) then s.contactApproach=false end
    if fresh and old<radius and distance<radius+6 and s.contactApproach and closing<=.05 and unobstructed then touching=true end
    local hitCount=#s.hits
    if touching and closing>.05 then s.contactApproach=true end
    if action.contact=="head_floor" then
        local head=bone(s.v,"Head1")
        if head then
            local tr=util.TraceLine({start=head,endpos=head-Vector(0,0,8),filter=s.actors,mask=MASK_SOLID})
            touching=tr.Hit and tr.HitWorld
            target=head
            hand=head+Vector(0,0,8)
            closing=(s.lastHeadZ or head.z)-head.z
            if not touching then s.contactApproach=false end
            if closing>.1 then s.contactApproach=true end
        end
    end
    if touching and s.contactApproach and closing<=.05 and hitCount<(action.hits or 1) and CurTime()>(s.lastHit or 0)+.3 then
        s.hits[hitCount+1]=true s.lastHit=CurTime() s.contactApproach=false s.contactDistance=nil
        local w=s.weapons[s.a]
        local amount=action.weapon=="knife" and ZCityInteractions.KnifeDamage(w) or (action.knockout and 35 or 55)
        damage(s,action.counter and s.a or s.v,target,action.counter and 20 or amount,
            action.damage=="slash" and DMG_SLASH or DMG_CLUB,action.counter and s.v or s.a,hand)
        return
    end
    s.contactDistance=distance s.contactTime=CurTime()
    local head=bone(s.v,"Head1") if head then s.lastHeadZ=head.z end
end
function S.CounterAttempt(s)
    if s.action.kind~="takedown" or s.action.above or s.body or not IsValid(s.v) then return false end
    if not ZCityInteractions.HandsAvailable(s.v) then return false end
    local action={id="counter",label="Countered takedown",weapon="either",kind="takedown",counter=true,
        clip="Paired_H2H_Stealth_FailedAttack_Att",damage="blunt",contact="neck"}
    local old=s.action s.action=action
    if not S.Preflight(s,action.clip) then s.action=old return false end
    S.Commit(s)
    return not s.done
end
local function phase(s,name,mode,mobile,speed)
    if not S.Preflight(s,name) then S.End(s,"Path blocked") return false end
    return S.Phase(s,name,mode,mobile,speed)
end
function S.Release(s)
    if s.done then return false end
    if s.wireHandoff then S.End(s,"Weapon switch canceled") return true end
    if s.phase=="release" or s.phase=="settle" then return true end
    if s.phase=="attempt" then S.End(s,"Attempt canceled") return true end
    if s.action.release then
        return phase(s,s.action.release,"release")
    end
    S.End(s,"Action canceled") return true
end
function S.SessionAction(s,p,id,selected,equipment,dropItem)
    if s.done or S.ByActor[p]~=s then return false,"Interaction has ended" end
    if p~=s.a then
        if id=="resist" then s.resistUntil=CurTime()+.2 return true end
        return false,"Hold your Use key to resist"
    end
    local nextId=string.match(id,"^drop_then:(.+)$")
    if nextId then
        if not S.Actions[nextId] then return false,"Unknown follow-up action" end
        dropItem=dropItem or s.item
        local allowed,why=S.CanSoloHandoff(p,s,false,dropItem)
        if not allowed or not dropItem then return false,why or "No held object to drop" end
        id=nextId
    elseif dropItem then return false,"Choose an explicit drop-object action" end
    if id=="release" then return S.Release(s) end
    if s.wireHandoff then return false,"Finish the weapon switch first" end
    local permitted,why=ZCityInteractions.PolicyAllowed(p,s.policyIntent,s.originalVictim or s.v)
    if not permitted then return false,why end
    if s.phase~="loop" then return false,"Wait for this action to finish" end
    if id=="finish" and s.action.finish then return phase(s,s.action.finish,"finish") end
    if id=="throw" and s.action.throw then
        if s.body then
            local allowed,why=ZCityInteractions.PolicyAllowed(p,"throw",s.originalVictim or s.v)
            if not allowed then return false,why end
        end
        if not s.body then return false,"There is nothing to throw" end
        return phase(s,s.action.throw,"throw")
    end
    if id=="turn_left" or id=="turn_right" then
        local clip=s.action[id=="turn_left" and "left" or "right"] or s.action.turn
        if clip then
            s.turnYaw=s.yaw+(id=="turn_left" and 1 or -1)*90
            return phase(s,clip,"turn")
        end
    end
    return false,"That action is not available here"
end
local function locomotion(s,input,dt)
    local speed=s.a:GetVelocity():Length2D()
    local name=s.action.loop
    if s.action.kind=="body" then
        if s.action.id=="drag" then name=(input.forward or 0)<0 and s.action.variant or s.action.loop
        elseif speed>3 then
            local backwards=(input.forward or 0)<0
            name=s.action[backwards and "back" or "forward"]
            if speed>25 then name=name.."_RootM" end
            if input.sprint then name=s.action[backwards and "backFast" or "forwardFast"] or name end
        end
    end
    -- Locomotion has bounded per-tick sweeps below; a direction change is not
    -- a newly committed multi-second trajectory through future geometry.
    if name and name~=s.clip then S.Phase(s,name,"loop",true,s.action.speed or 70) end
    if s.done then return end
    local yaw=math.ApproachAngle(s.yaw,input.yaw or s.yaw,dt*180)
    s.yaw=yaw s.a:SetNWFloat("zsf_yaw",yaw)
    if not S.PathClear(s.a,s.a:GetPos(),s.a:GetPos(),s.actors) or not ground(s.a,s.a:GetPos(),s.actors) then
        S.End(s,"Movement blocked") return
    end
    if IsValid(s.v) then s.v:SetNWFloat("zsf_yaw",yaw) end
    local clip=S.Assets.clips[s.clip]
    if clip then
        local rate=1/clip.duration
        if string.find(s.clip,"Walk",1,true) or string.find(s.clip,"DraggingBody_Loop",1,true) then
            rate=speed>3 and math.Clamp(speed/(s.action.speed or 70),0,1.25)/clip.duration or 0
        end
        s.walkCycle=((s.walkCycle or 0)+dt*rate)%1
        if math.abs(rate-(s.clockRate or -1))>.015 or CurTime()-(s.clockSent or 0)>.5 then
            s.clockRate=rate s.clockSent=CurTime()
            local value=Vector(s.walkCycle,CurTime(),rate)
            for _,p in ipairs(s.actors) do p:SetNWVector("zsf_clock",value) end
        end
    end
    if clip and not clip.loop and CurTime()>=s.deadline then phase(s,s.action.loop,"loop",true,s.action.speed or 70) end
    if IsValid(s.v) then
        local offset=S.PairOffset(s.clip,s.a,s.v)
        if not offset then S.End(s,"Missing pair profile") return end
        offset:Rotate(Angle(0,s.yaw,0))
        local phaseTime=(S.Cycle(s.a) or 0)*S.Assets.clips[s.clip].duration
        local start=S.Sample(s.clip,S.Gender(s.a),phaseTime) start:Rotate(Angle(0,s.yaw,0))
        s.anchor=s.a:GetPos()-start s.vAnchor=s.anchor+offset
        s.v:SetNWVector("zsf_anchor",s.vAnchor)
        if s.v:IsPlayer() then
            local desired=S.PoseOrigin(s.v,CurTime())
            if not desired or not S.PathClear(s.v,s.v:GetPos(),desired,s.actors) or not ground(s.v,desired,s.actors) then S.End(s,"Follower blocked") return end
            s.v:SetPos(desired)
            s.positions[s.v]=desired
        end
    end
end
function S.UpdateResistance(s,dt)
    if not s.hostile or s.done then return end
    local p=IsValid(s.originalVictim) and s.originalVictim or s.v
    if not IsValid(p) or not p:IsPlayer() then return end
    local now=CurTime()
    local input=S.Input[p] or {}
    local active=(input.struggle and now-(input.time or 0)<.25) or (s.resistUntil or 0)>now
    local strength=S.ResistanceStrength(p)
    local seconds=1/.35
    -- Short clips must not require more resistance time than they last.
    -- The windup can earn progress; phase changes never erase it. This does
    -- not promise escape before the first physical contact or undo wounds.
    if s.action.kind=="takedown" or s.phase=="finish" then
        local clip=S.Assets.clips[s.clip or s.action.clip]
        if clip then seconds=math.Clamp(clip.duration*.65,.65,seconds) end
    end
    s.resist=math.Clamp((s.resist or 0)+dt*(active and strength>0 and strength/seconds or -.1),0,1)
    s.a:SetNWFloat("zsf_resist",s.resist) p:SetNWFloat("zsf_resist",s.resist)
    if s.resist>=1 then S.End(s,"Target broke free") end
end
function S.Tick(s)
    if s.reaction then S.TickReaction(s) return end
    if s.awaitingBody then
        local p=s.awaitingBody.player
        if IsValid(p) and IsValid(p.FakeRagdoll) then S.AdoptRagdoll(s,p,p.FakeRagdoll) end
        if s.done then return end
        if s.awaitingBody then
            -- Briefly wait for the native lifecycle event without further
            -- movement, contact damage or control of a disappearing player.
            local ok=IsValid(s.a) and s.a:Alive() and S.Armed(s.a,s.action)
                and s.a:GetActiveWeapon()==s.weapons[s.a]
                and not (s.a.organism and s.a.organism.otrub) and not IsValid(s.a.FakeRagdoll)
            if not ok or not S.Enabled:GetBool() or CurTime()>=s.awaitingBody.deadline then
                S.End(s,"Ragdoll transition interrupted")
            end
            return
        end
    end
    local valid,why=S.Valid(s)
    if not valid then S.End(s,why or "Interaction interrupted") return end
    ZCityInteractions.StepObservedControl(s)
    local now=CurTime() local dt=math.Clamp(now-(s.last or now),0,.1) s.last=now
    local input=S.Input[s.a] or {}
    if now-(input.time or 0)>.25 then input={} end
    if input.release and not s.wasRelease then S.Release(s) end
    s.wasRelease=input.release
    if s.done then return end
    if s.wireHandoff then S.StepSoloWireHandoff(s) return end
    if s.item and not S.DriveItem(s,dt) then S.End(s,"Held object obstructed") return end
    S.UpdateResistance(s,dt)
    if s.done then return end
    if s.phase=="attempt" then
        if IsValid(s.v) then
            if not S.InApproach(s.a,s.v,s.action) then S.End(s,"Target evaded the attempt") return end
            if not s.body and not s.action.above and not S.Rear(s.a,s.v) then
                if not S.CounterAttempt(s) then S.End(s,"Target evaded the attempt") end
                return
            end
        end
        if now>=s.deadline then S.Commit(s) end
        return
    end
    if s.phase=="loop" then locomotion(s,input,dt)
    else
        for _,p in ipairs(s.actors) do
            if p:IsPlayer() then
                local target=S.PoseOrigin(p,now)
                if not target or not S.PathClear(p,p:GetPos(),target,s.actors) then S.End(s,"Movement blocked") return end
                -- The local initiator follows the shared Move trajectory.
                -- A Think teleport would fight prediction and shake the camera.
                if p~=s.a then p:SetPos(target) s.positions[p]=target end
            end
        end
        S.Contact(s,dt)
    end
    if s.done then return end
    if s.body and not s.bodyReleased and not S.DriveBody(s,dt) then S.End(s,"Body movement obstructed") return end
    if s.phase=="throw" then S.UpdateThrow(s,dt) end
    if s.phase~="loop" and now>=s.deadline then
        if s.phase=="settle" or s.phase=="release" or s.phase=="finish" or s.action.kind=="takedown" or s.action.kind=="roll" then S.End(s)
        elseif s.phase=="throw" then
            S.End(s)
        elseif s.action.loop then
            if s.turnYaw then s.yaw=s.turnYaw s.turnYaw=nil end
            phase(s,s.action.loop,"loop",s.action.kind~="interrogate",s.action.speed or 0)
        else S.End(s) end
    end
end
