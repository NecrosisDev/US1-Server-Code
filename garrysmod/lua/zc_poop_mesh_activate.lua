assert(SERVER and engine.ActiveGamemode()=="zcity")
include("autorun/server/zc_poop.lua")
assert(ZCityPoop.Version=="20260918.3"and ZCityPoop.Cooldown==30 and ZCityPoop.Limit==2)
assert(concommand.GetTable().poop==ZCityPoop.Callback)
local bytes=assert(file.Read("zc_poop/assets_v3.dat","DATA"))
local raw=assert(util.Decompress(bytes,8535114))
assert(#raw==8535114 and util.SHA256(raw)=="fcc5bb4b0d4e794dfb672c1c8710a7f75bf75fcdc87f13a973399b06865e03a0")
local visual=assert(file.Read("autorun/client/zc_poop_visuals.lua","LUA"))
assert(isfunction(CompileString(visual,"poop_visual_compile",false)))
local count=0
for _,p in ipairs(player.GetAll())do if not p:IsBot()then p:SendLua(visual);count=count+1 end end
local existing=0
for e in pairs(ZCityPoop.owned)do if IsValid(e)then
 e:SetNoDraw(false);e:SetNW2Bool("zc_poop",true);ZCityPoop.MakeStain(e);existing=existing+1
end end
file.Write("zc_poop/mesh_deployed.json",util.TableToJSON({version=ZCityPoop.Version,time=os.time(),
 clients_sent=count,existing_props=existing,cooldown=30,limit=2,archive_verified=true},true))
print("ZC_POOP_MESH_DECAL_DEPLOYED",ZCityPoop.Version,count,existing)
