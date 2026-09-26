if not CLIENT then return end
local G=ZCContextFolders or {}
ZCContextFolders=G
G.Version="1.0.0"
G.wrappers=G.wrappers or setmetatable({},{__mode="k"})
G.Categories={
    health={label="Health & Recovery",order=1,icon="icon16/heart.png"},
    equipment={label="Equipment",order=2,icon="icon16/gun.png"},
    control={label="Player Control",order=3,icon="icon16/user.png"},
    transform={label="Transformations",order=4,icon="icon16/user_edit.png"},
    damage={label="Damage & Effects",order=5,icon="icon16/lightning.png"},
    appearance={label="Appearance",order=6,icon="icon16/palette.png"},
    props={label="Doors & Props",order=7,icon="icon16/bricks.png"},
}
G.Groups={}
local function map(category,ids)
    for id in string.gmatch(ids,"%S+") do G.Groups[id]=category end
end
map("health","reset_org zc_returnlegs respawn_ply_in_rag respawn_lply_in_rag respawn_ragply_in_rag extinguish")
map("equipment","givegun strip fullstrip")
map("control","notify freeze snatch zc_snatchlite ragdollize")
map("transform","zc_makecrawler zc_maketorso zc_makecrusher zc_removecrusher zc_makesupercrusher zc_removesupercrusher setplayerclass furrify")
map("damage","break_limb amputate_limb vomit lobotomize zc_fearevent ignite killsilent removeply")
map("appearance","skin bodygroups bone_manipulate bone_manipulate_end indicator_add indicator_remove")
map("props","door_toggle door_lock door_unlock gravity persist persist_end editentity npc_bigger npc_smaller collision_off collision_on remove drive motioncontrol_ragdoll statue statue_stop keepupright keepupright_stop")
local ranks={reset_org=1,zc_returnlegs=2,respawn_ply_in_rag=10,respawn_lply_in_rag=11,respawn_ragply_in_rag=12,killsilent=10000,removeply=10001,remove=10000}

function G.Folder(root,key)
    local category=G.Categories[key]
    if not IsValid(root) or not category then return end
    root.ZCContextCategories=root.ZCContextCategories or {}
    local row=root.ZCContextCategories[key]
    if row and IsValid(row.menu) then return row.menu end
    local menu,option=root:AddSubMenu(category.label)
    menu.OptionSelected=function(_,selected,text) root:OptionSelected(selected,text) end
    option:SetImage(category.icon)
    option:SetZPos(-100+category.order)
    root.ZCContextCategories[key]={menu=menu,option=option}
    return menu
end

function G.Place(root,option,id,prop)
    if not IsValid(root) or not IsValid(option) or option.ZCContextPlaced then return end
    local key=G.Groups[id]
    if not key then return end -- New/unmapped addon entries stay visible at their original level.
    local preceding
    if prop and prop.PrependSpacer then
        local children=root:GetCanvas():GetChildren()
        for index,child in ipairs(children) do
            if child==option and index>1 then
                local previous=children[index-1]
                if previous~=root.ToggleSpacer and previous:GetTall()==1 then preceding=previous end
                break
            end
        end
    end
    local folder=G.Folder(root,key)
    if not IsValid(folder) then return end
    -- Native AddPanel reparents to the scroll canvas and fixes hover ownership.
    -- SetMenu separately fixes checked/radio selection and OptionSelected routing.
    if IsValid(preceding) then
        folder:AddPanel(preceding)
        preceding:SetZPos((ranks[id] or tonumber(prop.Order) or 500)-0.1)
    end
    folder:AddPanel(option)
    option:SetMenu(folder)
    option:SetZPos(ranks[id] or (tonumber(prop and prop.Order) or 500))
    option.ZCContextPlaced=true
    if prop and prop.Type=="toggle" and IsValid(root.ToggleSpacer) then
        -- Keep the native spacer only when another toggle still lives at root.
        local remaining=false
        for _,child in ipairs(root:GetCanvas():GetChildren()) do
            if child~=root.ToggleSpacer and child:GetZPos()==501 then remaining=true break end
        end
        if not remaining then root.ToggleSpacer:Remove();root.ToggleSpacer=nil end
    end
    if (id=="killsilent" or id=="removeply" or id=="remove") and not folder.ZCContextDangerSpacer then
        local spacer=folder:AddSpacer();spacer:SetZPos(9999)
        folder.ZCContextDangerSpacer=spacer
    end
end

function G.Bind()
    for id,prop in pairs(properties.List or {}) do
        if G.Groups[id] then
            local state=G.wrappers[prop] or {}
            G.wrappers[prop]=state
            -- MenuOpen reaches native menus AND the scoreboard's manual builder.
            if not state.menuWrapper or prop.MenuOpen~=state.menuWrapper then
                local original=prop.MenuOpen
                state.menuWrapper=function(self,option,ent,tr)
                    if original then original(self,option,ent,tr) end
                    if self.Type=="toggle" and self.Checked then option:SetChecked(self:Checked(ent,LocalPlayer())) end
                    G.Place(option.ParentMenu,option,id,self)
                end
                prop.MenuOpen=state.menuWrapper
            end
            -- Native toggles skip MenuOpen; OnCreate is their post-build callback.
            if not state.createWrapper or prop.OnCreate~=state.createWrapper then
                local original=prop.OnCreate
                state.createWrapper=function(self,menu,option)
                    if original then original(self,menu,option) end
                    G.Place(menu,option,id,self)
                end
                prop.OnCreate=state.createWrapper
            end
        end
    end
end

-- Shared property renderer for selfmenu. Existing network Actions/MenuOpen are
-- invoked on their original property object, preserving InternalName and checks.
function G.AddProperty(menu,id,prop,target,tr)
    local option=menu:AddOption(prop.MenuLabel and language.GetPhrase(prop.MenuLabel) or id,function()
        if not IsValid(target) then return end
        if not prop.Filter or not prop:Filter(target,LocalPlayer()) then return end
        if prop.Action then prop:Action(target,tr) end
    end)
    if prop.MenuIcon then option:SetImage(prop.MenuIcon) end
    if prop.Type=="toggle" and prop.Checked then option:SetChecked(prop:Checked(target,LocalPlayer())) end
    if prop.MenuOpen then prop:MenuOpen(option,target,tr) end
    if prop.OnCreate then prop:OnCreate(menu,option) end
    return option
end
function G.AddSelfAction(menu,id,label,command,icon)
    local option=menu:AddOption(label,function()
        local ply=LocalPlayer()
        if IsValid(ply) and ply:IsAdmin() then RunConsoleCommand("_zcself_relay",command) end
    end)
    option:SetImage(icon or "icon16/user_edit.png")
    G.Place(menu,option,id,{Order=100})
    return option
end

-- No global property, VGUI, hook or networking function replacement.
hook.Add("InitPostEntity","ZCContextFolders.Bind",function() G.Bind() end)
hook.Add("OnContextMenuOpen","ZCContextFolders.Bind",function() G.Bind() end)
hook.Add("OnReloaded","ZCContextFolders.Bind",function() G.Bind() end)
timer.Create("ZCContextFolders.InitialBind",1,30,function() G.Bind() end)
G.Bind()
