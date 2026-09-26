-- Activate the tested Guilt integration; no gameplay damage, respawns or role changes.
assert(SERVER and engine.ActiveGamemode()=="zcity")
local function up(fn,key)
    for i=1,80 do local name,value=debug.getupvalue(fn,i);if not name then return end;if name==key then return value end end
end
local action=assert(net.Receivers.zc_welcome_action_v2)
local state,commit,sync=assert(up(action,"state")),assert(up(action,"Commit")),assert(up(action,"SyncTo"))
assert(not up(action,"loadError"),"Guide has a load error")
local candidate=assert(util.JSONToTable(file.Read("zc_guilt_review_guide.txt","DATA")))
assert(candidate.revision==19 and #candidate.pages==9)
assert(state.revision==18 or state.revision==19,"Guide changed during deployment")
if state.revision==18 then assert(util.SHA256(file.Read("zc_welcome.txt","DATA"))=="2d8c5465505a9d4305b842b8c12e7f43f31b265699fe3178f685777de2642e34") end
local specifications={{"zc_guilt_justice/core.lua","LUA","c3dd03a6c2b60cd616cce5a649b28183b38b0540702dfb6ab8cf66c206ca4ba5"},{"zc_guilt_justice/runtime.lua","LUA","d6144f28c25ab1cfe58566edb34306c75a537ed2ae1cab8f79199125807dde74"},{"zc_guilt_justice/menu.lua","LUA","bc9fcfecde62c425fb5748836f644c5247370e6e152343ae03ec552c238b26b4"},{"zc_guilt_justice/client.lua","LUA","87c326cab28d59edd466cc0a53a228ba2cb272c9bb060ce62f1002569a3158ef"},{"addons/zcity/gamemodes/zcity/gamemode/libraries/guilt/sv_guilt.lua","GAME","78ec37a10b9c611a42ef4081f3fbdc7443226211491d7341e5299c9336f5b078"},{"zc_guilt_justice/legacy_server.lua","LUA","fcb3abe85760a7cc475da48fa992f8c449b0baf665a3682e7929feeb13e4d975"},{"autorun/zc_karma_bounties.lua","LUA","95d6f17b06b6e74a23d498add3ef2ccd8d6fb68c59fb1263218eb07e444e08c4"}}
local compiled,sources={},{}
for _,item in ipairs(specifications) do
    local body=assert(file.Read(item[1],item[2]),item[1])
    assert(util.SHA256(body)==item[3],"Wrong source: "..item[1])
    local fn=CompileString(body,item[1],false);assert(isfunction(fn),tostring(fn))
    compiled[item[1]]=fn;sources[item[1]]=body
end
local archived={}
for id,data in pairs(ZCITY_GUILT and ZCITY_GUILT.Data or {}) do
    if data.case then
        archived[id]={caseid=data.case.id,rows={}}
        for account,r in pairs(data.case.rows or {}) do
            archived[id].rows[account]={karma=r.nativeKarma or r.karma,harm=r.harm,decided=r.decided,decision=r.decision}
        end
    end
end
if not file.Exists("zc_guilt_review_legacy_cases.txt","DATA") then file.Write("zc_guilt_review_legacy_cases.txt",util.TableToJSON(archived,true)) end
compiled["autorun/zc_karma_bounties.lua"]()
compiled["addons/zcity/gamemodes/zcity/gamemode/libraries/guilt/sv_guilt.lua"]()
compiled["zc_guilt_justice/legacy_server.lua"]()
local J,K=assert(ZCityGuiltJustice),assert(ZCityKarmaBounties)
assert(J.Version=="20260915.1" and K.Version=="20260915.2")
assert(isfunction(net.Receivers.zc_guilt_action_v3) and isfunction(J.Resolve))
assert(ZCITY_GUILT.Config.AllowPunish==false)
assert(ZCityFFBrain.Settings.victimScale==0.5 and ZCityFFBrain.KarmaRate(25)==0.004)
assert(ZCityDronesCompat.Version=="20260915.6" and ZCityPillCompat.Version=="20260915.7")
ZCityFFBrain.InstallPillBridge();ZCityFFBrain.InstallDamagePriority()
if state.revision==18 then local ok,err=commit(candidate);assert(ok,tostring(err)) end
state=assert(up(action,"state"));assert(state.revision==19 and #state.pages==9)
sync()
local source=sources["autorun/zc_karma_bounties.lua"]
local client=sources["zc_guilt_justice/client.lua"]
local bundle=util.Compress(util.TableToJSON({policy=source,client=client}))
assert(bundle and #bundle<60000)
local channel,ack="zc_justice_source_v1","zc_justice_ack_v1"
util.AddNetworkString(channel);util.AddNetworkString(ack)
local result={version=J.Version,bountyVersion=K.Version,ffVersion=ZCityFFBrain.Version,
    guideRevision=state.revision,guidePages=#state.pages,sent=0,received=0,passed=0,clients={}}
local targets=setmetatable({}, {__mode="k"})
local function save()file.Write("zc_guilt_review_deployed.json",util.TableToJSON(result,true))end
net.Receive(ack,function(bits,p)
    local entry=targets[p];if not entry or entry.acked or bits>128 then return end
    local ok=net.ReadBool();entry.acked=ok;result.received=result.received+1
    if ok then result.passed=result.passed+1 end
    result.clients[tostring(p:EntIndex())]=ok;save()
    print("ZCJ_CLIENT",p:EntIndex(),ok and "PASS" or "FAIL")
end)
local bootstrap=[[
net.Receive("zc_justice_source_v1",function()
    local raw=util.Decompress(net.ReadData(net.ReadUInt(16)))
    local data=raw and #raw<100000 and util.JSONToTable(raw)
    local ok=false
    if istable(data) and isstring(data.policy) and isstring(data.client)
        and util.SHA256(data.policy)=="95d6f17b06b6e74a23d498add3ef2ccd8d6fb68c59fb1263218eb07e444e08c4" and util.SHA256(data.client)=="87c326cab28d59edd466cc0a53a228ba2cb272c9bb060ce62f1002569a3158ef" then
        local f=CompileString(data.policy,"autorun/zc_karma_bounties.lua",false)
        local ui=CompileString(data.client,"zc_guilt_justice/client.lua",false)
        if isfunction(f) and isfunction(ui) then
            local previous=include
            local env=setmetatable({include=function(path)
                if path=="zc_guilt_justice/client.lua" then return ui() end
                return previous(path)
            end},{__index=_G,__newindex=_G})
            setfenv(f,env);ok=pcall(f)
            if ok and not (ZCityGuiltReview and ZCityGuiltReview.Version=="20260915.1" and isfunction(net.Receivers.zc_guilt_review_v3)) then ok=pcall(ui) end
        end
    end
    ok=ok and ZCityKarmaBounties and ZCityKarmaBounties.Version=="20260915.2"
        and ZCityGuiltReview and ZCityGuiltReview.Version=="20260915.1"
        and isfunction(net.Receivers.zc_guilt_review_v3)
    net.Start("zc_justice_ack_v1");net.WriteBool(ok==true);net.SendToServer()
end)
]]
assert(#bootstrap<6000)
local send
send=function(p)
    if not IsValid(p) or p:IsBot() then return end
    local entry=targets[p]
    if entry and (entry.acked or entry.attempts>=3) then return end
    if not entry then entry={attempts=0};targets[p]=entry;result.sent=result.sent+1 end
    entry.attempts=entry.attempts+1;p:SendLua(bootstrap)
    timer.Simple(1,function()
        if not IsValid(p) then return end
        net.Start(channel);net.WriteUInt(#bundle,16);net.WriteData(bundle,#bundle);net.Send(p)
    end)
    timer.Simple(5,function()send(p)end);save()
end
hook.Add("PlayerInitialSpawn","ZCityKarmaBounties_LiveDelivery",function(p)timer.Simple(8,function()send(p)end)end)
for _,p in ipairs(player.GetHumans()) do send(p) end
K.Publish();save()
print("ZCJ_ACTIVATED",J.Version,"bounty",K.Version,"guide",state.revision,"clients",result.sent)
