local S=ZCityStealth
if not ZCityInteractions then include("zcity_interactions/sh_core.lua") end
S.Knives={}
for name,profile in pairs(ZCityInteractions.WeaponProfiles) do if profile.kind=="knife" then S.Knives[name]=true end end
function S.SeamsReady()
    local caps=ZCityStealthOwnerCapabilities or {}
    for _,path in ipairs({"zcity_hostage/sh_gameplay.lua","weapons/weapon_melee.lua","weapons/weapon_hands_sh.lua"}) do
        if caps[path]~=S.Version then return false end
    end
    local h=ZCityHostage and ZCityHostage.Gameplay
    return h and h.SeamsReady and h.SeamsReady() or false
end
function S.Gender(p)
    local model=string.lower(p:GetModel() or "")
    return (string.find(model,"female",1,true) or string.find(model,"/f/",1,true)
        or string.find(model,"mossman",1,true) or string.find(model,"alyx",1,true)) and "female" or "male"
end
function S.Mode(p) return p:GetNWString("zsf_mode","") end
function S.OwnsPose(p)
    local name=p:GetNWString("zsf_clip","")
    local clip=S.Assets.clips[name]
    return clip and p:GetNWString("hg_CustomAnim","")==clip.sequence or false
end
function S.Locked(p)
    local mode=S.Mode(p)
    return mode~="" and mode~="attempt"
end
function S.ResistanceStrength(p)
    local o=IsValid(p) and p.organism
    if not o or not p:IsPlayer() or not p:Alive() or o.otrub then return 0 end
    -- Bound hands cannot pry a grip open; usable legs still permit body
    -- struggling. These weights are gameplay tuning, not medical estimates.
    local strength=0
    for _,limb in ipairs({"larm","rarm","lleg","rleg"}) do
        local arm=limb=="larm" or limb=="rarm"
        if not o[limb.."amputated"] and (o[limb] or 0)<.99
            and not (arm and ZCityInteractions.Cuffed(p)) then strength=strength+.25 end
    end
    return strength
end
function S.WeaponKind(p,w)
    w=w or p:GetActiveWeapon()
    if not IsValid(w) then return end
    local class=w:GetClass()
    if class=="weapon_hands_sh" then return "hands" end
    if S.Knives[class] then return "knife" end
    if class=="weapon_zc_fiberwire_standalone" then return "wire" end
end
function S.WeaponMatches(action,kind)
    return kind and (action.weapon==kind or (action.weapon=="either" and (kind=="hands" or kind=="knife")))
end
function S.Sample(name,gender,elapsed)
    local clip=S.Assets.clips[name]
    local track=S.Assets.tracks[gender] and S.Assets.tracks[gender][name]
    if not clip or not track or #track==0 then return end
    local t=math.Clamp(elapsed,0,clip.duration)*clip.fps
    local i=math.min(math.floor(t)+1,#track)
    local j=math.min(i+1,#track)
    local a,b=track[i],track[j]
    return LerpVector(t-math.floor(t),Vector(a[1],a[2],a[3]),Vector(b[1],b[2],b[3]))
end
function S.Cycle(p)
    if not S.OwnsPose(p) then return end
    local clip=S.Assets.clips[p:GetNWString("zsf_clip")]
    local elapsed=math.max(0,CurTime()-p:GetNWFloat("zsf_start"))
    if clip.loop and p:GetNWString("zsf_mode")=="loop" then
        local owner=p:GetNWBool("zsf_initiator",false) and p or p:GetNWEntity("zsf_partner")
        if IsValid(owner) and owner:GetNWInt("zsf_id")==p:GetNWInt("zsf_id") then
            local clock=owner:GetNWVector("zsf_clock",Vector(0,CurTime(),0))
            local target=(clock.x+math.max(0,CurTime()-clock.y)*clock.z)%1
            if CLIENT and S.RenderCycle then return S.RenderCycle(owner,target,clock.z) end
            return target
        end
    end
    local rate=p:GetNWFloat("zsf_rate",1)
    return clip.loop and (elapsed*rate/clip.duration)%1 or math.Clamp(elapsed/clip.duration,0,1)
end
if CLIENT then
    local clocks=setmetatable({}, {__mode="k"})
    function S.RenderCycle(owner,target,rate)
        local id=owner:GetNWInt("zsf_id") local now,frame=CurTime(),FrameNumber()
        local state=clocks[owner]
        local start=owner:GetNWFloat("zsf_start")
        if not state or state.id~=id or state.start~=start or (frame~=state.frame and (now<state.time or now-state.time>.25)) then
            state={id=id,start=start,time=now,frame=frame,cycle=target} clocks[owner]=state
        elseif frame~=state.frame then
            local dt=now-state.time local advance=math.max(rate,0)*dt
            local cycle=(state.cycle+advance)%1 local error=(target-cycle+.5)%1-.5
            state.cycle=(cycle+math.Clamp(error*(1-math.exp(-dt/.12)),-advance*.5,advance*.5))%1
            state.time=now state.frame=frame
        end
        return state.cycle
    end
end
function S.PoseOrigin(p,time)
    local clip=p:GetNWString("zsf_clip")
    local elapsed=time-p:GetNWFloat("zsf_start")
    local data=S.Assets.clips[clip]
    if data and data.loop and S.Mode(p)=="loop" then elapsed=(S.Cycle(p) or elapsed/data.duration%1)*data.duration end
    local offset=S.Sample(clip,S.Gender(p),elapsed)
    if not offset then return end
    offset:Rotate(Angle(0,p:GetNWFloat("zsf_yaw"),0))
    local target=p:GetNWVector("zsf_anchor")+offset
    local duration=p:GetNWFloat("zsf_blend",.18)
    local blend=duration<=0 and 1 or math.Clamp((CurTime()-p:GetNWFloat("zsf_start"))/duration,0,1)
    return LerpVector(blend,p:GetNWVector("zsf_origin"),target)
end
function S.PathClear(p,from,to,filter)
    local lo,hi=ZCityInteractions.TravelHull(p)
    local tr=util.TraceHull({start=from,endpos=to,mins=lo,maxs=hi,filter=filter,mask=MASK_PLAYERSOLID})
    return not (tr.Hit or tr.StartSolid or tr.AllSolid)
end
function S.UpdateAnimation(p)
    if not S.OwnsPose(p) then return end
    p:SetRenderAngles(Angle(0,p:GetNWFloat("zsf_yaw",p:EyeAngles().y),0))
end
S.Input=setmetatable({}, {__mode="k"})
hook.Add("StartCommand","ZCityStealth.Controls",function(p,cmd)
    if S.Mode(p)=="" then return end
    S.Input[p]={forward=cmd:GetForwardMove(),side=cmd:GetSideMove(),yaw=cmd:GetViewAngles().y,
        struggle=cmd:KeyDown(IN_USE),release=cmd:KeyDown(IN_RELOAD),sprint=cmd:KeyDown(IN_SPEED),time=CurTime()}
    if not S.Locked(p) then return end
    for _,key in ipairs({IN_ATTACK,IN_ATTACK2,IN_JUMP,IN_DUCK,IN_SPEED,IN_USE,IN_RELOAD}) do cmd:RemoveKey(key) end
    if not p:GetNWBool("zsf_mobile",false) or p:GetNWBool("zsf_wire_switch",false) then cmd:ClearMovement() end
end)
hook.Add("SetupMove","ZCityStealth.Limits",function(p,mv)
    if not S.Locked(p) then return end
    local cap=p:GetNWFloat("zsf_speed",0)
    mv:SetMaxSpeed(math.min(mv:GetMaxSpeed(),cap)) mv:SetMaxClientSpeed(math.min(mv:GetMaxClientSpeed(),cap))
end)
hook.Add("Move","ZCityStealth.Trajectory",function(p,mv)
    if not S.Locked(p) or not S.OwnsPose(p) or p:GetNWBool("zsf_mobile",false) then return end
    local target=S.PoseOrigin(p,CurTime())
    mv:SetVelocity(vector_origin)
    if target and S.PathClear(p,mv:GetOrigin(),target,{p,p:GetNWEntity("zsf_partner")}) then mv:SetOrigin(target)
    elseif SERVER and S.ByActor and S.ByActor[p] then S.End(S.ByActor[p],"Movement blocked") end
    return true
end)
hook.Add("PlayerSwitchWeapon","ZCityStealth.WeaponLock",function(p,old,new)
    if SERVER and S.SoloWireSwitchAllowed and S.SoloWireSwitchAllowed(p,new) then return end
    if S.Locked(p) and S.Selecting~=p then return true end
end)
hook.Add("PlayerUse","ZCityStealth.UseLock",function(p) if S.Locked(p) then return false end end)
hook.Add("CanPlayerEnterVehicle","ZCityStealth.VehicleLock",function(p) if S.Mode(p)~="" then return false end end)
