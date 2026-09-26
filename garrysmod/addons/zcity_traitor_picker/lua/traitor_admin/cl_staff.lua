-- Rotation, native spawn tools, event staging, and curated gameplay countdowns.
local Page={}
local snapshots={}
local WHITE,MUTED,BG,HOVER,ACCENT=Color(245,247,250),Color(170,179,191),Color(42,48,58),Color(57,65,77),Color(192,62,72)
local function Action(page,action,target,value)
    net.Start("traitoradmin_staff_action")
    net.WriteString(page); net.WriteString(action); net.WriteString(target or ""); net.WriteString(tostring(value or "")); net.SendToServer()
end
local function category(frame)
    if frame.curTab==5 then return "events" end
    if frame.curTab==6 then return "timers" end
    if frame.curTab==2 and frame.staffSection~="overview" then return frame.staffSection end
end
function Page.Request(frame)
    local key=category(frame)
    if key then Action(key,"get") end
end
local function label(parent,y,text,height,bold)
    local p=vgui.Create("DLabel",parent)
    p:SetPos(12,y); p:SetSize(parent:GetWide()-24,height or 24)
    p:SetText(text); p:SetWrap(true); p:SetFont(bold and "DermaDefaultBold" or "DermaDefault"); p:SetTextColor(bold and WHITE or MUTED)
    return p
end
local function button(parent,x,y,w,text,fn,danger)
    local p=vgui.Create("DButton",parent); p:SetPos(x,y); p:SetSize(w,30)
    p:SetText(text); p:SetFont("DermaDefaultBold"); p:SetTextColor(WHITE)
    p.Paint=function(s,pw,ph) draw.RoundedBox(4,0,0,pw,ph,danger and ACCENT or (s:IsHovered() and HOVER or BG)) end
    p.DoClick=fn; return p
end
local function confirm(message,fn)
    Derma_Query(message,"Confirm staff action","Confirm",fn,"Cancel",function() end)
end
local function entry(frame,parent,x,y,w,value,placeholder)
    local p=vgui.Create("DTextEntry",parent); frame:StyleInput(p,true)
    p:SetPos(x,y); p:SetSize(w,30); p:SetValue(tostring(value or "")); p:SetPlaceholderText(placeholder or "")
    return p
end
function Page.Setup(frame)
    frame.staffSection="overview"
    frame.staffNav=vgui.Create("DPanel",frame); frame.staffNav:SetPos(16,116); frame.staffNav:SetSize(frame:GetWide()-32,30)
    frame.staffNav.Paint=nil; frame.staffNav:SetVisible(false)
    for i,item in ipairs({{"overview","Overview"},{"rotation","Rotation"},{"modevotes","Mode votes"},{"spawns","Spawn points"},{"karma","My karma"},{"restarts","Restarts"}}) do
        local id=item[1]
        local cell=(frame.staffNav:GetWide()+8)/6
        local b=button(frame.staffNav,(i-1)*cell,0,cell-8,item[2],function() frame.staffSection=id; frame:SetTab(2) end)
        b.Paint=function(s,w,h) draw.RoundedBox(4,0,0,w,h,frame.staffSection==id and ACCENT or (s:IsHovered() and HOVER or BG)) end
    end
    frame.staffScroll=vgui.Create("DScrollPanel",frame)
    frame.staffScroll:SetPos(16,154); frame.staffScroll:SetSize(frame:GetWide()-32,frame:GetTall()-214); frame.staffScroll:SetVisible(false)
    frame.staffScroll.Think=function(s)
        if frame.curTab==6 and s:IsVisible() and (frame.staffNextPoll or 0)<CurTime() then
            frame.staffNextPoll=CurTime()+1; Page.Request(frame)
        end
    end
end
function Page.SetTab(frame)
    local key=category(frame)
    frame.staffNav:SetVisible(frame.curTab==2)
    local top=frame.curTab==2 and 154 or 116
    frame.staffScroll:SetPos(16,top); frame.staffScroll:SetTall(frame:GetTall()-top-60)
    frame.staffScroll:SetVisible(key~=nil)
    if key then frame.staffNextPoll=CurTime()+1; Page.Request(frame); Page.Refresh(frame) end
end
net.Receive("traitoradmin_staff_data",function()
    local d=net.ReadTable(); d.received=CurTime(); snapshots[d.page]=d
    local frame=TraitorAdminFrame
    if IsValid(frame) and category(frame)==d.page then Page.Refresh(frame) end
end)
function Page.Refresh(frame)
    local key=category(frame); if not key then return end
    local scroll=frame.staffScroll; local old=scroll:GetVBar():GetScroll(); scroll:Clear()
    local c=vgui.Create("DPanel",scroll); c:SetWide(scroll:GetWide()-16); c.Paint=nil
    local w,y=c:GetWide(),8
    local d=snapshots[key]
    label(c,y,({modevotes="MODE VOTE WEIGHTS",rotation="ROTATION SETTINGS",spawns="NATIVE ZCITY SPAWN POINTS",events="EVENT SETUP",timers="ROUND TIMERS",karma="MY STATIC KARMA",restarts="SERVER RESTARTS"})[key],26,true); y=y+32
    if not d then label(c,y,"Loading staff controls...",40); c:SetTall(y+50); return end
    label(c,y,"Map: "..d.map.."  /  Round: "..d.round,26); y=y+30
    if d.message~="" then label(c,y,d.message,44,true); y=y+50 end
    if key=="restarts" then
        local k=d.restarts or {available=false,error="Restart controls are unavailable."}
        label(c,y,"Controls restart_warning only. Physgun panel schedules, host maintenance and external restarts are separate.",42); y=y+48
        label(c,y,"Or type !restart 10m <reason> in chat. !restart cancel stops it; !restart alone shows the status.",26,true); y=y+30
        if k.available then
            label(c,y,"Server clock: "..k.serverNow.."\nEastern clock: "..k.easternNow,46); y=y+52
            label(c,y,"NEXT RESTART"..(k.manual and " - ADMIN COUNTDOWN" or k.override and " - ONE-TIME OVERRIDE" or ""),24,true); y=y+30
            label(c,y,k.nextAt>0 and (k.easternNext.."\n"..k.serverNext) or "No restart is armed.",46,true); y=y+52
            if type(k.reason)=="string" and k.reason~="" and k.nextAt>0 then label(c,y,"Reason: "..k.reason,40); y=y+44 end
            local countdown=label(c,y,"",26); y=y+32
            countdown.Think=function(p)
                local left=math.max(0,(k.left or 0)-(CurTime()-d.received))
                p:SetText(k.nextAt>0 and (left>0 and string.format("%dh %02dm %02ds remaining",math.floor(left/3600),math.floor(left/60)%60,math.floor(left)%60) or "Due / restarting - refresh status") or "Scheduling unavailable")
            end
            countdown:Think()
            local cancel=button(c,12,y,230,"Cancel next restart...",function()
                confirm("Cancel the restart at "..(k.easternNext or "the shown time").."? Later daily restarts remain scheduled.",function() Action(key,"cancel",k.token) end)
            end,true); cancel:SetEnabled(k.canChange and k.nextAt>0)
            button(c,250,y,130,"Refresh status",function() Action(key,"get") end); y=y+42
            local function timezone(at,initial,changed)
                local box=vgui.Create("DComboBox",c); frame:StyleInput(box); box:SetPos(12,at); box:SetSize(w-24,30); box:SetSortItems(false)
                box:AddChoice("Eastern Time - EST/EDT automatic","eastern",initial=="eastern")
                box:AddChoice("Server local time","server",initial=="server")
                box.OnSelect=function(_,_,_,id) changed(id) end
                box:SetEnabled(k.canChange); return box
            end
            label(c,y,"MOVE NEXT RESTART",24,true); y=y+30
            label(c,y,"Choose a date and 24-hour time (30 seconds to seven days ahead). Earlier daily slots are skipped until the override runs; the replaced slot stays skipped.",56); y=y+62
            local zone="eastern"
            local date,time
            timezone(y,zone,function(id)
                zone=id
                if IsValid(date) then date:SetValue(id=="server" and k.serverDate or k.easternDate); time:SetValue(id=="server" and k.serverTime or k.easternTime) end
            end); y=y+38
            date=entry(frame,c,12,y,(w-32)/2,k.easternDate,"YYYY-MM-DD")
            time=entry(frame,c,20+(w-32)/2,y,(w-32)/2,k.easternTime,"HH:MM (24-hour)")
            date:SetEnabled(k.canChange); time:SetEnabled(k.canChange); y=y+38
            local move=button(c,12,y,230,"Move next restart...",function()
                local input={timezone=zone,date=date:GetValue(),time=time:GetValue()}
                confirm("Move the next restart to "..input.date.." "..input.time.." ("..(zone=="eastern" and "Eastern EST/EDT" or "server time")..")? This also skips daily slots before that time.",function() Action(key,"next",k.token,util.TableToJSON(input)) end)
            end); move:SetEnabled(k.canChange); y=y+44
            label(c,y,"SAVED DAILY SCHEDULE",24,true); y=y+30
            label(c,y,"Daily times: "..k.times.." / "..(k.timezone=="eastern" and "Eastern EST/EDT" or "server local time"),28,true); y=y+34
            local dailyZone=k.timezone
            timezone(y,dailyZone,function(id) dailyZone=id end); y=y+38
            local daily=entry(frame,c,12,y,w-24,k.times,"06:00, 18:00")
            daily:SetEnabled(k.canChange); y=y+38
            label(c,y,"One to eight comma-separated 24-hour times. Saving replaces the daily schedule and clears any pending cancellation or one-time override. Changes survive map changes and restarts.",56); y=y+62
            local save=button(c,12,y,230,"Save daily schedule...",function()
                local input={timezone=dailyZone,times=daily:GetValue()}
                confirm("Save daily restarts at "..input.times.." ("..(dailyZone=="eastern" and "Eastern EST/EDT" or "server time")..") and clear any one-time changes?",function() Action(key,"daily",k.token,util.TableToJSON(input)) end)
            end); save:SetEnabled(k.canChange); y=y+42
            label(c,y,"Eastern follows daylight saving. A missing spring-forward time is skipped for daily schedules; repeated fall-back times run once at the first occurrence. Cancelling during the warning clears its countdown.",56); y=y+62
        end
        if k.error and k.error~="" then label(c,y,k.error,56,true); y=y+62 end
    elseif key=="karma" then
        local k=d.karma or {available=false,error="Personal karma settings are unavailable."}
        label(c,y,"This setting changes only your account. Admins and superadmins can each choose their own value.",42); y=y+48
        if k.available then
            label(c,y,"Current karma: "..string.format("%.1f",k.current).."  /  Static target: "..k.target..(k.custom and " (personal)" or " (default)"),30,true); y=y+36
            label(c,y,"The addon reapplies your target every three seconds. Saved choices survive reconnects, map changes and server restarts.",42); y=y+48
            label(c,y,"Choose a whole value from 0 to "..k.maximum..". ZCity's normal karma-based role chances and low-karma effects still apply.",42); y=y+48
            local value=entry(frame,c,12,y,w-150,k.target,"Your static karma")
            local save=button(c,w-126,y,114,"Save my karma",function() Action(key,"set","",value:GetValue()) end)
            save:SetEnabled(k.canSave==true); value:SetEnabled(k.canSave==true); y=y+40
            local reset=button(c,12,y,210,"Reset my default",function() Action(key,"reset") end)
            reset:SetEnabled(k.canSave==true)
            button(c,234,y,130,"Refresh",function() Action(key,"get") end); y=y+42
        end
        if k.error and k.error~="" then label(c,y,k.error,56,true); y=y+62 end
    elseif key=="modevotes" then
        local k=d.modevotes or {available=false,error="Mode-vote controls are unavailable."}
        label(c,y,"Choose the odds of modes inside each winning vote category. These weights are separate from natural rotation.",42); y=y+48
        label(c,y,"Weights are relative: 2 is twice as likely as 1. Zero excludes a mode. Saves persist and apply to the next category roll without rerolling an existing pick.",56); y=y+62
        button(c,12,y,130,"Refresh weights",function() Action(key,"get") end); y=y+42
        if k.available then
            local function save(action,target,input)
                local n=tonumber(input:GetValue())
                if not n or n~=n or n<0 or n>100 then input:SetValue("0-100"); return end
                Action(key,action,target,util.TableToJSON({token=k.token,value=n}))
            end
            for _,group in ipairs(k.categories or {}) do
                local category=group
                label(c,y,category.label:upper(),26,true); y=y+32
                for _,row in ipairs(category.rows) do
                    local item=row
                    label(c,y,item.title.."  ("..string.format("%.2f",item.percent).."% of the normal roll)",26); y=y+30
                    local input=entry(frame,c,12,y,w-138,item.weight,"Weight 0-100")
                    local b=button(c,w-114,y,102,"Save weight",function() save("weight",category.id.."|"..item.id,input) end)
                    input:SetEnabled(k.canSave==true); b:SetEnabled(k.canSave==true); y=y+40
                end
                if category.id=="4" then
                    label(c,y,"Fear is a separate first roll when the map permits it. Other Customs modes share the remaining chance. Map currently "..(k.fearApproved and "permits Fear." or "blocks Fear."),56); y=y+62
                    local input=entry(frame,c,12,y,w-138,k.fearChance*100,"Fear chance (%)")
                    local b=button(c,w-114,y,102,"Save Fear %",function() save("fear","4",input) end)
                    input:SetEnabled(k.canSave==true); b:SetEnabled(k.canSave==true); y=y+42
                end
            end
        end
        if k.error and k.error~="" then label(c,y,k.error,56,true); y=y+62 end
    elseif key=="rotation" then
        label(c,y,"Weights are relative, not percentages. Save applies to future rolls; queued rounds are unchanged. Map and mode requirements still apply.",42); y=y+48
        for _,row in ipairs(d.rows) do
            local item=row
            label(c,y,item.title.." ["..item.id.."]",24,true); y=y+26
            label(c,y,"Effective weight now: "..string.format("%.4g",item.effective),22); y=y+24
            local value=entry(frame,c,12,y,w-138,item.weight,"Rotation weight")
            button(c,w-114,y,102,"Save weight",function() Action(key,"weight",item.id,value:GetValue()) end)
            y=y+42
        end
        label(c,y,"FEAR MAP APPROVAL",24,true); y=y+30
        label(c,y,(d.fearApproved and "This map is explicitly approved." or "This map is not explicitly approved.")..(d.night and " Its name contains 'night', so ZCity allows it automatically." or ""),40); y=y+46
        local fear=button(c,12,y,260,d.fearApproved and "Remove current map approval" or "Approve current map for Fear",function() Action(key,"fear_map","",d.fearApproved and "0" or "1") end)
        fear:SetEnabled(d.superadmin and d.fearAvailable); y=y+36
        label(c,y,"Fear map approval is restricted to superadmins and persists across restarts.",30); y=y+36
    elseif key=="spawns" then
        label(c,y,"Placement saves your current position and facing. Each bundle adds ONE location to every named group. Existing locations stay intact.",42); y=y+48
        button(c,12,y,(w-32)/2,"Place TDM T + HMCD T + Rioters",function() Action(key,"bundle","t") end)
        button(c,20+(w-32)/2,y,(w-32)/2,"Place TDM CT + HMCD CT + Law",function() Action(key,"bundle","ct") end); y=y+38
        local group=vgui.Create("DComboBox",c); frame:StyleInput(group); group:SetPos(12,y); group:SetSize(w-24,30); group:SetSortItems(false)
        for _,g in ipairs(d.groups) do group:AddChoice(g.title.." ["..g.id.."] - "..g.count.." points",g.id,g.id==d.group) end
        local add,remove
        group.OnSelect=function(_,_,_,id)
            if IsValid(add) then add:SetEnabled(false) end; if IsValid(remove) then remove:SetEnabled(false) end
            Action(key,"get",id)
        end; y=y+38
        add=button(c,12,y,230,"Place selected group here",function() Action(key,"add",d.group) end)
        button(c,250,y,200,Page.showPoints and "Hide selected points" or "Show selected points",function() Page.showPoints=not Page.showPoints; Page.Refresh(frame) end); y=y+38
        local point=vgui.Create("DComboBox",c); frame:StyleInput(point); point:SetPos(12,y); point:SetSize(w-154,30); point:SetSortItems(false)
        point:SetValue("Select a saved spawn point...")
        local selected
        for _,p in ipairs(d.points) do point:AddChoice(string.format("#%d  %.0f %.0f %.0f  yaw %.0f",p.index,p.x,p.y,p.z,p.yaw),p.index) end
        point.OnSelect=function(_,_,_,id) selected=id end
        remove=button(c,w-134,y,122,"Remove point...",function()
            if not selected then return end
            confirm("Remove point #"..selected.." from "..d.group.."?",function() Action(key,"remove",d.group,selected..":"..d.revision) end)
        end,true); remove:SetEnabled(#d.points>0); y=y+40
        if (d.pages or 1)>1 then
            local previous=button(c,12,y,110,"Previous",function() Action(key,"get",d.group,d.pointPage-1) end)
            previous:SetEnabled(d.pointPage>1)
            local following=button(c,130,y,110,"Next",function() Action(key,"get",d.group,d.pointPage+1) end)
            following:SetEnabled(d.pointPage<d.pages)
            y=y+36
            label(c,y,"Page "..d.pointPage.." / "..d.pages.." - "..d.total.." points in group",24); y=y+28
        end
        label(c,y,"Saved to native per-map files. Markers show the current page of the selected group and stay visible after closing. Mutation points are separate.",42); y=y+48
    elseif key=="events" then
        label(c,y,d.active and "Event mode is active." or "Event settings prepare Event mode; they do not switch the current round.",30,true); y=y+36
        if d.available then
            for _,spec in ipairs({{"title","Event name",d.title},{"role","Displayed player role",d.role},{"objective","Objective",d.objective}}) do
                local id=spec[1]
                label(c,y,spec[2],22); y=y+24
                local value=entry(frame,c,12,y,w-126,spec[3],spec[2])
                button(c,w-102,y,90,"Save",function() Action(key,"text",id,value:GetValue()) end); y=y+38
            end
            label(c,y,"End conditions",22); y=y+24
            local logic=vgui.Create("DComboBox",c); frame:StyleInput(logic); logic:SetPos(12,y); logic:SetSize(w-24,30); logic:SetSortItems(false)
            for i,title in ipairs({"Only event staff remain","One or fewer survivors","Manual ending only"}) do logic:AddChoice(title,i,d.logic==i) end
            logic.OnSelect=function(_,_,_,id) confirm("Change Event mode's end conditions?",function() Action(key,"logic","",id) end) end; y=y+38
            button(c,12,y,190,d.loot and "Event loot: ON" or "Event loot: OFF",function() Action(key,"loot","",d.loot and "0" or "1") end)
            button(c,210,y,200,"Open event loot editor",function() RunConsoleCommand("zb_event_loot_menu") end); y=y+44
        else label(c,y,"Event mode is not installed.",26); y=y+32 end
        label(c,y,"PLAYER STAGING",24,true); y=y+30
        label(c,y,"Affects living participants, including bots, except you. Spectators stay put. Teleport needs clear ground and standing players. No respawns or loadout changes.",42); y=y+48
        button(c,12,y,230,"Teleport all to crosshair...",function() confirm("Gather living participants around your crosshair?",function() Action(key,"teleport") end) end)
        button(c,250,y,150,"Freeze all...",function() confirm("Freeze all other living participants?",function() Action(key,"freeze") end) end)
        button(c,408,y,150,"Unfreeze all",function() Action(key,"unfreeze") end); y=y+38
        label(c,y,"Frozen by this menu: "..d.frozen..". Unfreeze releases this menu's freezes only; round changes and respawns release them automatically.",42); y=y+48
    elseif key=="timers" then
        label(c,y,"Live gameplay countdowns for the current round. Refreshes once per second while this page is open. Read-only: no background Lua timers or timer controls.",42); y=y+48
        if #d.rows==0 then label(c,y,"No supported gameplay countdowns are active.",30); y=y+36 end
        for _,item in ipairs(d.rows) do
            local row=item
            label(c,y,row.title,24,true); y=y+26
            local value=label(c,y,"",26)
            value.Think=function(p)
                local left=math.max(0,row.left-(row.paused and 0 or CurTime()-d.received))
                p:SetText(row.paused and string.format("Paused - %.1fs remaining",left) or (left<=0 and "Due / waiting for game conditions" or string.format("%02d:%02d remaining",math.floor(math.ceil(left)/60),math.ceil(left)%60)))
            end
            value:Think(); y=y+38
        end
        label(c,y,"Shown when available: round limit, end transition, police/Guard, SWAT, role selection, Homelander release, Fear events, and Informant calls. Mode rules may ignore the normal round limit.",42); y=y+48
    end
    c:SetTall(y+8); scroll:InvalidateLayout(true); scroll:GetVBar():SetScroll(old)
end
hook.Add("PostDrawTranslucentRenderables","traitoradmin_spawn_markers",function(_,sky)
    if sky or not Page.showPoints or not IsValid(LocalPlayer()) or not LocalPlayer():IsAdmin() then return end
    local d=snapshots.spawns; if not d then return end
    for _,p in ipairs(d.points) do
        render.DrawWireframeSphere(Vector(p.x,p.y,p.z)+Vector(0,0,12),12,8,8,ACCENT,true)
    end
end)
return Page
