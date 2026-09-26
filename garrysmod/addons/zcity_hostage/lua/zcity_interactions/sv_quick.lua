local I=ZCityInteractions
I.QuickOffers=setmetatable({}, {__mode="k"})
I.QuickPending=setmetatable({}, {__mode="k"})
local requestRates=setmetatable({}, {__mode="k"})
local pressRates=setmetatable({}, {__mode="k"})
local serial=0
util.AddNetworkString("zci_quick_request")
util.AddNetworkString("zci_quick_offer")
util.AddNetworkString("zci_quick_press")
util.AddNetworkString("zci_quick_armed")
util.AddNetworkString("zci_quick_result")
local function enabled(name) local c=GetConVar(name) return c and c:GetBool() end
local function ready(p)
    return IsValid(p) and p:IsPlayer() and p:Alive() and p.organism and not p.organism.otrub
end
local function eligible(p,t,row)
    local g=ZCityHostage.Gameplay local s=ZCityStealth
    if row.session then
        if I.Session(p)~=row.session or row.session.a~=p then return false end
        for _,offer in ipairs(I.ContextOffers(p,t)) do
            if offer.owner==row.owner and offer.id==row.id then return offer.reason=="" end
        end
        return false
    end
    if not ready(p) or I.Session(p) or not I.ContextTargetVisible(p,t)
        or not IsValid(row.weapon) or row.weapon:GetOwner()~=p then return false end
    if row.owner=="hostage" then
        return enabled("zch_gameplay_enabled") and g.CanQuickGrab(p,t,row.weapon)
    end
    return s and s.Begin(p,t,row.id,nil,nil,row.weapon)
end
I.QuickEligible=eligible
function I.QuickChoice(p,t)
    if not ready(p) then return end
    local session=I.Session(p)
    if session then
        if session.a~=p then return end -- captives retain the existing Use-to-resist input
        t=session.v or t
        for _,row in ipairs(I.ContextOffers(p,t)) do
            if row.reason=="" and row.id=="release" then
                local choice={owner=row.owner,id=row.id,label=row.label,hold=row.danger and .8 or .2,danger=row.danger and true or false,session=session,target=t}
                return choice
            end
        end
        return
    end
    if not I.ContextTargetVisible(p,t) then return end
    -- Quick input never draws a different weapon implicitly.
    local w=p:GetActiveWeapon()
    local profile,profileReason=I.WeaponProfile(w)
    local kind=profile and profile.kind
    if not IsValid(w) or w:GetOwner()~=p then return nil,"Ready your equipment first" end
    local ids=(kind=="pistol" or kind=="revolver") and {"grab"} or kind=="knife" and {"interrogate"}
        or kind=="wire" and {"fiberwire"} or kind=="hands" and (t:IsRagdoll() and {"carry"} or {"sleeper","neck_break"})
    if not ids then return nil,profileReason or "Equip a handgun, knife, fiberwire or hands; use the action menu for more options" end
    local labels={grab="Take hostage",interrogate="Knife hold",fiberwire="Fiberwire hold",carry="Carry body",sleeper="Sleeper hold",neck_break="Neck takedown"}
    local reason
    for _,id in ipairs(ids) do
        local owner=id=="grab" and "hostage" or "stealth"
        local row={owner=owner,id=id,label=labels[id],weapon=w,target=t,
            hold=(id=="fiberwire" or id=="sleeper" or id=="neck_break") and .8 or .35,danger=id=="neck_break"}
        local ok,why=eligible(p,t,row)
        if ok then return row end
        reason=reason or why
    end
    return nil,reason or "No quick action here; check the action menu"
end
local function identity(p,q)
    if not ready(p) or p.organism~=q.organism or p:GetModel()~=q.model or (I.PolicyLives[p] or 0)~=q.life
        or I.PolicyRound~=q.round or I.Session(p)~=q.row.session then return false end
    local mode=I.PolicyContext()
    if mode~=q.mode or (mode and mode.Type)~=q.submode then return false end
    if q.creation then
        if not IsValid(q.target) or q.target:GetCreationID()~=q.creation
            or I.Receiver(q.target)~=q.receiver or (q.receiver and ((I.PolicyLives[q.receiver] or 0)~=q.targetLife
                or q.receiver.organism~=q.targetOrganism)) then return false end
    end
    if q.row.weapon and (not IsValid(q.row.weapon) or q.row.weapon:GetOwner()~=p or q.row.weapon:GetCreationID()~=q.weaponCreation) then return false end
    return true
end
function I.OpenQuick(p,t,nonce)
    if I.QuickPending[p] then return end
    local old=I.QuickOffers[p]
    if old and old.armedAt and CurTime()<=old.expires then return old end
    local row=I.QuickChoice(p,t)
    I.QuickOffers[p]=nil
    if not row then return end
    t=row.target
    if old and identity(p,old) and old.originalWeapon==p:GetActiveWeapon() and old.target==t
        and old.row.id==row.id and old.row.owner==row.owner and old.row.weapon==row.weapon then
        old.nonce=nonce old.expires=CurTime()+.9 I.QuickOffers[p]=old return old
    end
    serial=serial%4294967295+1
    local mode=I.PolicyContext() local receiver=I.Receiver(t)
    local q={token=serial,nonce=nonce,row=row,target=t,creation=IsValid(t) and t:GetCreationID(),receiver=receiver,
        targetLife=receiver and (I.PolicyLives[receiver] or 0),targetOrganism=receiver and receiver.organism,
        life=I.PolicyLives[p] or 0,organism=p.organism,model=p:GetModel(),round=I.PolicyRound,mode=mode,submode=mode and mode.Type,
        originalWeapon=p:GetActiveWeapon(),weaponCreation=row.weapon and row.weapon:GetCreationID(),expires=CurTime()+.9}
    I.QuickOffers[p]=q
    return q
end
local function finish(p,q)
    if q.row.owner=="hostage" then return ZCityHostage.Gameplay.RequestAction(p,q.row.id,nil,q.target) end
    return ZCityStealth.RequestAction(p,q.row.id,q.target)
end
function I.PressQuick(p,token,stage)
    local q=I.QuickOffers[p]
    if stage==0 then
        -- Key up. A live grab already consumed its offer; the session kept the token.
        local g=ZCityHostage.Gameplay
        local rewound=g.KeyReleased and g.KeyReleased(p,token)
        if q and q.token==token then I.QuickOffers[p]=nil return true end
        return rewound or false
    end
    if not q or q.token~=token then return false end
    if not identity(p,q) or CurTime()>q.expires or p:GetActiveWeapon()~=q.originalWeapon or not eligible(p,q.target,q.row) then
        I.QuickOffers[p]=nil return false,"Action is no longer available"
    end
    if stage==1 then
        if q.armedAt then return false end
        if q.row.owner=="hostage" and q.row.id=="grab" and not q.row.session and q.row.weapon==p:GetActiveWeapon() then
            -- Hold = the grab entry itself (pistol already in hand). Third result
            -- marks the offer live: there is no stage 2, key-up rewinds instead.
            I.QuickOffers[p]=nil
            local ok,why=ZCityHostage.Gameplay.RequestAction(p,q.row.id,nil,q.target,nil,token)
            return ok==true,why,true
        end
        q.armedAt=CurTime() q.expires=CurTime()+3
        return true
    end
    if stage~=2 or not q.armedAt or CurTime()-q.armedAt<q.row.hold then return false end
    I.QuickOffers[p]=nil -- consume before callbacks; no repeated action on a held key
    if q.row.weapon and q.row.weapon~=p:GetActiveWeapon() then
        q.deadline=CurTime()+2 q.readyAt=CurTime()+.4
        I.QuickPending[p]=q
        local ok=pcall(p.SelectWeapon,p,q.row.weapon:GetClass())
        if not ok or I.QuickPending[p]~=q or p:GetActiveWeapon()~=q.row.weapon then
            I.QuickPending[p]=nil return false,"Weapon switch was refused or interrupted"
        end
        return true,"Readying equipment; Reload cancels"
    end
    return finish(p,q)
end
local function result(p,ok,why,token)
    if not IsValid(p) then return end
    net.Start("zci_quick_result") net.WriteUInt(token,32) net.WriteBool(ok==true) net.WriteString(why or "") net.Send(p)
end
local nextStep=0
local nextPrune=0
hook.Add("Think","ZCityInteractions.QuickEquipment",function()
    if CurTime()<nextStep then return end nextStep=CurTime()+.05
    if CurTime()>=nextPrune then
        nextPrune=CurTime()+.5
        for p,q in pairs(I.QuickOffers) do if not IsValid(p) or CurTime()>q.expires then I.QuickOffers[p]=nil end end
    end
    for p,q in pairs(I.QuickPending) do
        local w=q.row.weapon
        if not identity(p,q) or p:GetActiveWeapon()~=w or not I.ContextTargetVisible(p,q.target) or CurTime()>=q.deadline then
            I.QuickPending[p]=nil result(p,false,"Interaction canceled; target or equipment changed",q.token)
        elseif CurTime()>=q.readyAt and not w.deploy and not w.reload then
            I.QuickPending[p]=nil
            if eligible(p,q.target,q.row) then local ok,why=finish(p,q) result(p,ok,why,q.token)
            else result(p,false,"Interaction is no longer available",q.token) end
        end
    end
end)
for _,event in ipairs({"PlayerSpawn","PlayerDisconnected","PlayerDeath","PlayerSilentDeath"}) do
    hook.Add(event,"ZCityInteractions.QuickLife",function(p)
        if event=="PlayerSpawn" and OverrideSpawn then return end
        requestRates[p]=nil pressRates[p]=nil
        for a,q in pairs(I.QuickOffers) do if a==p or q.target==p or q.receiver==p then I.QuickOffers[a]=nil end end
        for a,q in pairs(I.QuickPending) do if a==p or q.target==p or q.receiver==p then I.QuickPending[a]=nil end end
    end)
end
for _,event in ipairs({"PreCleanupMap","ZB_EndRound","ZB_PreRoundStart","ShutDown"}) do
    hook.Add(event,"ZCityInteractions.QuickRound",function()
        I.QuickOffers=setmetatable({}, {__mode="k"}) I.QuickPending=setmetatable({}, {__mode="k"})
    end)
end
hook.Add("StartCommand","ZCityInteractions.QuickCancel",function(p,cmd)
    local q=I.QuickPending[p]
    if q and cmd:KeyDown(IN_RELOAD) then I.QuickPending[p]=nil result(p,false,"Interaction canceled",q.token) end
end)
hook.Add("PostEntityTakeDamage","ZCityInteractions.QuickInjury",function(p,dmg,took)
    if not took or dmg:GetDamage()<=0 then return end
    for a,q in pairs(I.QuickOffers) do if a==p or q.target==p or q.receiver==p then I.QuickOffers[a]=nil end end
    for a,q in pairs(I.QuickPending) do if a==p or q.target==p or q.receiver==p then I.QuickPending[a]=nil result(a,false,"Interrupted by injury",q.token) end end
end)
net.Receive("zci_quick_request",function(bits,p)
    if bits~=16 or not ready(p) or (requestRates[p] or 0)>CurTime() then return end
    requestRates[p]=CurTime()+.3
    local nonce=net.ReadUInt(16)
    if I.QuickPending[p] then return end
    local s=ZCityStealth local t=s and s.Target(p) or NULL
    local q=I.OpenQuick(p,t,nonce)
    net.Start("zci_quick_offer") net.WriteUInt(nonce,16) net.WriteUInt(q and q.token or 0,32)
    net.WriteEntity(q and q.target or NULL) net.WriteString(q and q.row.label or "") net.WriteFloat(q and q.row.hold or 0) net.WriteBool(q and q.row.danger or false) net.Send(p)
end)
net.Receive("zci_quick_press",function(bits,p)
    if bits~=40 or not ready(p) then return end
    local token=net.ReadUInt(32) local stage=net.ReadUInt(8)
    if stage>2 or (stage~=0 and (pressRates[p] or 0)>CurTime()) then return end
    if stage~=0 then pressRates[p]=CurTime()+.08 end
    local ok,why,live=I.PressQuick(p,token,stage)
    if stage==1 and ok then net.Start("zci_quick_armed") net.WriteUInt(token,32) net.WriteBool(live==true) net.Send(p)
    elseif stage==2 or (stage==1 and live) then result(p,ok,why,token) end
end)
