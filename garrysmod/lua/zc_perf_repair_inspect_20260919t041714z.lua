local r={time=os.time(),map=game.GetMap(),players=#player.GetHumans(),functions={},tick=engine.TickInterval()}
local definitions={shake=util.ScreenShake,grenade=weapons.GetStored('weapon_hg_grenade_tpik').Throw,
 medPrimary=weapons.GetStored('weapon_bandage_sh').PrimaryAttack,medSecondary=weapons.GetStored('weapon_bandage_sh').SecondaryAttack,
 shoot=weapons.GetStored('homigrad_base').Shoot}
for name,fn in pairs(definitions) do
 local d=debug.getinfo(fn,'S');local q={source=d.source,line=d.linedefined,upvalues={},environmentGlobal=getfenv(fn)==_G};r.functions[name]=q
 for i=1,100 do local n,v=debug.getupvalue(fn,i);if not n then break end
  q.upvalues[#q.upvalues+1]={name=n,type=type(v),functionSource=type(v)=='function' and debug.getinfo(v,'S').source or nil}
 end
end
r.upvaluejoin=type(debug.upvaluejoin)
r.soundFix=ZCityUrine and ZCityUrine.Version;r.throwVersion=ZCityPoopThrow and ZCityPoopThrow.Version
r.puff=ZCFartPuff and ZCFartPuff.Version
file.CreateDir('zc_perf_repairs')
file.Write('zc_perf_repairs/inspect_20260919t041714z.json',util.TableToJSON(r,true))
print('ZC_PERF_REPAIR_INSPECT',r.players,r.map)
