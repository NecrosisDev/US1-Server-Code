if not SERVER then return end
local payload=assert(util.JSONToTable(file.Read("zci_panel_stage/context-polish.txt","DATA")))
assert(payload.build=="20260923.context2" and util.SHA256(payload.source)==payload.hash)
assert(isfunction(CompileString(payload.source,"ContextPolishPreflight",false)))
local packed=assert(util.Compress(util.TableToJSON(payload))) assert(#packed<65536)
util.AddNetworkString("ZCI_ContextPolishPreview") util.AddNetworkString("ZCI_ContextPolishAck")
local sent={}
net.Receive("ZCI_ContextPolishAck",function(bits,p)
    if bits>16384 or not sent[p] or p:SteamID()~="STEAM_0:1:25635225" then return end
    local hash=net.ReadString() local ok=net.ReadBool() local detail=net.ReadString()
    if hash~=payload.hash then return end
    file.Write("zci_panel_stage/context-polish-ack.json",util.TableToJSON({hash=hash,ok=ok,detail=detail}))
end)
local bootstrap=[=[
net.Receive("ZCI_ContextPolishPreview",function()
    local n=net.ReadUInt(16) local p=util.JSONToTable(util.Decompress(net.ReadData(n)) or "")
    if not p or p.build~="20260923.context2" or util.SHA256(p.source)~=p.hash then return end
    local native=hg.CreateRadialMenu local press=hg.PressRadialMenu
    local fn=CompileString(p.source,"ZCI.ContextPolishPreview",false)
    local ok,err=isfunction(fn),isstring(fn) and fn or ""
    if ok then
        if ZCityInteractions.CloseActionPanel then ZCityInteractions.CloseActionPanel() end
        ok,err=xpcall(fn,debug.traceback)
    end
    ok=ok and hg.CreateRadialMenu==native and hg.PressRadialMenu==press
        and ZCityInteractions.CustomMenuVersion==p.build
    net.Start("ZCI_ContextPolishAck") net.WriteString(p.hash) net.WriteBool(ok==true)
    net.WriteString(ok and "Independent context UI loaded; native Q functions unchanged" or tostring(err):sub(1,1800)) net.SendToServer()
end)
]=]
for _,p in ipairs(player.GetHumans()) do
    if p:SteamID()=="STEAM_0:1:25635225" then
        sent[p]=true p:SendLua(bootstrap)
        timer.Simple(.5,function()
            if not IsValid(p) then return end
            net.Start("ZCI_ContextPolishPreview") net.WriteUInt(#packed,16) net.WriteData(packed,#packed) net.Send(p)
        end)
    end
end
