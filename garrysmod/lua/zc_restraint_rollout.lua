if not SERVER then return end
local function rollout()
local data=assert(util.JSONToTable(file.Read("zci_panel_stage/restraints-runtime.txt","DATA")))
assert(data.build=="20260923.restraints1")
-- The accepted server trial must still be active; do not reload occupied sessions.
assert(isfunction(hg.SetHandcuffed) and isfunction(ZCityHostage.Gameplay.CanUseCuffKey))
assert(isfunction(weapons.GetStored("weapon_handcuffs_key").CanUnTie))
local restraintSource=debug.getinfo(ZCityHostage.Gameplay.RestraintChanged,"S").source
assert(string.find(restraintSource,"RestraintTrial/posture_controller",1,true)
    or string.find(restraintSource,"zcity_hostage/sv_gameplay.lua",1,true))
-- Source auto-refresh can replace the trial closure with the installed file.
-- The old function only ended a session; the accepted one owns phase transitions.
local postureAware=false
for index=1,20 do
    local name=debug.getupvalue(ZCityHostage.Gameplay.RestraintChanged,index)
    if not name then break end
    if name=="phase" then postureAware=true end
end
assert(postureAware,"The accepted restraint transition owner is not active")
for _,r in ipairs(data.client) do
    assert(util.SHA256(r.source)==r.hash)
    assert(isfunction(CompileString(r.source,"RestraintRolloutPreflight/"..r.name,false)))
end
local packed=assert(util.Compress(util.TableToJSON({build=data.build,files=data.client}))) assert(#packed<65536)
util.AddNetworkString("ZCI_RestraintRollout") util.AddNetworkString("ZCI_RestraintRolloutAck")
local state={sent={},ack={}} ZCI_RestraintRollout=state
local function status()
    local out={time=os.time(),build=data.build,humans=0,applied=0,pending=0,failed={}}
    for _,p in ipairs(player.GetHumans()) do
        out.humans=out.humans+1 local a=state.ack[p]
        if a and a.ok then out.applied=out.applied+1
        elseif a then out.failed[#out.failed+1]={id=p:UserID(),detail=a.detail}
        else out.pending=out.pending+1 end
    end
    local joins=hook.GetTable().PlayerInitialSpawn or {}
    out.joinActive=isfunction(joins["ZCityInteractions.RestraintJoin"])
    out.oldJoinsRetired=joins["ZCityInteractions.CircleJoin"]==nil and joins["ZCityInteractions.RadialRestoreJoin"]==nil
    file.Write("zci_panel_stage/restraints-rollout-status.json",util.TableToJSON(out))
end
net.Receive("ZCI_RestraintRolloutAck",function(bits,p)
    if bits>16384 or not state.sent[p] then return end
    local build=net.ReadString() local ok=net.ReadBool() local detail=net.ReadString()
    if build~=data.build then return end
    state.ack[p]={ok=ok,detail=detail} status()
end)
local bootstrap=[=[
net.Receive("ZCI_RestraintRollout",function()
    local n=net.ReadUInt(16) local data=util.JSONToTable(util.Decompress(net.ReadData(n)) or "")
    if not data or data.build~="20260923.restraints1" then return end
    local compiled={}
    for _,r in ipairs(data.files) do
        if util.SHA256(r.source)~=r.hash then return end
        compiled[#compiled+1]=CompileString(r.source,"RestraintRollout/"..r.name,false)
    end
    local function apply()
        local native,press=hg.CreateRadialMenu,hg.PressRadialMenu
        local ok,err=xpcall(function()
            for _,fn in ipairs(compiled) do assert(isfunction(fn),tostring(fn)) end
            if ZCityInteractions.CustomMenuVersion~=data.build then for _,fn in ipairs(compiled) do fn() end end
            assert(ZCityInteractions.CustomMenuVersion==data.build and isfunction(hg.SetHandcuffed))
            assert(isfunction(ZCityHostage.Gameplay.CanUseCuffKey) and isfunction(weapons.GetStored("weapon_handcuffs_key").CanUnTie))
            assert(hg.CreateRadialMenu==native and hg.PressRadialMenu==press)
        end,debug.traceback)
        net.Start("ZCI_RestraintRolloutAck") net.WriteString(data.build) net.WriteBool(ok)
        net.WriteString(ok and "Merged restraint controls active; native Q unchanged" or tostring(err):sub(1,1800)) net.SendToServer()
    end
    for _,name in ipairs({"ZCI_CircleRollout","ZCI_CirclePreview","ZCI_ContextPolishPreview","ZCI_RadialRestore","ZCI_PanelRolloutPayload","ZCI_PanelPreviewPayload"}) do net.Receive(name,function()end) end
    timer.Remove("ZCI.CircleRetiredBuildGuard") timer.Remove("ZCI.RadialRestoreGuard")
    apply()
    timer.Create("ZCI.RestraintRetiredBuildGuard",5,6,function()
        local v=ZCityInteractions and ZCityInteractions.CustomMenuVersion
        if v=="20260923.circle1" or v=="20260923.separate1" or v=="20260923.context2" then apply() end
    end)
end)
]=]
local function send(p)
    if not IsValid(p) or p:IsBot() then return end
    state.sent[p]=true p:SendLua(bootstrap)
    timer.Simple(.5,function()
        if not IsValid(p) then return end
        net.Start("ZCI_RestraintRollout") net.WriteUInt(#packed,16) net.WriteData(packed,#packed) net.Send(p)
    end)
end
for _,name in ipairs({"ZCityInteractions.CircleJoin","ZCityInteractions.RadialRestoreJoin","ZCityInteractions.PanelJoin"}) do hook.Remove("PlayerInitialSpawn",name) end
hook.Remove("PlayerDisconnected","ZCityInteractions.CircleDepart")
hook.Add("PlayerInitialSpawn","ZCityInteractions.RestraintJoin",function(p)timer.Simple(15,function()send(p)status()end)end)
hook.Add("PlayerDisconnected","ZCityInteractions.RestraintDepart",function(p)state.sent[p]=nil state.ack[p]=nil timer.Simple(0,status)end)
state.Status=status state.Send=send
for _,p in ipairs(player.GetHumans()) do send(p) end
status()
end
local ok,err=xpcall(rollout,debug.traceback)
file.Write("zci_panel_stage/restraints-rollout-launch.json",util.TableToJSON({ok=ok,detail=tostring(err),time=os.time(),source=isfunction(ZCityHostage.Gameplay.RestraintChanged) and debug.getinfo(ZCityHostage.Gameplay.RestraintChanged,"S").source or "missing"}))
