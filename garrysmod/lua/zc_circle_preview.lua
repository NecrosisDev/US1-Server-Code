if not SERVER then return end
local payload=assert(util.JSONToTable(file.Read("zci_panel_stage/circle-preview.txt","DATA")))
assert(payload.build=="20260923.circle1")
for _,row in ipairs(payload.files) do
    assert(util.SHA256(row.source)==row.hash)
    assert(isfunction(CompileString(row.source,"CirclePreflight/"..row.name,false)))
end
local owners=0
for _,p in ipairs(player.GetHumans()) do if p:SteamID()=="STEAM_0:1:25635225" then owners=owners+1 end end
file.Write("zci_panel_stage/circle-preflight.json",util.TableToJSON({ok=true,build=payload.build,owners=owners,time=os.time()}))
function ZCI_CirclePreviewActivate()
    local ok,err=xpcall(function()
        include("zcity_interactions/sv_context.lua")
        include("zcity_interactions/sv_quick.lua")
    end,debug.traceback)
    file.Write("zci_panel_stage/circle-activation.json",util.TableToJSON({ok=ok,detail=tostring(err),time=os.time()}))
    if not ok then return end
    util.AddNetworkString("ZCI_CirclePreview") util.AddNetworkString("ZCI_CirclePreviewAck")
    local sent={}
    net.Receive("ZCI_CirclePreviewAck",function(bits,p)
        if bits>16384 or not sent[p] or p:SteamID()~="STEAM_0:1:25635225" then return end
        local build=net.ReadString() local success=net.ReadBool() local detail=net.ReadString()
        if build~=payload.build then return end
        file.Write("zci_panel_stage/circle-preview-ack.json",util.TableToJSON({build=build,ok=success,detail=detail,time=os.time()}))
    end)
    local client={build=payload.build,files={}}
    for _,row in ipairs(payload.files) do if row.name:sub(1,3)=="cl_" then client.files[#client.files+1]=row end end
    local packed=assert(util.Compress(util.TableToJSON(client))) assert(#packed<65536)
    local bootstrap=[=[
net.Receive("ZCI_CirclePreview",function()
    local n=net.ReadUInt(16) local data=util.JSONToTable(util.Decompress(net.ReadData(n)) or "")
    if not data or data.build~="20260923.circle1" then return end
    local native,press=hg.CreateRadialMenu,hg.PressRadialMenu
    local ok,err=xpcall(function()
        local compiled={}
        for _,row in ipairs(data.files) do
            assert(util.SHA256(row.source)==row.hash)
            local fn=CompileString(row.source,"CirclePreview/"..row.name,false)
            assert(isfunction(fn),tostring(fn)) compiled[#compiled+1]=fn
        end
        for _,fn in ipairs(compiled) do fn() end
        assert(ZCityInteractions.CustomMenuVersion==data.build)
        assert(not ZCityInteractions.ActionPanel and not ZCityInteractions.CreateActionPanel)
        assert(hg.CreateRadialMenu==native and hg.PressRadialMenu==press)
    end,debug.traceback)
    net.Start("ZCI_CirclePreviewAck") net.WriteString(data.build) net.WriteBool(ok)
    net.WriteString(ok and "Circle loaded; native Q functions unchanged; rendered check pending" or tostring(err):sub(1,1800)) net.SendToServer()
end)
]=]
    for _,p in ipairs(player.GetHumans()) do
        if p:SteamID()=="STEAM_0:1:25635225" then
            sent[p]=true p:SendLua(bootstrap)
            timer.Simple(.5,function()
                if not IsValid(p) then return end
                net.Start("ZCI_CirclePreview") net.WriteUInt(#packed,16) net.WriteData(packed,#packed) net.Send(p)
            end)
        end
    end
end
