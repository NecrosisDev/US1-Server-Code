local out={time=os.time(),map=game.GetMap(),gamemode=engine.ActiveGamemode(),players=#player.GetAll(),target={},groups={},commands={},hooks={}}
local function state(p)
 local o=p.organism;local P=ZCityPillCompat;local C=ZCityPoop;local U=ZCityUrine
 local s={alive=p:Alive(),team=p:Team(),teamName=team.GetName(p:Team()),observer=p:GetObserverMode(),move=p:GetMoveType(),vehicle=p:InVehicle(),class=p.PlayerClassName,organism=type(o),fake=IsValid(p.FakeRagdoll),spectating=IsValid(p:GetObserverTarget())}
 if type(o)=='table' then s.orgAlive=o.alive;s.unconscious=o.otrub end
 s.pillSpawning=P and P.spawning and P.spawning[p] and true or false
 if P and P.IsCarrier then local ok,v=pcall(P.IsCarrier,p);s.pillCarrier=ok and v or false end
 if C and C.Body then local ok,b=pcall(C.Body,p);s.body=ok and IsValid(b) and b:GetClass() or 'invalid' end
 local a=C and C.accounts[p:SteamID64()];s.poopWait=a and math.max(0,(a.next or 0)-RealTime()) or 0
 s.bladder=U and U.bladder[p] and U.bladder[p].value;s.peeWait=math.max(0,(p.ZCUrineNextStart or 0)-CurTime())
 s.oldGate=s.alive and s.team<1000 and s.observer==OBS_MODE_NONE
 return s
end
for _,p in ipairs(player.GetAll()) do
 local s=state(p);local k=tostring(s.alive)..':'..s.team..':'..s.observer
 out.groups[k]=(out.groups[k] or 0)+1
 if p:SteamID64()=='76561198011536179' then out.target=s end
end
for _,n in ipairs({'poop','pee','+pee','-pee'}) do
 local f=concommand.GetTable()[n];out.commands[n]=type(f)=='function' and debug.getinfo(f,'S') or false
end
for _,name in ipairs({'PlayerSpawn','PlayerInitialSpawn','PlayerDeath','PlayerSilentDeath'}) do
 out.hooks[name]={}
 for id,f in pairs(hook.GetTable()[name] or {}) do
  if type(f)=='function' then local d=debug.getinfo(f,'S');out.hooks[name][tostring(id)]={source=d.short_src,line=d.linedefined} end
 end
end
file.CreateDir('zc_waste_midround');file.Write('zc_waste_midround/state_20260919t000035z.json',util.TableToJSON(out,true))
print('ZCWASTE_MIDROUND_STATE_SAVED')
