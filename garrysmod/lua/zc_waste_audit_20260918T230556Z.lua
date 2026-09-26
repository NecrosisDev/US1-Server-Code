local out={time=os.time(),map=game.GetMap(),players=#player.GetAll(),systems={}}
for _,name in ipairs({"ZCityPoop","ZCityUrine","ZCityPoopThrow","ZCityPoopInvoluntary","ZCityPoopEat","ZCityPoopOdor"}) do
 local s=_G[name]
 if s then
  out.systems[name]={version=s.Version,stats=table.Copy(s.stats or {})}
 end
end
out.poops=0
for e in pairs(ZCityPoop and ZCityPoop.owned or {}) do
 if IsValid(e) then out.poops=out.poops+1 end
end
out.activeUrine=table.Count(ZCityUrine and ZCityUrine.active or {})
out.clientUrineReady=table.Count(ZCityUrine and ZCityUrine.ready or {})
out.timers={}
for _,name in ipairs({"ZCityUrine_Tick","ZCityUrine_Bladder","ZCityPoopThrow_Tick","ZCityPoop_Involuntary","ZCityPoop_Eating","ZCityPoop_Odor"}) do
 out.timers[name]=timer.Exists(name)
end
file.CreateDir("zc_waste_hardening")
file.Write("zc_waste_hardening/audit_20260918T230556Z.json",util.TableToJSON(out,true))
print("ZCWASTE_AUDIT_SAVED_20260918T230556Z")
