-- The existing context protocol drives one crosshair circle. Native Q owns its own UI.
local I=ZCityInteractions
if I.CloseActionPanel then I.CloseActionPanel() end
I.ContextUI=true I.CustomMenuVersion="20260923.restraints1"
I.ActionPanel=nil I.CreateActionPanel=nil I.NativeActionRows=nil I.CollectNativeActions=nil I.OpenNativeOptions=nil
hook.Remove("HUDPaint","ZCityInteractions.Feedback")
hook.Remove("radialOptions","ZCityInteractions.Actions")
hook.Remove("ZCityRadialOpening","ZCityInteractions.Snapshot")
local state,nonce,lastRequest=nil,0,-10
local useStart,useTarget,useWasDown,mustRelease,shortcutDown=nil,nil,false,false,false
local function key(command,fallback)
    local bound=input.LookupBinding(command) return bound and string.upper(bound) or fallback
end
I.Binding=key
function I.ContextEnabled()
    local a,b=GetConVar("zch_gameplay_enabled"),GetConVar("zsf_enabled")
    return (a and a:GetBool()) or (b and b:GetBool()) or false
end
local function inputReady()
    local p=LocalPlayer()
    return IsValid(p) and p:Alive() and not (p.organism and p.organism.otrub)
        and system.HasFocus() and not gui.IsGameUIVisible() and not vgui.CursorVisible()
        and not IsValid(MENUPANELHUYHUY)
end
function I.CircleVictim(p)
    return p:GetNWString("zch_role")=="victim"
        or (p:GetNWInt("zch_session")~=0 and p:GetNWInt("zch_initiator")~=p:EntIndex())
        or (p:GetNWInt("zsf_id")~=0 and not p:GetNWBool("zsf_initiator"))
        or (p:GetNWString("zci_native")~="" and not p:GetNWBool("zci_native_initiator"))
end
local function modifiers(p)
    local g=ZCityHostage and ZCityHostage.Gameplay
    -- v2 (B5): aiming (RMB) and ALT no longer close or latch the circle.
    if g and g.V2 and g.V2(p) then return p:KeyDown(IN_SPEED) or p:KeyDown(IN_ATTACK) or p:KeyDown(IN_RELOAD) end
    return p:KeyDown(IN_WALK) or p:KeyDown(IN_SPEED) or p:KeyDown(IN_ATTACK)
        or p:KeyDown(IN_ATTACK2) or p:KeyDown(IN_RELOAD)
end
local function carrying(p)
    return p.GetNetVar and (IsValid(p:GetNetVar("carryent")) or IsValid(p:GetNetVar("carryent2")))
end
local function target()
    local p=LocalPlayer() local t=p:GetEyeTrace().Entity
    if not IsValid(t) or t==p or (not t:IsPlayer() and not t:IsRagdoll()) then return end
    local g=ZCityHostage and ZCityHostage.Gameplay
    local reach=g and g.TraceReach and g.TraceReach(p) or 90
    if p:GetPos():DistToSqr(t:GetPos())>math.min(math.max(reach,90),180)^2 then return end
    return t
end
local function selected() return state and state.rows and state.order and state.rows[state.order[state.cursor or 1]] end
function I.CircleOpen() return state~=nil end
function I.CloseCircle()
    if state and state.held then mustRelease=true end
    state=nil useStart=nil useTarget=nil
end
I.CloseActionPanel=I.CloseCircle -- retained entry point for older callers; no panel exists
local function invalid()
    if not state or not inputReady() then return "Interaction interrupted" end
    local p=LocalPlayer()
    if p:GetActiveWeapon()~=state.weapon or p:GetNWInt("zch_session")~=state.hostage
        or p:GetNWInt("zsf_id")~=state.stealth or p:GetNWString("zci_native")~=state.native
        or p:GetNWInt("zci_native_id")~=state.nativeID then return "Equipment or interaction changed" end
    if CurTime()>state.expires then return "Selection expired; press again" end
    if state.creation and (not IsValid(state.target) or state.target:GetCreationID()~=state.creation) then return "Target changed" end
    -- While free, keep the exact target under the crosshair. Captors retain their partner.
    if state.creation and state.hostage==0 and state.stealth==0 and state.native=="" and target()~=state.target then return "Target changed" end
end
local function send(stage)
    if not state or not state.token or not state.order then return end
    net.Start("zci_context_select") net.WriteUInt(state.token,32)
    net.WriteUInt(state.order[state.cursor],6) net.WriteUInt(stage,2) net.SendToServer()
end
local function request(held,source)
    if CurTime()<lastRequest+.3 then return false end
    if not inputReady() or not I.ContextEnabled() then return false end
    local p=LocalPlayer()
    if I.CircleVictim(p) then return false end
    local t=target()
    local active=p:GetNWInt("zch_session")~=0 or p:GetNWInt("zsf_id")~=0 or p:GetNWString("zci_native")~=""
    -- A shortcut press is inert without a real target or active interaction.
    if not t and not active then return false end
    nonce=nonce%65535+1 lastRequest=CurTime()
    state={nonce=nonce,requested=CurTime(),expires=CurTime()+10,held=held,source=source or "shortcut",auto=held,
        weapon=p:GetActiveWeapon(),hostage=p:GetNWInt("zch_session"),stealth=p:GetNWInt("zsf_id"),
        native=p:GetNWString("zci_native"),nativeID=p:GetNWInt("zci_native_id"),cursor=1,target=t,
        creation=IsValid(t) and t:GetCreationID(),lastInput=CurTime()}
    if util.NetworkStringToID("zci_context_request")==0 then state.failure="Interactions are not ready" return false end
    net.Start("zci_context_request") net.WriteUInt(nonce,16) net.WriteEntity(t or NULL) net.SendToServer()
    return true
end
function I.OpenContextMenu()
    if state then I.CloseCircle() return end
    request(false,"shortcut")
end
I.OpenContextGroup=I.OpenContextMenu I.RequestContext=function()return request(false,"shortcut")end
concommand.Add("zci_menu",I.OpenContextMenu)
local function beginHold(automatic)
    local row=selected()
    if not row or row.reason~="" or invalid() then return end
    -- A recommended primary is always safe. Lethal alternatives require a new deliberate press.
    if automatic and (row.danger or not state.primary or state.order[state.cursor]~=state.primary) then return end
    state.held=true state.started=RealTime() state.failure=nil state.lastInput=CurTime()
    if row.danger then state.armDeadline=RealTime()+1.5 send(1) end
end
function I.CirclePress(source)
    if source~="use" then shortcutDown=true end
    if mustRelease or not inputReady() or I.CircleVictim(LocalPlayer()) then return true end
    if not state then request(true,source) return true end
    if state.held then return true end
    if invalid() or state.needsFresh or state.failure or not state.token then
        request(false,source) -- refresh never carries a dangerous hold into a new token
        return true
    end
    state.source=source or "shortcut" beginHold(false)
    return true
end
function I.CircleRelease(fromUse)
    if not fromUse then shortcutDown=false end
    mustRelease=false useStart=nil useTarget=nil
    if not state then return end
    if state.armDeadline or state.armedAt then state.needsFresh=true end
    state.held=false state.auto=false state.started=nil state.armedAt=nil state.armDeadline=nil
    state.lastInput=CurTime()
end
function I.CircleCycle(direction)
    if not state or not state.order or #state.order<2 then return end
    if state.held then I.CircleRelease() mustRelease=true end
    state.cursor=((state.cursor-1+direction)%#state.order)+1 state.lastInput=CurTime()
end
net.Receive("zci_context",function()
    local reply,token,t,count=net.ReadUInt(16),net.ReadUInt(32),net.ReadEntity(),net.ReadUInt(6)
    if count>48 then return end
    local rows={}
    for index=1,count do rows[index]={label=net.ReadString(),reason=net.ReadString(),group=net.ReadUInt(2),danger=net.ReadBool()} end
    local _,bits=net.BytesLeft()
    local primary=bits and bits>=6 and net.ReadUInt(6) or 0
    if not state or reply~=state.nonce then return end
    if state.token and state.token~=token then return end
    local hasValid=false
    for _,row in ipairs(rows) do if row.reason=="" then hasValid=true break end end
    -- Empty or fully unavailable catalogs stay invisible. The circle represents
    -- a usable action, not a "No actions here" status panel.
    if not hasValid then I.CloseCircle() return end
    if state.token then
        if #rows~=#state.rows then I.CloseCircle() return end
        for index,row in ipairs(rows) do
            if row.label~=state.rows[index].label or row.danger~=state.rows[index].danger then I.CloseCircle() return end
            state.rows[index].reason=row.reason
        end
        if selected() and selected().reason~="" and state.held then I.CircleRelease() mustRelease=true end
        return -- keep the chosen slot stable as availability changes
    end
    if state.creation and t~=state.target and state.hostage==0 and state.stealth==0 and state.native=="" then I.CloseCircle() return end
    state.token=token state.rows=rows state.target=t state.creation=IsValid(t) and t:GetCreationID()
    state.primary=rows[primary] and rows[primary].reason=="" and not rows[primary].danger and primary or nil
    local order={} for index in ipairs(rows) do order[#order+1]=index end
    table.sort(order,function(a,b)
        if a==state.primary or b==state.primary then return a==state.primary end
        local x,y=rows[a],rows[b]
        if (x.reason=="")~=(y.reason=="") then return x.reason=="" end
        if x.group~=y.group then return x.group<y.group end
        return a<b
    end)
    state.order=order state.cursor=1
    if state.auto and state.held then state.held=false beginHold(true) end
end)
net.Receive("zci_context_arm",function()
    local token,index=net.ReadUInt(32),net.ReadUInt(6)
    if state and state.held and state.armDeadline and not state.needsFresh and state.token==token
        and state.order[state.cursor]==index and RealTime()<=state.armDeadline then
        state.armedAt=RealTime() state.armDeadline=nil
    end
end)
hook.Add("PlayerBindPress","ZCityInteractions.CircleChoices",function(p,bind,pressed)
    if not state then return end
    if bind=="+menu" then I.CloseCircle() return end -- never claim Q or stop its handlers
    if not inputReady() then I.CloseCircle() return end
    if bind=="invnext" or bind=="invprev" then
        if pressed then I.CircleCycle(bind=="invnext" and 1 or -1) end
        return true -- weapon wheel is redirected only while this explicit chooser is open
    end
end)
hook.Add("Think","ZCityInteractions.ContextRefresh",function()
    local p=LocalPlayer()
    if not IsValid(p) then I.CloseCircle() return end
    local g=ZCityHostage and ZCityHostage.Gameplay
    local raw=g and g.UseInput
    local down=p:KeyDown(IN_USE)
    if raw and RealTime()-raw.time<.25 then down=raw.down end
    if not down and useWasDown then I.CircleRelease(true) end
    useWasDown=down
    if not inputReady() or I.CircleVictim(p) then I.CloseCircle() useStart=nil return end
    if input.IsKeyDown(KEY_ESCAPE) or modifiers(p) then
        if state then I.CloseCircle() end
        if down then mustRelease=true end
        return
    end
    if not down and not shortcutDown and not state then mustRelease=false end
    if down and not mustRelease and not useStart then
        local t=target()
        local active=p:GetNWInt("zch_session")~=0 or p:GetNWInt("zsf_id")~=0 or p:GetNWString("zci_native")~=""
        local eye=p:GetEyeTrace()
        if (t or state or active) and not carrying(p) then useStart=RealTime() useTarget=t end
    end
    if down and useStart and RealTime()-useStart>=.3 and not mustRelease then
        if carrying(p) then useStart=nil mustRelease=true return end
        if not state then
            if target()==useTarget then I.CirclePress("use") end
        elseif not state.held and not state.auto then I.CirclePress("use") end
        useStart=nil mustRelease=true -- one press per physical hold
    end
    if not state then return end
    local why=invalid()
    if why then I.CloseCircle() return end
    if not state.token then
        if CurTime()-state.requested>1.5 then
            state.failure="No response. Release and try again." state.held=false state.auto=false
        end
        return
    end
    local row=selected()
    if state.held and row then
        if state.armDeadline and RealTime()>state.armDeadline then
            I.CircleRelease() mustRelease=true state.needsFresh=true state.failure="Confirmation timed out. Release and retry." return
        end
        local start=state.started if row.danger then start=state.armedAt end
        if start and RealTime()-start>=(row.danger and .85 or .4) then
            send(row.danger and 2 or 0) I.CloseCircle() mustRelease=true return
        end
    elseif CurTime()-state.lastInput>6 then I.CloseCircle() return end
    if CurTime()>=(state.refreshAt or 0) then
        state.refreshAt=CurTime()+.5
        net.Start("zci_context_refresh") net.WriteUInt(state.token,32) net.SendToServer()
    end
end)
function I.CircleState()
    if not state then return end
    if state.failure then return "denied",state.failure,"Release and hold Use again" end
    if not state.token then return "checking","Reading target","Release to choose an alternative" end
    local row=selected()
    if not row then return "denied","No actions here","Try different equipment or a nearby target" end
    local hint=row.reason~="" and row.reason or state.needsFresh and "Release and press again to refresh"
        or state.held and (row.danger and "Confirming dangerous action · release to cancel" or "Keep holding · release to choose")
        or "Hold "..key("+use","Use").." or "..(I.QuickKey and I.QuickKey() or "M3").." · Wheel: change action"
    local start=state.started if row.danger then start=state.armedAt end
    local progress=state.held and start and math.Clamp((RealTime()-start)/(row.danger and .85 or .4),0,1) or nil
    return row.reason~="" and "denied" or row.danger and "danger" or state.held and "hold" or "ready",row.label,hint,progress,state.held
end
function I.CircleChoices()
    if not state or not state.order or #state.order<2 or state.held then return end
    local count=#state.order local index=state.cursor
    return state.rows[state.order[(index-2)%count+1]].label,state.rows[state.order[index%count+1]].label,index,count
end

function I.InteractionFeedback(p)
    local menu=key("+use","Use") local use=key("+use","Use") local release=key("+reload","Reload")
    local resist=use.." or "..key("+attack","Attack")
    local native=p:GetNWString("zci_native")
    if native=="disarm" or native=="legacy_neck" then
        local initiator=p:GetNWBool("zci_native_initiator")
        local title=native=="disarm" and (initiator and "Disarming" or "Being disarmed")
            or (initiator and "Neck-break" or "Neck-break attempt")
        local hint="Move away or attack the captor"
        if initiator then
            hint=p:GetNWBool("zci_native_contextual") and release..": cancel"
                or "Hold "..key("+walk","Walk").." + "..use.." · "..release..": cancel"
        end
        return title,hint,"Progress",p:GetNWFloat("zci_native_progress")
    end
    if native=="fiberwire" then
        local initiator=p:GetNWBool("zci_native_initiator")
        local hint=initiator and key("+attack","Primary attack")..": release" or "Hold "..resist.." to resist with usable, uncuffed hands"
        if not initiator and p.organism and p.organism.otrub then hint="Unconscious — unable to resist"
        elseif not initiator and not I.HandsAvailable(p) then hint="Resisting requires usable, uncuffed hands" end
        return "Fiberwire hold",hint,"Escape",p:GetNWFloat("zci_native_resist")
    end
    local g=ZCityHostage and ZCityHostage.Gameplay
    if g and g.Feedback and g.Role(p)~="" then
        local title,hint,label,progress=g.Feedback(p)
        -- Preserve gameplay guidance but do not direct interactions into native Q.
        if hint then hint=string.Replace(hint,key("+menu","action menu")..": actions",menu..": actions") end
        return title,hint,label,progress
    end
    local s=ZCityStealth
    if s and s.Mode(p)~="" then
        if p:GetNWBool("zsf_wire_switch",false) then return "Readying fiberwire",release..": cancel · Keep the target within reach" end
        local action=s.Actions[p:GetNWString("zsf_action")]
        local hint=p:GetNWBool("zsf_initiator") and release..": release · "..menu..": interact" or "Hold "..resist.." to escape"
        if s.Mode(p)=="attempt" then hint=p:GetNWBool("zsf_initiator") and "Reaching · "..release..": cancel" or "Move away or turn to face them · Hold "..resist.." to resist" end
        if not p:GetNWBool("zsf_initiator") then
            local strength=s.ResistanceStrength(p)
            if strength==0 then hint=p.organism and p.organism.otrub and "Unconscious — unable to resist" or "Unable to struggle with your current injuries"
            elseif strength<1 then hint=hint.." · Reduced strength" end
        end
        return action and action.label or "Interaction",hint,"Escape",p:GetNWFloat("zsf_resist")
    end
end
