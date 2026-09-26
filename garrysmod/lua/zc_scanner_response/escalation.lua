-- A patrol is the exact pair from one scanner, not a global Metropolice death count.
local S=assert(ZCityScannerResponse)
S.patrols=S.patrols or {}
S.memberPatrol=S.memberPatrol or {}
S.Rosters={
    [1]={{class="npc_metropolice",weapon="weapon_pistol",health=40},
         {class="npc_metropolice",weapon="weapon_pistol",health=40}},
    [2]={{class="npc_combine_s",model="models/combine_super_soldier.mdl",weapon="weapon_ar2",health=70,role="elite",skin=0},
         {class="npc_combine_s",model="models/combine_soldier.mdl",weapon="weapon_smg1",health=50,role="soldier",skin=0},
         {class="npc_combine_s",model="models/combine_soldier.mdl",weapon="weapon_shotgun",health=50,role="shotgunner",skin=1}}
}
function S.CancelPatrol(group)
    if not group or group.finished then return end
    group.finished=true
    for npc in pairs(group.members)do S.memberPatrol[npc]=nil end
    S.patrols[group.id]=nil
end
function S.TrackPatrol(job,made)
    if (job.stage or 1)~=1 or #made~=2 then return end
    local group={id=job.id,origin=Vector(job.origin),kind=job.kind,round=job.round,killed=0,members={}}
    S.patrols[group.id]=group
    for _,npc in ipairs(made)do group.members[npc]="alive";S.memberPatrol[npc]=group end
end
function S.ResponseKilled(npc)
    local group=S.memberPatrol[npc]
    if not group or group.finished or group.members[npc]~="alive" then return false end
    if not S.Active() or group.round~=S.Round() then S.CancelPatrol(group);return false end
    group.members[npc]="killed";group.killed=group.killed+1;S.responders[npc]=nil
    if group.killed<2 then return true end
    -- Consume the escalation before enqueueing; duplicate deaths can never retry it.
    S.CancelPatrol(group)
    if S.Enqueue(group.origin,group.kind,2,group.id) then
        S.stats.escalated=(S.stats.escalated or 0)+1
    end
    return true
end
hook.Add("EntityRemoved","ZCityScannerResponse_PatrolRemoved",function(npc)
    local group=S.memberPatrol[npc]
    if not group then return end
    if group.members[npc]=="alive" then S.CancelPatrol(group)
    else S.memberPatrol[npc]=nil end
end)
-- Never guess that a missing legacy officer was killed. Only adopt a complete
-- live pair whose recorded squad and original scene both remain identifiable.
function S.AdoptLegacyPair()
    local job=S.lastSpawn
    if not job or job.stage or job.round~=S.Round() or S.patrols[job.id] then return 0 end
    local made={}
    for npc in pairs(S.responders)do
        if IsValid(npc) and npc:Health()>0 and npc:GetClass()=="npc_metropolice"
            and npc:GetSquad()=="zc_scanner_response_"..job.id then made[#made+1]=npc end
    end
    if #made~=2 then return 0 end
    S.TrackPatrol(job,made);return 1
end
