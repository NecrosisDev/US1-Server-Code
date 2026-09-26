local root='zc_splat_stage_20260919t035103z/'
local r={time=os.time(),passed=false,tests={},worldValid=IsValid(game.GetWorld()),hashes={},prepared={}}
local ok,err=xpcall(function()
 for _,path in ipairs({'autorun/server/zc_poop_throw.lua','autorun/zc_fart_puff.lua','weapons/weapon_hands_sh.lua'})do
  local s=assert(file.Read(root..path,'LUA'));r.hashes[path]=util.SHA256(s)
  assert(isfunction(CompileString(s,'syntax_'..path,false)),'syntax failed '..path)
 end
 local suite=CompileString(assert(file.Read(root..'test_splat.lua','LUA')),'splat_tests',false)
 assert(isfunction(suite));r.tests=suite()(assert(file.Read(root..'autorun/server/zc_poop_throw.lua','LUA')))
 for _,t in ipairs(r.tests)do assert(t.pass,t.name..': '..tostring(t.error))end
 local compile=CompileString(assert(file.Read(root..'compile_native.lua','LUA')),'compile_native',false)()
 local stored=assert(weapons.GetStored('weapon_hands_sh'));local original={ApplyForce=stored.ApplyForce,SetCarrying=stored.SetCarrying,held=(hook.GetTable().Think or {})['held-entities']}
 for name,f in pairs(original)do
  local code=assert(file.Read(root..name..'_candidate.lua','LUA'))
  local revised=compile(f,code,name);assert(isfunction(revised));r.prepared[name]=true
 end
 local old=assert(file.Read('weapons/weapon_hands_sh.lua','LUA')):gsub('\r\n','\n')
 local new=assert(file.Read(root..'weapons/weapon_hands_sh.lua','LUA'))
 new=new:gsub('[^\n]*hook.Run%("ZCityHandsThrown"[^\n]*\n',''):gsub('[^\n]*hook.Run%("ZCityHandsPickedUp"[^\n]*\n','')
 assert(old==new,'native hands changes exceed notification lines')
 r.passed=true
end,debug.traceback)
if not ok then r.error=err end
file.CreateDir('zc_splat_puff');file.Write('zc_splat_puff/preflight_20260919t035103z.json',util.TableToJSON(r,true))
print('ZC_SPLAT_PREFLIGHT',r.passed,#r.tests,r.error or '')
