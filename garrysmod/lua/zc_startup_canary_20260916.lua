-- Owner-only correction of two named startup callbacks. No startup-event replay.
assert(SERVER and engine.ActiveGamemode()=="zcity")
local owner
for _,p in ipairs(player.GetHumans())do if p:SteamID64()=="76561198011536179" then owner=p end end
assert(IsValid(owner),"Owner client is not connected; no client changed")
local channel="zc_startup_return_canary"
local token=tonumber(util.CRC(tostring(SysTime())))
util.AddNetworkString(channel)
local report={time=os.time(),map=game.GetMap(),target=owner:UserID(),received=false}
local function save()file.CreateDir("zc_startup_repair");file.Write("zc_startup_repair/canary.json",util.TableToJSON(report,true))end
net.Receive(channel,function(bits,p)
    if p~=owner or bits>16384 or bits<33 or report.received then return end
    if net.ReadUInt(32)~=token then return end
    local row=util.JSONToTable(net.ReadString());if not istable(row)then return end
    report.client=row;report.received=true;save()
end)
local code=[[
local r={checks={},errors={}}
local ok,err=xpcall(function()
    local t=assert(ZCPerf2TOZ,"TOZ guard missing")
    local h=hook.GetTable();r.before={}
    for _,event in ipairs({"InitPostEntity","PostGamemodeLoaded"})do
        local current=h[event] and h[event].ZCPerf2TOZ
        assert(current==t.Install or current==t.OnStartup,"Unexpected startup handler: "..event)
        r.before[event]=current==t.Install
    end
    function t.OnStartup()t.Install()end
    hook.Add("InitPostEntity","ZCPerf2TOZ",t.OnStartup)
    hook.Add("PostGamemodeLoaded","ZCPerf2TOZ",t.OnStartup)
    t.StartupHookFix="20260916.2"
    r.checks.noReturn=select('#',t.OnStartup())==0
    r.checks.postHook=hook.GetTable().PostGamemodeLoaded.ZCPerf2TOZ==t.OnStartup
    r.checks.entityHook=hook.GetTable().InitPostEntity.ZCPerf2TOZ==t.OnStartup
    r.checks.skin=derma.SkinList.ZCity~=nil
    r.checks.pause=vgui.GetControlTable("ZMainMenu")~=nil
    r.checks.settings=hg and isfunction(hg.DrawSettings)
    r.lateZCity=isfunction(SDOIsDoor) and hg and hg.precachedsounds~=nil
    r.alive=LocalPlayer():Alive();r.width=ScrW();r.height=ScrH()
    r.checks.uiErrorsClear=ZCUIRecovery and next(ZCUIRecovery.errors)==nil
    assert(r.checks.noReturn and r.checks.postHook and r.checks.entityHook,"Startup correction failed")
end,debug.traceback)
r.ok=ok;if not ok then r.errors.apply=tostring(err)end
net.Start("zc_startup_return_canary");net.WriteUInt(__TOKEN__,32);net.WriteString(util.TableToJSON(r));net.SendToServer()
]]
code=string.Replace(code,"__TOKEN__",tostring(token))
assert(#code<6000);save();owner:SendLua(code)
timer.Simple(15,function()report.finished=os.time();save();net.Receivers[channel]=nil end)
