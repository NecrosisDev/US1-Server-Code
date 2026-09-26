-- Explicit, hash-checked hot deployment on Goob's ZCity. No test damage or respawns.
assert(SERVER and engine.ActiveGamemode()=="zcity")
local function upvalue(fn,wanted)
    if not isfunction(fn) then return end
    for i=1,60 do local name,value=debug.getupvalue(fn,i);if not name then return end;if name==wanted then return value end end
end
local action=assert(net.Receivers.zc_welcome_action_v2)
local state=assert(upvalue(action,"state"));local commit=assert(upvalue(action,"Commit"))
local sync=assert(upvalue(action,"SyncTo"));local valid=assert(upvalue(action,"ValidPages"))
assert(not upvalue(action,"loadError"),"Guide is locked: stop before deployment")
local candidate=assert(util.JSONToTable(file.Read("zkb_guide_candidate.txt","DATA")))
assert(valid(candidate.pages) and candidate.version==2 and candidate.revision==18)
assert(state.revision==17 or state.revision==18,"Guide changed: reconcile instead of overwriting")
if state.revision==17 then assert(util.SHA256(file.Read("zc_welcome.txt","DATA"))=="794a2d7e118f88c1bfa21af7a29d35f53819dc071d3d258a0feb7cdcf9fcbb93") end
if state.revision==18 then assert(state.pages[4] and state.pages[4].title=="KARMA BOUNTIES" and state.pages[4].body==candidate.pages[4].body,"Guide changed") end
local specifications={
    {"autorun/zc_karma_bounties.lua","LUA","1933c01f8d926de27ed07a70dfa8aa68bfa7393394f2b7c09f764ddf6a400b7e"},
    {"addons/zcity/gamemodes/zcity/gamemode/libraries/guilt/sv_guilt.lua","GAME","7a53c018e9573aae83fe06a5ac677f81aff4a59e748aa222fa42f26f859c3fe8"},
    {"autorun/server/zc_ff_brain.lua","LUA","84fe4511c1873c8ac089a5ae85274305b2a0c79852e46e5cdc0f40d262c11381"}
}
local functions={};local source
for i,item in ipairs(specifications) do
    local body=assert(file.Read(item[1],item[2]),item[1]);assert(util.SHA256(body)==item[3],item[1])
    local fn=CompileString(body,item[1],false);assert(isfunction(fn),tostring(fn));functions[i]=fn
    if i==1 then source=body end
end
AddCSLuaFile("autorun/zc_karma_bounties.lua")
for _,fn in ipairs(functions) do fn() end
local K=assert(ZCityKarmaBounties);assert(K.Version=="20260915.1" and ZCityFFBrain.Version=="20260915.3")
ZCityFFBrain.InstallPillBridge();ZCityFFBrain.InstallDamagePriority()
if state.revision==17 then local ok,err=commit(candidate);assert(ok,tostring(err)) end
state=assert(upvalue(action,"state"))
assert(state.revision==18 and #state.pages==8)
local actualPage
for _,p in ipairs(state.pages) do if p.title=="KARMA BOUNTIES" then actualPage=p end end
assert(actualPage and actualPage.body==candidate.pages[4].body,"Unexpected guide contents")
sync()
local targets=setmetatable({}, {__mode="k"})
local result={version=K.Version,ffVersion=ZCityFFBrain.Version,guideRevision=state.revision,
    guidePages=#state.pages,sent=0,received=0,passed=0,clients={},curve={}}
for _,n in ipairs({0,25,50,100,120}) do result.curve[tostring(n)]=K.Value(n) end
ZCityKarmaBountyDeployment=result
local function save()file.Write("zkb_deployment.json",util.TableToJSON(result,true))end
local channel,ack="zkb_source_20260915","zkb_ack_20260915"
util.AddNetworkString(channel);util.AddNetworkString(ack)
net.Receive(ack,function(bits,p)
    if bits>1024 or not targets[p] or targets[p].acked then return end
    local ok=net.ReadBool();targets[p].acked=true;result.received=result.received+1
    if ok then result.passed=result.passed+1 end
    result.clients[tostring(p:EntIndex())]=ok;save()
    print("ZKB_CLIENT",p:EntIndex(),ok and "PASS" or "FAIL")
end)
local compressed=util.Compress(source);assert(compressed and #compressed<60000)
local bootstrap=[[
net.Receive("zkb_source_20260915",function()
    local body=util.Decompress(net.ReadData(net.ReadUInt(16)))
    local ok=false
    if body and util.SHA256(body)=="1933c01f8d926de27ed07a70dfa8aa68bfa7393394f2b7c09f764ddf6a400b7e" then
        local fn=CompileString(body,"autorun/zc_karma_bounties.lua",false)
        if isfunction(fn) then ok=pcall(fn) end
    end
    local k=ZCityKarmaBounties
    ok=ok and k and k.Version=="20260915.1" and k.Value(120)==-30 and k.Value(100)==-20
        and k.Value(50)==-10 and k.Value(25)==0 and k.Value(0)==10
        and isfunction((hook.GetTable().HUDPaint or {}).ZCityKarmaBounties_TargetLine)
    net.Start("zkb_ack_20260915");net.WriteBool(ok==true);net.SendToServer()
end)
]]
assert(#bootstrap<6000)
local send
send=function(p)
    if not IsValid(p) or p:IsBot() then return end
    local entry=targets[p]
    if entry and (entry.acked or entry.attempts>=3) then return end
    if not entry then entry={attempts=0};targets[p]=entry;result.sent=result.sent+1 end
    entry.attempts=entry.attempts+1
    p:SendLua(bootstrap)
    timer.Simple(1,function()
        if not IsValid(p) then return end
        net.Start(channel);net.WriteUInt(#compressed,16);net.WriteData(compressed,#compressed);net.Send(p)
    end)
    timer.Simple(5,function()send(p)end)
    save()
end
for _,p in ipairs(player.GetHumans()) do send(p) end
hook.Add("PlayerInitialSpawn","ZCityKarmaBounties_LiveDelivery",function(p)timer.Simple(8,function()send(p)end)end)
K.Publish();save()
print("ZKB_ACTIVATED",K.Version,"guide",state.revision,"clients",result.sent)
