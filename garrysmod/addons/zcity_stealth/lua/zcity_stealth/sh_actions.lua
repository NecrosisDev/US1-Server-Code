-- Every source clip has a gameplay role. Variants belong to one action rather
-- than exposing raw sequence names or client-supplied damage/positions.
local actions={}
local function add(id,label,clip,weapon,kind,extra)
    local a=extra or {}
    a.id=id a.label=label a.clip=clip a.weapon=weapon a.kind=kind or "takedown"
    actions[id]=a
end
local function pair(id,label,stem,weapon,extra)
    add(id,label,"Paired_"..stem.."_Att",weapon,"takedown",extra)
end
pair("neck_stab","Neck stab","Knife_Stealth_NeckStab","knife",{damage="slash",contact="neck"})
pair("kidney_neck","Kidney and neck","Knife_Stealth_KidneyAndNeck","knife",{damage="slash",contact="torso_neck",hits=3})
pair("reverse_grip","Kidney and neck — reverse grip","Knife_GripVariant_Stealth_KidneyAndNeck","knife",{damage="slash",contact="torso_neck",hits=3})
pair("thigh_neck","Thigh and neck","Knife_Stealth_ThighAndNeckStab","knife",{damage="slash",contact="leg_neck",hits=2})
pair("clavicle","Downward stab","Knife_Stealth_ClavicleStabDown","knife",{damage="slash",contact="torso"})
pair("spin_stab","Turn and stab","Knife_Stealth_SpinStab","knife",{damage="slash",contact="torso"})
pair("flip_stab","Takedown and stab","Knife_Stealth_GrabFlipStab","knife",{damage="slash",contact="torso"})
pair("drop_stab","Stab from above","Knife_Stealth_FromAbove_Stab","knife",{damage="slash",contact="torso",above=true,variant="Paired_Knife_Stealth_FromAbove_Stab_Z_AxisInPlace_Att"})
pair("neck_break","Neck takedown","H2H_Stealth_NeckBreak","hands",{damage="crush",contact="neck",grip=true})
pair("chop","Neck chop","H2H_Stealth_KarateChopKO","hands",{damage="blunt",contact="neck",knockout=true})
pair("reverse_ddt","Reverse DDT","H2H_Stealth_ReverseDDT","hands",{damage="crush",contact="head_floor"})
pair("flip_stomp","Flip and head stomp","H2H_Stealth_GrabFlipHeadStomp","hands",{damage="crush",contact="foot_head"})
pair("drop_kick","Kick from above","H2H_Stealth_FromAbove_NeckKick","hands",{damage="crush",contact="foot_head",above=true,variant="Paired_H2H_Stealth_FromAbove_NeckKick_Z_AxisInPlace_Att"})
pair("sleeper","Sleeper hold","H2H_Stealth_SleeperChoke","hands",{damage="choke",contact="neck",knockout=true,grip=true})
pair("sleeper_fast","Quick sleeper hold","H2H_Stealth_SleeperChoke_Fast","hands",{damage="choke",contact="neck",knockout=true,grip=true})
add("fiberwire","Fiberwire hold",nil,"wire","wire")
add("disarm","Disarm",nil,"hands","native")
add("interrogate","Knife interrogation","Paired_Knife_Stealth_Interrogate_Start_Att","knife","interrogate",{
    loop="Paired_Knife_Stealth_Interrogate_Loop_Att",release="Paired_Knife_Stealth_Interrogate_EndRelease_Att",
    finish="Paired_Knife_Stealth_Interrogate_EndKill_Att",damage="slash",contact="neck"})
add("drag","Drag body","Paired_H2H_Stealth_DraggingBody_Start_Att","hands","body",{
    loop="Paired_H2H_Stealth_DraggingBody_LoopSmoother_Att",variant="Paired_H2H_Stealth_DraggingBody_Loop_Att",
    release="Paired_H2H_Stealth_DraggingBody_End_Att",speed=45})
add("carry","Carry body","Paired_Stealth_CarryBody_Start_Att","hands","body",{
    loop="Paired_Stealth_CarryBody_IdleLoop_Att",release="Paired_Stealth_CarryBody_End_Att",throw="Paired_Stealth_CarryBody_Throw_Att",
    forward="Paired_Stealth_CarryBody_WalkForward_Att",back="Paired_Stealth_CarryBody_WalkBack_Att",
    forwardFast="Paired_Stealth_CarryBody_WalkForwardFaster_Att_RootM",backFast="Paired_Stealth_CarryBody_WalkBackFaster_Att_RootM",
    left="Paired_Stealth_CarryBody_TurnLeft90_Att",right="Paired_Stealth_CarryBody_TurnRight90_Att",speed=65})
for _,dir in ipairs({"Forward","Back","Left","Right"}) do
    add("roll_"..string.lower(dir),"Roll "..string.lower(dir),"H2H_Stealth_Roll"..dir,"either","roll",{stamina=22})
end
return actions
