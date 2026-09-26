local S=ZCityStealth
if S.StopFollowerRendering then S.StopFollowerRendering() end
local follower
function S.StopFollowerRendering()
    local old=follower follower=nil
    if old and IsValid(old.entity) then
        old.entity:RemoveCallback("BuildBonePositions",old.callback)
        old.entity:InvalidateBoneCache()
    end
end
function S.FollowerOffset(a,v)
    if not IsValid(a) or not IsValid(v) or not v:IsPlayer() or not a:GetNWBool("zsf_initiator")
        or not S.OwnsPose(a) or not S.OwnsPose(v) or a:GetNWInt("zsf_id")==0
        or a:GetNWInt("zsf_id")~=v:GetNWInt("zsf_id") or v:GetNWEntity("zsf_partner")~=a
        or a:GetModelScale()~=1 or v:GetModelScale()~=1 then return end
    local target=S.PoseOrigin(v,CurTime())
    if not target then return end
    local delta=target-v:GetPos()
    if delta:LengthSqr()>32*32 then return end
    if delta:LengthSqr()>16*16 then delta=delta:GetNormalized()*16 end
    if not S.PathClear(v,v:GetPos(),v:GetPos()+delta,{a,v}) then return end
    return delta
end
hook.Add("PreRender","ZCityStealth.Follower",function()
    local a=LocalPlayer()
    local v=IsValid(a) and a:GetNWEntity("zsf_partner") or NULL
    local delta=IsValid(v) and S.FollowerOffset(a,v)
    if not delta then S.StopFollowerRendering() return end
    if follower and follower.entity~=v then S.StopFollowerRendering() end
    if not follower then
        local entry={entity=v}
        entry.callback=v:AddCallback("BuildBonePositions",function(ent,count)
            if follower~=entry or entry.frame~=FrameNumber() or not S.OwnsPose(ent)
                or LocalPlayer():GetNWEntity("zsf_partner")~=ent then return end
            for bone=0,count-1 do
                local matrix=ent:GetBoneMatrix(bone)
                if matrix then matrix:SetTranslation(matrix:GetTranslation()+entry.offset) ent:SetBoneMatrix(bone,matrix) end
            end
        end)
        if not entry.callback then return end
        follower=entry
    end
    follower.offset=delta follower.frame=FrameNumber()
    v:InvalidateBoneCache()
end)
hook.Add("ShutDown","ZCityStealth.Follower",S.StopFollowerRendering)

-- First-person camera through every posed action, not just rolls. These clips
-- move the body hard -- a takedown throws you, an execution drops you to your
-- knees -- but the view sits at the entity's static eye position, so from the
-- inside almost nothing happens. Follow the animated head bone so the motion is
-- felt, and lean into a roll's tumble.
--
-- Weight is phase-aware. A one-shot clip (takedown, roll, entry) eases in and
-- out on a sine across its cycle, so the view leaves and returns to the
-- player's own camera without a pop. A held/looping clip (interrogation, carry,
-- drag) ramps in over the action's own blend time and then stays attached,
-- because a sine would visibly breathe once per loop.
--
-- Strength is per action KIND, so being thrown reads as violent while being
-- walked along as a hostage stays readable. BOTH actors get this: taking a
-- takedown from the inside is most of why it lands.
--
-- The head POSITION comes from the bone and is exact. A roll's lean is
-- synthesised from the clip cycle and the roll's axis rather than read off the
-- bone's angles, because ValveBiped bone axes are not world-oriented and
-- reading pitch/roll off them would be a guess about the rig.
--
-- This shapes the RENDERED view only. Command angles, the authoritative
-- zsf_yaw, hitboxes and collision are untouched.
local poseCam=CreateClientConVar("zsf_posecam","1",true,false,
    "First-person camera follow during posed stealth actions (0 off, 1 on)")
local poseStrength=CreateClientConVar("zsf_posecam_strength","1.0",true,false,
    "Overall strength of the posed-action camera follow, 0..1")
local rollLean=CreateClientConVar("zsf_rollcam_lean","0.7",true,false,
    "How far the roll camera leans into the tumble, 0..1")
local LEAN_DEGREES=70
-- PROVISIONAL(2026-09-21, per-kind strengths are a starting feel and have not
-- been judged rendered; ratify-by: 2026-10-21)
local strength={roll=1,takedown=1,interrogate=.55,body=.5,wire=.6,native=.5}
local leanAxis={forward={1,0},back={-1,0},right={0,1},left={0,-1}}
local function poseWeight(p)
    local blend=math.max(p:GetNWFloat("zsf_blend",.18),.01)
    if S.Mode(p)=="loop" then
        return math.Clamp((CurTime()-p:GetNWFloat("zsf_start"))/blend,0,1)
    end
    local cycle=S.Cycle(p)
    if not cycle then return 0 end
    return math.sin(math.pi*math.Clamp(cycle,0,1))
end
function S.PoseView(p,view)
    if not poseCam:GetBool() or not IsValid(p) or not S.OwnsPose(p) then return end
    local id=p:GetNWString("zsf_action","")
    local action=S.Actions and S.Actions[id]
    if not action then return end
    local scale=strength[action.kind]
    if not scale then return end
    scale=scale*math.Clamp(poseStrength:GetFloat(),0,1)
    if scale<=0 then return end
    local weight=poseWeight(p)*scale
    if weight<=0 then return end
    -- LookupBone returns NO value on a miss and non-ValveBiped playermodels
    -- exist; hoist and guard before touching any matrix.
    local bone=p:LookupBone("ValveBiped.Bip01_Head1")
    if not bone then return end
    local matrix=p:GetBoneMatrix(bone)
    if not matrix then return end
    view.origin=LerpVector(weight,view.origin,matrix:GetTranslation())
    if action.kind=="roll" then
        local lean=leanAxis[string.sub(id,6)]
        local degrees=lean and weight*LEAN_DEGREES*math.Clamp(rollLean:GetFloat(),0,1)
        if lean and degrees>0 then
            view.angles=Angle(view.angles.p+degrees*lean[1],view.angles.y,view.angles.r+degrees*lean[2])
        end
    end
    return view
end
-- The gamemode already owns a sanctioned camera seam: homigrad/cl_camera.lua
-- calls ZCityHostage.Gameplay.ViewOrigin(ply,eyePos) and uses what it returns,
-- and that function already defers to this addon for stealth poses. That seam
-- is the correct home for a pose-driven view, so expose an origin function for
-- it rather than registering a competing CalcView hook: CalcView short-circuits
-- on the first non-nil return with undefined hook order, so a second hook would
-- win or lose at random and, when it won, would discard the owner's entire
-- camera (TPIK, ADS, sway).
--
-- LIMITATION: that seam carries the eye POSITION only. A roll's lean is an
-- ANGLE and cannot ride it, so the lean is not applied. Adding it needs an
-- angles bridge in cl_camera.lua, which is an owner-patch decision rather than
-- something to force through a hook that fights the camera owner.
function S.PoseViewOrigin(p,fallback)
    local view=S.PoseView(p,{origin=fallback,angles=angle_zero,fov=0})
    return view and view.origin or fallback
end
