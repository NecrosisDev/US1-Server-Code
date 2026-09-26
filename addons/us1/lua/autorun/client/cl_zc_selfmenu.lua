-- Grouped self context menu. Native property filters use the actual self target.
-- UI cohesion U5 (2026-09-26): with the GoobOS kit loaded this is a kit list - the Staff app's Player tools page
-- (zc_goobos/staff.lua) or, for the zc_selfmenu command, a small kit frame. A property that builds its own options
-- (a submenu) opens exactly that submenu at the cursor. Without the kit it is the old DermaMenu. The crusher/torso
-- actions go through the server's whitelisted _zcself_relay, which checks the "zc staff playertools" ULX right.
if not CLIENT then return end
if not ZCContextFolders then include("zc_context_folders/client.lua") end
ZCSelfMenuUI=ZCSelfMenuUI or {}
local UI=ZCSelfMenuUI
local SKIP={zc_maketorso=true,zc_makecrusher=true,zc_makesupercrusher=true,zc_removecrusher=true,zc_removesupercrusher=true}
-- The relay actions: property id (for its folder), label, relay command (sv_zc_selfmenu.lua whitelist), icon.
local RELAY={
    {"zc_makecrusher","Make Crusher (self)","give_crusher","icon16/user_red.png"},
    {"zc_makesupercrusher","Make Super Crusher (self)","give_supercrusher","icon16/user_red.png"},
    {"zc_maketorso","Make Torso (self)","make_torso","icon16/user_delete.png"},
    {"zc_removecrusher","Remove Crusher (self)","remove_crusher","icon16/user_gray.png"},
    {"zc_removesupercrusher","Remove Super Crusher (self)","remove_supercrusher","icon16/user_gray.png"},
}
local function selfTrace(ply) return {Entity=ply,HitPos=ply:WorldSpaceCenter(),Hit=true,HitNonWorld=true} end

-- Presentation only (the server checks every action): the Staff app's rights once the server has sent them, IsAdmin() before.
function UI.Allowed(ply)
    local St=ZCGoobApps and ZCGoobApps.Staff
    if St and St.known then return St.Has("playertools") end
    return ply:IsAdmin()
end

-- Rows for the kit list: folder headers (zc_context_folders categories, in their order) and the actions under them.
function UI.Rows(ply)
    local G=ZCContextFolders
    if G then G.Bind() end
    local items={}
    for id,prop in SortedPairsByMemberValue(properties.List or {},"Order") do
        if not SKIP[id] and prop.Filter then
            local ok,pass=pcall(prop.Filter,prop,ply,ply)
            if ok and pass then
                items[#items+1]={id=id,prop=prop,label=prop.MenuLabel and language.GetPhrase(prop.MenuLabel) or id,icon=prop.MenuIcon}
            elseif not ok then
                ErrorNoHalt("[ZCSelfMenu] filter "..id..": "..tostring(pass).."\n")
            end
        end
    end
    for _,r in ipairs(RELAY) do items[#items+1]={id=r[1],label=r[2],relay=r[3],icon=r[4]} end
    local cats,groups=G and G.Categories or {},G and G.Groups or {}
    local function order(item) local c=item.cat and cats[item.cat] return c and c.order or 99 end
    for i,item in ipairs(items) do item.seq=i; item.cat=groups[item.id] end
    table.sort(items,function(a,b)
        local oa,ob=order(a),order(b)
        if oa~=ob then return oa<ob end
        return a.seq<b.seq
    end)
    local rows,last={},false
    for _,item in ipairs(items) do
        if item.cat~=last then
            last=item.cat
            rows[#rows+1]={header=item.cat and cats[item.cat] and cats[item.cat].label or "Other"}
        end
        rows[#rows+1]=item
    end
    return rows
end

-- One action. done() runs after an action that finished at once (not after opening a submenu).
function UI.Run(item,ply,done)
    if not IsValid(ply) then return end
    if item.relay then
        RunConsoleCommand("_zcself_relay",item.relay)
        if done then done() end
        return
    end
    local prop=item.prop
    if not prop or not prop.Filter or not prop:Filter(ply,ply) then return end
    local tr=selfTrace(ply)
    if prop.MenuOpen then
        local menu=DermaMenu()
        local option=menu:AddOption(item.label,function()
            if IsValid(ply) and prop:Filter(ply,ply) and prop.Action then prop:Action(ply,tr) end
        end)
        option.ZCContextPlaced=true -- stays at the root: G.Place would fold it into a category submenu
        if item.icon then option:SetImage(item.icon) end
        if prop.Type=="toggle" and prop.Checked then option:SetChecked(prop:Checked(ply,ply)) end
        prop:MenuOpen(option,ply,tr)
        if prop.OnCreate then prop:OnCreate(menu,option) end
        if IsValid(option.SubMenu) then menu:Open() return end
        menu:Remove()
    end
    if prop.Action then prop:Action(ply,tr) end
    if done then done() end
end

-- Kit list of the rows in `parent` (docked FILL). Returns the list, or nil without the kit.
function UI.Build(parent,done)
    local A=ZCGoobApps
    local K,T=A and A.Kit,A and A.Theme
    local ply=LocalPlayer()
    if not K or not T or not IsValid(ply) then return nil end
    local rows=UI.Rows(ply)
    local icons={}
    local function icon(path)
        if not path then return nil end
        if icons[path]==nil then icons[path]=Material(path,"smooth") end
        return icons[path]
    end
    local list
    list=K.List(parent,{rowHeight=32,gap=4,count=function() return #rows end,
        build=function(row)
            local b=vgui.Create("DButton",row)
            b:SetText("")
            b:Dock(FILL)
            b.DoClick=function(s)
                if not s.Item or s.Item.header then return end
                UI.Run(s.Item,LocalPlayer(),done)
                if IsValid(list) then list:Refresh() end
            end
            b.Paint=function(s,w,h)
                local item=s.Item
                if not item then return end
                if item.header then
                    K.Text(string.upper(item.header),11,600,4,h-5,T.muted,TEXT_ALIGN_LEFT,TEXT_ALIGN_BOTTOM)
                    return
                end
                local hover=K.Hover(s)
                draw.RoundedBox(4,0,0,w,h,T.card)
                if hover>0.01 then draw.RoundedBox(4,0,0,w,h,K.Alpha(T.white,13*hover)) end
                local x=10
                local mat=icon(item.icon)
                if mat then
                    surface.SetMaterial(mat)
                    surface.SetDrawColor(T.white)
                    surface.DrawTexturedRect(x,math.floor(h/2)-8,16,16)
                    x=x+24
                end
                local state=item.checked~=nil and (item.checked and "On" or "Off") or nil
                K.Text(K.Fit(item.label,K.Font(14,500),w-x-(state and 44 or 10)),14,500,x,h/2,T.text,TEXT_ALIGN_LEFT,TEXT_ALIGN_CENTER)
                if state then K.Text(state,12,600,w-10,h/2,item.checked and T.gold or T.muted,TEXT_ALIGN_RIGHT,TEXT_ALIGN_CENTER) end
            end
            row.Btn=b
        end,
        fill=function(row,index)
            local item=rows[index]
            row.Btn.Item=item
            row.Btn:SetCursor(item and not item.header and "hand" or "arrow")
            if item and item.prop and item.prop.Type=="toggle" and item.prop.Checked then
                local me=LocalPlayer()
                local ok,on=pcall(item.prop.Checked,item.prop,me,me)
                item.checked=ok and on and true or false
            end
        end})
    list:Dock(FILL)
    return list
end

-- zc_selfmenu with the kit: a small frame holding the same list; an action closes it, like the menu it replaces.
function UI.Open()
    local A=ZCGoobApps
    local K,T=A and A.Kit,A and A.Theme
    if not K or not T then return false end
    if IsValid(UI.activeFrame) then UI.activeFrame:Remove() end
    if IsValid(UI.activeMenu) then UI.activeMenu:Remove() end
    local frame=vgui.Create("DFrame")
    frame:SetTitle("")
    frame:ShowCloseButton(false)
    frame:SetSize(math.min(380,ScrW()-32),math.min(560,math.floor(ScrH()*0.7)))
    frame:Center()
    frame:MakePopup()
    frame:DockPadding(12,46,12,12)
    frame.Paint=function(_,w,h)
        K.Card(0,0,w,h,T.glass,K.Alpha(T.edge,200))
        K.Text("Player tools",16,700,14,12,T.text)
        K.Text("zc_selfmenu",11,600,14,31,T.muted)
    end
    local close=K.Button(frame,{label="Close",kind="quiet",size=13,dock=false,click=function() frame:Remove() end})
    close:SetSize(64,26)
    local layout=frame.PerformLayout
    frame.PerformLayout=function(s,w,h)
        if layout then layout(s,w,h) end
        close:SetPos(w-76,10)
    end
    UI.activeFrame=frame
    if not UI.Build(frame,function() if IsValid(frame) then frame:Remove() end end) then
        frame:Remove()
        return false
    end
    return true
end

-- The DermaMenu this command always opened; used when the GoobOS kit is not loaded.
local function openMenu(ply)
    local G=ZCContextFolders
    if not G then return end
    G.Bind()
    if IsValid(UI.activeMenu) then UI.activeMenu:Remove() end
    local tr=selfTrace(ply)
    local menu=DermaMenu()
    UI.activeMenu=menu
    for id,prop in SortedPairsByMemberValue(properties.List or {},"Order") do
        if not SKIP[id] and prop.Filter then
            local ok,pass=pcall(prop.Filter,prop,ply,ply)
            if ok and pass then
                local built,err=pcall(G.AddProperty,menu,id,prop,ply,tr)
                if not built then ErrorNoHalt("[ZCSelfMenu] "..id..": "..tostring(err).."\n") end
            elseif not ok then
                ErrorNoHalt("[ZCSelfMenu] filter "..id..": "..tostring(pass).."\n")
            end
        end
    end
    -- Retain the existing admin-only, whitelisted self-command relay.
    for _,r in ipairs(RELAY) do G.AddSelfAction(menu,r[1],r[2],r[3],r[4]) end
    local cursorWasVisible=vgui.CursorVisible()
    menu.OnRemove=function()
        if UI.activeMenu==menu then
            UI.activeMenu=nil
            if not cursorWasVisible then gui.EnableScreenClicker(false) end
        end
    end
    menu:Open(ScrW()/2-60,ScrH()/2-40)
    gui.EnableScreenClicker(true)
end

concommand.Add("zc_selfmenu",function()
    local ply=LocalPlayer()
    if not IsValid(ply) or not UI.Allowed(ply) then return end
    if UI.Open() then return end
    openMenu(ply)
end,nil,"Staff: actions on yourself - crusher, super crusher, torso and your own context-menu properties (needs the 'zc staff playertools' ULX right; the server checks each action).")
