-- Server-only update; do not force any live player into or out of fake.
assert(SERVER and engine.ActiveGamemode()=="zcity")
local C=assert(ZCityPillCompat)
local functions={}
for _,s in ipairs({{name="fake",path="homigrad/fake/sv_tier_0.lua",hash="178793573f6a34e7aa5ad430514070b077e5903c5ba3b728cabed4bd1ed0dd81"},{name="fake_input",path="homigrad/fake/sv_input.lua",hash="38c72fd10976b2e41b3239ae893961f08b5a886a7c4435ee13a4a46dac92b2bc"},{name="super",path="autorun/server/sv_supercrusher.lua",hash="131f7627f090cfde01d445609217941f5f06fd1cde0592d1a2e8ad7bbd152e35"}})do
    local text=assert(file.Read(s.path,"LUA"));assert(util.SHA256(text)==s.hash,s.path)
    local body=string.gsub(text,"^\239\187\191","")
    local fn=CompileString(body,s.path,false);assert(isfunction(fn),tostring(fn));functions[s.name]=fn
end
local wrapped=C.wraps[hg] and C.wraps[hg].Fake
local original=wrapped and hg.Fake==wrapped.wrapper and wrapped.original or hg.Fake
assert(debug.getinfo(original,"S").short_src:find("fake/sv_tier_0.lua",1,true),"Unexpected fake implementation; refusing overwrite")
local registry,modelCache=hg.ragdollFake,hg.cachedmodels
local carriers=C.states
functions.fake()
local patchedFake=hg.Fake
functions.fake_input()
functions.super()
C.Install()
assert(hg.SupercrusherFakeVersion=="20260915.1")
assert(hg.ragdollFake==registry and hg.cachedmodels==modelCache,"Live ragdoll registry was reset")
assert(C.states==carriers,"Pill carrier state changed")
assert(C.wraps[hg].Fake.original==patchedFake and hg.Fake==C.wraps[hg].Fake.wrapper)
assert(isfunction(hg.FakeByPlayerRequest) and isfunction(concommand.GetTable().fake))
local supers,down=0,0
for _,p in ipairs(player.GetHumans())do
    if p.SuperCrusher then supers=supers+1;if IsValid(p.FakeRagdoll)then down=down+1 end end
end
local result={time=os.time(),version=hg.SupercrusherFakeVersion,map=game.GetMap(),
    players=#player.GetHumans(),supercrushers=supers,alreadyFaked=down,
    nativeSource=debug.getinfo(patchedFake,"S").short_src,
    factorySource=debug.getinfo(hg.Ragdoll_Create,"S").short_src,
    commandSource=debug.getinfo(concommand.GetTable().fake,"S").short_src,
    spawnSource=debug.getinfo(hook.GetTable().PlayerSpawn.SuperCrusher_ClearOnSpawn,"S").short_src,
    pillWrapperPreserved=true,registryPreserved=true,modelCachePreserved=true,
    ff=ZCityFFBrain.Version,rtv=SolidMapVote.RerollVersion,
    scanner=ZCityScannerResponse.Version,pill=C.Version,drone=ZCityDronesCompat.Version}
file.Write("zc_supercrusher_fake_deployed.json",util.TableToJSON(result,true))
print("ZCITY_SUPERCRUSHER_FAKE_ACTIVATED",result.version)
