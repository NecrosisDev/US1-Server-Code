local S=ZCityStealth
local menu
local function command(id) RunConsoleCommand("zsf_action",id) end
local function key(commandName,fallback)
    local bound=input.LookupBinding(commandName)
    return bound and string.upper(bound) or fallback
end
local function compatible(action)
    if not ZCityInteractions.ClientHasAction(action.id) then return false end
    local kind=S.WeaponKind(LocalPlayer())
    return S.WeaponMatches(action,kind)
end
concommand.Add("zsf_menu",function()
    if ZCityInteractions.ContextUI then RunConsoleCommand("zci_menu") return end
    if IsValid(menu) then menu:Remove() end
    menu=vgui.Create("DFrame")
    menu:SetSize(math.min(570,ScrW()-40),math.min(700,ScrH()-40))
    menu:Center() menu:SetTitle("Stealth actions") menu:MakePopup()
    local help=vgui.Create("DLabel",menu)
    help:Dock(TOP) help:SetTall(64) help:SetWrap(true)
    help:SetText("Look at your target. Takedowns need a clear approach from behind; aerial attacks need height. Hands handle bodies. R releases an action; E resists. Bind zsf_menu to a free key for quick access.")
    local list=vgui.Create("DScrollPanel",menu) list:Dock(FILL)
    local function button(label,id,enabled,tooltip)
        local b=vgui.Create("DButton",list)
        b:Dock(TOP) b:DockMargin(0,0,0,5) b:SetTall(34) b:SetText(label) b:SetEnabled(enabled)
        if tooltip then b:SetTooltip(tooltip) end
        b.DoClick=function() command(id) menu:Remove() end
    end
    local current=S.Actions[LocalPlayer():GetNWString("zsf_action")]
    if LocalPlayer():GetNWString("zci_native")=="disarm" then
        if LocalPlayer():GetNWBool("zci_native_initiator") then
            help:SetText("Disarming the selected player. Stay close; "..key("+reload","Reload").." cancels.")
            button("Cancel disarm","release",true)
        else help:SetText("Someone is trying to disarm you. Move away or break their grip.") end
        return
    end
    if LocalPlayer():GetNWString("zci_native")=="fiberwire" and not LocalPlayer():GetNWBool("zci_native_initiator") then
        help:SetText("You are caught in fiberwire. Close this menu and hold "..key("+use","your Use key").." to resist while conscious with usable hands. Injury to the wielder can break the grip.")
        return
    end
    local weapon=LocalPlayer():GetActiveWeapon()
    if IsValid(weapon) and weapon:GetClass()=="weapon_zc_fiberwire_standalone" and weapon.GetStrangling and weapon:GetStrangling() then
        help:SetText("You are holding the wire. Release here or press your primary attack key. Dropping it, losing your grip, injury or the round ending interrupts the hold.")
        button("Release fiberwire","release",true)
        return
    end
    if S.Mode(LocalPlayer())~="" then
        if not LocalPlayer():GetNWBool("zsf_initiator") then
            help:SetText("You are being held. Close this menu and hold your Use key (normally E) to resist. The progress bar shows your escape progress.")
            button("Struggle","resist",true)
            return
        else
            button("Release / cancel","release",true)
            if current and current.finish then button("Finish interrogation","finish",true) end
            if current and current.throw then button("Throw carried body / held object","throw",true) end
            if current and (current.turn or current.left) then button("Turn left","turn_left",true) button("Turn right","turn_right",true) end
        end
    end
    local sorted={} for _,action in pairs(S.Actions) do sorted[#sorted+1]=action end
    table.sort(sorted,function(a,b) return a.kind==b.kind and a.label<b.label or a.kind<b.kind end)
    for _,action in ipairs(sorted) do
      if not current and ZCityInteractions.ClientHasAction(action.id) then
        local equipment=action.weapon=="either" and "Hands or knife" or action.weapon=="knife" and "Knife" or action.weapon=="wire" and "Fiberwire" or "Hands"
        button(action.label.."  ·  "..equipment,action.id,compatible(action),"Console: zsf_action "..action.id)
      end
    end
end, nil, "Open the stealth actions menu (the interaction circle when it is on).")
concommand.Add("zsf_finish",function()
    if LocalPlayer():GetNWString("zsf_action")=="interrogate" then command("finish") return end
    local kind=S.WeaponKind(LocalPlayer())
    command(kind=="wire" and "fiberwire" or kind=="knife" and "neck_stab" or "chop")
end, nil, "Stealth: finish the current takedown or interrogation.")
concommand.Add("zsf_release",function() command("release") end, nil, "Stealth: release the player you hold.")
concommand.Add("zsf_carry",function() command("carry") end, nil, "Stealth: carry the body you hold.")
concommand.Add("zsf_drag",function() command("drag") end, nil, "Stealth: drag the body you hold.")
concommand.Add("zsf_roll",function(_,_,args) command("roll_"..(args[1] or "forward")) end, nil, "Stealth: roll: zsf_roll [forward|back|left|right].")
timer.Create("ZCityStealth.Ready",2,0,function()
    local p=LocalPlayer()
    if not IsValid(p) then return end
    if util.NetworkStringToID("zsf_ready")==0 or not S.SeamsReady() then return end
    local token=S.Version..":"..p:GetModel()
    if p:GetNWString("zsf_ready_ack")==token then return end
    for _,clip in pairs(S.Assets.clips) do
        local id,d=p:LookupSequence(clip.sequence)
        if not id or id<0 or not d or d<=0 then return end
    end
    net.Start("zsf_ready") net.WriteString(token) net.SendToServer()
end)
concommand.Add("zsf_help",function()
    chat.AddText(Color(231,171,77),"Interactions: ",color_white,key("+menu","Action menu").." → Interact. Look at a player or body before opening. Your equipment and approach determine the actions. "..key("+reload","Reload").." releases; hold "..key("+use","Use").." to resist. Direct zsf commands remain optional shortcuts.")
end, nil, "Print the interaction key hints in chat.")
hook.Add("HUDPaint","ZCityStealth.Help",function()
    if ZCityInteractions.ContextUI then return end
    local p=LocalPlayer()
    if not IsValid(p) then return end
    if S.Mode(p)=="" then
        local cv=GetConVar("zsf_enabled")
        if not cv or not cv:GetBool() or not S.WeaponKind(p) or p:GetNWString("hg_CustomAnim","")~="" then return end
        local target=p:GetEyeTrace().Entity
        if not IsValid(target) or (not target:IsPlayer() and not target:IsRagdoll()) or p:GetPos():DistToSqr(target:GetPos())>90*90 then return end
        local hint=target:IsRagdoll() and "Body actions: type !stealth" or key("zsf_finish","Bind zsf_finish")..": takedown from behind  ·  !stealth: all actions"
        draw.SimpleTextOutlined(hint,"DermaDefaultBold",ScrW()/2,ScrH()*.78,Color(240,238,225),TEXT_ALIGN_CENTER,TEXT_ALIGN_TOP,1,Color(0,0,0,220))
        return
    end
    local action=S.Actions[p:GetNWString("zsf_action")]
    local label=action and action.label or "Stealth"
    local partner=p:GetNWEntity("zsf_partner")
    local victim=IsValid(partner) and partner:GetNWBool("zsf_initiator",false)
    local hint=victim and "Hold "..key("+use","E").." to resist" or key("+reload","R")..": release  ·  "..key("zsf_menu","!stealth")..": actions"
    if S.Mode(p)=="attempt" then hint="Reaching for target — the attempt can still be evaded" end
    local w,h=440,64 local x,y=(ScrW()-w)/2,ScrH()*.78
    draw.RoundedBox(7,x,y,w,h,Color(15,19,24,225))
    draw.SimpleText(label,"DermaDefaultBold",ScrW()/2,y+10,Color(240,238,225),TEXT_ALIGN_CENTER)
    draw.SimpleText(hint,"DermaDefault",ScrW()/2,y+30,Color(210,218,225),TEXT_ALIGN_CENTER)
    local progress=p:GetNWFloat("zsf_resist",0)
    if progress>0 then draw.RoundedBox(2,x+12,y+h-9,(w-24)*progress,4,Color(231,171,77)) end
end)
