if not SERVER then return end
local T=ZCityPoopThrow or {}
ZCityPoopThrow=T
T.Version="20260919.stick3"
T.TickInterval=0.05
T.StepRadius=18
T.StepHeight=18
T.StepScanInterval=0.1
T.ThrowSpeed=40
T.ThrowWindow=6
T.SmearCooldown=0.18
T.MinCollisionSpeed=8
T.MaxSmears=48
T.Squish="physics/flesh/flesh_squishy_impact_hard1.wav"
T.serial=T.serial or 0
T.ready=T.ready or setmetatable({},{__mode="k"})
T.stats=T.stats or {grabs=0,releases=0,throws=0,smears=0,client_ready=0,errors=0}
T.logged=T.logged or {}
T.grabPending=T.grabPending or setmetatable({},{__mode="k"})
AddCSLuaFile("autorun/client/zc_poop_smear.lua")
util.AddNetworkString("ZCPoopSmearV1")
util.AddNetworkString("ZCPoopSmearReadyV1")
local function C()return ZCityPoop end
local function isPoop(ent)
    local c=C()
    return c and c.owned and IsValid(ent) and c.owned[ent]
end
local function hands(p)
    if not IsValid(p) or not p:IsPlayer()then return end
    local w=p:GetActiveWeapon()
    if not IsValid(w) or w:GetClass()~="weapon_hands_sh"then return end
    return w
end
function T.Error(tag,err)
    T.stats.errors=T.stats.errors+1
    if T.logged[tag]then return end
    T.logged[tag]=true
    file.CreateDir("zc_poop")
    file.Append("zc_poop/throw_errors.txt",os.date("!%Y-%m-%dT%H:%M:%SZ").." "..tag.." "..tostring(err):sub(1,1000).."\n")
end
function T.SendClient()
    -- Client Lua is delivered by AddCSLuaFile on join, not live code injection.
    return false
end
net.Receive("ZCPoopSmearReadyV1",function(_,p)
    if not IsValid(p) or T.ready[p]then return end
    T.ready[p]=true
    T.stats.client_ready=T.stats.client_ready+1
end)
hook.Add("PlayerInitialSpawn","ZCityPoopThrow_Client",function(p)
    timer.Simple(5,function()T.SendClient(p)end)
end)
timer.Simple(1,function()
    for _,p in ipairs(player.GetAll())do T.SendClient(p)end
end)
function T.ActiveHolder(ent,roster)
    if roster then
        local row=roster.holders[ent]
        if row then return row[1],row[2] end
        return
    end
    for _,p in ipairs(player.GetAll())do
        local w=hands(p)
        if w and type(w.GetCarrying)=="function" and w:GetCarrying()==ent then
            return p,w
        end
    end
end
-- One current hands/feet snapshot per timer pass; no cross-tick cache.
function T.BuildRoster()
    local r={holders={},cells={},cellSize=math.max(1,T.StepRadius)}
    for _,p in ipairs(player.GetAll()) do
        local w=hands(p)
        if w and type(w.GetCarrying)=="function" then
            local ent=w:GetCarrying()
            if IsValid(ent) and not r.holders[ent] then r.holders[ent]={p,w} end
        end
        if IsValid(p) and p:Alive() and not p:InVehicle() and not IsValid(p.FakeRagdoll)
            and p:GetMoveType()~=MOVETYPE_NOCLIP and p:OnGround() then
            local pos=p:GetPos()
            local x,y=math.floor(pos.x/r.cellSize),math.floor(pos.y/r.cellSize)
            local column=r.cells[x];if not column then column={};r.cells[x]=column end
            local bucket=column[y];if not bucket then bucket={};column[y]=bucket end
            bucket[#bucket+1]={player=p,pos=pos}
        end
    end
    return r
end

function T.SetActivePhysics(ent,active)
    if not IsValid(ent)then return end
    local phys=ent:GetPhysicsObject()
    if not IsValid(phys)then return end
    if active then
        if not phys:IsMotionEnabled()then phys:EnableMotion(true)end
        ent:SetCollisionGroup(COLLISION_GROUP_NONE)
        phys:Wake()
    else
        ent:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
    end
end
function T.SendSmear(hit,pos,normal)
    T.serial=(T.serial+1)%4294967295
    if T.serial==0 then T.serial=1 end
    local world=not IsValid(hit) or hit:IsWorld()
    net.Start("ZCPoopSmearV1")
    net.WriteUInt(T.serial,32)
    net.WriteBool(world)
    if not world then net.WriteEntity(hit)end
    net.WriteVector(pos)
    net.WriteNormal(normal)
    net.Broadcast()
end
-- Cosmetic attachment state in the existing timer; never mutate physics in PhysicsCollide.
T.StickEpoch=(T.StickEpoch or 0)+1
T.StickGap=0.12
local function finiteVector(v)
    return isvector(v) and v.x==v.x and v.y==v.y and v.z==v.z
        and math.abs(v.x)<math.huge and math.abs(v.y)<math.huge and math.abs(v.z)<math.huge
end
function T.StickPose(contact,normal,mins,maxs,scale)
    local ang=normal:Angle()
    ang:RotateAroundAxis(ang:Right(),-90)
    local bottom=Vector((mins.x+maxs.x)*0.5,(mins.y+maxs.y)*0.5,mins.z)*scale
    local offset=LocalToWorld(bottom,angle_zero,vector_origin,ang)
    return contact+normal*T.StickGap-offset,ang
end
function T.DetachSticky(ent)
    if not IsValid(ent) then return end
    ent.ZCPoopStickPending=nil
    local s=ent.ZCPoopSticky
    if not s then return end
    ent.ZCPoopSticky=nil
    ent:SetCollisionGroup(s.group or COLLISION_GROUP_DEBRIS)
    local phys=ent:GetPhysicsObject()
    if IsValid(phys) then phys:EnableMotion(true);phys:Wake() end
    ent.ZCPoopThrownUntil=nil;ent.ZCPoopPickupArmedUntil=nil;ent.ZCPoopSettleSince=nil
end
function T.QueueStick(ent,data,now)
    if not isPoop(ent) or ent.ZCPoopSticky or ent.ZCPoopStickPending then return false end
    local last=IsValid(ent.ZCPoopHolder) and ent.ZCPoopHolder or ent.ZCPoopLastHolder
    if not ent.ZCPoopWasManipulated or not IsValid(last) then return false end
    if not IsValid(ent.ZCPoopHolder) and (ent.ZCPoopThrownUntil or 0)<=now then return false end
    if IsValid(T.ActiveHolder(ent)) then return false end
    local hit=data.HitEntity
    if not IsValid(hit) or hit==ent or isPoop(hit) then return false end
    local velocity=data.OurOldVelocity
    if not finiteVector(velocity) or velocity:LengthSqr()<T.ThrowSpeed*T.ThrowSpeed then return false end
    if not finiteVector(data.HitPos) or not finiteVector(data.HitNormal) or data.HitNormal:LengthSqr()<0.5 then return false end
    if (hit==last or hit==last.FakeRagdoll)
        and (ent.ZCPoopHolder~=nil or now<(ent.ZCPoopIgnoreHolderUntil or 0)) then return false end
    -- The contact normal faces out of our colliding surface; orient against approach.
    local normal=-data.HitNormal:GetNormalized()
    if normal:Dot(velocity)>0 then normal=-normal end
    local mins,maxs=ent:GetModelBounds()
    local pos,ang=T.StickPose(data.HitPos,normal,mins,maxs,ent:GetModelScale())
    local s={epoch=T.StickEpoch,creation=ent:GetCreationID(),target=hit,
        targetCreation=hit:GetCreationID(),world=hit:IsWorld(),pos=pos,ang=ang,expires=now+0.5}
    if not s.world then
        local object=data.HitObject
        if hit:GetPhysicsObjectCount()>1 and not IsValid(object) then return false end
        s.object=IsValid(object) and object or nil
        if s.object and s.object:GetEntity()~=hit then return false end
        local frame=s.object or hit
        s.localPos,s.localAng=WorldToLocal(pos,ang,frame:GetPos(),frame:GetAngles())
    end
    ent.ZCPoopStickPending=s
    return true
end
function T.StickTargetPose(s)
    if not IsValid(s.target) or s.target:GetCreationID()~=s.targetCreation then return end
    if s.world then return s.pos,s.ang end
    if s.object and (not IsValid(s.object) or s.object:GetEntity()~=s.target) then return end
    local frame=s.object or s.target
    return LocalToWorld(s.localPos,s.localAng,frame:GetPos(),frame:GetAngles())
end
function T.ApplyPendingStick(ent,now)
    local s=ent.ZCPoopStickPending
    if not s then return false end
    ent.ZCPoopStickPending=nil
    if s.epoch~=T.StickEpoch or s.creation~=ent:GetCreationID() or now>s.expires
        or IsValid(T.ActiveHolder(ent)) then return false end
    local pos,ang=T.StickTargetPose(s)
    local phys=ent:GetPhysicsObject()
    if not pos or not IsValid(phys) or not util.IsInWorld(pos) then return false end
    s.group=ent:GetCollisionGroup()
    ent.ZCPoopSticky=s
    local ok,err=pcall(function()
    -- Use the engine collision group, not EnableCollisions(false).
    ent:SetCollisionGroup(COLLISION_GROUP_WORLD)
    phys:SetVelocityInstantaneous(vector_origin)
    phys:SetAngleVelocityInstantaneous(vector_origin)
    phys:EnableMotion(false)
    ent:SetAngles(ang);ent:SetPos(pos)
    ent.ZCPoopHolder=nil;ent.ZCPoopThrownUntil=nil;ent.ZCPoopPickupArmedUntil=nil
    ent.ZCPoopSettleSince=nil
    T.UpdateCollisionFilter(ent,nil)
    s.lastPos=pos;s.lastAng=ang
    end)
    if not ok then T.DetachSticky(ent);T.Error("stick_apply",err);return false end
    T.stats.sticks=(T.stats.sticks or 0)+1
    return true
end
function T.UpdateSticky(ent)
    local s=ent.ZCPoopSticky
    if not s then return false end
    local pos,ang=T.StickTargetPose(s)
    if not pos or not util.IsInWorld(pos) then T.DetachSticky(ent);return false end
    if not s.world and (not s.lastPos or pos:DistToSqr(s.lastPos)>0.0001 or ang~=s.lastAng) then
        ent:SetAngles(ang);ent:SetPos(pos);s.lastPos=pos;s.lastAng=ang
    end
    return true
end

function T.OnCollide(ent,data)
    if not IsValid(ent) or not data then return end
    local now=CurTime()
    local queued=T.QueueStick(ent,data,now)
    local active=queued or IsValid(ent.ZCPoopHolder) or (ent.ZCPoopThrownUntil or 0)>now
    if not active or (data.Speed or 0)<T.MinCollisionSpeed then return end
    if now<(ent.ZCPoopNextSmear or 0) then return end
    if (ent.ZCPoopSmearCount or 0)>=T.MaxSmears then return end
    local hit=data.HitEntity
    if IsValid(ent.ZCPoopLastHolder) and hit==ent.ZCPoopLastHolder
        and now<(ent.ZCPoopIgnoreHolderUntil or 0)then return end
    ent.ZCPoopNextSmear=now+T.SmearCooldown
    ent.ZCPoopSmearCount=(ent.ZCPoopSmearCount or 0)+1
    T.stats.smears=T.stats.smears+1
    T.SendSmear(hit,data.HitPos,data.HitNormal)
    ent:EmitSound(T.Squish,60,math.random(92,108),0.75,CHAN_BODY)
end
function T.Attach(ent)
    if not isPoop(ent) or ent.ZCPoopThrowAttached then return end
    ent.ZCPoopThrowAttached=true
    ent:AddCallback("PhysicsCollide",function(e,data)
        local ok,err=pcall(T.OnCollide,e,data)
        if not ok then T.Error("collide",err)end
    end)
end
function T.FindGrabTarget(p,w)
    local Cfg=C()
    if not Cfg or type(Cfg.owned)~="table"then return end
    local pos
    if hg and type(hg.eye)=="function"then pos=select(1,hg.eye(p))end
    pos=pos or p:EyePos()
    local reach=tonumber(w.ReachDistance) or 40
    local dir=p:GetAimVector()
    local filter={p}
    if hg and type(hg.GetCurrentCharacter)=="function"then
        local body=hg.GetCurrentCharacter(p)
        if IsValid(body)then filter[#filter+1]=body end
    end
    local tr=util.TraceHull({
        start=pos,endpos=pos+dir*(reach+8),filter=filter,
        mins=Vector(-8,-8,-8),maxs=Vector(8,8,8),mask=MASK_SOLID
    })
    if isPoop(tr.Entity)then
        local point=tr.HitPos
        return tr.Entity,tr.PhysicsBone or 0,point,pos:Distance(point)
    end
    local best,bestPoint,bestScore
    local maxDist=reach+10
    for ent in pairs(Cfg.owned)do
        if IsValid(ent)then
            local point=ent:NearestPoint(pos)
            local delta=point-pos
            local dist=delta:Length()
            if dist<=maxDist and dist>0 then
                local dot=dir:Dot(delta/dist)
                if dot>=0.65 then
                    local los=util.TraceLine({
                        start=pos,endpos=ent:WorldSpaceCenter(),
                        mask=MASK_SOLID_BRUSHONLY
                    })
                    if not los.Hit then
                        local score=dist+(1-dot)*30
                        if not bestScore or score<bestScore then
                            best,bestPoint,bestScore=ent,point,score
                        end
                    end
                end
            end
        end
    end
    if IsValid(best)then return best,0,bestPoint,pos:Distance(bestPoint)end
end

function T.ArmGrab(p)
    if not IsValid(p) or not p:IsPlayer() or not p:Alive() or p:Team()>=1000
        or p:GetObserverMode()~=OBS_MODE_NONE or p:InVehicle() then return false end
    local org=p.organism
    if type(org)=="table" and (org.alive==false or org.otrub) then return false end
    local w=hands(p)
    if not w or (type(w.GetFists)=="function" and w:GetFists())then return false end
    if IsValid(p.FakeRagdoll) or type(w.SetCarrying)~="function"then return false end
    if type(w.GetCarrying)=="function" and IsValid(w:GetCarrying())then return false end
    local ent,bone,point,dist=T.FindGrabTarget(p,w)
    if not IsValid(ent)then return false end
    local holder=T.ActiveHolder(ent)
    if IsValid(holder) and holder~=p then return false end
    T.DetachSticky(ent)
    ent.ZCPoopPickupArmedUntil=CurTime()+0.75
    ent.ZCPoopWasManipulated=true
    T.SetActivePhysics(ent,true)
    w:SetCarrying(ent,bone or 0,point,dist)
    if type(w.GetCarrying)=="function" and w:GetCarrying()==ent then
        T.stats.nativegrabs=(T.stats.nativegrabs or 0)+1
        if type(w.ApplyForce)=="function"then pcall(w.ApplyForce,w)end
        return true
    end
    return false
end

hook.Add("KeyPress","ZCityPoopThrow_Arm",function(p,key)
    if key==IN_ATTACK2 then T.grabPending[p]=CurTime()+0.2 end
end)
hook.Add("ShouldCollide","ZCityPoopThrow_HolderCollision",function(a,b)
    local poop,other
    if isPoop(a)then poop,other=a,b elseif isPoop(b)then poop,other=b,a else return end
    -- This hook must only read cached rules: no clock-dependent decisions.
    if other==poop.ZCPoopIgnoreEntity or other==poop.ZCPoopIgnoreBody then return false end
end)
function T.UpdateCollisionFilter(ent,owner)
    owner=IsValid(owner) and owner or nil
    local body=owner and IsValid(owner.FakeRagdoll) and owner.FakeRagdoll or nil
    if ent.ZCPoopIgnoreEntity==owner and ent.ZCPoopIgnoreBody==body then return end
    ent.ZCPoopIgnoreEntity=owner
    ent.ZCPoopIgnoreBody=body
    -- Called from the timer, never from ShouldCollide or PhysicsCollide.
    ent:CollisionRulesChanged()
end
function T.CheckStepped(ent,now,roster)
    if now<(ent.ZCPoopNextStepScan or 0)then return end
    ent.ZCPoopNextStepScan=now+T.StepScanInterval
    local contacts=ent.ZCPoopStepContacts
    if not contacts then contacts=setmetatable({},{__mode="k"});ent.ZCPoopStepContacts=contacts end
    local pos=ent:GetPos();local r2=T.StepRadius*T.StepRadius;local seen={}
    roster=roster or T.BuildRoster()
    local gx,gy=math.floor(pos.x/roster.cellSize),math.floor(pos.y/roster.cellSize)
    for x=gx-1,gx+1 do
        local column=roster.cells[x]
        if column then for y=gy-1,gy+1 do
            local bucket=column[y]
            if bucket then for _,row in ipairs(bucket) do
                local p,pp=row.player,row.pos
                local dx,dy=pp.x-pos.x,pp.y-pos.y
                if IsValid(p) and dx*dx+dy*dy<=r2 and math.abs(pp.z-pos.z)<=T.StepHeight then
                    seen[p]=true
                    if not contacts[p] then
                        contacts[p]=true;T.stats.steps=(T.stats.steps or 0)+1
                        ent:EmitSound(T.Squish,58,math.random(94,106),0.7,CHAN_BODY)
                    end
                end
            end end
        end end
    end
    for p in pairs(contacts)do if not seen[p]then contacts[p]=nil end end
end

function T.Step(ent,now,roster)
    T.Attach(ent)
    local c=C()
    local scale=(c and c.Scale) or 0.75
    if ent:GetModelScale()~=scale then ent:SetModelScale(scale,0) end
    local holder=T.ActiveHolder(ent,roster)
    if IsValid(holder) then T.DetachSticky(ent)
    else
        T.ApplyPendingStick(ent,now)
        if T.UpdateSticky(ent) then return end
    end
    T.CheckStepped(ent,now,roster)
    local phys=ent:GetPhysicsObject()
    if not IsValid(phys)then return end
    if IsValid(holder)then
        if ent.ZCPoopHolder~=holder then
            ent.ZCPoopHolder=holder
            ent.ZCPoopLastHolder=holder
            ent.ZCPoopThrownUntil=nil
            ent.ZCPoopSettleSince=nil
            ent.ZCPoopWasManipulated=true
            T.stats.grabs=T.stats.grabs+1
        end
        T.UpdateCollisionFilter(ent,holder)
        T.SetActivePhysics(ent,true)
        return
    end
    if ent.ZCPoopHolder~=nil then
        local old=ent.ZCPoopHolder
        ent.ZCPoopHolder=nil
        ent.ZCPoopLastHolder=old
        ent.ZCPoopIgnoreHolderUntil=now+0.25
        ent.ZCPoopWasManipulated=true
        T.stats.releases=T.stats.releases+1
        local speed=phys:GetVelocity():Length()
        ent.ZCPoopThrownUntil=now+(speed>=T.ThrowSpeed and T.ThrowWindow or 1)
        if speed>=T.ThrowSpeed then T.stats.throws=T.stats.throws+1 end
    end
    T.UpdateCollisionFilter(ent,now<(ent.ZCPoopIgnoreHolderUntil or 0) and ent.ZCPoopLastHolder or nil)
    local active=(ent.ZCPoopPickupArmedUntil or 0)>now or (ent.ZCPoopThrownUntil or 0)>now
    if active then
        T.SetActivePhysics(ent,true)
        ent.ZCPoopSettleSince=nil
        return
    end
    ent:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
    if not ent.ZCPoopWasManipulated then return end
    local speed=phys:GetVelocity():Length()
    if speed<20 then
        ent.ZCPoopSettleSince=ent.ZCPoopSettleSince or now
        if now-ent.ZCPoopSettleSince>=0.6 and phys:IsMotionEnabled()then
            phys:EnableMotion(false)
        end
    else
        ent.ZCPoopSettleSince=nil
    end
end
function T.Tick()
    local c=C()
    if not c or type(c.owned)~="table"then return end
    local now=CurTime()
    for p,untilTime in pairs(T.grabPending)do
        if not IsValid(p) or untilTime<now or not p:KeyDown(IN_ATTACK2)then
            T.grabPending[p]=nil
        else
            local w=hands(p)
            local carrying=w and type(w.GetCarrying)=="function" and w:GetCarrying() or nil
            if IsValid(carrying)then
                T.grabPending[p]=nil
            else
                local ok,grabbed=pcall(T.ArmGrab,p)
                if not ok then T.Error("nativegrab",grabbed);T.grabPending[p]=nil
                elseif grabbed then T.grabPending[p]=nil end
            end
        end
    end
    if next(c.owned)==nil then return end
    local roster=T.BuildRoster()
    for ent in pairs(c.owned)do
        if IsValid(ent)then
            local ok,err=pcall(T.Step,ent,now,roster)
            if not ok then T.Error("step",err)end
        end
    end
end
timer.Create("ZCityPoopThrow_Tick",T.TickInterval,0,T.Tick)
hook.Add("PostCleanupMap","ZCityPoopThrow_Reset",function()
    T.serial=0;T.StickEpoch=T.StickEpoch+1
end)
hook.Add("ZB_EndRound","ZCityPoopThrow_StickReset",function() T.StickEpoch=T.StickEpoch+1 end)
