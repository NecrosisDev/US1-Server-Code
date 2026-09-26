local G=ZCityHostage.Gameplay
local struggling=false
local nextPulse=0
local confirmation
local function action(name,arg) RunConsoleCommand("zch_action",name,tostring(arg or "")) end
local function binding(command,fallback)
    local key=input.LookupBinding(command)
    return key and string.upper(key) or fallback
end
local function partner(p) return p:GetNWEntity("zch_partner") end
local function isInitiator(p) return p:GetNWInt("zch_initiator")==p:EntIndex() end

-- Presentation only. The server revalidates every request.
function G.MenuOptions(p,t)
    local options={}
    local function add(label,name,danger) options[#options+1]={label=label,action=name,danger=danger,target=t} end
    local role,phase=G.Role(p),p:GetNWString("zch_phase")
    if role=="victim" then
        add(struggling and "Stop struggling" or "Struggle to escape","struggle_toggle")
    elseif role=="captor" then
        add("Release hostage","release")
        local w=p:GetActiveWeapon()
        if phase=="hold" and IsValid(w) and w:Clip1()>0 then t=partner(p) add("Prepare to shoot hostage...","execute",true) end
    elseif role=="surrender" or role=="restrained" then
        add(G.Cuffed(p) and "Stand up" or "Stand up / stop surrendering","stand")
        if G.Cuffed(p) and phase~="posture_entry" and phase~="stand_up" then
            if phase~="kneeling" then add("Kneel","kneel") end
            if phase~="lying" then add("Lie down","lie") end
        end
    elseif role=="attempt" then
        if isInitiator(p) then add("Cancel grab","release") end
    elseif p:OnGround() and not p:Crouching() then
        add(G.Cuffed(p) and "Kneel" or "Surrender (kneel)","surrender")
        if not IsValid(t) or not t:IsPlayer() or t==p or not t:Alive() or G.Cuffed(p) then return options end
        if p:GetPos():DistToSqr(t:GetPos())>G.Reach(p,t)^2 then return options end
        local targetPhase=t:GetNWString("zch_phase")
        if G.Cuffed(t) then
            if targetPhase~="posture_entry" and targetPhase~="stand_up" then
                if targetPhase~="kneeling" then add("Make kneel","order_kneel") end
                if targetPhase~="lying" then add("Make lie down","order_lie") end
            end
        elseif targetPhase=="" then add("Ask to kneel","order_kneel") end
        local w=p:GetActiveWeapon()
        if not IsValid(w) then return options end
        local busy=G.Role(t)~="" and G.Role(t)~="surrender" and G.Role(t)~="restrained"
        if G.IsPistol(w) and not busy then
            local key=input.LookupBinding("+zci_action")
            add(key and ("Grab hostage ["..string.upper(key).."]") or "Grab hostage","grab")
            if targetPhase=="kneeling" and w:Clip1()>0 then add("Prepare to shoot hostage...","execute",true) end
        end
        if w:GetClass()=="weapon_handcuffs" and not G.Cuffed(t)
            and (targetPhase=="kneeling" or (G.Role(t)=="victim" and targetPhase=="hold")) then add("Apply handcuffs","cuff") end
    end
    return options
end

local function confirmShot(t)
    local p=LocalPlayer()
    if not IsValid(p) or not IsValid(t) or not t:IsPlayer() or not t:Alive() then return end
    if IsValid(confirmation) then confirmation:Remove() end
    local session=p:GetNWInt("zch_session")
    local panel=vgui.Create("DFrame") confirmation=panel
    panel:SetSize(math.min(420,ScrW()-20),175) panel:Center() panel:SetTitle("Shoot hostage") panel:MakePopup()
    local label=vgui.Create("DLabel",panel)
    label:Dock(TOP) label:SetTall(50) label:SetWrap(true)
    label:SetText("Target: "..t:Nick().."\nHold the button to commit. Closing this window cancels.")
    local fire=vgui.Create("DButton",panel)
    fire:Dock(TOP) fire:SetTall(40) fire:SetText("Hold to commit shot")
    local held,sent
    fire.OnMousePressed=function(_,button) if button==MOUSE_LEFT then held=RealTime() end end
    fire.OnMouseReleased=function() held=nil end
    fire.Think=function(self)
        if sent then return end
        if not system.HasFocus() or not IsValid(t) or not t:Alive() or not IsValid(p) or not p:Alive()
            or p:GetNWInt("zch_session")~=session then panel:Close() return end
        if not self:IsHovered() or not input.IsMouseDown(MOUSE_LEFT) then held=nil end
        local progress=held and math.Clamp((RealTime()-held)/0.8,0,1) or 0
        self:SetText(progress>0 and ("Hold to commit: "..math.floor(progress*100).."%") or "Hold to commit shot")
        if progress>=1 then sent=true action("execute",t:EntIndex()) panel:Close() end
    end
    local cancel=vgui.Create("DButton",panel)
    cancel:Dock(TOP) cancel:SetTall(28) cancel:SetText("Cancel")
    cancel.DoClick=function() panel:Close() end
end
concommand.Add("+zch_struggle",function() struggling=true nextPulse=0 end)
concommand.Add("-zch_struggle",function() struggling=false action("struggle","0") end)
for _,name in ipairs({"grab","release","surrender","cuff","kneel","lie","stand"}) do
    concommand.Add("zch_"..name,function() action(name) end)
end
concommand.Add("zch_execute",function()
    local p=LocalPlayer()
    if IsValid(p) then confirmShot(G.Role(p)=="captor" and partner(p) or p:GetEyeTrace().Entity) end
end)
-- Diagnostics only: acknowledgements never decide target eligibility.
timer.Create("ZCityHostage.Ready",2,0,function()
    local p=LocalPlayer()
    if not IsValid(p) or p:GetNWString("zch_ready_ack")==G.ReadyToken(p) then return end
    local id,duration=p:LookupSequence(G.Clips.holdA)
    if G.SeamsReady() and id and id>=0 and duration and duration>0 and file.Exists("models/zcity_hostage/gameplay_male.mdl","GAME")
        and file.Exists("models/zcity_hostage/gameplay_female.mdl","GAME") then RunConsoleCommand("zch_ready",G.Version) end
end)
hook.Add("Think","ZCityHostage.StruggleInput",function()
    local p=LocalPlayer()
    if not IsValid(p) then return end
    if G.Role(p)~="victim" or not system.HasFocus() then struggling=false end
    if struggling and RealTime()>=nextPulse then action("struggle","1") nextPulse=RealTime()+0.2 end
end)
hook.Add("radialOptions","ZCityHostage.Actions",function()
    if ZCityInteractions.ContextUI then return end
    local p=LocalPlayer() local cv=GetConVar("zch_gameplay_enabled")
    if not cv or not cv:GetBool() or not IsValid(p) or not p:Alive() then return end
    for _,option in ipairs(G.MenuOptions(p,p:GetEyeTrace().Entity)) do
        local choice=option
        hg.radialOptions[#hg.radialOptions+1]={function()
            if choice.danger then confirmShot(choice.target)
            elseif choice.action=="struggle_toggle" then struggling=not struggling nextPulse=0
            else action(choice.action) end
        end,choice.label}
    end
end)

function G.Feedback(p)
    local role,phase=G.Role(p),p:GetNWString("zch_phase")
    local menu=binding("+menu","action menu")
    local release=binding("+reload","Reload")
    local use=binding("+use","Use")
    if role=="attempt" then
        if p:GetNWString("zch_kind")=="cuff" then
            if isInitiator(p) then return "Attempting restraint",release..": cancel",nil end
            return "Someone is trying to cuff you","Move away or turn to evade; hold "..use.." to resist if caught",nil
        end
        if isInitiator(p) then return "Attempting grab",release..": cancel",nil end
        return "Someone is grabbing you","Move away to evade; hold "..use.." to resist if caught",nil
    end
    if role=="victim" then
        if phase=="handoff" then return "Captor is changing weapons","Hold "..use.." to escape | "..menu..": actions","Escape",p:GetNWFloat("zch_escape") end
        return phase=="execute" and "Captor is preparing to shoot!" or phase=="cuffing" and "You are being handcuffed" or "You are being held",
            "Hold "..use.." to escape | "..menu..": actions","Escape",p:GetNWFloat("zch_escape")
    end
    if role=="captor" then
        -- v2: R no longer releases a hold; release is the held-Use circle's danger row.
        if G.V2(p) and p:GetNWString("zch_kind")=="hold" then release="Hold "..use end
        if phase=="handoff" then return p:GetNWString("zch_handoff")=="wire" and "Switching to fiberwire" or "Switching to knife control",release..": release","Hostage escape",p:GetNWFloat("zch_escape") end
        local title=phase=="cuffing" and "Applying handcuffs" or phase=="execute" and "Preparing to shoot" or phase=="release" and "Releasing hostage" or "Holding hostage"
        local hint=release..": release | "..menu..": actions"
        if phase=="hold" then
            if p:GetNWBool("zch_aim_v1",false) then
                local mode=G.AimMode(p,p:GetActiveWeapon())
                title=mode=="self" and "Gun aimed at yourself" or mode=="ads" and "Aiming down sights" or "Gun aimed at hostage"
            end
            hint=hint.." | "..binding("+forward","Forward").."/"..binding("+back","Back").."/"..binding("+moveleft","Left").."/"..binding("+moveright","Right")..": escort | "..binding("+attack","Attack")..": fire"
        end
        if phase=="cuffing" then
            local start,finish=p:GetNWFloat("zch_phase_start"),p:GetNWFloat("zch_phase_end")
            return title,hint,"Applying cuffs",math.Clamp((CurTime()-start)/math.max(finish-start,0.01),0,1)
        end
        return title,hint,"Hostage escape",p:GetNWFloat("zch_escape")
    end
    if role=="surrender" or role=="restrained" then
        local cuffed=G.Cuffed(p)
        local title=phase=="lying" and "Lying down" or phase=="standing" and "Standing" or "Kneeling"
        if phase=="posture_entry" or phase=="stand_up" then
            local start,finish=p:GetNWFloat("zch_phase_start"),p:GetNWFloat("zch_phase_end")
            return phase=="stand_up" and "Standing up" or "Changing posture","Keep still until the transition finishes","Posture",math.Clamp((CurTime()-start)/math.max(finish-start,.01),0,1)
        end
        local hint=(phase~="standing" and (release..": stand up | ") or "").."Hold "..use..": posture / actions"
        if G.CanUseCuffKey(p) then hint=hint.." | "..binding("+attack","Attack")..": unlock cuffs" end
        return title..(cuffed and " · cuffed" or " · surrendering"),hint,nil
    end
    local t=p:GetEyeTrace().Entity
    if IsValid(t) and t:IsPlayer() and t~=p and t:Alive() then
        if p:GetPos():DistToSqr(t:GetPos())>G.Reach(p,t)^2 then return "Player interaction","Move closer to interact",nil end
        for _,option in ipairs(G.MenuOptions(p,t)) do
            if option.action=="grab" then
                local key=input.LookupBinding("zch_grab")
                return "Grab hostage",key and (string.upper(key)..": grab now | "..menu..": other actions")
                    or ("Quick grab: bind a free key to zch_grab | "..menu..": actions"),nil
            end
        end
        return "Player interaction",menu..": surrender or interact | Grab from behind or after surrender",nil
    end
end
local fontScale
hook.Add("HUDPaint","ZCityHostage.Feedback",function()
    if ZCityInteractions.ContextUI then return end
    local p=LocalPlayer() local cv=GetConVar("zch_gameplay_enabled")
    if not cv or not cv:GetBool() or not IsValid(p) or not p:Alive() then return end
    local title,hint,label,amount=G.Feedback(p)
    if not title then return end
    local scale=math.Clamp(ScrH()/1080,0.8,1.3)
    if fontScale~=scale then
        fontScale=scale
        surface.CreateFont("ZCH.Title",{font="Roboto",size=math.floor(20*scale),weight=600})
        surface.CreateFont("ZCH.Hint",{font="Roboto",size=math.floor(15*scale),weight=500})
    end
    local width=math.min(ScrW()*0.9,820*scale)
    local x,y=(ScrW()-width)/2,ScrH()*0.70
    local height=(label and 103 or 72)*scale
    draw.RoundedBox(6,x,y,width,height,Color(15,18,23,225))
    draw.SimpleText(title,"ZCH.Title",ScrW()/2,y+10*scale,Color(255,235,200),TEXT_ALIGN_CENTER)
    surface.SetFont("ZCH.Hint")
    while #hint>0 and surface.GetTextSize(hint)>width-24*scale do hint=string.sub(hint,1,-2) end
    draw.SimpleText(hint,"ZCH.Hint",ScrW()/2,y+38*scale,Color(245,245,245),TEXT_ALIGN_CENTER)
    if label then
        draw.SimpleText(label,"ZCH.Hint",x+12*scale,y+60*scale,Color(235,235,235))
        surface.SetDrawColor(55,60,67,255) surface.DrawRect(x+12*scale,y+83*scale,width-24*scale,7*scale)
        surface.SetDrawColor(235,170,65,255) surface.DrawRect(x+12*scale,y+83*scale,(width-24*scale)*math.Clamp(amount or 0,0,1),7*scale)
    end
end)
