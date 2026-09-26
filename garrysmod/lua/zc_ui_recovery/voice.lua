if SERVER then return end
hg=hg or {}
-- Both legacy blockers must honor the same admin preference. Mark speech before
-- returning, because a non-nil hook return stops later observers from running.
function hg.CanIdentifyVoicePanel(ply)
    if not IsValid(ply) then return end
    local listener=LocalPlayer()
    if not IsValid(listener) then return end
    local adminView=GetConVar("zb_admin_show_voicechat")
    if listener:IsAdmin() and adminView and adminView:GetBool() then return true end
    local org=ply.organism
    local hidden=(ply:Alive() and listener~=ply)
        or (org and (org.otrub or (org.brain and org.brain>0.05)))
    return not hidden
end
function hg.ShouldSuppressVoicePanel(ply)
    if not IsValid(ply) then return end
    ply.IsSpeak = true
    if not IsValid(LocalPlayer()) then return end
    if not hg.CanIdentifyVoicePanel(ply) then return true end
    if ZCGoobApps and ZCGoobApps.Voice and ZCGoobApps.Voice.Ready() then return true end
end
hook.Add("PlayerEndVoice","ZCityUIVoiceState",function(ply)
    if IsValid(ply)then ply.IsSpeak=false end
end)
