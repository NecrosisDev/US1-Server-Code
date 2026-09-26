-- Hot activation without recreating weapons, armor, fires, players, or their state.
assert(SERVER and engine.ActiveGamemode()=="zcity")
local files={{name="work",path="zc_tick_budget/work.lua",hash="ce443a607559a581d673cffa628698821a8bd1b8aad4819a6785b97bc09dc904"},{name="monitor",path="zc_tick_budget/monitor.lua",hash="8798983d2369dd86768adaed2ce2dfcda71a8e1c8f0d0d6c06d8a31b270c0b7f"},{name="budget",path="autorun/server/zc_tick_budget.lua",hash="a92d071a6b9787c1e4a76e2a99635631d82027a0a45895fcbf6cc679fdbccf3c"},{name="methods",path="zc_tick_budget/methods.lua",hash="1628b43c56e82a86108bbac05f01813ec9dac12ce0b8d882e13d94acf56ac3a4"},{name="weapon_shared",path="weapons/homigrad_base/shared.lua",hash="198e339f6376f25da81d57a9b0ec0db7fefbf98cea1eac0a274367002a35dc89"},{name="weapon_attachment",path="weapons/homigrad_base/sv_attachment.lua",hash="b8607b589a687448147d5b617cf472d36d831e1611499d2ec5f8d55be23daca2"},{name="armor",path="homigrad/sh_armorstuff.lua",hash="f586bf0c2a917a5eb957bf0d4cd916a35bdd01bec2d682de09fc543f11b3e7a2"},{name="fire",path="entities/vfire/shared.lua",hash="7484d7585f3a36ac47087a12dda7618908eb308da13493133faed0aab2ecb005"}};local compiled={}
for _,row in ipairs(files)do
    local body=assert(file.Read(row.path,"LUA"));assert(util.SHA256(body)==row.hash,row.path)
    body=body:gsub("^\239\187\191","")
    local fn=CompileString(body,row.path,false);assert(isfunction(fn),tostring(fn));compiled[row.name]=fn
end
assert(weapons.GetStored("homigrad_base"),"Weapon base missing")
local stored=assert(scripted_ents.GetStored("vfire"))
local replacement=table.Copy(stored.t)
local env=setmetatable({ENT=replacement},{__index=_G})
setfenv(compiled.fire,env);compiled.fire()
compiled.budget()
local B=assert(ZCTickBudget);assert(B.Install(),"Network sender changed; integration stopped")
compiled.methods()
local oldThink,oldBurn=stored.t.Think,stored.t.BurnThink
stored.t.Think=replacement.Think;stored.t.BurnThink=replacement.BurnThink
local fires=0
for _,e in ipairs(ents.FindByClass("vfire"))do
    if e.Think==oldThink then e.Think=replacement.Think end
    if e.BurnThink==oldBurn then e.BurnThink=replacement.BurnThink end
    fires=fires+1
end
assert(B.Version=="20260916.1" and hook.GetTable().Tick.ZCityTickBudget==B.Step)
assert(FindMetaTable("Entity").SendNetVar==B.entitySender.wrapper)
B.integrationVersion="20260916.1"
local result=B.Snapshot()
result.time=os.time();result.activeFires=fires
result.weaponSyncSource=debug.getinfo(hg.SyncWeapons,"S").short_src
result.armorLookupSource=debug.getinfo(hg.GetArmorPlacement,"S").short_src
result.fireThinkSource=debug.getinfo(stored.t.Think,"S").short_src
result.ff=ZCityFFBrain and ZCityFFBrain.Version
result.scanner=ZCityScannerResponse and ZCityScannerResponse.Version
result.fake=hg.SupercrusherFakeVersion
result.rtv=SolidMapVote and SolidMapVote.RerollVersion
file.CreateDir("zc_tick_budget")
file.Write("zc_tick_budget/deployed.json",util.TableToJSON(result,true))
RunConsoleCommand("zc_budget_capture","60")
print("ZCITY_TICK_BUDGET_ACTIVATED",B.Version,"soft-ms",B.limit:GetFloat())
