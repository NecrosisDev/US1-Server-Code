local I=ZCityInteractions
-- Fixed, versioned bit positions. Only the actor receives this presentation
-- snapshot; server admission always recomputes from current authoritative state.
I.CapabilityOrder={"hostage","restraint","execution","knife","precision","unarmed","choke","fast_choke","aerial","roll","throw","wire","legacy_neck","disarm","arrest"}
I.ActionCapabilities={
    hold="hostage",cuff="restraint",arrest="arrest",posture="restraint",kneeling_execution="execution",execution="execution",hurt_grab="restraint",
    neck_stab="knife",clavicle="knife",spin_stab="knife",interrogate="knife",
    kidney_neck="precision",reverse_grip="precision",thigh_neck="precision",flip_stab="precision",
    neck_break="unarmed",reverse_ddt="unarmed",flip_stomp="unarmed",chop="choke",
    sleeper="choke",sleeper_fast="fast_choke",drop_stab="aerial",drop_kick="aerial",
    roll_forward="roll",roll_back="roll",roll_left="roll",roll_right="roll",
    fiberwire="wire",legacy_neck="legacy_neck",disarm="disarm",throw="throw",
    carry="utility",drag="utility",stealth="utility",cover_left="utility",cover_right="utility"
}
I.NonhostileIntents={carry=true,drag=true,stealth=true,cover_left=true,cover_right=true,
    roll_forward=true,roll_back=true,roll_left=true,roll_right=true}
if SERVER then return end
I.PrivateCapabilities={}
net.Receive("zci_capabilities",function()
    local revision=net.ReadUInt(8) local mask=net.ReadUInt(16)
    if revision~=1 then I.PrivateCapabilities={} return end
    local caps={utility=true}
    for index,name in ipairs(I.CapabilityOrder) do caps[name]=bit.band(mask,2^(index-1))~=0 end
    I.PrivateCapabilities=caps
end)
function I.ClientHasAction(id)
    local capability=I.ActionCapabilities[id]
    return capability=="utility" or (capability and I.PrivateCapabilities[capability]) or false
end
