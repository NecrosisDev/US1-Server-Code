-- Scoped activation: preserve the current RTV phase, choices, votes and deadline.
assert(SERVER and engine.ActiveGamemode()=="zcity")
local M=assert(SolidMapVote);assert(M.initialized)
local function up(fn,key)
    for i=1,80 do local n,v=debug.getupvalue(fn,i);if not n then return end;if n==key then return v end end
end
local action=assert(net.Receivers.zc_welcome_action_v2)
local state,commit,sync=assert(up(action,"state")),assert(up(action,"Commit")),assert(up(action,"SyncTo"))
assert(not up(action,"loadError"))
local guide=assert(util.JSONToTable(file.Read("zc_admin_rtv_guide.txt","DATA")))
assert(guide.revision==22 and state.revision==21,"Guide changed; stop activation")
assert(util.SHA256(file.Read("zc_welcome.txt","DATA"))=="eb29604d6a936ab8b7aaf1b228fc14e4ede003c8a1f4769ecdc8a9172706572b")
local compiled,source={},{}
for _,s in ipairs({{name="sv_net",path="solidmapvote/core/server/sv_net.lua",hash="fb68f273f1aec490d5fcded6e1da369aafa24968c20761f05fb05843d2d5000c"},{name="sv_mapvote",path="solidmapvote/core/server/sv_mapvote.lua",hash="9581c501aae5f4b1fbb54bb0210fb681f58ce817da2ab50e4f15ca4017f4c9df"},{name="sv_reroll",path="solidmapvote/core/server/sv_reroll.lua",hash="948e34654a0cec98e722f752627088673714eded57c10c77cd71ee3297c3c9b6"},{name="cl_net",path="solidmapvote/core/client/cl_net.lua",hash="71ab444a04c3dc007c6f1173a88376153b518b9962ad7740cbd53aa0e6fe7e32"},{name="solidmapvote",path="solidmapvote/vgui/solidmapvote.lua",hash="3f2d274655280b616d89104fcf2c027823652978bb75f1028d4a5626a4128d13"},{name="solidmapvotebutton",path="solidmapvote/vgui/solidmapvotebutton.lua",hash="773560a508057431c9e621249b0c8e969b11987bdd07addc7cd6a065782adfe6"},{name="solidmapvotemap",path="solidmapvote/vgui/solidmapvotemap.lua",hash="0a1a3264bca36b6f7665fe7d8842aa9405a2580e64194a87351b8d0e52b3eb41"},{name="loader",path="autorun/sh_solidmapvote_loader.lua",hash="c014fcad973bb30e4b6ecc71453665052b1463fd581204392c7b847e6f5bf732"},{name="config",path="solidmapvote/sh_mapvote_config.lua",hash="1a5be1c5fa6c7b75042b3dce788c0760252fcb6851cf1653c7ed378d51361145"},{name="ff",path="autorun/server/zc_ff_brain.lua",hash="12b99cdbb3c40161bcfc798b180b3bafcff48a19bcd5403ec4f3efa65f4d7c93"}})do
    local text=assert(file.Read(s.path,"LUA"));assert(util.SHA256(text)==s.hash,s.path)
    local fn=CompileString(text,s.path,false);assert(isfunction(fn),tostring(fn))
    compiled[s.name]=fn;source[s.name]={path=s.path,body=text}
end
local previous={phase=M.phase,votes=M.votes,maps=M.maps,deadline=M.deadline}
compiled.ff();compiled.sv_net();compiled.sv_mapvote();compiled.sv_reroll()
M.Config["Enable Random"]=true
if M.phase=="voting" and M.ballotRevision==0 then M.beginBallotRevision()end
assert(M.phase==previous.phase and M.votes==previous.votes and M.maps==previous.maps and M.deadline==previous.deadline)
assert(ZCityFFBrain.Version=="20260915.6" and M.RerollVersion=="20260915.1")
for _,name in ipairs({"cl_net","solidmapvotebutton","solidmapvotemap","solidmapvote","loader","config"})do AddCSLuaFile(source[name].path)end
local ok,err=commit(guide);assert(ok,tostring(err));sync()
local bundle={source.cl_net,source.solidmapvotebutton,source.solidmapvotemap,source.solidmapvote}
local raw=util.TableToJSON(bundle);local packed=util.Compress(raw);assert(packed and #packed<60000)
local channel,ack="zc_admin_rtv_source_v1","zc_admin_rtv_ack_v1"
util.AddNetworkString(channel);util.AddNetworkString(ack)
local result={time=os.time(),ff=ZCityFFBrain.Version,reroll=M.RerollVersion,guide=22,
    sent=0,received=0,passed=0,clients={},map=game.GetMap(),phase=M.phase,
    mapPool=#M.mapPool,threshold=M.rerollThreshold(),random=M.Config["Enable Random"],
    scanner=ZCityScannerResponse and ZCityScannerResponse.Version,phasePreserved=true}
local targets=setmetatable({},{__mode="k"})
local function save()file.Write("zc_admin_rtv_deployed.json",util.TableToJSON(result,true))end
local function saveSoon()timer.Create("ZCityAdminRTV_Receipt",2,1,save)end
net.Receive(ack,function(bits,p)
    local t=targets[p];if not t or t.done or bits>32 then return end
    t.done=true;local success=net.ReadBool()
    result.received=result.received+1;if success then result.passed=result.passed+1 end
    result.clients[tostring(p:EntIndex())]=success;saveSoon()
end)
local bootstrap=[[
net.Receive("zc_admin_rtv_source_v1",function()
    local raw=util.Decompress(net.ReadData(net.ReadUInt(16)))
    local ok=raw and util.SHA256(raw)=="__BUNDLE_HASH__"
    if ok then
        local files=util.JSONToTable(raw)
        ok=istable(files) and #files==4
        if ok then
            SolidMapVote.close()
            for _,s in ipairs(files)do
                local fn=CompileString(s.body,s.path,false)
                if not isfunction(fn) or not pcall(fn) then ok=false;break end
            end
        end
    end
    local panel=vgui.GetControlTable("SolidMapVote")
    ok=ok and SolidMapVote.RerollClientVersion=="20260915.1" and panel and panel.RerollVersion=="20260915.1"
    if ok then
        SolidMapVote.Config["Enable Random"]=true;SolidMapVote.receivedSync=false
        RunConsoleCommand("solidmapvote_ready")
        timer.Simple(3,function()if not SolidMapVote.receivedSync then RunConsoleCommand("solidmapvote_ready")end end)
    end
    net.Start("zc_admin_rtv_ack_v1");net.WriteBool(ok==true);net.SendToServer()
end)
]]
bootstrap=string.Replace(bootstrap,"__BUNDLE_HASH__",util.SHA256(raw));assert(#bootstrap<6000)
local send
send=function(p)
    if not IsValid(p) or p:IsBot() then return end
    local t=targets[p]
    if t and (t.done or t.tries>=3) then return end
    if not t then t={tries=0};targets[p]=t;result.sent=result.sent+1 end
    t.tries=t.tries+1;p:SendLua(bootstrap)
    timer.Simple(1,function()
        if not IsValid(p)then return end
        net.Start(channel);net.WriteUInt(#packed,16);net.WriteData(packed,#packed);net.Send(p)
    end)
    timer.Simple(5,function()send(p)end);saveSoon()
end
hook.Add("PlayerInitialSpawn","ZCityAdminRTV_LiveDelivery",function(p)timer.Simple(8,function()send(p)end)end)
for _,p in ipairs(player.GetHumans())do send(p)end
save()
print("ZCITY_ADMIN_RTV_ACTIVATED",result.ff,result.reroll,"guide",result.guide)
