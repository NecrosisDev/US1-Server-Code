local out={time=os.time(),map=game.GetMap(),players=#player.GetAll(),systems={},timers={},poops=0,activeUrine=0,humans=0,urineClientV2=0}
for _,name in ipairs({'ZCityPoop','ZCityUrine','ZCityPoopThrow','ZCityPoopInvoluntary','ZCityPoopEat','ZCityPoopOdor'})do
 local s=_G[name];if s then out.systems[name]={version=s.Version,stats=table.Copy(s.stats or {})}end
end
for e in pairs(ZCityPoop and ZCityPoop.owned or {})do if IsValid(e)then out.poops=out.poops+1 end end
for _ in pairs(ZCityUrine and ZCityUrine.active or {})do out.activeUrine=out.activeUrine+1 end
for _,p in ipairs(player.GetAll())do
 if not p:IsBot()then out.humans=out.humans+1;if ZCityUrine and ZCityUrine.ready[p]==2 then out.urineClientV2=out.urineClientV2+1 end end
end
for _,name in ipairs({'ZCityUrine_Tick','ZCityUrine_Bladder','ZCityPoopThrow_Tick','ZCityPoop_Involuntary','ZCityPoop_Eating','ZCityPoop_Odor'})do out.timers[name]=timer.Exists(name)end
out.commands={}
for _,name in ipairs({'poop','pee','+pee','-pee'})do out.commands[name]=type(concommand.GetTable()[name])=='function'end
file.CreateDir('zc_waste_hardening')
file.Write('zc_waste_hardening/runtime_20260918t233404z.json',util.TableToJSON(out,true))
print('ZCWASTE_SNAPSHOT',out.players,out.poops,out.urineClientV2)
