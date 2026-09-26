-- One-shot read-only audit: never calls startup callbacks or changes client state.
assert(SERVER and engine.ActiveGamemode()=="zcity")
local channel="zc_startup_return_audit"
local token=tonumber(util.CRC(tostring(SysTime())))
local pending={};local r={time=os.time(),map=game.GetMap(),targets=0,received=0,clients={}}
local function src(fn)if not isfunction(fn)then return false end;return debug.getinfo(fn,"S").short_src end
r.serverLateDamageSource=src(GAMEMODE.ScalePlayerDamage)
r.serverLateAnimationSource=src(GAMEMODE.MouthMoveAnimation)
local function save()file.CreateDir("zc_startup_repair");file.Write("zc_startup_repair/clients.json",util.TableToJSON(r,true))end
util.AddNetworkString(channel)
net.Receive(channel,function(bits,p)
    if not pending[p] or bits<33 or bits>32768 then return end
    if net.ReadUInt(32)~=token then return end
    local data=util.JSONToTable(net.ReadString());if not istable(data)then return end
    pending[p]=nil;r.clients[tostring(p:UserID())]=data;r.received=r.received+1;save()
end)
local code=[[
local h=hook.GetTable();local t=ZCPerf2TOZ
local r={version=t and t.Version,fix=t and t.StartupHookFix,
    postCorrect=t~=nil and t.OnStartup~=nil and (h.PostGamemodeLoaded or {}).ZCPerf2TOZ==t.OnStartup,
    entityCorrect=t~=nil and t.OnStartup~=nil and (h.InitPostEntity or {}).ZCPerf2TOZ==t.OnStartup,
    skin=derma.SkinList.ZCity~=nil,pause=vgui.GetControlTable("ZMainMenu")~=nil,
    settings=hg~=nil and isfunction(hg.DrawSettings),lateZCity=isfunction(SDOIsDoor),
    uiErrorsClear=ZCUIRecovery~=nil and next(ZCUIRecovery.errors)==nil}
net.Start("zc_startup_return_audit");net.WriteUInt(__TOKEN__,32);net.WriteString(util.TableToJSON(r));net.SendToServer()
]]
code=string.Replace(code,"__TOKEN__",tostring(token))
for _,p in ipairs(player.GetHumans())do pending[p]=true;r.targets=r.targets+1;p:SendLua(code)end
save();timer.Simple(15,function()r.missing=r.targets-r.received;r.finished=os.time();save();net.Receivers[channel]=nil end)
