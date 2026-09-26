-- Server-only hot update; client display and drone/pill archives are unchanged.
assert(SERVER and engine.ActiveGamemode()=="zcity")
local function up(fn,key)
    for i=1,80 do local n,v=debug.getupvalue(fn,i);if not n then return end;if n==key then return v end end
end
local action=assert(net.Receivers.zc_welcome_action_v2)
local state,commit,sync=assert(up(action,"state")),assert(up(action,"Commit")),assert(up(action,"SyncTo"))
assert(not up(action,"loadError"))
local guide=assert(util.JSONToTable(file.Read("zc_combat_policy_guide.txt","DATA")))
assert(guide.revision==21 and #guide.pages==9)
assert(state.revision==20 or state.revision==21,"Guide changed; refusing activation")
if state.revision==20 then
    assert(util.SHA256(file.Read("zc_welcome.txt","DATA"))=="b1edfcb811772826d6f247f25638e26fda1e61262d96ac4a640407911672518c","Guide hash changed")
else
    for i,p in ipairs(guide.pages)do assert(state.pages[i].body==p.body and state.pages[i].title==p.title)end
end
local compiled={}
for _,s in ipairs({{"policy","zc_guilt_justice/policy.lua","LUA","b951a66bfea9ae566938070310162c5a408f733d57ee19d2309755f342086a91"},{"combat_runtime","zc_guilt_justice/combat_runtime.lua","LUA","34acc3ef377e1fa8a2a50251e3a093aa2326c6bf880936570e0adbbd3d68aae6"},{"core","zc_guilt_justice/core.lua","LUA","68167f1f662e16673fa80e295fcd44234a1fad7df047d5cfa92b1fb056a01a10"},{"runtime","zc_guilt_justice/runtime.lua","LUA","e41b3f8763714e02054279fd1456def824c0ff9fa7ddb4d706c1bff434015016"},{"ff","autorun/server/zc_ff_brain.lua","LUA","1177fd1b75fbf794bc5fcde2e29011e1c915d46dd654d99a2cefadc0bc4e0400"},{"guilt","gamemodes/zcity/gamemode/libraries/guilt/sv_guilt.lua","GAME","59563ba84a9430b63269448767d3dda36c0aa9dd7449002ab8bd856e934f4599"},{"bounty","autorun/zc_karma_bounties.lua","LUA","8d0ac4de498fc70505a795041a9a12a29ff231953b555860acf969aad96c76b7"}})do
    local body=assert(file.Read(s[2],s[3]),s[2]);assert(util.SHA256(body)==s[4],s[2])
    local fn=CompileString(body,s[2],false);assert(isfunction(fn),tostring(fn));compiled[s[1]]=fn
end
compiled.bounty()
compiled.guilt()
compiled.ff()
local J,K,F=assert(ZCityGuiltJustice),assert(ZCityKarmaBounties),assert(ZCityFFBrain)
assert(J.Version=="20260915.3" and J.PolicyVersion=="20260915.1")
assert(K.Version=="20260915.3" and F.Version=="20260915.5")
assert(F.VictimScale(zb.modes.tdm)==0.75 and F.VictimScale(zb.modes.cstrike)==0.75)
assert(F.VictimScale(zb.modes.hmcd)==1 and F.VictimScale(zb.modes.fear)==1)
assert(F.KarmaRate(25)==0.004 and F.Settings.absoluteCap==0.25)
assert(K.Value(120)==-30 and K.Value(100)==-20 and K.Value(50)==-10 and K.Value(25)==0 and K.Value(0)==10)
assert(ZCITY_GUILT.Config.AllowPunish==false)
assert(debug.getinfo(K.HarmCharge,"S").short_src:find("combat_runtime",1,true))
assert(debug.getinfo(K.EndPill,"S").short_src:find("combat_runtime",1,true))
F.InstallPillBridge();F.InstallDamagePriority();assert(J.InstallLegacy())
assert(F.pillBridge.wrapper==ZCityPillCompat.Damage)
if state.revision==20 then local ok,err=commit(guide);assert(ok,tostring(err))end
state=assert(up(action,"state"));assert(state.revision==21);sync()
local result={time=os.time(),ff=F.Version,justice=J.Version,policy=J.PolicyVersion,
    bounty=K.Version,guide=state.revision,players=#player.GetHumans(),
    creatureBridge=F.pillBridge.wrapper==ZCityPillCompat.Damage,
    legacyActions=J.legacyHandler==net.Receivers.zcity_guilt_action,
    extraPunishments=ZCITY_GUILT.Config.AllowPunish,
    nativeSource=debug.getinfo(hook.GetTable().HomigradDamage.GuiltReg,"S").short_src,
    policySource=debug.getinfo(K.HarmCharge,"S").short_src,
    drone=ZCityDronesCompat.Version,pill=ZCityPillCompat.Version,tdmModes={}}
for name,m in pairs(zb.modes)do if F.VictimScale(m)==0.75 then result.tdmModes[#result.tdmModes+1]=name end end
table.sort(result.tdmModes)
file.Write("zc_combat_policy_deployed.json",util.TableToJSON(result,true))
print("ZCITY_COMBAT_POLICY_ACTIVATED",J.PolicyVersion,"guide",state.revision)
