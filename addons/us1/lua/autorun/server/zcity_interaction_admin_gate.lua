-- Public admission compatibility owner. Keep this historical path so an old
-- startup include cannot reinstall the retired admin-only trial.
local version="20260922.public2"
local function apply()
    local I,S=ZCityInteractions,ZCityStealth
    if not I or not S or not I.TrialUser or not S.TrialUser or not I.PublicAccessAllowed then return false end
    I.TrialGateVersion=version S.TrialGateVersion=version
    function I.TrialIdentityAllowed(p,selector)
        if not IsValid(p) or not p:IsPlayer() then return false end
        if selector=="admin" then return p:IsAdmin() end
        return selector=="" or p:SteamID64()==selector
    end
    function I.TrialAllowed(p)
        return I.PublicAccessAllowed(p) or I.TrialIdentityAllowed(p,I.TrialUser:GetString())
    end
    function S.TrialAllowed(p)
        return I.PublicAccessAllowed(p) or (I.TrialIdentityAllowed(p,S.TrialUser:GetString()) and I.TrialAllowed(p))
    end
    I.CapabilitySent=setmetatable({}, {__mode="k"})
    return true
end
hook.Add("InitPostEntity","ZCityInteractions.AdminTrial",apply)
apply()
concommand.Add("zci_admin_trial_status",function(p)
    if IsValid(p) and not p:IsAdmin() then return end
    local I,S=ZCityInteractions,ZCityStealth
    print("[Interaction access]",version,I and I.PublicAccess and I.PublicAccess:GetBool(),
        I and I.TrialGateVersion,S and S.TrialGateVersion)
end)
