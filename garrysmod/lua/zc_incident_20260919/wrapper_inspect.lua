assert(SERVER)
local K=assert(ZC_TRAITOR_POPULATION)
local function info(f)
 if not isfunction(f)then return {type=type(f)}end
 local i=debug.getinfo(f,'S');local r={source=i.source,line=i.linedefined,upvalues={}}
 for n=1,15 do local name,v=debug.getupvalue(f,n)if not name then break end
  if isfunction(v)then local d=debug.getinfo(v,'S');r.upvalues[name]={source=d.source,line=d.linedefined}end
 end
 return r
end
local r={slotOwned=K.mode.Intermission==K.wrapper,original=info(K.original),wrapper=info(K.wrapper),slot=info(K.mode.Intermission)}
file.Write('zc_incident_20260919/round_wrapper_state.json',util.TableToJSON(r,false))
