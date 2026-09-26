-- Server-console installation verification; non-enforcing source observation only.
assert(SERVER and engine.ActiveGamemode()=="zcity","Wrong server gamemode")
local expected={["autorun/server/sv_giveup.lua"]="185d44f20c56154c0d509e24f21cdd18a1ab447254b11194dc6cdea113e80e08",["autorun/server/sv_ko_reaper.lua"]="55ab8a6e577c655d0b4bfff3475d3ca70d3d38c15fb9b4ca990d7756490693f8",["autorun/server/zc_justice_v3_shadow.lua"]="f78cb42e22e427227114fed6b4045b1c817504b144bf8f97290cdf67acdc7cc5",["zc_justice_v3/adjudicator.lua"]="96e21e58c65c336ddcfa68631e7769eacf98272b95b1614d4ad395a7de697b34",["zc_justice_v3/bootstrap.lua"]="a05a3b7e56788c9e3d9474491da984a012924a6788c26154c3fb888845ba3d5c",["zc_justice_v3/bridge.lua"]="a1ea8b63ca16571e2e8be8205cf5d43bc8c45ac52ea303d0cc8f9a680cf32602",["zc_justice_v3/config.lua"]="b7bfa7b520546adffdf08e469bfc8a8ebd4b6ded1b0b68a064b0e8a9eb6a6321",["zc_justice_v3/controls.lua"]="bba47ded000057b05a29d43c7f148dbfc02399a608931b37cc5f00a6cc0809b4",["zc_justice_v3/effects.lua"]="3517cef281da3eeeab6ffabe148a9f0d0421dd3d2ffe640c9a256fc99ad6b00c",["zc_justice_v3/geometry.lua"]="d0efc62a4104a5ef274345b776b85b5df477d9874c8c25deb2481623da4ee1f9",["zc_justice_v3/ledger.lua"]="8852812255b8dfc332126cec3759b815ac894d563a156b3ab1c1636c518ca1cc",["zc_justice_v3/lifecycle.lua"]="cf34efb8dbd7fba200972b504bc83a1b626ecb755fcd9c361bc32580217c8dd3",["zc_justice_v3/modes.lua"]="57ecf42f4eeba4b319bbaad2a25a7d221149550eff38ef47b86b1db7fc8ea472",["zc_justice_v3/physical.lua"]="0ed732d4794b8fae97d09adbcf8cde5b3717006dd2bcd0f2d66b39fb0ab3b8b1",["zc_justice_v3/pricing.lua"]="170efaa56578aacb0a2327d68525d04410720bc93d056c3658b860ac17c9ab8c",["zc_justice_v3/provenance.lua"]="0195a40eb81c59baa9f0af980adb34127fb8ade2e42b3b0f2e319be9e884ec40",["zc_justice_v3/shadow.lua"]="af8e612393c4006971e155c13d592d9990be52e4d120ccfce2784aa5c7935b5f",["zc_justice_v3/store_memory.lua"]="a725978a547fa6f7b9d5ce2aa5247adab1418864c9804041d7f98af7b7f2d6d7",["zc_justice_v3/store_sqlite.lua"]="ce36b8f5e58c8fcba6750f07b75644432a31d503c18beedadd7afafa455ab196",["zc_justice_v3/terminals.lua"]="50d6cf37ef59c31fb3a155e624129d8f63ae07c815db3a7f51dcef5821b96e11",["zc_justice_v3/util.lua"]="00105b4e2b981831cb2b3942a3935906f68232d361b6984d358769a36fa0c827",["zc_justice_v3/version.lua"]="d38a297643d02b03db14b018403a08a99692396a852e5b3acb5476d9f99f608a"}
for path,hash in pairs(expected)do
    local text=assert(file.Read(path,"LUA"),path)
    assert(util.SHA256(text)==hash,"Mounted file hash mismatch: "..path)
    local compiled=CompileString(text,path,false)
    assert(isfunction(compiled),tostring(compiled))
end
local J,F,M,P=assert(ZCityGuiltJustice),assert(ZCityFFBrain),assert(ZCityMetaSafety),assert(ZCityPillCompat)
local saved={change=J.Change,policy=J.Assess,settle=J.Flush,brain=F.Apply,privacy=M.Change,
    carrier=P.Damage,guilt=(hook.GetTable().HomigradDamage or {}).GuiltReg}
local ok,err=pcall(function()
    include("autorun/server/zc_justice_v3_shadow.lua")
    local observer,runtime=assert(ZCJusticeV3Shadow),assert(ZCJusticeV3Integration)
    assert(observer.enabled and runtime.enabled and runtime.version=="3.2.0-shadow.1","Load failed")
    local labels={}
    for _,w in ipairs(runtime.wrappers)do
        assert(w.table[w.key]==w.wrapper,"Source ownership mismatch: "..w.label)
        labels[w.label]=true
    end
    for _,label in ipairs({"hands_committed_method","hands_trace_observation","melee_action_scope",
        "melee_trace_observation","handcuff_acceptance","fiberwire_CustomAttack","fiberwire_maintenance",
        "direct_damage_scope","accepted_trace_dispatch"})do assert(labels[label],"Missing actual adapter: "..label)end
    include("autorun/server/sv_giveup.lua")
    include("autorun/server/sv_ko_reaper.lua")
    assert(J.Change==saved.change and J.Assess==saved.policy and J.Flush==saved.settle)
    assert(F.Apply==saved.brain and M.Change==saved.privacy and P.Damage==saved.carrier)
    assert((hook.GetTable().HomigradDamage or {}).GuiltReg==saved.guilt,"Legacy scoring owner changed")
    assert(F.Settings.scale==0.0005 and F.Settings.absoluteCap==0.125)
    assert(F.VictimScale(zb.modes.tdm)==0.75 and F.VictimScale(zb.modes.hmcd)==1)
    observer:WriteStatus();runtime:WriteStatus()
    file.Write("zc_justice_v3_shadow/integration_verified.json",util.TableToJSON({
        version=runtime.version,time=os.time(),enforcement=false,legacy_ownership_unchanged=true,
        source_wrappers=#runtime.wrappers,labels=labels,observer_enabled=observer.enabled,
        bridge_enabled=runtime.enabled,financial_writes=0,public_writes=0,
        full_source_coverage=false,terminal_adapters={giveup=true,timeout=true}},true))
end)
if not ok then
    if ZCJusticeV3Integration then ZCJusticeV3Integration:Stop()end
    if ZCJusticeV3Shadow then ZCJusticeV3Shadow:Stop()end
    error("Justice source activation failed; legacy scoring preserved: "..tostring(err),0)
end
print("ZC_JUSTICE_SOURCE_INTEGRATION_ACTIVE","3.2.0-shadow.1","enforcement=false")
