ZCityStealthOwnerCapabilities=ZCityStealthOwnerCapabilities or {}
ZCityStealthOwnerCapabilities["zcity_hostage/sh_gameplay.lua"]="20260920.stealth3"
-- Shared contract. Server state is authoritative; clients only render and request actions.
local H = ZCityHostage
H.Gameplay = H.Gameplay or {}
local G = H.Gameplay
if SERVER then AddCSLuaFile("zcity_interactions/sh_core.lua") end
if not ZCityInteractions then include("zcity_interactions/sh_core.lua") end
G.Version = "20260920.5"
G.MotionRevision = "20260920.motion2"
G.AimRevision = "20260920.aim1"
G.HumanClasses={none=true,default=true,bloodz=true,groove=true,police=true,swat=true,nationalguard=true,commanderforces=true,terrorist=true,rebel=true,refuge=true,metrocop=true}
G.Data = include("zcity_hostage/sh_generated.lua")
G.Tuning = {range = 64, windup = 0.45, speed = 70, escape = 4, cuffEscape = 8, grace = 2, step = 18}
G.Tuning.escapeV2=7 -- PROVISIONAL(2026-09-25, escape time untuned, ratify-by: 2026-10-25)
G.Tuning.blockedV2=6 -- PROVISIONAL(2026-09-25, obstruction release delay untuned, ratify-by: 2026-10-25)
G.Pistols = {weapon_glock17=true, weapon_glock26=true, weapon_glock18c=true,
    weapon_makarov=true, weapon_m9beretta=true, weapon_px4beretta=true, weapon_hk_usp=true}
for name,profile in pairs(ZCityInteractions.WeaponProfiles) do
    if profile.kind=="pistol" or profile.kind=="revolver" then G.Pistols[name]=true end
end
function G.IsPistol(w)
    return ZCityInteractions.IsHandgun(w)
end
G.Clips = {
    rearA="zcg_paired_pistol_grabhostagefrombehind_start_att",
    rearV="zcg_paired_pistol_grabhostagefrombehind_start_vic",
    frontA="zcg_paired_pistol_grabhostagefromfront_start_att",
    frontV="zcg_paired_pistol_grabhostagefromfront_start_vic",
    holdA="zcg_paired_pistol_grabhostagefromfront_loop_att",
    holdV="zcg_paired_pistol_grabhostagefromfront_loop_vic",
    exitA="zcg_paired_pistol_grabhostagefromfront_end_att",
    exitV="zcg_paired_pistol_grabhostagefromfront_end_vic",
    cuffA="zcg_paired_handcuffhostage_start_att", cuffV="zcg_paired_handcuffhostage_start_vic",
    surrenderIn="zcg_idle_handsuphostage_kneel_start", surrender="zcg_idle_handsuphostage_kneel_loop",
    surrenderOut="zcg_idle_handsuphostage_kneel_end",
    kneelIn="zcg_idle_handcuffhostage_kneel_start", kneel="zcg_idle_handcuffhostage_kneel_loop",
    kneelOut="zcg_idle_handcuffhostage_kneel_end",
    kneelToLie="zcg_idle_handcuffhostage_kneel_to_layonfloor_transition",
    surrenderToCuffed="zcg_idle_handsuphostage_kneel_to_handscuffed_kneel_transition",
    uncuffGetUp="zcg_hostage_handscuffed_releasedgetup",
    lieIn="zcg_hostage_handscuffed_layonfloor_start", lie="zcg_hostage_handscuffed_layonfloor_loop",
    lieOut="zcg_hostage_handscuffed_layonfloor_end", standing="zcg_paired_handcuffhostage_loop_vic",
    executeA="zcg_paired_pistol_handsuphostage_kneel_headshotexecution_att"
}
function G.Role(p) return p:GetNWString("zch_role", "") end
-- US1 single-client test lock. v2 behaviour follows the session captor in both
-- realms: "*" = everyone, "" = nobody, else SteamID64s separated by commas/spaces.
G.V2Convar=CreateConVar("zch_v2_tester","76561198011536179",FCVAR_ARCHIVE+FCVAR_REPLICATED,"SteamID64s that get the v2 hostage hold (* = everyone)")
local v2List,v2Set
function G.V2Allowed(list,id)
    if list=="*" then return true end
    if type(id)~="string" or id=="" then return false end
    if list~=v2List then
        v2List,v2Set=list,{}
        for token in string.gmatch(list or "","[^,%s]+") do v2Set[token]=true end
    end
    return v2Set["*"] or v2Set[id] or false
end
function G.V2(p)
    return IsValid(p) and p:IsPlayer() and G.V2Allowed(G.V2Convar:GetString(),p:SteamID64()) or false
end
function G.EscapeSeconds(cuffed,v2)
    if cuffed then return G.Tuning.cuffEscape end
    return v2 and G.Tuning.escapeV2 or G.Tuning.escape
end
-- GetHull is the configured, unscaled movement hull. Source multiplies it by
-- GetModelScale for live player collision. Account for the extra body width
-- only while approaching; paired animations themselves run at scale 1.
local function extraBodyReach(p,direction)
    local scale=p:GetModelScale()
    if type(scale)~="number" or scale~=scale or scale<=1 or scale==math.huge then return 0 end
    local mins,maxs=p:GetHull()
    local x=math.max(math.abs(mins.x),math.abs(maxs.x))
    local y=math.max(math.abs(mins.y),math.abs(maxs.y))
    local dx,dy=math.abs(direction.x),math.abs(direction.y)
    local radius=math.min(dx>0.0001 and x/dx or math.huge,dy>0.0001 and y/dy or math.huge)
    return radius<math.huge and radius*(scale-1) or 0
end
function G.Reach(a,v)
    local d=v:GetPos()-a:GetPos() d.z=0 d:Normalize()
    return G.Tuning.range+extraBodyReach(a,d)+extraBodyReach(v,d)
end
function G.TraceReach(p)
    return 80+extraBodyReach(p,Angle(0,p:EyeAngles().y,0):Forward())
end
function G.ReadyToken(p) return G.Version .. ":" .. (p:GetModel() or "") end
-- The addon's own animation ownership. Addon code must use this, never
-- G.OwnsPose: the host consults G.OwnsPose to decide who places the gun.
function G.PoseOwned(p)
    if ZCityStealth and ZCityStealth.OwnsPose(p) then return true end
    local seq = p:GetNWString("zch_sequence", "")
    return seq ~= "" and p:GetNWString("hg_CustomAnim", "") == seq
end
-- v2 self-aim: while the host's suicide flag is up the host places the gun
-- (vecSuicidePist in PosAngChanges), runs TPIK for the right arm and fires
-- from its own bore. The body keeps the authored hold animation.
function G.HostOwnsGun(p)
    if G.Role(p)~="captor" or p:GetNWString("zch_phase")~="hold" or not G.V2(p) then return false end
    if SERVER then return p.suiciding==true end
    return p:GetNWBool("suiciding",false)
end
-- Host-facing: sh_worldmodel/sv_worldmodel (zchPose) and cl_tpik's early return.
function G.OwnsPose(p)
    return G.PoseOwned(p) and not G.HostOwnsGun(p)
end
-- Grab-entry progress (0..1) from the replicated phase clock, identical in both
-- realms. "entry_reverse" ends at zch_phase_end having spent exactly as long
-- as the entry had run, so (end-now)/duration retraces the same cycle to 0.
function G.EntryProgress(p, duration)
    local name=p:GetNWString("zch_phase")
    if name~="entry" and name~="entry_reverse" then return end
    local d=G.Data.clips[p:GetNWString("zch_sequence", "")]
    duration=duration or (d and d.duration)
    if not duration or duration<=0 then return end
    if name=="entry" then return math.Clamp((CurTime()-p:GetNWFloat("zch_phase_start"))/duration,0,1) end
    return math.Clamp((p:GetNWFloat("zch_phase_end")-CurTime())/duration,0,1)
end
function G.Cycle(p, elapsed, duration)
    if ZCityStealth and ZCityStealth.OwnsPose(p) then return ZCityStealth.Cycle(p) end
    local walking=p:GetNWString("zch_phase")=="hold" and string.find(p:GetNWString("zch_sequence"),"_walk",1,true)
    if CLIENT and not walking and G.ResetWalkCycle then G.ResetWalkCycle(p) end
    if not G.PoseOwned(p) then return end
    if p:GetNWString("zch_phase")=="entry_reverse" then return G.EntryProgress(p,duration) end
    local d = G.Data.clips[p:GetNWString("zch_sequence", "")]
    if not d or duration <= 0 then return end
    if walking then
        if CLIENT and G.RenderWalkCycle then
            local cycle=G.RenderWalkCycle(p)
            if cycle~=nil then return cycle end
        end
        return (p:GetNWFloat("zch_walk_cycle")+math.max(0,CurTime()-p:GetNWFloat("zch_walk_time"))*p:GetNWFloat("zch_walk_rate"))%1
    end
    return d.loop and (elapsed / duration) % 1 or math.Clamp(elapsed / duration, 0, 1)
end
function G.Cuffed(p) return ZCityInteractions.Cuffed(p) end
function G.Gender(p)
    -- Canonical ValveBiped proportions only; model/hand contact still needs client acceptance.
    local model = string.lower(p:GetModel() or "")
    return (string.find(model, "female", 1, true) or string.find(model, "/f/", 1, true)
        or string.find(model, "mossman", 1, true) or string.find(model, "alyx", 1, true)) and "female" or "male"
end
function G.CanUseCuffKey(p)
    local w=p:GetActiveWeapon()
    return G.Cuffed(p) and p:GetNWString("zch_kind")=="solo" and G.Role(p)=="restrained"
        and IsValid(w) and w:GetClass()=="weapon_handcuffs_key"
end
function G.BlockAttack(p)
    if ZCityStealth and ZCityStealth.Locked(p) then return true end
    local role = G.Role(p)
    if role == "" or role == "attempt" then return false end
    if SERVER and G.Firing == p then return false end
    if G.CanUseCuffKey(p) then return false end
    return role ~= "captor" or p:GetNWString("zch_phase") ~= "hold"
end
function G.BlockSwitch(p,newWeapon)
    if ZCityStealth and ZCityStealth.Locked(p) then return true end
    if SERVER and G.HandoffSwitchAllowed and G.HandoffSwitchAllowed(p,newWeapon) then return false end
    if G.Role(p)=="restrained" and IsValid(newWeapon) and p:GetNWString("zch_kind")=="solo"
        and (newWeapon:GetClass()=="weapon_handcuffs_key" or newWeapon:GetClass()=="weapon_hands_sh") then return false end
    return G.Role(p) ~= "" and G.Role(p) ~= "attempt" and not (SERVER and G.Selecting == p)
end
function G.WeaponPose(p, weapon, pos, ang)
    if not G.PoseOwned(p) or G.Role(p) ~= "captor" then return end
    -- Entry/release use the authored wrist. Established holds are adjusted at
    -- the world-model seam below, shared by rendering and native muzzle traces.
    return pos, ang
end

-- The owner publishes this per session only after the captor has loaded the
-- matching controller. Existing clients retain the previous movement contract.
function G.StableView(p)
    return G.Role(p)=="captor" and p:GetNWBool("zch_motion_v2",false) and G.PoseOwned(p)
end
function G.FreeAim(p)
    return G.StableView(p) and p:GetNWString("zch_phase")=="hold"
end
-- v2 captor view: pitch locks at 45 down; self-aim enters just before the lock
-- and leaves below 40, so resting on the lock never flickers the suicide pose.
G.PitchLock=45 G.SelfAimEnter=44.5 G.SelfAimExit=40
function G.ClampPitch(pitch)
    local n=(pitch+180)%360-180
    return n>G.PitchLock and G.PitchLock or pitch
end
function G.SelfAim(pitch,was)
    return pitch>=G.SelfAimEnter or (was==true and pitch>=G.SelfAimExit)
end
G.MoveInput = setmetatable({}, {__mode="k"})

hook.Add("StartCommand", "ZCityHostage.Input", function(p, cmd)
    local role = G.Role(p)
    if CLIENT and p==LocalPlayer() then G.UseInput={down=cmd:KeyDown(IN_USE),time=RealTime()} end
    if role == "" then return end
    -- Replaced for every user command, including prediction replays; no
    -- accumulated client position/yaw state survives a replay.
    G.MoveInput[p]={forward=cmd:GetForwardMove(),side=cmd:GetSideMove(),yaw=cmd:GetViewAngles().y}
    if SERVER and G.CaptureInput and G.CaptureInput(p, cmd) then cmd:RemoveKey(IN_RELOAD) end
    role=G.Role(p)
    if role=="" or role=="attempt" then return end
    cmd:RemoveKey(IN_JUMP)
    cmd:RemoveKey(IN_DUCK)
    cmd:RemoveKey(IN_SPEED)
    cmd:RemoveKey(IN_RELOAD)
    cmd:RemoveKey(IN_USE)
    if G.BlockAttack(p) then cmd:RemoveKey(IN_ATTACK) cmd:RemoveKey(IN_ATTACK2) end
    if not G.FreeAim(p) and (role ~= "restrained" or p:GetNWString("zch_phase") ~= "standing") then
        cmd:ClearMovement()
    end
    if role=="captor" and G.StableView(p) and G.V2(p) then
        local a=cmd:GetViewAngles()
        local pitch=G.ClampPitch(a.p)
        if pitch~=a.p then a.p=pitch cmd:SetViewAngles(a) end
    end
    -- View ownership lasts through entry/release/execution; movement and
    -- manual firing remain restricted to hold. R must not rotate the camera.
    if (role == "captor" or role == "victim") and not G.StableView(p) then
        local a = cmd:GetViewAngles()
        local yaw = p:GetNWFloat("zch_yaw", a.y)
        a.y = yaw + math.Clamp(math.AngleDifference(a.y, yaw), -50, 50)
        a.p = math.Clamp(a.p, -35, 35)
        cmd:SetViewAngles(a)
    end
end)
hook.Add("SetupMove", "ZCityHostage.MoveLimits", function(p, mv)
    local role = G.Role(p)
    if role == "" or role == "attempt" then return end
    if role == "restrained" and p:GetNWString("zch_phase") == "standing" then
        mv:SetMaxSpeed(math.min(mv:GetMaxSpeed(), 100))
        mv:SetMaxClientSpeed(math.min(mv:GetMaxClientSpeed(), 100))
    elseif not G.FreeAim(p) then
        mv:SetForwardSpeed(0) mv:SetSideSpeed(0) mv:SetUpSpeed(0)
        mv:SetVelocity(Vector(0, 0, 0))
    end
end)
-- Translation is simulated on both sides from the command's CMoveData
-- origin. Think must never teleport/pin the captor while this path owns it.
-- A flat hull sweep refuses every kerb and low ledge the engine would simply
-- step over, which made escorting a hostage across ordinary pavement edges
-- impossible. Mirror Source's step behaviour: if the level sweep is blocked,
-- retry it raised by the step height. groundSnap/the ground probe below then
-- settle the follower onto the new height. CLIENT and SERVER must evaluate
-- this identically -- it runs inside the predicted Move hook, and any
-- divergence shows up as rubberbanding.
function G.StepSweep(p,from,to,pair)
    local mins,maxs=ZCityInteractions.TravelHull(p)
    local tr=util.TraceHull({start=from,endpos=to,mins=mins,maxs=maxs,filter=pair,mask=MASK_PLAYERSOLID})
    if tr.StartSolid or tr.AllSolid then return false end
    if not tr.Hit then return true end
    local lift=Vector(0,0,G.Tuning.step)
    local up=util.TraceHull({start=from+lift,endpos=to+lift,mins=mins,maxs=maxs,filter=pair,mask=MASK_PLAYERSOLID})
    return not up.Hit and not up.StartSolid and not up.AllSolid
end
-- A front grab's victim clip is authored in the VICTIM's own starting frame:
-- its bones carry the 180-degree turn that ends with their back to the captor.
-- Publishing the captor's yaw for the victim during that entry applied the
-- rotation a second time, which read in game as the victim snapping to face
-- away and then rotating back to face the captor. Hold the victim on their
-- entry facing for the entry phases; the authored turn then lands exactly on
-- the captor's yaw as the hold loop takes over, so the handover is seamless.
-- Rear grabs are unaffected: the victim already faces the captor's direction.
function G.EntryYawOffset(p)
    if not IsValid(p) or G.Role(p)~="victim" then return 0 end
    if p:GetNWString("zch_kind")~="hold" or not p:GetNWBool("zch_front") then return 0 end
    local phase=p:GetNWString("zch_phase")
    if phase~="entry" and phase~="entry_reverse" then return 0 end
    return 180
end
-- v2 also stands on movers (doors, lifts: MOVETYPE_PUSH) and physics props.
function G.WalkableGround(tr,v2)
    if not tr.Hit or tr.StartSolid or tr.AllSolid or tr.HitNormal.z<=0.7 then return false end
    if tr.HitWorld then return true end
    local e=tr.Entity
    if not IsValid(e) then return false end
    local mt=e:GetMoveType()
    return mt==MOVETYPE_NONE or (v2==true and (mt==MOVETYPE_PUSH or mt==MOVETYPE_VPHYSICS)) or false
end
-- Second result: the ground height at `to`, so a v2 escort follows kerbs,
-- slopes and stairs instead of sinking into or hovering over them.
function G.ClearEscortPath(p,from,to,pair,v2)
    if not G.StepSweep(p,from,to,pair) then return false end
    local mins,maxs=ZCityInteractions.TravelHull(p)
    -- Search a full step in both directions so stepping up onto a kerb and
    -- dropping off one are both supported. A larger fall still has no ground
    -- here and is still refused.
    local step=G.Tuning.step
    local ground=util.TraceHull({start=to+Vector(0,0,step),endpos=to-Vector(0,0,step),
        mins=mins,maxs=maxs,filter=pair,mask=MASK_PLAYERSOLID})
    if not G.WalkableGround(ground,v2) then return false end
    return true,ground.HitPos.z
end
hook.Add("Move","ZCityHostage.PredictedEscort",function(p,mv)
    if not G.FreeAim(p) then return end
    local v=p:GetNWEntity("zch_partner")
    local i=G.MoveInput[p]
    mv:SetVelocity(vector_origin)
    if not IsValid(v) or not i or not p:OnGround() or not v:OnGround() then return true end
    local cap=p:GetNWFloat("zch_move_limit",0)
    if SERVER then cap=math.min(cap,G.EscortSpeed(p)) end
    local facing=Angle(0,i.yaw,0)
    local direction=facing:Forward()*math.Clamp(i.forward/200,-1,1)+facing:Right()*math.Clamp(i.side/200,-1,1)
    if direction:LengthSqr()>1 then direction:Normalize() end
    local velocity=direction*math.Clamp(cap,0,G.Tuning.speed)
    local start=mv:GetOrigin()
    local dest=start+velocity*FrameTime()
    local offset=p:GetNWVector("zch_offset",vector_origin)
    offset=Vector(offset.x,offset.y,0)
    offset:Rotate(Angle(0,p:GetNWFloat("zch_yaw"),0))
    local pair={p,v}
    local v2=G.V2(p)
    -- Use the same formation geometry on prediction and authority. Authority
    -- additionally sweeps the real follower, so it cannot be pulled through cover.
    -- v2: reposition() applies this same predicate (one rule, both paths).
    local clear,groundZ=G.ClearEscortPath(p,start,dest,pair,v2)
    if not clear or not G.ClearEscortPath(v,start+offset,dest+offset,pair,v2)
        or (SERVER and not G.ClearEscortPath(v,v:GetPos(),dest+offset,pair,v2)) then return true end
    if v2 and groundZ then dest.z=groundZ end -- `return true` skips the engine's step-up and gravity
    mv:SetOrigin(dest)
    mv:SetVelocity(velocity)
    return true -- this session owns movement; native movement must not run again.
end)
-- The follower's own client must predict the formation the server pins in
-- FinishMove. Predicting "stand still" produced a correction every snapshot,
-- which is the vibration both players saw.
if CLIENT then
    hook.Add("Move","ZCityHostage.PredictedFollower",function(p,mv)
        if G.Role(p)~="victim" or p:GetNWString("zch_phase")~="hold" then return end
        local a=p:GetNWEntity("zch_partner")
        if not IsValid(a) or not a:GetNWBool("zch_motion_v2",false) then return end
        local offset=a:GetNWVector("zch_offset",vector_origin)
        offset=Vector(offset.x,offset.y,0)
        offset:Rotate(Angle(0,p:GetNWFloat("zch_yaw"),0))
        local dest=a:GetPos()+offset
        if G.V2(a) then
            -- GetPos is the captor's interpolated origin (~100 ms old). The server
            -- pins us to where the captor is when it runs this command: the newest
            -- networked origin led by one round trip.
            -- PROVISIONAL(2026-09-25, follower lead is a ping heuristic, ratify-by: 2026-10-25)
            dest=a:GetNetworkOrigin()+a:GetVelocity()*math.Clamp(p:Ping()/1000,0,.25)+offset
        end
        dest.z=mv:GetOrigin().z -- height is owned by the server's ground snap
        mv:SetOrigin(dest)
        mv:SetVelocity(a:GetVelocity())
        return true
    end)
end

hook.Add("PlayerSwitchWeapon", "ZCityHostage.WeaponSwitch", function(p,oldWeapon,newWeapon)
    if G.BlockSwitch(p,newWeapon) then return true end
end)
hook.Add("PlayerUse", "ZCityHostage.Use", function(p)
    if G.Role(p) ~= "" and G.Role(p) ~= "attempt" then return false end
end)
hook.Add("CanPlayerEnterVehicle", "ZCityHostage.Vehicle", function(p)
    if G.Role(p) ~= "" then return false end
end)

-- Called at the existing world-model transform seam in both realms.
function G.ExecutionTarget(p)
    if p:GetNWString("zch_phase")~="execute" then return end
    local v=p:GetNWEntity("zch_partner")
    if not IsValid(v) or not v:Alive() then return end
    local b=v:LookupBone("ValveBiped.Bip01_Head1")
    local m=b and v:GetBoneMatrix(b)
    return m and m:GetTranslation()
end

local function headTarget(p)
    if not IsValid(p) or not p:Alive() then return end
    local bone=p:LookupBone("ValveBiped.Bip01_Head1")
    local matrix=bone and p:GetBoneMatrix(bone)
    return matrix and matrix:GetTranslation() or p:EyePos()
end
-- v2: the side of the hostage's head facing the gun, not its centre, so the
-- line of fire stays clear of the captor's gripping left forearm.
function G.TempleTarget(v,from)
    local head=headTarget(v)
    if not head then return end
    local right=Angle(0,v:GetNWFloat("zch_yaw",v:EyeAngles().y),0):Right()
    return head+right*((from-head):Dot(right)>=0 and 4 or -4)
end
-- v2 ADS: gun parallel to the view with its sight on the eye line, so the
-- host camera (SWEP:GetZoomPos) lands on the eye and the bore follows the view.
function G.SightOnEyeLine(p,w)
    local zoom=w.ZoomPos
    if not isvector(zoom) then return end
    local eye=p:EyePos()
    local aim=p:GetAimVector():Angle() aim.r=0
    local fwd=aim:Forward()
    local sight=LocalToWorld(zoom,angle_zero,vector_origin,aim)
    local rh=isvector(w.RHPos) and w.RHPos.x or 12
    local wp=isvector(w.WorldPos) and w.WorldPos.x or 0
    local pos=eye+fwd*math.Clamp(rh+wp,6,24)-(sight-fwd*sight:Dot(fwd))
    local aimM,muzzleM=Matrix(),Matrix()
    aimM:SetAngles(aim) muzzleM:SetAngles(w.LocalMuzzleAng or angle_zero)
    return pos,(aimM*muzzleM:GetInverse()):GetAngles()
end
function G.AimMode(p,w)
    if not G.FreeAim(p) then return end
    if not p:GetNWBool("zch_aim_v1",false) then return "ads" end
    -- Stateless in both realms: replaying a command cannot retain a previous
    -- aim mode. Looking almost straight down deliberately overrides ADS.
    local pitch=math.AngleDifference(p:EyeAngles().p,0)
    if G.V2(p) then
        -- The hysteresis memory is the host's replicated suicide flag.
        local was
        if SERVER then was=p.suiciding==true else was=p:GetNWBool("suiciding",false) end
        if G.SelfAim(pitch,was) then return "self" end
    elseif pitch>=80 then return "self" end
    return IsValid(w) and w.IsZoom and w:IsZoom() and "ads" or "hostage"
end
function G.HoldAimTarget(p,w,mode)
    if mode=="self" then return headTarget(p) end
    if mode=="hostage" then return headTarget(p:GetNWEntity("zch_partner")) end
    if mode~="ads" then return end
    local eye=p:EyePos()
    local endpoint=eye+p:GetAimVector()*8192
    -- The hostage and nearby cover remain real obstructions.
    local tr=util.TraceLine({start=eye,endpos=endpoint,filter={p,w,w.worldModel},mask=MASK_SHOT})
    return tr.HitPos or endpoint
end
function G.AdjustWeapon(p,w,pos,ang)
    w.ZCHAimHandPos=nil w.ZCHAimHandAng=nil
    local target=G.ExecutionTarget(p)
    local mode=G.AimMode(p,w)
    local v2=mode and G.V2(p)
    -- v2 self-aim before the host flag lands (or if hg.CanSuicide refuses): keep
    -- covering the hostage; G.OwnsPose hands the gun to the host once it is up.
    if v2 and mode=="self" then mode="hostage" end
    if v2 and mode=="hostage" then
        -- Authored hand (host bone-derived pos); only the muzzle turns.
        target=G.TempleTarget(p:GetNWEntity("zch_partner"),pos)
        if not target then return pos,ang end
    elseif v2 and mode=="ads" and isvector(w.ZoomPos) then
        local eye=p:EyePos()
        pos,ang=G.SightOnEyeLine(p,w)
        local clearance=util.TraceHull({start=eye,endpos=pos,mins=Vector(-2,-2,-2),maxs=Vector(2,2,2),
            filter={p,w,w.worldModel,p:GetNWEntity("zch_partner")},mask=MASK_SHOT})
        if clearance.Hit then pos=clearance.HitPos or eye end
        return pos,ang
    elseif mode then
        local eye=p:EyePos()
        target=G.HoldAimTarget(p,w,mode)
        if not target then return pos,ang end
        -- ADS retains the existing eye-relative position. Threat poses stay
        -- beside the body rather than orbiting with the free-look camera.
        local aim=mode=="ads" and p:GetAimVector():Angle() or Angle(0,p:GetNWFloat("zch_yaw"),0)
        local hand=eye+aim:Forward()*12+aim:Right()*9-aim:Up()*10
        local handAng=Angle(aim.p,aim.y,aim.r)
        handAng:RotateAroundAxis(handAng:Forward(),180)
        pos,ang=LocalToWorld(w.WorldPos or vector_origin,w.WorldAng or angle_zero,hand,handAng)
        ang:RotateAroundAxis(ang:Forward(),180)
        -- Do not place a muzzle/hand through a nearby wall. The normal shot
        -- trace still owns collision, spread, damage and ammunition.
        -- The partner must be filtered HERE. This trace only keeps the hand and
        -- muzzle out of nearby geometry; the hostage stands directly in front of
        -- the captor, so leaving them in clamped the weapon onto their body
        -- almost every frame and made ADS feel damped and unreliable. The aim
        -- TARGET trace above still treats the hostage as a real obstruction.
        local clearance=util.TraceHull({start=eye,endpos=pos,mins=Vector(-2,-2,-2),maxs=Vector(2,2,2),
            filter={p,w,w.worldModel,p:GetNWEntity("zch_partner")},mask=MASK_SHOT})
        if clearance.Hit then pos=clearance.HitPos or eye end
    end
    if not target or not G.PoseOwned(p) then return pos,ang end
    local muzzleLocal=w.LocalMuzzlePos or vector_origin
    local localRotation=Matrix()
    localRotation:SetAngles(w.LocalMuzzleAng or angle_zero)
    local inverse=localRotation:GetInverse()
    if mode and mode~="ads" then
        -- Solve the ray from the physical muzzle, including its local offset.
        -- Iterating toward a nearby head can oscillate around that offset.
        local forward=(w.LocalMuzzleAng or angle_zero):Forward()
        local along=muzzleLocal:Dot(forward)
        local discriminant=along*along+(target-pos):LengthSqr()-muzzleLocal:LengthSqr()
        local distance=discriminant>=0 and -along+math.sqrt(discriminant) or -1
        if distance>0 then
            local aim,reference=Matrix(),Matrix()
            aim:SetAngles((target-pos):Angle())
            reference:SetAngles((muzzleLocal+forward*distance):Angle())
            ang=(aim*reference:GetInverse()):GetAngles()
        end
    else
        -- Preserve the existing ADS/execution transform.
        for _=1,3 do
            local muzzle=LocalToWorld(muzzleLocal,angle_zero,pos,ang)
            local aim=Matrix()
            aim:SetAngles((target-muzzle):Angle())
            ang=(aim*inverse):GetAngles()
        end
    end
    if G.FreeAim(p) then
        local modelRotation=Matrix()
        local unflipped=Angle(ang.p,ang.y,ang.r)
        unflipped:RotateAroundAxis(unflipped:Forward(),180)
        modelRotation:SetAngles(unflipped)
        local localRotation=Matrix()
        localRotation:SetAngles(w.WorldAng or angle_zero)
        local handAng=(modelRotation*localRotation:GetInverse()):GetAngles()
        local offset=LocalToWorld(w.WorldPos or vector_origin,angle_zero,vector_origin,handAng)
        local handPos=pos-offset-handAng:Up()
        w.ZCHAimHandPos,w.ZCHAimHandAng=LocalToWorld(w.RHPosOffset or vector_origin,w.RHAngOffset or angle_zero,handPos,handAng)
    end
    return pos,ang
end

if CLIENT then
    G.PresentationRevision="20260920.presentation1"
    G.FollowRevision="20260920.follow1"
    G.GaitRevision="20260920.gait1"
    if G.StopFollowerRendering then G.StopFollowerRendering() end
    local yawStates=setmetatable({}, {__mode="k"})
    local viewStates=setmetatable({}, {__mode="k"})
    local walkStates=setmetatable({}, {__mode="k"})
    local function presentationPair(p)
        local a=G.Role(p)=="victim" and p:GetNWEntity("zch_partner") or p
        if not IsValid(a) or not G.StableView(a) then return end
        local v=a:GetNWEntity("zch_partner")
        local id=a:GetNWInt("zch_session")
        if not IsValid(v) or G.Role(v)~="victim" or not G.PoseOwned(v) or id==0
            or v:GetNWInt("zch_session")~=id or v:GetNWEntity("zch_partner")~=a then return end
        return a,v,id
    end
    function G.ResetPresentation(p)
        yawStates[p]=nil viewStates[p]=nil
        G.ResetWalkCycle(p)
    end
    function G.ResetWalkCycle(p)
        walkStates[p]=nil
        if G.Role(p)=="victim" then walkStates[p:GetNWEntity("zch_partner")]=nil end
    end
    function G.AdvanceWalkCycle(cycle,target,rate,dt)
        local advance=rate*dt
        local predicted=(cycle+advance)%1
        local error=(target-predicted+0.5)%1-0.5
        -- Correct phase by changing playback speed, never by reversing feet
        -- or jumping to a new packet's cycle. Zero speed stops immediately.
        return (predicted+math.Clamp(error*(1-math.exp(-dt/0.12)),-advance*0.5,advance*0.5))%1
    end
    function G.RenderWalkCycle(p)
        local a,v,id=presentationPair(p)
        if not a then G.ResetWalkCycle(p) return end
        for _,actor in ipairs({a,v}) do
            if actor:GetNWString("zch_phase")~="hold"
                or not string.find(actor:GetNWString("zch_sequence"),"_walk",1,true) then
                walkStates[a]=nil return
            end
        end
        local frame,now=FrameNumber(),CurTime()
        local rate=math.Clamp(a:GetNWFloat("zch_walk_rate"),0,1)
        local target=(a:GetNWFloat("zch_walk_cycle")+math.max(0,now-a:GetNWFloat("zch_walk_time"))*rate)%1
        local phaseStart=a:GetNWFloat("zch_phase_start")
        local s=walkStates[a]
        if not s or s.id~=id or s.partner~=v or s.phaseStart~=phaseStart
            or (s.frame~=frame and (now<s.time or now-s.time>0.25)) then
            s={id=id,partner=v,phaseStart=phaseStart,cycle=target,frame=frame,time=now}
            walkStates[a]=s
        elseif s.frame~=frame then
            s.cycle=G.AdvanceWalkCycle(s.cycle,target,rate,now-s.time)
            s.frame=frame s.time=now
        end
        -- One clock for both actors, including direction changes and multiple
        -- render passes. CurTime preserves game pause/timescale behavior.
        return s.cycle
    end
    function G.RenderYaw(p)
        local target=p:GetNWFloat("zch_yaw",p:EyeAngles().y)
        local a,v,id=presentationPair(p)
        if not a then yawStates[p]=nil return target end
        target=a:GetNWFloat("zch_yaw",target)
        local s=yawStates[a]
        local frame,now=FrameNumber(),RealTime()
        local phaseStart=a:GetNWFloat("zch_phase_start")
        if not s or s.id~=id or s.partner~=v or s.phaseStart~=phaseStart then
            s={id=id,partner=v,phaseStart=phaseStart,yaw=target,frame=frame,time=now}
            yawStates[a]=s
        elseif s.frame~=frame then
            local dt=math.Clamp(now-s.time,0,0.1)
            local delta=math.AngleDifference(target,s.yaw)
            s.yaw=target-math.Clamp(delta*math.exp(-dt/0.04),-8,8)
            s.frame=frame s.time=now
        end
        -- Both actors use exactly one sample per render frame. This never
        -- changes collision yaw, entity origins, hitboxes or command angles.
        -- The victim's entry offset rides outside the smoothing: it flips at a
        -- phase boundary where the pose changes with it, so nothing jumps.
        return s.yaw+G.EntryYawOffset(p)
    end
    function G.ViewOrigin(p,fallback)
    -- Stealth owns its own posed camera; this was a no-op stub returning the
    -- static eye position, which is why takedowns read as nothing happening.
    if ZCityStealth and ZCityStealth.OwnsPose(p) then
        if ZCityStealth.PoseViewOrigin then return ZCityStealth.PoseViewOrigin(p,p:EyePos()) end
        return p:EyePos()
    end
        if G.StableView(p) then viewStates[p]=nil return p:EyePos() end
        local a,v,id=presentationPair(p)
        if not a or p~=v or p~=LocalPlayer() then viewStates[p]=nil return fallback end
        local target=p:EyePos()
        local frame,now=FrameNumber(),RealTime()
        local s=viewStates[p]
        local phaseStart=p:GetNWFloat("zch_phase_start")
        if not s or s.id~=id or s.partner~=a or s.phaseStart~=phaseStart or target:DistToSqr(s.target)>24*24 then
            s={id=id,partner=a,phaseStart=phaseStart,pos=target,target=target,frame=frame,time=now}
            viewStates[p]=s
        elseif s.frame~=frame or target:DistToSqr(s.target)>0.0001 then
            local dt=math.Clamp(now-s.time,0,0.1)
            local pos=LerpVector(1-math.exp(-dt/0.035),s.pos,target)
            local offset=pos-target
            if offset:LengthSqr()>6*6 then pos=target+offset:GetNormalized()*6 end
            -- Camera-only correction: never interpolate the player through
            -- cover or let the camera lag far outside its authoritative body.
            local tr=util.TraceHull({start=target,endpos=pos,mins=Vector(-2,-2,-2),maxs=Vector(2,2,2),
                filter={a,v},mask=MASK_SOLID})
            if tr.StartSolid or tr.AllSolid then pos=target
            elseif tr.Hit then pos=tr.HitPos or target end
            s.pos=pos s.target=target s.frame=frame s.time=now
        end
        -- The native camera mutates its eye vector. Never give it our cache.
        return Vector(s.pos.x,s.pos.y,s.pos.z)
    end
    function G.FollowerDrawOffset(v)
        local a,partner=presentationPair(v)
        if not a or partner~=v or a~=LocalPlayer() or not G.FreeAim(a)
            or v:GetNWString("zch_phase")~="hold" or a:GetModelScale()~=1 or v:GetModelScale()~=1 then return end
        local offset=a:GetNWVector("zch_offset",vector_origin)
        offset=Vector(offset.x,offset.y,0)
        offset:Rotate(Angle(0,G.RenderYaw(a),0))
        local from=v:GetPos()
        local delta=a:GetPos()+offset-from
        if delta:LengthSqr()>32*32 then return end -- interruption/teleport, not normal network lag
        if delta:LengthSqr()>16*16 then delta=delta:GetNormalized()*16 end
        if not G.ClearEscortPath(v,from,from+delta,{a,v}) then return end
        return delta
    end
    local follower
    function G.ApplyFollowerBoneOffset(ent,count,offset)
        for bone=0,count-1 do
            local matrix=ent:GetBoneMatrix(bone)
            if matrix then
                matrix:SetTranslation(matrix:GetTranslation()+offset)
                ent:SetBoneMatrix(bone,matrix)
            end
        end
    end
    function G.StopFollowerRendering()
        local old=follower follower=nil
        if old and IsValid(old.entity) then
            old.entity:RemoveCallback("BuildBonePositions",old.callback)
            old.entity:InvalidateBoneCache()
        end
    end
    hook.Add("PreRender","ZCityHostage.FollowerContact",function()
        local a=LocalPlayer()
        local v=IsValid(a) and a:GetNWEntity("zch_partner") or NULL
        local delta=IsValid(v) and G.FollowerDrawOffset(v)
        if not delta then G.StopFollowerRendering() return end
        if follower and follower.entity~=v then G.StopFollowerRendering() end
        if not follower then
            local entry={entity=v}
            entry.callback=v:AddCallback("BuildBonePositions",function(ent,count)
                -- Bones are rebuilt from the real entity origin. Translate the
                -- full pose together; never override GetPos or movement state.
                if follower~=entry or entry.frame~=FrameNumber() or not G.FreeAim(LocalPlayer())
                    or LocalPlayer():GetNWEntity("zch_partner")~=ent or not G.PoseOwned(ent)
                    or ent:GetNWString("zch_phase")~="hold" then return end
                G.ApplyFollowerBoneOffset(ent,count,entry.offset)
            end)
            if not entry.callback then return end
            follower=entry
        end
        follower.offset=delta follower.frame=FrameNumber()
        v:InvalidateBoneCache()
    end)
    hook.Add("ShutDown","ZCityHostage.FollowerContact",function() G.StopFollowerRendering() end)
    function G.DrawAimArm(ent,p,w)
        if not G.FreeAim(p) or ent~=p or not IsValid(w) or not w.WorldModel_Transform then return end
        w:WorldModel_Transform(true)
        if not w.ZCHAimHandPos or not hg.DragRightHand_Ex or hg.ZCHRightArmSolver~=hg.DoTPIK then return end
        -- Vehicle-style hand placement and the native arm solver; the gripping
        -- left arm, torso and legs continue to come from the paired animation.
        p.rhold=nil
        hg.DragRightHand_Ex(ent,w,Vector(w.ZCHAimHandPos.x,w.ZCHAimHandPos.y,w.ZCHAimHandPos.z),w.ZCHAimHandAng)
        hg.DoTPIK(p,ent,true)
    end
    -- (a) Keep the local camera on the lock too; StartCommand alone clamps
    -- only the command, and the engine's view would drift past it.
    local function pitchLocked(p)
        return IsValid(p) and G.Role(p)=="captor" and G.StableView(p) and G.V2(p)
    end
    hook.Add("HG.InputMouseApply","ZCityHostage.PitchLock",function(tbl)
        if tbl.override_angle or not tbl.angle or not pitchLocked(LocalPlayer()) then return end
        if (tbl.angle.p+180)%360-180+(tbl.y or 0)/50>G.PitchLock then tbl.angle.p=G.PitchLock tbl.y=math.min(tbl.y or 0,0) end
    end)
    hook.Add("CreateMove","ZCityHostage.PitchLock",function(cmd)
        if not pitchLocked(LocalPlayer()) then return end
        local a=cmd:GetViewAngles()
        local pitch=G.ClampPitch(a.p)
        if pitch~=a.p then a.p=pitch cmd:SetViewAngles(a) end
    end)
    timer.Create("ZCityHostage.MotionReady",2,0,function()
        if not IsValid(LocalPlayer()) or util.NetworkStringToID("zch_motion_ready")==0 then return end
        if LocalPlayer():GetNWString("zch_motion_ack")==G.MotionRevision then return end
        net.Start("zch_motion_ready") net.WriteString(G.MotionRevision) net.SendToServer()
        -- A staged client can load before its server. Retry until the server
        -- acknowledges this exact revision; a send alone proves no readiness.
    end)
    timer.Create("ZCityHostage.AimReady",2,0,function()
        if not IsValid(LocalPlayer()) or util.NetworkStringToID("zch_aim_ready")==0 then return end
        if LocalPlayer():GetNWString("zch_aim_ack")==G.AimRevision then return end
        net.Start("zch_aim_ready") net.WriteString(G.AimRevision) net.SendToServer()
    end)
end

function G.SeamsReady()
    local caps=ZCityHostageOwnerCapabilities or {}
    local required=SERVER and {
        "homigrad/dynamic_anims_util/sv_util.lua", "weapons/homigrad_base/shared.lua",
        "weapons/homigrad_base/sv_worldmodel.lua", "weapons/weapon_handcuffs.lua", "weapons/weapon_handcuffs_key.lua",
        "homigrad/movement/sh_inertia.lua"
    } or {
        "homigrad/dynamic_anims_util/cl_util.lua", "homigrad/cl_tpik.lua",
        "weapons/homigrad_base/shared.lua", "weapons/homigrad_base/sh_worldmodel.lua"
    }
    for _,name in ipairs(required) do if caps[name]~=G.Version then return false end end
    return true
end

-- The aim-space blend (zcg_yaw/zcg_pitch, driving the AimSpace_AllDirections
-- sequences) was derived from raw view angles in EVERY mode. In hostage mode the
-- gun holds on the hostage's head while the body kept re-blending with each step
-- of camera pitch, so the pose never settled. Derive the blend from the
-- direction to the hostage instead, so the pose and the aim agree.
--
-- ADS deliberately keeps the view angles: its target lies along the view, so the
-- two already agree. Self aim keeps them too -- it only engages past 80 degrees
-- of downward pitch, where -a.p/35 is already saturated against the clamp, so
-- that pose is held by construction.
--
-- The reference is the partner's EyePos, NOT their animated head bone. The
-- VICTIM's pose parameters are set from this same angle and their head bone
-- moves with their pose, so feeding the bone back in would close a feedback
-- loop. The muzzle solve in G.AdjustWeapon still uses the precise head bone.
--
-- Both realms must compute this identically or the pose fights itself.
function G.AimPoseAngles(captor,fallback)
    if not IsValid(captor) then return fallback end
    local w=captor.GetActiveWeapon and captor:GetActiveWeapon()
    if G.AimMode(captor,w)~="hostage" then return fallback end
    local partner=captor:GetNWEntity("zch_partner")
    if not IsValid(partner) then return fallback end
    local delta=partner:EyePos()-captor:EyePos()
    if delta:LengthSqr()<1 then return fallback end
    return delta:Angle()
end
G.Rendered=G.Rendered or setmetatable({}, {__mode="k"})
local rendered=G.Rendered
hook.Add("UpdateAnimation","ZCityHostage.AimPose",function(p)
    if ZCityStealth and ZCityStealth.OwnsPose(p) then ZCityStealth.UpdateAnimation(p) return end
    if not G.PoseOwned(p) then
        if CLIENT and G.ResetPresentation then G.ResetPresentation(p) end
        if rendered[p] then p:SetPoseParameter("zcg_yaw",0) p:SetPoseParameter("zcg_pitch",0) rendered[p]=nil end
        return
    end
    rendered[p]=true
    local yaw=CLIENT and G.RenderYaw(p) or (p:GetNWFloat("zch_yaw",p:EyeAngles().y)+G.EntryYawOffset(p))
    p:SetRenderAngles(Angle(0,yaw,0))
    local a=p:EyeAngles()
    local captor=p
    if G.Role(p)=="victim" then
        local partner=p:GetNWEntity("zch_partner")
        if IsValid(partner) then captor=partner a=partner:EyeAngles() end
    end
    a=G.AimPoseAngles(captor,a)
    p:SetPoseParameter("zcg_yaw",math.Clamp(math.AngleDifference(a.y,yaw)/50,-1,1))
    p:SetPoseParameter("zcg_pitch",math.Clamp(-a.p/35,-1,1))
end)
