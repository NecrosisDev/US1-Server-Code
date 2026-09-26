if not SERVER then return end
local data=assert(util.JSONToTable(file.Read("zci_panel_stage/restraints-runtime.txt","DATA")))
assert(data.build=="20260923.restraints1")
local compiled={}
for realm,rows in pairs({server=data.server,client=data.client}) do
    for _,r in ipairs(rows) do
        assert(util.SHA256(r.source)==r.hash)
        local fn=CompileString(r.source,"RestraintTrial/"..r.name,false)
        assert(isfunction(fn),tostring(fn))
        if realm=="server" then compiled[#compiled+1]=fn end
    end
end
local owners=0
for _,p in ipairs(player.GetHumans()) do if p:SteamID()=="STEAM_0:1:25635225" then owners=owners+1 end end
local sessions=0 for _,s in pairs(ZCityHostage.Gameplay.Sessions) do if not s.done then sessions=sessions+1 end end
file.Write("zci_panel_stage/restraints-runtime-preflight.json",util.TableToJSON({ok=true,owners=owners,sessions=sessions,time=os.time()}))
function ZCI_ApplyRestraintTrial()
    -- Do not cancel a real player's session to reload the controller.
    for _,s in pairs(ZCityHostage.Gameplay.Sessions) do
        if not s.done then file.Write("zci_panel_stage/restraints-trial-status.json",util.TableToJSON({ok=false,reason="Active interaction; trial deferred",time=os.time()})) return end
    end
    local ownerOnline=false
    for _,p in ipairs(player.GetHumans()) do if p:SteamID()=="STEAM_0:1:25635225" then ownerOnline=true end end
    if not ownerOnline then file.Write("zci_panel_stage/restraints-trial-status.json",util.TableToJSON({ok=false,reason="Owner disconnected; trial deferred",time=os.time()})) return end
    local ok,err=xpcall(function() for _,fn in ipairs(compiled) do fn() end end,debug.traceback)
    file.Write("zci_panel_stage/restraints-trial-status.json",util.TableToJSON({ok=ok,detail=tostring(err),time=os.time()}))
    if not ok then return end
    util.AddNetworkString("ZCI_RestraintTrial") util.AddNetworkString("ZCI_RestraintTrialAck")
    local client={build=data.build,files=data.client}
    local packed=assert(util.Compress(util.TableToJSON(client))) assert(#packed<65536)
    local sent={}
    net.Receive("ZCI_RestraintTrialAck",function(bits,p)
        if bits>16384 or not sent[p] or p:SteamID()~="STEAM_0:1:25635225" then return end
        local build=net.ReadString() local success=net.ReadBool() local detail=net.ReadString()
        if build~=data.build then return end
        file.Write("zci_panel_stage/restraints-client-ack.json",util.TableToJSON({ok=success,detail=detail,build=build,time=os.time()}))
    end)
    local bootstrap=[=[
net.Receive("ZCI_RestraintTrial",function()
    local n=net.ReadUInt(16) local data=util.JSONToTable(util.Decompress(net.ReadData(n)) or "")
    if not data or data.build~="20260923.restraints1" then return end
    local native,press=hg.CreateRadialMenu,hg.PressRadialMenu
    local ok,err=xpcall(function()
        local compiled={}
        for _,r in ipairs(data.files) do
            assert(util.SHA256(r.source)==r.hash)
            local fn=CompileString(r.source,"RestraintTrial/"..r.name,false)
            assert(isfunction(fn),tostring(fn));compiled[#compiled+1]=fn
        end
        for _,fn in ipairs(compiled) do fn() end
        assert(ZCityInteractions.CustomMenuVersion==data.build)
        assert(isfunction(hg.SetHandcuffed) and isfunction(ZCityHostage.Gameplay.CanUseCuffKey))
        assert(hg.CreateRadialMenu==native and hg.PressRadialMenu==press)
    end,debug.traceback)
    net.Start("ZCI_RestraintTrialAck") net.WriteString(data.build) net.WriteBool(ok)
    net.WriteString(ok and "Restraint integration loaded; native Q unchanged; rendered check pending" or tostring(err):sub(1,1800)) net.SendToServer()
end)
]=]
    for _,p in ipairs(player.GetHumans()) do if p:SteamID()=="STEAM_0:1:25635225" then
        sent[p]=true p:SendLua(bootstrap)
        timer.Simple(.5,function()
            if not IsValid(p) then return end
            net.Start("ZCI_RestraintTrial") net.WriteUInt(#packed,16) net.WriteData(packed,#packed) net.Send(p)
        end)
    end end
end
