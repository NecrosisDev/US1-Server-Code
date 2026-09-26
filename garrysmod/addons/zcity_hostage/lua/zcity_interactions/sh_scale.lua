local I=ZCityInteractions
I.ScaleLeases=I.ScaleLeases or setmetatable({}, {__mode="k"})
local starts=setmetatable({}, {__mode="k"})
local function scale(value)
    return type(value)=="number" and value==value and value>0 and value<math.huge and value or 1
end
function I.TravelHull(p)
    local original=p:GetNWFloat("zci_original_scale",0)
    if SERVER and I.ScaleLeases[p] then original=I.ScaleLeases[p].original end
    local factor=math.max(1,scale(original),scale(p:GetModelScale()))
    local lo,hi=p:GetHull()
    return lo*factor,hi*factor
end
local function clear(p,from,to,filter,factor)
    local lo,hi
    if factor then lo,hi=p:GetHull() lo=lo*factor hi=hi*factor else lo,hi=I.TravelHull(p) end
    local trace=util.TraceHull({start=from,endpos=to,mins=lo,maxs=hi,filter=filter,mask=MASK_PLAYERSOLID})
    return not trace.Hit and not trace.StartSolid and not trace.AllSolid
end
I.ScalePathClear=clear
local function copy(pos) return Vector(pos.x,pos.y,pos.z) end
function I.RecordScalePosition(p,pos)
    local lease=SERVER and I.ScaleLeases[p]
    if not lease or lease.original<=1 then return end
    local history=lease.history
    if #history==0 or history[#history]:DistToSqr(pos)>=16*16 then
        history[#history+1]=copy(pos)
        if #history>8 then table.remove(history,1) end
    end
    lease.last=copy(pos)
end
hook.Add("SetupMove","ZCityInteractions.ScaleStart",function(p,mv)
    if p:GetNWFloat("zci_original_scale",0)>1 and p:GetModelScale()==1 then starts[p]=copy(mv:GetOrigin())
    else starts[p]=nil end
end)
function I.GuardScaleMovement(p,mv)
    local from=starts[p]
    if not from or p:GetModelScale()~=1 or p:GetNWFloat("zci_original_scale",0)<=1 then return end
    local lease=SERVER and I.ScaleLeases[p]
    local partner=p:GetNWEntity("zci_native_partner")
    local body=IsValid(partner) and partner:GetNWEntity("FakeRagdoll") or NULL
    local filter=lease and lease.actors or {p,p:GetNWEntity("zch_partner"),p:GetNWEntity("zsf_partner"),partner,body}
    local to=mv:GetOrigin()
    if not clear(p,from,to,filter) then
        mv:SetOrigin(from) mv:SetVelocity(vector_origin)
        if SERVER and not clear(p,from,from,filter) then
            local lease=I.ScaleLeases[p] local session=lease and lease.session
            if session and not session.done and session.cancel then
                session.cancel(session,"Full-size space became obstructed")
                mv:SetOrigin(p:GetPos()) -- retain a safe restoration move in the engine result
            end
        end
        return false
    end
    I.RecordScalePosition(p,to)
    return true
end
if CLIENT then
    hook.Add("FinishMove","ZCityInteractions.ScaleMovement",function(p,mv) I.GuardScaleMovement(p,mv) end)
    return
end
hook.Add("FinishMove","ZCityInteractions.NativeScaleMovement",function(p,mv)
    local lease=I.ScaleLeases[p] local s=lease and lease.session
    if s and (s.system=="disarm" or s.system=="fiberwire") then I.GuardScaleMovement(p,mv) end
end)
function I.BeginScale(s,p,original,actors)
    if not IsValid(p) or not p:IsPlayer() then return end
    local lease=I.ScaleLeases[p]
    if lease and lease.session==s then return end
    lease={session=s,original=scale(original),history={},model=p:GetModel(),actors=actors}
    I.ScaleLeases[p]=lease p:SetNWFloat("zci_original_scale",lease.original)
    if clear(p,p:GetPos(),p:GetPos(),actors) then I.RecordScalePosition(p,p:GetPos()) end
end
function I.TransferScale(old,new,p)
    local lease=I.ScaleLeases[p]
    if lease and lease.session==old then lease.session=new lease.actors=new.actors or new.participants end
end
local function supported(p,pos,filter,factor)
    local lo,hi=p:GetHull()
    local tr=util.TraceHull({start=pos+Vector(0,0,2),endpos=pos-Vector(0,0,8),mins=lo*factor,maxs=hi*factor,filter=filter,mask=MASK_PLAYERSOLID})
    return tr.Hit and not tr.StartSolid and not tr.AllSolid and tr.HitNormal.z>.7
        and (tr.HitWorld or (IsValid(tr.Entity) and tr.Entity:GetMoveType()==MOVETYPE_NONE))
end
local function restorePosition(p,lease,original)
    local pos=p:GetPos() local filter=lease.actors or {p}
    if original<=1 or not p:Alive() or IsValid(p.FakeRagdoll) or p:GetModel()~=lease.model then return true end
    if clear(p,pos,pos,filter,original) then return true end
    -- An external teleport owns position. Do not rewind it across the map.
    if not lease.last or lease.last:DistToSqr(pos)>128*128 then return false end
    local function try(candidate)
        if candidate:DistToSqr(pos)>128*128 or not clear(p,pos,candidate,filter,1)
            or not clear(p,candidate,candidate,filter,original) or not supported(p,candidate,filter,original) then return false end
        p:SetPos(candidate) return true
    end
    if try(lease.last) then return true end
    for index=#lease.history,1,-1 do if try(lease.history[index]) then return true end end
    -- Bounded local unsticking, with a swept normal-size route. Never cross
    -- a closed door/wall, change inventory, respawn, or keep a free small size.
    for _,distance in ipairs({32,64}) do
        for yaw=0,315,45 do
            if try(pos+Angle(0,yaw,0):Forward()*distance) then return true end
        end
    end
    return false
end
function I.EndScale(s,p,original)
    local lease=I.ScaleLeases[p]
    if lease and lease.session~=s then return end
    I.ScaleLeases[p]=nil starts[p]=nil
    if not IsValid(p) then return end
    p:SetNWFloat("zci_original_scale",0)
    if p:GetModelScale()~=1 then return end -- preserve a newer scale owner
    local placed=not lease or restorePosition(p,lease,original)
    if original~=1 then p:SetModelScale(original,0) end
    -- A map edit can remove every reachable full-size location. Restore the
    -- requested size anyway; native unsticking remains the movement owner's job.
    return placed
end
