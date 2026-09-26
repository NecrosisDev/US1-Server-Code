-- Grouped self context menu. Native property filters use the actual self target.
if not CLIENT then return end
if not ZCContextFolders then include("zc_context_folders/client.lua") end
ZCSelfMenuUI=ZCSelfMenuUI or {}
local UI=ZCSelfMenuUI
local SKIP={zc_maketorso=true,zc_makecrusher=true,zc_makesupercrusher=true,zc_removecrusher=true,zc_removesupercrusher=true}
concommand.Add("zc_selfmenu",function()
    local ply=LocalPlayer()
    if not IsValid(ply) or not ply:IsAdmin() then return end
    local G=ZCContextFolders
    if not G then return end
    G.Bind()
    if IsValid(UI.activeMenu) then UI.activeMenu:Remove() end
    local tr={Entity=ply,HitPos=ply:WorldSpaceCenter(),Hit=true,HitNonWorld=true}
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
    G.AddSelfAction(menu,"zc_makecrusher","Make Crusher (self)","give_crusher","icon16/user_red.png")
    G.AddSelfAction(menu,"zc_makesupercrusher","Make Super Crusher (self)","give_supercrusher","icon16/user_red.png")
    G.AddSelfAction(menu,"zc_maketorso","Make Torso (self)","make_torso","icon16/user_delete.png")
    G.AddSelfAction(menu,"zc_removecrusher","Remove Crusher (self)","remove_crusher","icon16/user_gray.png")
    G.AddSelfAction(menu,"zc_removesupercrusher","Remove Super Crusher (self)","remove_supercrusher","icon16/user_gray.png")
    local cursorWasVisible=vgui.CursorVisible()
    menu.OnRemove=function()
        if UI.activeMenu==menu then
            UI.activeMenu=nil
            if not cursorWasVisible then gui.EnableScreenClicker(false) end
        end
    end
    menu:Open(ScrW()/2-60,ScrH()/2-40)
    gui.EnableScreenClicker(true)
end)
