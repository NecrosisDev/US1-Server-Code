local I=ZCityInteractions
local previousSerial=I.ContextSerial or 0
for _,context in pairs(I.Contexts or {}) do previousSerial=math.max(previousSerial,context.token or 0) end
I.Contexts=setmetatable({}, {__mode="k"})
local rates=setmetatable({}, {__mode="k"})
local openRates=setmetatable({}, {__mode="k"})
local refreshRates=setmetatable({}, {__mode="k"})
local serial=previousSerial
util.AddNetworkString("zci_context_request")
util.AddNetworkString("zci_context")
util.AddNetworkString("zci_context_select")
util.AddNetworkString("zci_context_arm")
util.AddNetworkString("zci_context_refresh")
local function enabled(name)
    local cv=GetConVar(name) return cv and cv:GetBool()
end
local function ready(p)
    return IsValid(p) and p:IsPlayer() and p:Alive() and p.organism and not p.organism.otrub
end
function I.ContextTargetVisible(p,t)
    if not IsValid(t) or t==p or (not t:IsPlayer() and not t:IsRagdoll()) then return false end
    local g=ZCityHostage and ZCityHostage.Gameplay
    local reach=t:IsPlayer() and g and g.Reach(p,t) or 180
    if p:GetPos():DistToSqr(t:GetPos())>math.max(180,reach)^2 then return false end
    local eye=p:EyePos() local point=t:IsPlayer() and t:EyePos() or t:WorldSpaceCenter()
    local direction=point-eye
    if direction:LengthSqr()>1 and p:GetAimVector():Dot(direction:GetNormalized())<.75 then return false end
    local trace=util.TraceLine({start=eye,endpos=point,filter=p,mask=MASK_SHOT})
    return not trace.Hit or trace.Entity==t
end
function I.ContextOffers(p,t)
    local rows={}
    local g=ZCityHostage and ZCityHostage.Gameplay local s=ZCityStealth
    local session=I.Session(p)
    local function add(owner,id,label,group,danger,intent,targeted)
        if #rows>=48 then return end
        local allowed,reason=true,""
        if intent then allowed,reason=I.PolicyAllowed(p,intent,t) end
        rows[#rows+1]={owner=owner,id=id,label=label,group=group or 0,danger=danger or false,
            reason=allowed and "" or (reason or "Unavailable"),targeted=targeted or false}
        return rows[#rows]
    end
    if session and (session.system=="fiberwire" or session.system=="disarm") then
        if session.a==p then add("stealth","release",session.system=="fiberwire" and "Release fiberwire" or "Cancel disarm") end
        return rows
    end
    local function unlockRow(ent,id,label)
        local w=p:GetActiveWeapon()
        if not IsValid(w) or w:GetClass()~="weapon_handcuffs_key" or not w.CanUnTie or not I.Cuffed(ent) then return end
        local row=add("hostage",id,label,0,false,nil,ent~=p)
        local ok,why=w:CanUnTie(ent)
        if not ok then row.reason=why or "Cannot unlock these cuffs" end
    end
    if I.Cuffed(p) then unlockRow(p,"unlock_self","Unlock your cuffs") end
    local hostage=g and g.ByPlayer and g.ByPlayer[p]
    if hostage then
        if hostage.a==p then
            local transition=hostage.phase=="posture_entry" or hostage.phase=="stand_up"
            -- v2: letting go is a danger row, so a held Use (0.4 s auto-commit) never releases (B4).
            local release=add("hostage","release",hostage.kind=="solo" and (I.Cuffed(p) and "Stand up (keep cuffs)" or "Stand up / stop surrendering") or "Release hostage",
                0,hostage.kind=="hold" and g.V2 and g.V2(p) or false)
            if hostage.kind=="solo" and transition then release.reason="Finish changing posture first" end
            if hostage.kind=="hold" and hostage.phase=="hold" then
                add("hostage","execute","Shoot hostage",0,true,"execution",true)
                local knife=g.ControlKnife(p)
                if IsValid(knife) then
                    local row=add("hostage","knife_hold","Switch to knife hold",0,false,"interrogate",true)
                    row.equipment=knife row.equipmentCreation=knife:GetCreationID()
                    if row.reason=="" then
                        local allowed,why=g.KnifeHandoffStatus(p,knife,true)
                        if not allowed then row.reason=why or "Knife handoff unavailable" end
                    end
                end
                local wire=g.ControlWire(p)
                if IsValid(wire) then
                    local row=add("hostage","wire_hold","Switch to fiberwire",0,false,"fiberwire",true)
                    row.equipment=wire row.equipmentCreation=wire:GetCreationID()
                    if row.reason=="" then
                        local allowed,why=g.WireHandoffStatus(p,wire)
                        if not allowed then row.reason=why or "Fiberwire handoff unavailable" end
                    end
                end
            end
            if hostage.kind=="solo" and I.Cuffed(p) and hostage.phase~="posture_entry" and hostage.phase~="stand_up" then
                if hostage.phase~="lying" then add("hostage","lie","Lie down") end
            end
        elseif hostage.v==p then
            add("hostage","struggle","Struggle to escape")
        end
        return rows
    end
    local stealth=s and s.ByActor and s.ByActor[p]
    if stealth then
        if stealth.a~=p then add("stealth","resist","Struggle to escape") return rows end
        add("stealth","release",stealth.action.kind=="body" and "Put body down" or "Release / cancel")
        if stealth.wireHandoff then return rows end
        if stealth.phase~="loop" then return rows end
        if stealth.action.finish then add("stealth","finish","Stab held target",0,true,stealth.policyIntent,true) end
        if stealth.action.throw then add("stealth","throw",stealth.body and "Throw body" or "Throw held object",0,true,stealth.body and "throw" or nil) end
        if stealth.action.turn or stealth.action.left then
            add("stealth","turn_left","Turn left") add("stealth","turn_right","Turn right")
        end
        return rows
    end
    local targetPlayer=IsValid(t) and t:IsPlayer() and t~=p and t:Alive()
    local dropItem=stealth and IsValid(stealth.item) and stealth.item or nil
    local dropAllowed,dropReason=true,nil
    if dropItem then dropAllowed,dropReason=s.CanReleaseItem(stealth,dropItem) end
    local function withDrop(row)
        if row and dropItem then row.dropItem=dropItem;row.dropCreation=dropItem:GetCreationID() end
        if row and row.reason=="" and not dropAllowed then row.reason=dropReason end
        return row
    end
    if stealth and targetPlayer and s.SoloWireStatus and g then
        local wire=g.ControlWire(p)
        if IsValid(wire) then
            local row=withDrop(add("stealth",dropItem and "drop_then:fiberwire" or "fiberwire",
                dropItem and "Drop object, then ready fiberwire" or "Switch to fiberwire",0,false,"fiberwire",true))
            row.equipment=wire row.equipmentCreation=wire:GetCreationID()
            if row.reason=="" then
                local allowed,why=s.SoloWireStatus(p,t,wire,dropItem)
                if not allowed then row.reason=why or "Fiberwire handoff unavailable" end
            end
        end
    end
    local w=p:GetActiveWeapon()
    if not stealth and g and enabled("zch_gameplay_enabled") then
        if I.Cuffed(p) then add("hostage","lie","Lie down (cuffed)",2) end
        if IsValid(t) then unlockRow(t,"uncuff","Unlock their cuffs") end
        if targetPlayer then
            if I.IsHandgun(w) then
                local row=add("hostage","grab","Take hostage",0,false,"hold",true)
                if row.reason=="" then local ok,why=g.CanQuickGrab(p,t,w) if not ok then row.reason=why or "Hostage grab unavailable" end end
            end
            if IsValid(w) and w:GetClass()=="weapon_handcuffs" then
                local intent=g.CuffIntent(p,t)
                local row=add("hostage",intent,intent=="arrest" and "Restrain and cuff" or "Apply handcuffs",0,false,intent,true)
                if row and row.reason=="" then
                    local allowed,why=g.CanStartCuff(p,t,intent=="arrest")
                    if not allowed then row.reason=why or "Restraint is unavailable" end
                end
            end
            if I.Cuffed(t) then add("hostage","order_lie","Make lie down",1,false,"posture",true) end
        end
    end
    if not s or not enabled("zsf_enabled") or not s.TrialAllowed(p) then return rows end
    local kind=s.WeaponKind(p)
    local primary={neck_stab=true,interrogate=true,sleeper=true,disarm=true,fiberwire=true,carry=true,drag=true,stealth=true}
    local caps=I.ActorCapabilities(p)
    local sorted={} for _,action in pairs(s.Actions) do sorted[#sorted+1]=action end
    table.sort(sorted,function(a,b) return a.id<b.id end)
    for _,action in ipairs(sorted) do
        local cap=I.ActionCapabilities[action.id]
        local available=cap=="utility" or (cap and caps[cap])
        local body=action.kind=="body"
        local paired=body or action.kind=="takedown" or action.kind=="interrogate" or action.kind=="wire" or action.kind=="native"
        if available and s.WeaponMatches(action,kind) and (not stealth or action.id~=stealth.action.id)
            and (not paired or (body and IsValid(t) and t:IsRagdoll()) or (not body and targetPlayer)
                or (action.kind=="wire" and IsValid(t) and t:IsRagdoll())) then
            local group=primary[action.id] and 0 or paired and 1 or 2
            local danger=action.kind=="takedown" and action.damage~="choke"
            local row=withDrop(add("stealth",dropItem and "drop_then:"..action.id or action.id,
                dropItem and "Drop object, then "..string.lower(action.label) or action.label,group,danger,action.id,paired))
            if row and row.reason=="" then
                if not s.Armed(p,action) then row.reason="Your hands or weapon are not ready"
                elseif paired and ((action.kind=="wire" or action.kind=="native")
                    and (p:GetPos():DistToSqr(t:GetPos())>(action.kind=="wire" and 100 or 90)^2 or not s.Visible(p,t))
                    or (action.kind~="wire" and action.kind~="native" and not s.InApproach(p,t,action))) then row.reason="Move within clear reach"
                elseif paired and not body and action.kind~="native" and t:IsPlayer() and not action.above
                    and not IsValid(t.FakeRagdoll) and not s.Rear(p,t) then row.reason="Approach from behind"
                end
            end
        end
    end
    return rows
end
function I.MenuOffers(p,t)
    -- This catalog belongs to the interaction circle, never native Q.
    return I.ContextOffers(p,t)
end
function I.ContextPrimaryIndex(p,c)
    local w=p:GetActiveWeapon()
    if IsValid(w) and (w:GetClass()=="weapon_handcuffs" or w:GetClass()=="weapon_handcuffs_key") then
        for index,row in ipairs(c.rows) do
            if row.reason=="" and (row.id=="cuff" or row.id=="arrest" or row.id=="uncuff" or row.id=="unlock_self") then return index end
        end
    end
    if not I.QuickChoice then return 0 end
    local primary=I.QuickChoice(p,c.target)
    if not primary or primary.danger then return 0 end
    for index,row in ipairs(c.rows) do
        if row.owner==primary.owner and row.id==primary.id and row.reason=="" and not row.danger then return index end
    end
    return 0 -- no automatic surrender, lethal follow-up or inventory draw
end
function I.OpenContext(p,t,nonce)
    if not ready(p) then return end
    local session=I.Session(p)
    if session and IsValid(session.v) and session.a==p then t=session.v end
    if IsValid(t) and not (session and session.v==t) and not I.ContextTargetVisible(p,t) then t=NULL end
    if not IsValid(t) then t=NULL end
    local mode=I.PolicyContext()
    serial=serial%4294967295+1 I.ContextSerial=serial
    local receiver=I.Receiver(t)
    local context={token=serial,target=t,targetCreation=IsValid(t) and t:GetCreationID(),nonce=nonce,
        life=I.PolicyLives[p] or 0,targetLife=receiver and (I.PolicyLives[receiver] or 0),
        receiver=receiver,round=I.PolicyRound,mode=mode,submode=mode and mode.Type,
        weapon=p:GetActiveWeapon(),session=session,expires=CurTime()+10,rows=I.MenuOffers(p,t)}
    I.Contexts[p]=context
    return context
end
function I.ContextValid(p,c)
    if not ready(p) or not c or CurTime()>c.expires or (I.PolicyLives[p] or 0)~=c.life
        or I.PolicyRound~=c.round or p:GetActiveWeapon()~=c.weapon or I.Session(p)~=c.session then return false end
    local mode=I.PolicyContext()
    if mode~=c.mode or (mode and mode.Type)~=c.submode then return false end
    if c.targetCreation then
        if not IsValid(c.target) or c.target:GetCreationID()~=c.targetCreation
            or (c.receiver and (I.PolicyLives[c.receiver] or 0)~=c.targetLife) then return false end
        if not (c.session and c.session.v==c.target) and not I.ContextTargetVisible(p,c.target) then return false end
    end
    return true
end
function I.SelectContext(p,token,index,stage)
    local c=I.Contexts[p]
    if not c or c.token~=token or not I.ContextValid(p,c) then return false,"Selection expired; reopen the action menu" end
    local row=c.rows[index]
    if not row then return false,"Unknown action" end
    local current
    for _,candidate in ipairs(I.MenuOffers(p,c.target)) do
        if candidate.owner==row.owner and candidate.id==row.id then current=candidate break end
    end
    if not current or current.reason~="" then return false,current and current.reason or "Action no longer available" end
    if row.equipment and (row.equipment~=current.equipment or row.equipmentCreation~=current.equipmentCreation) then
        return false,"Equipment changed; reopen the action menu"
    end
    if row.dropItem and (row.dropItem~=current.dropItem or row.dropCreation~=current.dropCreation) then
        return false,"Held object changed; reopen the action menu"
    end
    if row.danger then
        if stage==1 then c.armed=index c.armedAt=CurTime() return true end
        if stage~=2 or c.armed~=index or not c.armedAt or CurTime()-c.armedAt<.8 or CurTime()-c.armedAt>3 then
            return false,"Hold to confirm this action"
        end
    elseif stage~=0 then return false,"Invalid action request" end
    I.Contexts[p]=nil -- single use, even if a native callback rejects or re-enters
    local g=ZCityHostage and ZCityHostage.Gameplay local s=ZCityStealth
    if row.owner=="hostage" then
        return g.RequestAction(p,row.id,row.id=="struggle" and "1" or nil,c.target,row.equipment)
    end
    return s.RequestAction(p,row.id,c.target,row.equipment,row.dropItem)
end
local function sendContext(p,c)
    net.Start("zci_context") net.WriteUInt(c.nonce,16) net.WriteUInt(c.token,32) net.WriteEntity(c.target)
    net.WriteUInt(#c.rows,6)
    for _,row in ipairs(c.rows) do
        net.WriteString(row.label) net.WriteString(row.reason) net.WriteUInt(row.group,2) net.WriteBool(row.danger)
    end
    net.WriteUInt(I.ContextPrimaryIndex(p,c),6) -- optional trailing field; legacy readers ignore it
    net.Send(p)
end
function I.RefreshContext(p,token)
    local c=I.Contexts[p] if not c or c.token~=token then return end
    local available={}
    local valid=I.ContextValid(p,c)
    if valid then
        for _,row in ipairs(I.MenuOffers(p,c.target)) do available[row.owner..":"..row.id]=row end
    else I.Contexts[p]=nil end
    for _,row in ipairs(c.rows) do
        local current=available[row.owner..":"..row.id]
        row.reason=valid and (current and current.reason or "Action no longer available") or "Selection expired; reopen menu"
        if valid and current and row.equipment and (row.equipment~=current.equipment or row.equipmentCreation~=current.equipmentCreation) then
            row.reason="Equipment changed; reopen the action menu"
        end
        if valid and current and row.dropItem and (row.dropItem~=current.dropItem or row.dropCreation~=current.dropCreation) then
            row.reason="Held object changed; reopen the action menu"
        end
    end
    return c
end
net.Receive("zci_context_request",function(bits,p)
    if bits>64 or bits<16 or not ready(p) or (openRates[p] or 0)>CurTime() then return end
    openRates[p]=CurTime()+.25
    local nonce=net.ReadUInt(16) local target=net.ReadEntity()
    local c=I.OpenContext(p,target,nonce) if c then sendContext(p,c) end
end)
net.Receive("zci_context_refresh",function(bits,p)
    if bits~=32 or not ready(p) or (refreshRates[p] or 0)>CurTime() then return end
    refreshRates[p]=CurTime()+.4
    local c=I.RefreshContext(p,net.ReadUInt(32)) if c then sendContext(p,c) end
end)
net.Receive("zci_context_select",function(bits,p)
    if bits~=40 or not ready(p) or (rates[p] or 0)>CurTime() then return end
    rates[p]=CurTime()+.1
    local token=net.ReadUInt(32) local index=net.ReadUInt(6) local stage=net.ReadUInt(2)
    local ok,reason=I.SelectContext(p,token,index,stage)
    if ok and stage==1 then
        net.Start("zci_context_arm") net.WriteUInt(token,32) net.WriteUInt(index,6) net.Send(p)
    end
    if not ok and reason then p:ChatPrint("Interaction: "..reason) end
end)
for _,event in ipairs({"PlayerSpawn","PlayerDisconnected","PlayerDeath","PlayerSilentDeath"}) do
    hook.Add(event,"ZCityInteractions.ContextLife",function(p) if event=="PlayerSpawn" and OverrideSpawn then return end I.Contexts[p]=nil rates[p]=nil openRates[p]=nil refreshRates[p]=nil end)
end
for _,event in ipairs({"ZB_EndRound","ZB_PreRoundStart","PreCleanupMap","ShutDown"}) do
    hook.Add(event,"ZCityInteractions.ContextRound",function() I.Contexts=setmetatable({}, {__mode="k"}) end)
end
