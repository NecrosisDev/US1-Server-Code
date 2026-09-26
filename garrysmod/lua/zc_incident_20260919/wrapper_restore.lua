assert(SERVER)
local K=assert(ZC_TRAITOR_POPULATION)
assert(K.mode and K.mode.Intermission==K.wrapper,'traitor owner drifted')
local escaped=K.original
assert(debug.getinfo(escaped,'S').source=='@lua/zc_incident_20260919/round_20260919t234727z.lua','not our diagnostic')
local function up(fn,wanted)
 for i=1,30 do local name,value=debug.getupvalue(fn,i)if not name then break end if name==wanted then return value end end
 error('missing upvalue '..wanted)
end
assert(up(K.wrapper,'original')==escaped,'delegate changed')
local prior=assert(up(escaped,'original'))
assert(debug.getinfo(prior,'S').source=='@addons/zc_traitor_population/lua/autorun/server/sv_zc_traitor_population.lua')
local native=assert(up(prior,'original'))
assert(debug.getinfo(native,'S').source~='@lua/zc_incident_20260919/round_20260919t234727z.lua')
K.original=native
K.wrapper=prior
K.mode.Intermission=prior
K.Sync()
assert(K.wrapper==prior and K.original==native and K.mode.Intermission==prior,'restoration did not hold')
file.Write('zc_incident_20260919/round_wrapper_repaired.json',util.TableToJSON({at=os.time(),restored=true,source=debug.getinfo(prior,'S').source,delegate=debug.getinfo(native,'S').source},false))
print('ZC_ROUND_WRAPPER_RESTORED')
