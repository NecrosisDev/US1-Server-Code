-- Owner-requested, one-client preview. No panel is opened and no action is performed.
local BUILD="20260922.panel1"
local OWNER="STEAM_0:1:25635225"
local payload=assert(file.Read("zci_panel_stage/payload.txt","DATA"))
local decoded=assert(util.JSONToTable(payload))
assert(isfunction(CompileString(decoded.source,"InteractionPanelPreflight",false)))
local packed=assert(util.Compress(payload))
assert(#packed<65536,"preview payload too large")
util.AddNetworkString("ZCI_PanelPreviewPayload")
util.AddNetworkString("ZCI_PanelPreviewAck")
ZCI_PanelPreview={build=BUILD,sent={},ack={},created=CurTime()}
local state=ZCI_PanelPreview
net.Receive("ZCI_PanelPreviewAck",function(bits,p)
    if bits>16384 or not state.sent[p] or p:SteamID()~=OWNER then return end
    local build=net.ReadString() local ok=net.ReadBool() local detail=net.ReadString()
    if build~=BUILD then return end
    state.ack[p]={ok=ok,detail=detail,time=CurTime()}
    file.Write("zci_panel_stage/owner-ack.json",util.TableToJSON({build=build,id=p:UserID(),ok=ok,detail=detail}))
    print("ZCI_PANEL_PREVIEW_ACK",p:UserID(),ok,detail)
end)
local bootstrap=[=[
net.Receive("ZCI_PanelPreviewPayload",function()
    local length=net.ReadUInt(16)
    local payload=util.JSONToTable(util.Decompress(net.ReadData(length)) or "")
    if not payload or payload.build~="20260922.panel1" then return end
    local fn=CompileString(payload.source,"ZCI.PanelPreview",false)
    local ok,why=isfunction(fn),isstring(fn) and fn or ""
    if ok then ok,why=xpcall(fn,debug.traceback) end
    if ok then
        local I=ZCityInteractions
        ok=I and I.CustomMenuVersion==payload.build and isfunction(I.OpenContextMenu)
            and not (hook.GetTable().HUDPaint or {})["ZCityInteractions.Feedback"]
            and not (hook.GetTable().Think or {})["hg-radial-menu"]
        why=ok and "Loaded; old strip/radial input absent; rendered check pending" or "UI ownership check failed"
    end
    if not ok then
        ErrorNoHalt("[Interaction panel preview] "..tostring(why).."\n")
        local rollback=CompileString(payload.rollback,"ZCI.PanelPreviewRollback",false)
        if isfunction(rollback) then xpcall(rollback,debug.traceback) end
    end
    net.Start("ZCI_PanelPreviewAck") net.WriteString(payload.build) net.WriteBool(ok==true)
    net.WriteString(tostring(why):sub(1,1800)) net.SendToServer()
end)
]=]
for _,p in ipairs(player.GetHumans()) do
    if p:SteamID()==OWNER then
        state.sent[p]=true p:SendLua(bootstrap)
        timer.Simple(1,function()
            if not IsValid(p) or p:SteamID()~=OWNER then return end
            net.Start("ZCI_PanelPreviewPayload") net.WriteUInt(#packed,16) net.WriteData(packed,#packed) net.Send(p)
        end)
    end
end
print("ZCI_PANEL_PREVIEW_STAGED",BUILD,#packed)
