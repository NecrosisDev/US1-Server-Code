-- Hash-checked activation. No test damage, role reroll, respawn, map change or restart.
assert(SERVER and engine.ActiveGamemode()=="zcity")
local function up(fn,key)
    for i=1,80 do local n,v=debug.getupvalue(fn,i);if not n then return end;if n==key then return v end end
end
local action=assert(net.Receivers.zc_welcome_action_v2)
local state,commit,sync=assert(up(action,"state")),assert(up(action,"Commit")),assert(up(action,"SyncTo"))
assert(not up(action,"loadError"),"Guide locked")
local guide=assert(util.JSONToTable(file.Read("zc_meta_guide.txt","DATA")))
assert(guide.revision==23 and #guide.pages==10)
assert(state.revision==22 or state.revision==guide.revision,"Guide changed")
if state.revision==22 then assert(util.SHA256(file.Read("zc_welcome.txt","DATA"))=="4b1ec4e385e5121ec91eedd010eb0fd7055c044bcf844fe3660149afebaa77f0") end
if state.revision==guide.revision then
    assert(#state.pages==#guide.pages)
    for i,p in ipairs(guide.pages)do assert(state.pages[i].id==p.id and state.pages[i].body==p.body) end
end
local specifications={{path="zc_guilt_justice/meta.lua",realm="LUA",hash="572104258d3039ceaa6620fd8dd41d25c891caae94e3987cc2a525f9c6974f33"},{path="zc_guilt_justice/roles.lua",realm="LUA",hash="41a291d2552be91716689a7b3a61d4517cb383e82b5017daa062e93b5496895c"},{path="zc_guilt_justice/core.lua",realm="LUA",hash="7d44af13c1315b258d8de248ea868524e38bb38243de5e741964ca012f523fe5"},{path="zc_guilt_justice/runtime.lua",realm="LUA",hash="2a97318d1bb0027d56aadbda2fddd21eefed6c354a16fb0f5a49eaf187b75734"},{path="zc_guilt_justice/menu.lua",realm="LUA",hash="3f5c93a9d153d3e396cef1c1ee74d99a3c647060722dfcabbfe7fac256438a17"},{path="zc_guilt_justice/client.lua",realm="LUA",hash="73dd50660d5dd5999f1f82f8efedb28aaf4b10a3b9200ca870bfd86f0f6d0be9"},{path="zc_guilt_justice/combat_runtime.lua",realm="LUA",hash="dc9fb546c71d30832527445d518bd4e2dd140fbe79cf3585614b3ac66d22dca1"},{path="zc_guilt_justice/legacy_server.lua",realm="LUA",hash="7287b63b20f849440164ea77f5f966500ae1e3e6e2fccac53bfd0d79fb74c3de"},{path="autorun/zc_karma_bounties.lua",realm="LUA",hash="d0c2e35cf78799dc3650862f3f2d2063f48b332a5add4522ffde78a7a2fba848"},{path="addons/zcity/gamemodes/zcity/gamemode/libraries/guilt/sv_guilt.lua",realm="GAME",hash="51e9ecb30d54f6520aebadd9bb27c9e227357fb24a85014c872ff53fda3c7c8d"},{path="autorun/server/zc_ff_brain.lua",realm="LUA",hash="96049aecf6719ea397d144b1c5413c8da81b714e01a348d0964b720e43a9808d"},{path="addons/zc_wildwest_karma/lua/autorun/server/sv_zc_wildwest_karma.lua",realm="GAME",hash="044be4184751158fae9341c987237156a15932881d7c697f2d8f18b68e7def82"},{path="addons/zc_traitor_population/lua/autorun/server/sv_zc_traitor_population.lua",realm="GAME",hash="0f868ce37b1d67b411afce2fe174b67a4597ca330359b12dd0e0f69fbcf8e6d7"}}
local functions,sources={},{}
for _,item in ipairs(specifications)do
    local body=assert(file.Read(item.path,item.realm),item.path)
    assert(util.SHA256(body)==item.hash,item.path)
    local fn=CompileString(body,item.path,false);assert(isfunction(fn),tostring(fn))
    functions[item.path]=fn;sources[item.path]=body
end
local roleSnapshots={}
for _,p in ipairs(player.GetAll())do roleSnapshots[p]={p.isTraitor,p.SubRole,p.MainTraitor} end
functions["autorun/zc_karma_bounties.lua"]()
functions["addons/zcity/gamemodes/zcity/gamemode/libraries/guilt/sv_guilt.lua"]()
functions["autorun/server/zc_ff_brain.lua"]()
functions["zc_guilt_justice/legacy_server.lua"]()
ZCityGuiltJustice.legacyHandler=net.Receivers.zcity_guilt_action
functions["addons/zc_wildwest_karma/lua/autorun/server/sv_zc_wildwest_karma.lua"]()
functions["addons/zc_traitor_population/lua/autorun/server/sv_zc_traitor_population.lua"]()
local M,J,F,K=assert(ZCityMetaSafety),assert(ZCityGuiltJustice),assert(ZCityFFBrain),assert(ZCityKarmaBounties)
assert(M.Version=="20260916.1" and F.Version==M.Version and J.Version==M.Version and K.Version==M.Version)
assert(not M.loadError and not J.queueLocked)
for p,r in pairs(roleSnapshots)do assert(p.isTraitor==r[1] and p.SubRole==r[2] and p.MainTraitor==r[3],"Existing role changed") end
F.InstallPillBridge();F.InstallDamagePriority();assert(J.InstallLegacy())
M.InstallRoles();M.Tick()
assert(M.roleAudit[ZC_TRAITOR_POPULATION.original],"Population selector was not protected")
assert(M.roleAudit[zb.modes.hmcd.SpawnPlayers] and M.roleAudit[zb.modes.fear.Intermission])
assert(F.VictimScale(zb.modes.tdm)==0.75 and F.VictimScale(zb.modes.cstrike)==0.75)
assert(F.VictimScale(zb.modes.hmcd)==1 and F.VictimScale(zb.modes.fear)==1)
assert(F.KarmaRate(25)==0.004 and ZCITY_GUILT.Config.AllowPunish==false)
if M.Locked() then
    for _,p in ipairs(player.GetAll())do assert(#J.Payload(p)==0) end
end
if state.revision==22 then local ok,err=commit(guide);assert(ok,tostring(err)) end
state=assert(up(action,"state"));assert(state.revision==guide.revision);sync()
local source=sources["autorun/zc_karma_bounties.lua"]
local compressed=util.Compress(source);assert(compressed and #compressed<60000)
local channel,ack="zc_meta_source_v1","zc_meta_ack_v1"
util.AddNetworkString(channel);util.AddNetworkString(ack)
local result={version=M.Version,guide=state.revision,sent=0,received=0,passed=0,clients={},
    hidden=M.Locked()==true,sourceHash=util.SHA256(source),rolesProtected=true,tdmRetention=0.75,otherRetention=1}
ZCityMetaDeployment=result
local targets=setmetatable({},{__mode="k"})
local function save()file.Write("zc_meta_deployed.json",util.TableToJSON(result,true))end
local function saveSoon()timer.Create("ZCityMetaSafety_Receipt",2,1,save)end
net.Receive(ack,function(bits,p)
    local entry=targets[p];if not entry or entry.done or bits>32 then return end
    entry.done=true;local ok=net.ReadBool();result.received=result.received+1
    if ok then result.passed=result.passed+1 end
    result.clients[tostring(p:UserID())]=ok;saveSoon()
end)
local bootstrap=[[
net.Receive("zc_meta_source_v1",function()
    local source=util.Decompress(net.ReadData(net.ReadUInt(16)))
    local ok=false
    if source and util.SHA256(source)=="d0c2e35cf78799dc3650862f3f2d2063f48b332a5add4522ffde78a7a2fba848" then
        local fn=CompileString(source,"autorun/zc_karma_bounties.lua",false)
        if isfunction(fn) then ok=pcall(fn) end
    end
    local K,C=ZCityKarmaBounties,ZCityGuiltReview
    ok=ok and K and C and K.Version=="20260916.1" and C.Version=="20260916.1"
        and isfunction((hook.GetTable().Think or {}).ZCityGuiltReview_MetaGuard)
    if ok then
        for _,p in ipairs(player.GetAll())do
            local text=K.Preview(LocalPlayer(),p)
            if text and text~="BOUNTY" then ok=false end
        end
        if GetGlobalBool("zc_meta_review_hold",false) and IsValid(C.frame) then ok=false end
    end
    net.Start("zc_meta_ack_v1");net.WriteBool(ok==true);net.SendToServer()
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
        net.Start(channel);net.WriteUInt(#compressed,16);net.WriteData(compressed,#compressed);net.Send(p)
    end)
    timer.Simple(5,function()send(p)end);saveSoon()
end
hook.Add("PlayerInitialSpawn","ZCityKarmaBounties_LiveDelivery",function(p)timer.Simple(8,function()send(p)end)end)
for _,p in ipairs(player.GetHumans())do send(p)end
K.Publish();M.Save();save()
print("ZCITY_META_ACTIVATED",M.Version,"guide",state.revision)
