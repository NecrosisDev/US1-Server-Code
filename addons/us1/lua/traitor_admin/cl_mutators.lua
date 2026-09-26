-- UI extension loaded by the picker, independent of the abnormality controls.
local Page = {}
local data
local WHITE, GREY = Color(255,255,255), Color(170,179,191)
local RED, BG, HOVER = Color(192,62,72), Color(42,48,58), Color(57,65,77)
local function Action(action, target, value)
    net.Start("traitoradmin_mutator_action")
    net.WriteString(action)
    net.WriteString(target or "")
    net.WriteString(tostring(value or ""))
    net.SendToServer()
end
function Page.Request() Action("get") end
net.Receive("traitoradmin_mutator_data", function()
    data = net.ReadTable()
    if IsValid(TraitorAdminFrame) and IsValid(TraitorAdminFrame.mutatorScroll) then
        Page.Refresh(TraitorAdminFrame)
    end
end)
local function Label(parent, y, text, height, bold)
    local p = vgui.Create("DLabel", parent)
    p.TraitorAdminLabel=true
    p:SetPos(12,y)
    p:SetSize(parent:GetWide()-24,height or 22)
    p:SetFont(bold and "DermaDefaultBold" or "DermaDefault")
    p:SetTextColor(bold and WHITE or GREY)
    p:SetWrap(true)
    p:SetText(text)
    return p
end
local function Button(parent, x, y, w, text, callback, active)
    local p = vgui.Create("DButton", parent)
    p:SetPos(x,y); p:SetSize(w,26)
    p:SetText(text); p:SetTextColor(WHITE); p:SetFont("DermaDefaultBold")
    p.Paint = function(s,pw,ph) draw.RoundedBox(4,0,0,pw,ph,active and Color(46,100,78) or (s:IsHovered() and HOVER or BG)) end
    p.DoClick = callback
    return p
end
local function Header(parent,y,text)
    Label(parent,y,text,24,true)
    return y+28
end
local function NumberRow(parent,y,label,value,lo,hi,decimals,save)
    local slider = vgui.Create("DNumSlider",parent)
    slider:SetPos(12,y); slider:SetSize(382,30)
    slider:SetText(label); slider:SetMin(lo); slider:SetMax(hi); slider:SetDecimals(decimals)
    slider:SetValue(value)
    if IsValid(slider.TextArea) then parent.AdminFrame:StyleInput(slider.TextArea, true) end
    Button(parent,402,y+2,94,"Save",function() save(slider:GetValue()) end)
    return y+36
end
function Page.Setup(frame)
    frame.mutatorSection = "Rounds"
    frame.mutatorNav = vgui.Create("DPanel", frame)
    frame.mutatorNav:SetPos(16,116); frame.mutatorNav:SetSize(frame:GetWide()-32,30)
    frame.mutatorNav.Paint=nil; frame.mutatorNav:SetVisible(false)
    for i,title in ipairs({"Rounds", "Special roles", "Automatic", "Mutation pool", "Tools"}) do
        local name=title
        local tab=Button(frame.mutatorNav,(i-1)*132,0,124,name,function()
            frame.mutatorSection=name
            frame.mutatorScroll:GetVBar():SetScroll(0)
            Page.Refresh(frame)
        end)
        tab.Paint=function(s,w,h) draw.RoundedBox(4,0,0,w,h,frame.mutatorSection==name and RED or (s:IsHovered() and HOVER or BG)) end
    end
    frame.mutatorScroll = vgui.Create("DScrollPanel",frame)
    frame.mutatorScroll:SetPos(16,154)
    frame.mutatorScroll:SetSize(frame:GetWide()-32,frame:GetTall()-214)
    frame.mutatorScroll:SetVisible(false)
end
function Page.Refresh(frame)
    local scroll=frame.mutatorScroll
    if not IsValid(scroll) then return end
    local oldScroll=scroll:GetVBar():GetScroll()
    scroll:Clear()
    local canvas=vgui.Create("DPanel",scroll)
    canvas.AdminFrame=frame
    canvas:SetWide(scroll:GetWide()-16); canvas.Paint=nil
    local y=6
    y=Header(canvas,y,"HOMICIDE / "..string.upper(frame.mutatorSection))
    if not data or not data.available then
        Label(canvas,y,data and data.message or "Loading mutation controls...",60)
        canvas:SetTall(y+70)
        return
    end
    local d=data
    Label(canvas,y,"Active: "..d.active.."   |   Next: "..d.queued,40,true); y=y+42
    Label(canvas,y,"Variant: "..d.variant.."   |   Waiting for roles/spawns: "..(d.waiting and "yes" or "no"),22); y=y+24
    if d.message~="" then Label(canvas,y,d.message,40,true); y=y+44 end
    if frame.mutatorSection=="Rounds" then
    y=Header(canvas,y,"NEXT COMPATIBLE ROUND")
    local combo=vgui.Create("DComboBox",canvas)
    frame:StyleInput(combo)
    combo:SetPos(12,y); combo:SetSize(330,26); combo:SetSortItems(false)
    frame.mutatorSelection=frame.mutatorSelection or d.queued
    combo:AddChoice("None (clear queue)","none",frame.mutatorSelection=="none")
    for _,def in ipairs(d.definitions) do
        combo:AddChoice(def.title.." ["..def.variants.."]",def.id,frame.mutatorSelection==def.id)
    end
    combo.OnSelect=function(_,_,_,id) frame.mutatorSelection=id end
    Button(canvas,350,y,146,"Queue selection",function() Action("next",frame.mutatorSelection or "none") end)
    y=y+32
    Button(canvas,12,y,160,"Clear next mutation",function() frame.mutatorSelection="none"; Action("next","none") end)
    Button(canvas,180,y,188,"Cancel current / waiting",function() Action("cancel") end,true)
    y=y+32
    Label(canvas,y,"Queues bypass chance and repeat cooldown. The master switch and mutation requirements still apply. Cancel leaves the next queue intact.",42); y=y+48
    y=Header(canvas,y,"START IN THIS ROUND")
    local current=vgui.Create("DComboBox",canvas)
    frame:StyleInput(current)
    current:SetPos(12,y); current:SetSize(330,26); current:SetSortItems(false)
    current:SetValue("Choose a mutation for this round...")
    local nowChoice, startNow, why
    for _,def in ipairs(d.definitions) do
        current:AddChoice(def.title .. (def.nowAllowed and "" or " (unavailable)"),def)
    end
    startNow=Button(canvas,350,y,146,"Start now",function()
        if nowChoice and nowChoice.nowAllowed then Action("now",nowChoice.id,d.nowToken) end
    end)
    startNow:SetEnabled(false)
    y=y+32
    why=Label(canvas,y,"Choose a mutation to see whether it can start now.",48); y=y+52
    current.OnSelect=function(_,_,_,def)
        nowChoice=def
        startNow:SetEnabled(d.midRoundSupport == true and def.nowAllowed == true)
        why:SetText(def.nowReason or "Update zc_hmcd_mutators for mid-round controls.")
    end
    Label(canvas,y,"Applies to living players now and announces Mid Round Mutation. One mutation per round; no stacking. Next-round queue stays saved. Postmortem affects future deaths only. Special-role picks apply at activation.",64); y=y+70
    Button(canvas,12,y,180,"Refresh availability",function() Page.Request() end); y=y+34
    y=Header(canvas,y,"AVAILABLE MUTATIONS")
    for _,def in ipairs(d.definitions) do
        Label(canvas,y,def.title.."  /  "..def.variants,24,true); y=y+26
        Label(canvas,y,def.description,40); y=y+42
        Label(canvas,y,"Current eligibility: "..def.reason,22); y=y+30
    end
    end
    if frame.mutatorSection=="Special roles" then
    y=Header(canvas,y,"NEXT SPECIAL ROLE PLAYER")
    Label(canvas,y,"Queue the matching mutation above, then pick its recipient here. Picks apply once when that mutation activates, including Start now, and keep normal role requirements.",52); y=y+56
    if not d.roleSupport then Label(canvas,y,"Update zc_hmcd_mutators to enable special-role selection.",40); y=y+44 end
    for _,role in ipairs(d.specialRoles or {}) do
        local item=role
        Label(canvas,y,item.title.." ["..item.mutation.."]  |  Queued: "..item.name,40,true); y=y+44
        Label(canvas,y,item.status,40); y=y+44
        local selected=item.queued
        local players=vgui.Create("DComboBox",canvas)
    frame:StyleInput(players)
        players:SetPos(12,y); players:SetSize(330,26); players:SetSortItems(false)
        players:SetValue(item.name)
        players:AddChoice("Random (clear pick)","none",selected=="none")
        for _,p in ipairs(d.rolePlayers or {}) do
            players:AddChoice(p.name.." ["..p.id.."]",p.id,selected==p.id)
        end
        players.OnSelect=function(_,_,_,id) selected=id end
        Button(canvas,350,y,146,"Save role pick",function() Action("role_pick",item.id,selected) end)
        y=y+32
    end
    Label(canvas,y,"Disconnected/ineligible picks stay queued and block that mutation until eligible or cleared. Refresh to update players. Picks survive addon reload, but clear on map change/server restart.",52); y=y+56
    Button(canvas,12,y,180,"Refresh role players",function() Page.Request() end); y=y+32
    end
    if frame.mutatorSection=="Automatic" then
    y=Header(canvas,y,"SAVED SERVER SETTINGS")
    Button(canvas,12,y,230,d.settings.enabled==1 and "Framework: ON" or "Framework: OFF",function() Action("setting","enabled",d.settings.enabled==1 and 0 or 1) end,d.settings.enabled==1)
    Button(canvas,250,y,246,d.settings.auto==1 and "Automatic rolls: ON" or "Automatic rolls: OFF",function() Action("setting","auto",d.settings.auto==1 and 0 or 1) end,d.settings.auto==1)
    y=y+34
    y=NumberRow(canvas,y,"Roll chance (%)",d.settings.chance,0,100,1,function(v) Action("setting","chance",v) end)
    y=NumberRow(canvas,y,"Repeat cooldown (rounds)",d.settings.cooldown,0,20,0,function(v) Action("setting","cooldown",math.Round(v)) end)
    y=NumberRow(canvas,y,"Role/spawn wait (seconds)",d.settings.timeout,5,300,0,function(v) Action("setting","timeout",math.Round(v)) end)
    Label(canvas,y,"Saved settings survive restarts. Chance applies once per eligible HMCD round with automatic rolls ON; each mutation lists its supported round variants below.",42); y=y+48
    end
    if frame.mutatorSection=="Mutation pool" then
    y=Header(canvas,y,"MUTATION POOL")
    for _,def in ipairs(d.definitions) do
        local item=def
        Label(canvas,y,item.title.."  ["..item.variants.."]",24,true); y=y+26
        Label(canvas,y,item.description,40); y=y+42
        Label(canvas,y,"Current eligibility: "..item.reason,22); y=y+24
        Button(canvas,12,y,150,item.enabled and "Enabled: ON" or "Enabled: OFF",function() Action("module_enabled",item.id,item.enabled and 0 or 1) end,item.enabled)
        y=y+32
        y=NumberRow(canvas,y,"Selection weight",item.weight,0,100,2,function(v) Action("module_weight",item.id,v) end)
    end
    Label(canvas,y,"Weights affect the automatic pool. Weight 0 excludes an automatic pick; admins may still queue it. Changes affect future selections.",40); y=y+46
    end
    if frame.mutatorSection=="Tools" then
    y=Header(canvas,y,"SAVED MAP POINTS")
    local group=vgui.Create("DComboBox",canvas)
    frame:StyleInput(group)
    group:SetPos(12,y); group:SetSize(330,26); group:SetSortItems(false)
    local selectedGroup=d.group or "altar"
    local found=false
    for _, item in ipairs(d.pointGroups or {{id="altar",title="Altars"}}) do
        local selected=item.id==selectedGroup
        group:AddChoice(item.title.." ["..item.id.."]",item.id,selected)
        if selected then found=true end
    end
    if not found then group:AddChoice(selectedGroup,selectedGroup,true) end
    local add, remove
    group.OnSelect=function(_,_,_,id)
        selectedGroup=id
        -- Do not let old point indices or coordinates act on a newly chosen type
        -- until the server has returned that group's list.
        if IsValid(add) then add:SetEnabled(false) end
        if IsValid(remove) then remove:SetEnabled(false) end
        Action("point_list",selectedGroup)
    end
    Button(canvas,350,y,146,"Load group",function() Action("point_list",selectedGroup) end)
    y=y+32
    local coords=vgui.Create("DTextEntry",canvas)
    frame:StyleInput(coords, true)
    coords:SetPos(12,y); coords:SetSize(300,26)
    coords:SetPlaceholderText("Optional x y z yaw; blank = crosshair")
    add=Button(canvas,320,y,176,"Add saved point",function() Action("point_add",d.group,coords:GetValue()) end)
    y=y+32
    local point=vgui.Create("DComboBox",canvas)
    frame:StyleInput(point)
    point:SetPos(12,y); point:SetSize(330,26); point:SetSortItems(false)
    point:SetValue(#d.points==0 and "No saved points in this group" or "Select a saved point...")
    local selectedPoint
    for i,p in ipairs(d.points) do point:AddChoice(string.format("#%d  %.0f %.0f %.0f  yaw %.0f",i,p.x,p.y,p.z,p.yaw),i) end
    point.OnSelect=function(_,_,_,index) selectedPoint=index end
    remove=Button(canvas,350,y,146,"Remove selected",function()
        if selectedPoint then Action("point_remove",d.group,selectedPoint) end
    end)
    remove:SetEnabled(#d.points>0)
    y=y+32
    Label(canvas,y,"Point types include saved map groups and types declared by mutations. Adding a point only saves a location; it does not spawn anything.",40); y=y+46
    y=Header(canvas,y,"COMMANDS")
    Button(canvas,12,y,150,"Status to console",function() Action("status") end)
    Button(canvas,170,y,150,"List to console",function() Action("list") end)
    Button(canvas,328,y,168,"Active info to console",function() RunConsoleCommand("zc_mutator_info") end)
    y=y+32
    Button(canvas,12,y,236,"Show my announcements",function() RunConsoleCommand("zc_mutators_hud","1") end)
    Button(canvas,256,y,240,"Hide my announcements",function() RunConsoleCommand("zc_mutators_hud","0") end)
    y=y+34
    Label(canvas,y,"Command reference (select text to copy). Server convars are changed with the saved controls above or the server console.",40); y=y+44
    local lines={
        "zc_mutator_role <role> <SteamID64|none>", "zc_mutator_roles",
        "zc_mutator_now <id>", "zc_mutator_status", "zc_mutator_list", "zc_mutator_next <id|none>", "zc_mutator_cancel",
        "zc_mutator_point_add <group> [x y z yaw]", "zc_mutator_point_list <group>", "zc_mutator_point_remove <group> <index>",
        "zc_mutator_info  (client console)", "zc_mutators_hud <0|1>  (client console)",
        "zc_mutators_enabled <0|1>", "zc_mutators_auto <0|1>", "zc_mutators_chance <0..1>  (0.25 = 25%)",
        "zc_mutators_cooldown <0..20>", "zc_mutators_ready_timeout <5..300>"
    }
    for _,def in ipairs(d.definitions) do
        lines[#lines+1]="zc_mutator_"..def.id.."_enabled <0|1>"
        lines[#lines+1]="zc_mutator_"..def.id.."_weight <0..100>"
    end
    for _,def in ipairs(d.definitions) do
        if def.id=="informant" then
            for _,line in ipairs({"zc_mutator_informant_status", "zc_mutator_phone_status (client console)",
                "zc_mutator_informant_hint <0|1|2>", "zc_mutator_informant_interval <5..600>",
                "zc_mutator_informant_delay <5..900>", "zc_mutator_informant_ring_time <5..60>",
                "zc_mutator_informant_call_time <4..30>"}) do lines[#lines+1]=line end
        end
    end
    local reference=vgui.Create("DTextEntry",canvas)
    frame:StyleInput(reference, true)
    reference:SetPos(12,y); reference:SetSize(484,math.max(290,#lines*17+12))
    reference:SetMultiline(true); reference:SetEditable(false); reference:SetText(table.concat(lines,"\n"))
    y=y+reference:GetTall()+12
    end
    -- Preserve compact row proportions while using the available window width.
    -- Labels already use the full width and do not need horizontal scaling.
    local scale=(canvas:GetWide()-24)/484
    for _, control in ipairs(canvas:GetChildren()) do
        if not control.TraitorAdminLabel then
            local x,cy=control:GetPos()
            control:SetPos(12+(x-12)*scale,cy)
            control:SetWide(control:GetWide()*scale)
        end
    end
    canvas:SetTall(y)
    scroll:InvalidateLayout(true)
    scroll:GetVBar():SetScroll(oldScroll)
end
return Page
