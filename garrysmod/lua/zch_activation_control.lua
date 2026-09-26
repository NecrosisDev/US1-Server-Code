local O={}
ZCH_ACTIVATION=O
local user="76561198011536179"
local function write(name,t)
    t.time=os.time()
    file.Write("zch_activation_"..name..".json",util.TableToJSON(t,true))
    print("ZCH_ACTIVATION_"..name,util.TableToJSON(t))
end
util.AddNetworkString("zch_activation_probe")
net.Receive("zch_activation_probe",function(len,p)
    if not IsValid(p) or p:SteamID64()~=user or len>16000 then return end
    write("client",{steamid=p:SteamID64(),data=util.JSONToTable(net.ReadString())})
end)
function O.Probe()
    local source=[=[local function info(f) return type(f)=='function' and debug.getinfo(f).short_src or 'missing' end local t={tpik=info(hg.MainTPIKFunction),anim=info(FindMetaTable('Player').PlayCustomAnims),model=LocalPlayer():GetModel(),hostageModel=file.Exists('models/zcity_hostage/gameplay_male.mdl','GAME')} net.Start('zch_activation_probe') net.WriteString(util.TableToJSON(t)) net.SendToServer()]=]
    for _,p in ipairs(player.GetHumans()) do if p:SteamID64()==user then p:SendLua(source) end end
    write("server",{players=#player.GetHumans(),map=game.GetMap(),restart=ZC_RESTART_WARNING.Status()})
end
function O.BeginMaintenance()
    assert(not O.begun,"Already announced")
    local R=assert(ZC_RESTART_WARNING)
    assert(not R.warningEnd and not R.triggered and R.Status().left>120)
    O.begun=true
    net.Start("restartwarn_state") net.WriteFloat(30) net.WriteBool(true) net.Broadcast()
    PrintMessage(HUD_PRINTTALK,"[ZCity Maintenance] Brief shutdown in 30s to install the hostage animations. Please finish your current bad decision.")
    timer.Create("ZCHActivation.FinalWarning",20,1,function()
        net.Start("restartwarn_start") net.WriteFloat(10) net.Broadcast()
    end)
    timer.Create("ZCHActivation.StopReady",30,1,function() write("stopready",{ready=true}) end)
    write("announced",{seconds=30,players=#player.GetHumans(),purpose="Stopped-server installation; operator will stop, install and start main."})
end
