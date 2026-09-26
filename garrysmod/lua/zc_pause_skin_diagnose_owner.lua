-- Read-only UI inspection: no panels, keys, menus or preferences are changed.
assert(SERVER and engine.ActiveGamemode()=="zcity")
local token=tonumber(util.CRC(tostring(SysTime())))
local channel="zc_pause_skin_diag_20260916"
util.AddNetworkString(channel)
local expected={};local r={time=os.time(),map=game.GetMap(),clients={}}
local function save()file.CreateDir("zc_pause_skin");file.Write("zc_pause_skin/before.json",util.TableToJSON(r,true))end
net.Receive(channel,function(bits,p)
    if not expected[p] or bits>65536 then return end
    if net.ReadUInt(32)~=token then return end
    expected[p]=nil
    local s=util.JSONToTable(net.ReadString());if not istable(s)then return end
    s.alive=p:Alive();s.admin=p:IsAdmin();s.userid=p:UserID()
    r.clients[tostring(p:UserID())]=s;save()
end)
local code=[[
local function source(fn)
    if not isfunction(fn)then return false end
    local i=debug.getinfo(fn,"S");return i.short_src..":"..i.linedefined
end
local h=hook.GetTable()
local default=derma.GetDefaultSkin()
local skins={};for name in pairs(derma.SkinList or {})do skins[#skins+1]=name end
local s={skins=skins,default=default and default.PrintName or "?",
    defaultZCity=default==derma.SkinList.ZCity,skin=derma.SkinList.ZCity~=nil,
    pauseClass=vgui.GetControlTable("ZMainMenu")~=nil,frameClass=vgui.GetControlTable("ZFrame")~=nil,
    settings=hg and isfunction(hg.DrawSettings),pluv=hg and hg.PluvTown~=nil,
    uiErrors=ZCUIRecovery and ZCUIRecovery.errors,bootstrap=ZCUIRecovery and ZCUIRecovery.Version,
    mainMenu=IsValid(MainMenu),width=ScrW(),height=ScrH(),pauseHooks={},skinHooks={}}
for k,v in pairs(h.OnPauseMenuShow or {})do s.pauseHooks[tostring(k)]=source(v)end
for k,v in pairs(h.ForceDermaSkin or {})do s.skinHooks[tostring(k)]=source(v)end
s.lateHook=source((h.InitPostEntity or {}).zcity)
s.files={}
for _,path in ipairs({"initpost/cl_derma_skin.lua","initpost/menu-n-derma/derma/cl_menu_panel.lua","initpost/menu-n-derma/derma/cl_menu_options.lua"})do
    s.files[path]={exists=file.Exists(path,"LUA"),size=file.Size(path,"LUA")}
end
local a,b=file.Find("initpost/*","LUA");s.discovery={files=a,dirs=b}
local raw=util.TableToJSON(s);if #raw>7000 then s.uiErrors={overflow=true};raw=util.TableToJSON(s)end
net.Start("zc_pause_skin_diag_20260916");net.WriteUInt(__TOKEN__,32);net.WriteString(raw);net.SendToServer()
]]
code=string.Replace(code,"__TOKEN__",tostring(token))
for _,p in ipairs(player.GetHumans())do
    if p:SteamID64()=="76561198011536179" then expected[p]=true;p:SendLua(code)end
end
save()
local recv=net.Receivers[channel]
timer.Simple(15,function()if net.Receivers[channel]==recv then net.Receivers[channel]=nil end end)
