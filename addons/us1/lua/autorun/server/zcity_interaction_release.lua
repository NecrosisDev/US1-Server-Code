-- Read-only operator diagnostic; no activation, restart or client action.
local release="20260920.rc2"
concommand.Add("zci_release_status",function(p)
    if IsValid(p) and not p:IsSuperAdmin() then return end
    local i=ZCityInteractions
    local h=ZCityHostage and ZCityHostage.Gameplay
    local s=ZCityStealth
    print("[Interaction release]",release)
    print("[Interaction versions]",i and i.Version,h and h.Version,s and s.Version)
    print("[Interaction native seams]",h and h.SeamsReady and h.SeamsReady(),s and s.SeamsReady and s.SeamsReady())
    print("[Interaction wire lungs]",hg and hg.organism and hg.organism.InteractionWireBreathingVersion)
    for _,name in ipairs({"zch_gameplay_enabled","zsf_enabled","zci_trial_steamid","zsf_trial_steamid","zci_sandbox_trial","zc_headshot_slowmo"}) do
        local cv=GetConVar(name);print("[Interaction config]",name,cv and cv:GetString() or "MISSING")
    end
    print("[Interaction acceptance] Local candidate; diagnostics do not prove rendering, medical outcomes or release acceptance.")
end)
