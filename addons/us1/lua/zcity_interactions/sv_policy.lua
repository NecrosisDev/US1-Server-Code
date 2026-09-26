local I=ZCityInteractions
I.PolicyLives=I.PolicyLives or setmetatable({}, {__mode="k"})
I.RoleAssignments=I.RoleAssignments or setmetatable({}, {__mode="k"})
I.CapabilitySent=I.CapabilitySent or setmetatable({}, {__mode="k"})
I.PolicyRound=I.PolicyRound or 0
I.ModeAdapters=I.ModeAdapters or {}
I.SandboxTrial=CreateConVar("zci_sandbox_trial","0",FCVAR_ARCHIVE,"Allow the full interaction catalog for admins in sandbox only",0,1)
I.TrialUser=CreateConVar("zci_trial_steamid","",FCVAR_ARCHIVE,"Optional SteamID64 allowed to initiate this interaction trial")
I.PublicAccess=CreateConVar("zci_public_access","1",FCVAR_ARCHIVE,"Allow all players the supported interaction catalog",0,1)
function I.PublicAccessAllowed(p)
    return I.PublicAccess:GetBool() and IsValid(p) and p:IsPlayer() and p:Alive()
end
function I.TrialAllowed(p)
    if I.PublicAccessAllowed(p) then return true end
    local id=I.TrialUser:GetString()
    return id=="" or (IsValid(p) and p:IsPlayer() and p:SteamID64()==id)
end
util.AddNetworkString("zci_capabilities")
function I.PolicyContext()
    local mode=CurrentRound and CurrentRound()
    return mode or {},mode and mode.name or (engine and engine.ActiveGamemode and engine.ActiveGamemode()) or "unknown"
end
function I.AssignRole(p,mode,role)
    if not IsValid(p) or p.SubRole~=role then return end
    I.RoleAssignments[p]={life=I.PolicyLives[p] or 0,round=I.PolicyRound,mode=mode,submode=mode.Type,role=role,class=p.PlayerClassName}
    I.CapabilitySent[p]=nil
end
local function assignedRole(p,mode)
    local row=I.RoleAssignments[p]
    local catalog=mode.RoleChooseRoundTypes and mode.RoleChooseRoundTypes[mode.Type]
    if not row or row.life~=(I.PolicyLives[p] or 0) or row.round~=I.PolicyRound or row.mode~=mode
        or row.submode~=mode.Type or row.role~=p.SubRole or row.class~=p.PlayerClassName or not p.isTraitor or p.isPolice or p.isGunner
        or not catalog or not catalog.Traitor or not catalog.Traitor[row.role] then return end
    return row.role
end
local function police(p)
    local class=p.PlayerClassName
    return p.isPolice and (class=="police" or class=="swat" or class=="nationalguard")
end
local function capabilities(...)
    local out={utility=true}
    for _,name in ipairs({...}) do out[name]=true end
    return out
end
I.ModeAdapters.hmcd=function(p,mode)
    -- Equipment-based threats stay physical possibilities for every role;
    -- this grants neither innocent status nor permission to evade justice.
    local caps=capabilities("hostage","restraint","execution","knife","wire")
    if police(p) then caps.choke=true caps.roll=true caps.arrest=true return caps end
    local role=assignedRole(p,mode)
    if role=="traitor_infiltrator" or role=="traitor_infiltrator_soe" then
        for _,name in ipairs({"precision","unarmed","aerial","roll","throw","legacy_neck"}) do caps[name]=true end
    elseif role=="traitor_assasin" or role=="traitor_assasin_soe" then
        for _,name in ipairs({"choke","fast_choke","roll","throw","disarm"}) do caps[name]=true end
    end
    return caps
end
I.ModeAdapters.riot=function(p)
    local caps=capabilities("hostage","restraint")
    if p:Team()==1 and p.PlayerClassName=="police" then caps.choke=true caps.roll=true caps.arrest=true end
    return caps
end
I.ModeAdapters.uncontainedriot=function(p)
    local caps=I.ModeAdapters.riot(p)
    caps.execution=true caps.knife=true caps.wire=true
    return caps
end
function I.ActorCapabilities(p,mode,name)
    if not IsValid(p) or not p:IsPlayer() or not p:Alive() then return {} end
    local trialAllowed=I.TrialAllowed(p)
    if not mode then mode,name=I.PolicyContext() end
    if I.PublicAccessAllowed(p) and (name=="hmcd" or name=="riot" or name=="uncontainedriot" or name=="sandbox") then
        local caps={utility=true} for _,key in ipairs(I.CapabilityOrder) do caps[key]=true end return caps
    end
    if name=="sandbox" and I.SandboxTrial:GetBool() and p:IsAdmin() then
        local caps={utility=true} for _,key in ipairs(I.CapabilityOrder) do caps[key]=true end return caps
    end
    local adapter=I.ModeAdapters[name]
    local caps
    if adapter then
        caps=adapter(p,mode)
    else
        -- Explicit custom-mode opt-in. No inherited deathmatch/coop/role guesses.
        caps={utility=true}
        for _,key in ipairs(I.CapabilityOrder) do caps[key]=mode.InteractionCapabilities and mode.InteractionCapabilities[key]==true or false end
    end
    -- The public slice is deliberately one capability wide. Trial users keep
    -- the existing role/mode catalog; everyone else receives hostage-taking
    -- only when that mode already opted into it.
    if not trialAllowed then return caps.hostage and {hostage=true} or {} end
    return caps
end
function I.PolicyAllowed(a,intent,target)
    local capability=I.ActionCapabilities[intent]
    if not capability then return false,"This action has no mode policy" end
    if not I.TrialAllowed(a) and capability~="hostage" then return false,"A controlled interaction trial is running" end
    local mode,name=I.PolicyContext()
    local caps=I.ActorCapabilities(a,mode,name)
    if not caps[capability] then return false,"This technique is unavailable for your current role or mode" end
    if not I.NonhostileIntents[intent] then
        local allowed,reason=I.RoundAllowsHostility()
        if not allowed then return false,reason end
        local receiver=I.Receiver(target)
        if IsValid(receiver) and receiver:IsPlayer() then
            -- Homicide targets are deliberately never classified by secret role.
            if name=="riot" or name=="uncontainedriot" or mode.InteractionEnemyOnly==true then
                if a:Team()==receiver:Team() then return false,"Hostile control of teammates is disabled" end
                if (name=="riot" or name=="uncontainedriot") and
                    ((a:Team()~=0 and a:Team()~=1) or (receiver:Team()~=0 and receiver:Team()~=1)) then
                    return false,"A participating opponent is required"
                end
            end
        end
    end
    return true
end
function I.SendCapabilities(p,mode,name)
    local caps=I.ActorCapabilities(p,mode,name) local mask=0
    for index,key in ipairs(I.CapabilityOrder) do if caps[key] then mask=mask+2^(index-1) end end
    if I.CapabilitySent[p]==mask then return end
    I.CapabilitySent[p]=mask
    net.Start("zci_capabilities") net.WriteUInt(1,8) net.WriteUInt(mask,16) net.Send(p)
end
local nextPublish=0
hook.Add("Think","ZCityInteractions.PrivateCapabilities",function()
    if CurTime()<nextPublish then return end nextPublish=CurTime()+.5
    local mode,name=I.PolicyContext()
    for _,p in ipairs(player.GetAll()) do I.SendCapabilities(p,mode,name) end
end)
for _,event in ipairs({"PlayerSpawn","PlayerDisconnected"}) do
    hook.Add(event,"ZCityInteractions.PolicyLife",function(p)
        if event=="PlayerSpawn" and OverrideSpawn then return end -- FakeUp's get-up Spawn is the same life
        I.PolicyLives[p]=(I.PolicyLives[p] or 0)+1 I.RoleAssignments[p]=nil I.CapabilitySent[p]=nil
    end)
end
for _,event in ipairs({"ZB_EndRound","ZB_PreRoundStart","PreCleanupMap"}) do
    hook.Add(event,"ZCityInteractions.PolicyRound",function()
        I.PolicyRound=I.PolicyRound+1 I.RoleAssignments=setmetatable({}, {__mode="k"}) I.CapabilitySent=setmetatable({}, {__mode="k"})
    end)
end
