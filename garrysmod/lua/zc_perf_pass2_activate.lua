-- Scoped performance update. Do not restart the server or touch gameplay state.
assert(SERVER and engine.ActiveGamemode()=="zcity")
assert(not (ZCPERF and ZCPERF.wrapped),"Existing profiler is active; postpone activation")
assert(not (ZCPerfPass2 and ZCPerfPass2.active),"Perf2 capture is active")
local toz=assert(weapons.GetStored("weapon_toz194"),"TOZ weapon definition missing")
assert(util.SHA256(file.Read("weapons/weapon_toz194.lua","LUA"))=="479827c74314e9a3395ebec84af951cb98ed12f511a99c7eeacd9092cf4bd9d3","Mounted TOZ source changed")
assert(debug.getinfo(toz.ModelCreated,"S").short_src:find("weapons/weapon_toz194.lua",1,true),"TOZ callback was replaced externally")
local compiled,source={},{}
for _,row in ipairs({{name="profile",path="autorun/server/zc_perf_pass2.lua",hash="4e3f9b960166cb9d4537918ba25c1ddf8918348e7d5fed7719a9e5a3f549e64d"},{name="budget",path="autorun/server/zc_tick_budget.lua",hash="dd03d56a913796643f999b20c23fc75365c3ac094ce72f550d7265769377550f"},{name="toz_guard",path="autorun/sh_zc_perf2_toz.lua",hash="e62da0886cf50a3032fc8faf1dbd9ab08dd9b214e08336212a717120885b1fc2"},{name="client_methods",path="zc_perf_pass2/client_methods.lua",hash="3ee177e2bf5886e632cfde19cf88832024aeccf74a745806544ee256ab3d8746"},{name="worldmodel",path="weapons/homigrad_base/sh_worldmodel.lua",hash="2864ca0686448fb05859948e319c9d92f356cd034ae6e5d109cae986f7bbe86c"}})do
    local text=assert(file.Read(row.path,"LUA"));assert(util.SHA256(text)==row.hash,row.path)
    local fn=CompileString(text:gsub("^\239\187\191",""),row.path,false);assert(isfunction(fn),tostring(fn))
    compiled[row.name]=fn;source[row.name]={path=row.path,body=text}
end
local B=assert(ZCTickBudget)
local queues,owners=B.queues,B.byOwner
compiled.budget();compiled.profile();compiled.toz_guard()
assert(B.Version=="20260916.2" and B.queues==queues and B.byOwner==owners)
assert(B.entitySender.wrapper==FindMetaTable("Entity").SendNetVar)
assert(toz.ModelCreated==ZCPerf2TOZ.ModelCreated and toz.ZCTozBoneGuard=="20260916.1")
B.integrationVersion="20260916.2"
for _,key in ipairs({"worldmodel","client_methods","toz_guard"})do AddCSLuaFile(source[key].path)end
local bundle={source.toz_guard,source.client_methods}
local raw=util.TableToJSON(bundle);local packed=assert(util.Compress(raw));assert(#packed<60000)
local token=os.time()%4294967295
local result={version="20260916.1",time=os.time(),token=token,map=game.GetMap(),
    budget=B.Version,profile=ZCPerfPass2.Version,toz=ZCPerf2TOZ.Version,
    targets=0,received=0,passed=0,clients={},queuesPreserved=true,
    ff=ZCityFFBrain.Version,scanner=ZCityScannerResponse.Version,rtv=SolidMapVote.RerollVersion,
    fake=hg.SupercrusherFakeVersion,pill=ZCityPillCompat.Version,drone=ZCityDronesCompat.Version}
local channel,ack="zc_perf2_bundle_v1","zc_perf2_bundle_ack_v1"
util.AddNetworkString(channel);util.AddNetworkString(ack)
local targets=setmetatable({},{__mode="k"})
local function save()
    file.CreateDir("zc_perf_pass2")
    file.Write("zc_perf_pass2/deployed.json",util.TableToJSON(result,true))
end
local function saveSoon()timer.Create("ZCPerf2_Receipt",2,1,save)end
net.Receive(ack,function(bits,p)
    local t=targets[p];if not t or t.done or bits<41 or bits>4096 then return end
    if net.ReadUInt(32)~=token then return end
    local ok=net.ReadBool();local reason=net.ReadString():sub(1,240)
    if t.ack==nil then result.received=result.received+1 end
    t.ack=ok;t.done=ok
    if ok then result.passed=result.passed+1 end
    result.clients[t.id]={ok=ok,error=not ok and reason or nil};saveSoon()
end)
local bootstrap=[[
net.Receive("zc_perf2_bundle_v1",function()
    local token=net.ReadUInt(32)
    local raw=util.Decompress(net.ReadData(net.ReadUInt(16)))
    if token~=__TOKEN__ then return end
    local function ack(ok,reason)
        net.Start("zc_perf2_bundle_ack_v1");net.WriteUInt(token,32)
        net.WriteBool(ok);net.WriteString(tostring(reason or ""):sub(1,240));net.SendToServer()
    end
    if ZCPerf2BundleApplied==token then ack(true);return end
    if not raw or util.SHA256(raw)~="__BUNDLE_HASH__" then ack(false,"Source checksum mismatch");return end
    local files=util.JSONToTable(raw)
    if not istable(files) or #files~=2 then ack(false,"Invalid source bundle");return end
    local attempts=0
    local function apply()
        attempts=attempts+1
        if not weapons.GetStored("homigrad_base") or not weapons.GetStored("weapon_toz194") then
            if attempts<8 then timer.Simple(1,apply)else ack(false,"Weapon definitions not ready")end
            return
        end
        local ok,err=pcall(function()
            for _,s in ipairs(files)do
                local fn=CompileString(s.body,s.path,false);assert(isfunction(fn),tostring(fn));fn()
            end
            local b=weapons.GetStored("homigrad_base");local t=weapons.GetStored("weapon_toz194")
            assert(ZCPerf2Client and ZCPerf2Client.Version=="20260916.1")
            assert(b.WorldModel_Transform==ZCPerf2Client.methods.WorldModel_Transform)
            assert(b.WorldModel_Transform_Holstered==ZCPerf2Client.methods.WorldModel_Transform_Holstered)
            assert(t.ModelCreated==ZCPerf2TOZ.ModelCreated)
            assert(t.AnimsEvents.base_reload_insert[0.1]==ZCPerf2TOZ.Insert)
            assert(t.AnimsEvents.base_reload_end[0]==ZCPerf2TOZ.EndReload)
        end)
        if ok then ZCPerf2BundleApplied=token end
        ack(ok,err)
    end
    apply()
end)
]]
bootstrap=string.Replace(bootstrap,"__TOKEN__",tostring(token))
bootstrap=string.Replace(bootstrap,"__BUNDLE_HASH__",util.SHA256(raw));assert(#bootstrap<6000)
local send
send=function(p)
    if not IsValid(p) or p:IsBot() then return end
    local t=targets[p]
    if t and (t.done or t.tries>=3) then return end
    if not t then t={tries=0,id=tostring(p:UserID())};targets[p]=t;result.targets=result.targets+1 end
    t.tries=t.tries+1;p:SendLua(bootstrap)
    timer.Simple(1,function()
        if not IsValid(p) or t.done then return end
        net.Start(channel);net.WriteUInt(token,32);net.WriteUInt(#packed,16)
        net.WriteData(packed,#packed);net.Send(p)
    end)
    timer.Simple(12,function()send(p)end);saveSoon()
end
hook.Add("PlayerInitialSpawn","ZCPerf2_LiveDelivery",function(p)timer.Simple(8,function()send(p)end)end)
for _,p in ipairs(player.GetHumans())do send(p)end
save()
print("ZCITY_PERF_PASS2_ACTIVATED",result.version,"budget",B.Version)
