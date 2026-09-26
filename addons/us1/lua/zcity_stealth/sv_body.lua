local S=ZCityStealth
local cache={}
local cacheOrder={}
local I=ZCityInteractions
S.CollisionLeases={owners=I.CollisionOwners,separations=I.Collisions}
function S.BodyAvailable(body,session,holder)
    if not IsValid(body) or not body:IsRagdoll() or not body:LookupBone("ValveBiped.Bip01_Pelvis") then return false end
    if S.ByActor[body] and S.ByActor[body]~=session then return false end
    if not I.Available(body,session) or body.StrangleLocked then return false end
    local owner=hg.RagdollOwner(body)
    if IsValid(owner) and not I.Available(owner,session) then return false end
    if IsValid(owner) and owner:Alive() and not (owner.organism and owner.organism.otrub)
        and not (session and session.originalVictim==owner and session.action.damage=="choke")
        and not (session and session.reaction and session.sourcePlayer==owner and S.IsPoisonCollapse(owner)) then return false end
    if body.welds and next(body.welds) then return false end
    if constraint.HasConstraints(body) then return false end
    for _,p in ipairs(player.GetAll()) do
        if p~=holder and (p:GetNetVar("carryent2")==body or p:GetNetVar("carryent")==body) then return false end
    end
    for i=0,body:GetPhysicsObjectCount()-1 do
        local phys=body:GetPhysicsObjectNum(i)
        if not IsValid(phys) or not phys:IsMotionEnabled() then return false end
    end
    return body:GetPhysicsObjectCount()>5
end
local function rig(name,gender)
    local clip=S.Assets.clips[name]
    if not clip then return end
    local key=gender.."_"..clip.sequence
    if cache[key] then return cache[key] end
    local raw=file.Read("zcity_stealth/rigs/"..key..".json","LUA")
    local data=raw and util.JSONToTable(raw)
    if not istable(data) or #data~=clip.frames then return end
    cache[key]=data cacheOrder[#cacheOrder+1]=key
    if #cacheOrder>12 then cache[table.remove(cacheOrder,1)]=nil end
    return data
end
local function rotation(row)
    local w,x,y,z=row[4],row[5],row[6],row[7]
    return Angle(math.deg(math.asin(math.Clamp(2*(w*y-z*x),-1,1))),
        math.deg(math.atan2(2*(w*z+x*y),1-2*(y*y+z*z))),
        math.deg(math.atan2(2*(w*x+y*z),1-2*(x*x+y*y))))
end
function S.BonePose(name,gender,bone,elapsed)
    local data=rig(name,gender) local clip=S.Assets.clips[name]
    if not data or not clip then return end
    local frame=math.Clamp(elapsed,0,clip.duration)*clip.fps
    local i=math.min(math.floor(frame)+1,#data) local j=math.min(i+1,#data)
    local a,b=data[i][bone],data[j][bone]
    if not a or not b then return end
    local alpha=frame-math.floor(frame)
    return LerpVector(alpha,Vector(a[1],a[2],a[3]),Vector(b[1],b[2],b[3])),LerpAngle(alpha,rotation(a),rotation(b))
end
function S.AcquireBody(s)
    local body=s.v
    if not S.BodyAvailable(body,s) then return false end
    s.bodyPhysics={}
    for i=0,body:GetPhysicsObjectCount()-1 do
        local phys=body:GetPhysicsObjectNum(i)
        local bone=body:TranslatePhysBoneToBone(i)
        local matrix=bone and body:GetBoneMatrix(bone)
        if not IsValid(phys) or not matrix then return false end
        local name=body:GetBoneName(bone)
        local pos,ang=WorldToLocal(phys:GetPos(),phys:GetAngles(),matrix:GetTranslation(),matrix:GetAngles())
        s.bodyPhysics[#s.bodyPhysics+1]={phys=phys,bone=name,pos=pos,ang=ang}
    end
    return #s.bodyPhysics>5
end
function S.ReleaseBody(s)
    -- Shadow control expires without another update. Do not restore obsolete
    -- body positions, resurrect players, replace corpses or modify inventory.
    if not s.bodyPhysics then return end
    for _,part in ipairs(s.bodyPhysics) do if IsValid(part.phys) then part.phys:Wake() end end
    s.bodyPhysics=nil
end
function S.DriveBody(s,dt)
    if not s.bodyPhysics then return false end
    local name=s.v:GetNWString("zsf_clip") local clip=S.Assets.clips[name]
    if not clip then return false end
    local elapsed=math.max(0,CurTime()-s.start)
    if clip.loop then elapsed=(S.Cycle(s.a) or (elapsed/clip.duration)%1)*clip.duration end
    local root=S.PoseOrigin(s.v,s.start+elapsed)
    if not root then return false end
    local targets={}
    for _,part in ipairs(s.bodyPhysics) do
        if not IsValid(part.phys) then return false end
        local pos,ang=S.BonePose(name,S.Gender(s.v),part.bone,elapsed)
        if not pos then return false end
        pos,ang=LocalToWorld(pos,ang,root,Angle(0,s.yaw,0))
        pos,ang=LocalToWorld(part.pos,part.ang,pos,ang)
        -- Physics pivots can lie outside the convex body (notably feet).
        -- Sweep the mass center, then convert the correction back to its pivot.
        local mass=part.phys:GetMassCenter()
        local from=part.phys:LocalToWorld(mass)
        local center=LocalToWorld(mass,angle_zero,pos,ang)
        local centerOffset=center-pos
        pos=center
        local sweep={start=from,endpos=pos,mins=Vector(-2,-2,-2),maxs=Vector(2,2,2),filter=s.actors,mask=MASK_PLAYERSOLID}
        local tr=util.TraceHull(sweep)
        if tr.StartSolid and not tr.AllSolid then
            -- Foot physics pivots can rest less than two units above the
            -- floor although their actual collision shape is not embedded.
            local floor=util.TraceLine({start=from+Vector(0,0,6),endpos=from-Vector(0,0,3),filter=s.actors,mask=MASK_PLAYERSOLID})
            if floor.HitWorld and not floor.StartSolid and floor.HitNormal.z>.7 then
                local height=(from-floor.HitPos):Dot(floor.HitNormal)
                local clearing=(pos-floor.HitPos):Dot(floor.HitNormal)>=2.1
                if height<2.1 and (height>=0 or (height>=-4 and clearing)) then
                    sweep.start=from+floor.HitNormal*(2.1-height)
                    tr=util.TraceHull(sweep)
                end
            end
        end
        if tr.Hit or tr.StartSolid or tr.AllSolid then
            -- Authored floor contacts can place a joint just below the
            -- conservative two-unit sweep. Rest on that surface; walls,
            -- embedded starts and larger penetration still interrupt.
            local depth=tr.HitNormal:Dot(tr.HitPos-pos)
            if tr.HitWorld and not tr.StartSolid and not tr.AllSolid and tr.HitNormal.z>.7 and depth>=0 and depth<=4 then
                pos=pos+tr.HitNormal*(depth+.1)
                sweep.endpos=pos
                local slide=util.TraceHull(sweep)
                if slide.Hit or slide.StartSolid or slide.AllSolid then return false end
            else
                s.blockage={bone=part.bone,time=elapsed,from=from,target=pos,hit=tr.HitPos,normal=tr.HitNormal,startSolid=tr.StartSolid,allSolid=tr.AllSolid}
                return false
            end
        end
        targets[#targets+1]={part=part,pos=pos-centerOffset,ang=ang}
    end
    for _,t in ipairs(targets) do
        t.part.phys:ComputeShadowControl({secondstoarrive=.04,pos=t.pos,angle=t.ang,maxangular=800,maxangulardamp=1000,
            maxspeed=400,maxspeeddamp=800,dampfactor=.8,teleportdistance=0,deltatime=dt})
        t.part.phys:Wake()
    end
    return true
end
function S.AcquireCollision(s)
    if not IsValid(s.v) then return end
    s.collision=true
    I.AcquireCollision(s,s.actors,s.a,s.v)
end
function S.ReleaseCollision(s)
    I.ReleaseCollision(s)
end
-- Native fake movement also drives bones, even for a conscious choking
-- victim. Only one owner may apply physics while the authored body is held.
hook.Add("CanControlFake","ZCityStealth.BodyDriver",function(p,body)
    body=IsValid(body) and body or p.FakeRagdoll
    local s=IsValid(body) and S.ByActor[body]
    if s and not s.done and s.bodyPhysics and not s.bodyReleased then return false end
end)
-- Eligibility hooks must not mutate a carry before another owner can veto.
hook.Add("Fake Up","ZCityStealth.Carried",function(p,body)
    body=IsValid(body) and body or p.FakeRagdoll
    local s=IsValid(body) and S.ByActor[body]
    if s then S.End(s,"The carried player stood up") end
end)
