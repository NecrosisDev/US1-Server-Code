-- Verified live update: policy/UI, audit logging, TDM-only retention and guide.
assert(SERVER and engine.ActiveGamemode()=="zcity")
local function up(fn,key)
    for i=1,80 do local n,v=debug.getupvalue(fn,i);if not n then return end;if n==key then return v end end
end
local action=assert(net.Receivers.zc_welcome_action_v2)
local state,commit,sync=assert(up(action,"state")),assert(up(action,"Commit")),assert(up(action,"SyncTo"))
assert(not up(action,"loadError"))
local guide=assert(util.JSONToTable(file.Read("zc_cleanup_guide.txt","DATA")))
assert(guide.revision==20 and #guide.pages==9)
assert(state.revision==19 or state.revision==20,"Guide changed; stop before activation")
if state.revision==19 then assert(util.SHA256(file.Read("zc_welcome.txt","DATA"))=="b674e885841f00d1025e3e9902b5b2225c9c6b690a11617cb73aea72d308ce43") end
local specifications={{"autorun/zc_karma_bounties.lua","8d0ac4de498fc70505a795041a9a12a29ff231953b555860acf969aad96c76b7"},{"autorun/server/zc_ff_brain.lua","1dbeeba327cbdf0add87fd5694b3deabddcf340f389c244614b248bbe0903839"},{"zc_guilt_justice/core.lua","0ba64db20026d2d25b5cd8dcd6709a5a371dd30e73e9b53518c5fa1e038df890"},{"zc_guilt_justice/runtime.lua","7a1ae2bb52c890344c53816fd1420a4d61fd46f9cdc2fcb1cde7df0102b39b52"}}
local compiled,sources={},{}
for _,s in ipairs(specifications)do
    local body=assert(file.Read(s[1],"LUA"),s[1]);assert(util.SHA256(body)==s[2],s[1])
    local fn=CompileString(body,s[1],false);assert(isfunction(fn),tostring(fn))
    compiled[s[1]]=fn;sources[s[1]]=body
end
compiled["autorun/zc_karma_bounties.lua"]()
compiled["autorun/server/zc_ff_brain.lua"]()
local K,F,J=assert(ZCityKarmaBounties),assert(ZCityFFBrain),assert(ZCityGuiltJustice)
assert(K.Version=="20260915.3" and F.Version=="20260915.4" and J.Version=="20260915.2")
assert(F.VictimScale(zb.modes.tdm)==0.75 and F.VictimScale(zb.modes.cstrike)==0.75)
assert(F.VictimScale(zb.modes.hmcd)==1 and F.VictimScale(zb.modes.fear)==1)
assert(F.VictimScale(zb.modes.coop)==1 and F.VictimScale(zb.modes.defense)==1)
assert(F.KarmaRate(25)==0.004 and ZCITY_GUILT.Config.AllowPunish==false)
F.InstallPillBridge();F.InstallDamagePriority();assert(J.InstallLegacy())
if state.revision==19 then local ok,err=commit(guide);assert(ok,tostring(err)) end
state=assert(up(action,"state"));assert(state.revision==20);sync()
local source=sources["autorun/zc_karma_bounties.lua"]
local packed=util.Compress(source);assert(packed and #packed<60000)
local channel,ack="zc_cleanup_source_v1","zc_cleanup_ack_v1"
util.AddNetworkString(channel);util.AddNetworkString(ack)
local result={bounty=K.Version,ff=F.Version,justice=J.Version,guide=state.revision,
    sent=0,received=0,passed=0,clients={},sourceHash=util.SHA256(source),tdmModes={}}
for name,m in pairs(zb.modes)do if F.VictimScale(m)==0.75 then result.tdmModes[#result.tdmModes+1]=name end end
table.sort(result.tdmModes)
ZCityCleanupDeployment=result
local targets=setmetatable({},{__mode="k"})
local function save()file.Write("zc_cleanup_deployed.json",util.TableToJSON(result,true))end
local function saveSoon()timer.Create("ZCityCleanup_SaveReceipt",2,1,save)end
net.Receive(ack,function(bits,p)
    local entry=targets[p];if not entry or entry.done or bits>32 then return end
    entry.done=true;local ok=net.ReadBool()
    result.received=result.received+1;if ok then result.passed=result.passed+1 end
    result.clients[tostring(p:EntIndex())]=ok;saveSoon()
end)
local bootstrap=[[
net.Receive("zc_cleanup_source_v1",function()
    local src=util.Decompress(net.ReadData(net.ReadUInt(16)))
    local ok=false
    if src and util.SHA256(src)=="8d0ac4de498fc70505a795041a9a12a29ff231953b555860acf969aad96c76b7" then
        local fn=CompileString(src,"autorun/zc_karma_bounties.lua",false)
        if isfunction(fn) then ok=pcall(fn) end
    end
    local k=ZCityKarmaBounties
    ok=ok and k and k.Version=="20260915.3" and isfunction(k.Preview)
    if ok then
        for _,target in ipairs(player.GetAll())do
            local text=k.Preview(LocalPlayer(),target)
            if text~=nil and text~="BOUNTY" then ok=false;break end
        end
    end
    net.Start("zc_cleanup_ack_v1");net.WriteBool(ok==true);net.SendToServer()
end)
]]
assert(#bootstrap<6000)
local send
send=function(p)
    if not IsValid(p) or p:IsBot() then return end
    local entry=targets[p]
    if entry and (entry.done or entry.tries>=3) then return end
    if not entry then entry={tries=0};targets[p]=entry;result.sent=result.sent+1 end
    entry.tries=entry.tries+1;p:SendLua(bootstrap)
    timer.Simple(1,function()
        if not IsValid(p) then return end
        net.Start(channel);net.WriteUInt(#packed,16);net.WriteData(packed,#packed);net.Send(p)
    end)
    timer.Simple(5,function()send(p)end);saveSoon()
end
hook.Add("PlayerInitialSpawn","ZCityKarmaBounties_LiveDelivery",function(p)timer.Simple(8,function()send(p)end)end)
for _,p in ipairs(player.GetHumans())do send(p)end
K.Publish();save()
-- No per-client console receipts; the deployment result is stored in DATA.
print("ZCITY_CLEANUP_ACTIVATED",K.Version,F.Version,"guide",state.revision)
