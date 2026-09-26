local r={time=os.time(),worldValid=IsValid(game.GetWorld()),worldIsWorld=game.GetWorld():IsWorld(),players=#player.GetHumans(),map=game.GetMap(),functions={},puffReady=ZCFartPuff and table.Copy(ZCFartPuff.ready or {}) or {}}
r.puffReady=nil -- Do not serialize player identifiers.
r.puffModes={}
for _,state in pairs(ZCFartPuff and ZCFartPuff.ready or {}) do r.puffModes[tostring(state)]=(r.puffModes[tostring(state)] or 0)+1 end
local w=weapons.GetStored('weapon_hands_sh')
for _,name in ipairs({'ApplyForce','SetCarrying'}) do
 local f=w and w[name];if isfunction(f) then local d=debug.getinfo(f,'S');local u={}
 for i=1,60 do local n,v=debug.getupvalue(f,i);if not n then break end;u[#u+1]={name=n,type=type(v)} end
 r.functions[name]={source=d.source,line=d.linedefined,last=d.lastlinedefined,upvalues=u}
 end
end
local f=(hook.GetTable().Think or {})['held-entities']
if isfunction(f) then local d=debug.getinfo(f,'S');local u={}
 for i=1,60 do local n,v=debug.getupvalue(f,i);if not n then break end;u[#u+1]={name=n,type=type(v)} end
 r.functions.held={source=d.source,line=d.linedefined,last=d.lastlinedefined,upvalues=u}
end
file.CreateDir('zc_splat_puff');file.Write('zc_splat_puff/inspect_20260919t035103z.json',util.TableToJSON(r,true))
print('ZC_SPLAT_INSPECT_SAVED')
