-- Syntax/asset/dependency preflight only. Does not execute the candidate.
local r={time=os.time(),passed=false,behavioralTestsRun=false}
local ok,err=xpcall(function()
 local text=assert(file.Read('zc_fart_puff_stage_20260919t012630z/candidate.lua','LUA'))
 r.hash=util.SHA256(text)
 assert(type(CompileString(text,'fart_puff_syntax_only',false))=='function','syntax failure')
 r.particleFile=file.Exists('particles/antlion_worker.pcf','GAME')
 assert(r.particleFile,'particle asset missing')
 assert(file.Read('particles/antlion_worker.pcf','GAME'):find('antlion_spit_trail',1,true),'effect name missing')
 r.randomSource=util.SHA256(assert(file.Read('homigrad/organism/tier_1/modules/sv_random_event.lua','LUA')))
 r.soundPresent=file.Exists('sound/snd_jack_hmcd_fart.wav','GAME')
 assert(r.soundPresent,'existing fart sound missing')
 r.existingPuff=ZCFartPuff and ZCFartPuff.Version or false
 assert(not ZCFartPuff,'another puff implementation is already active')
 r.passed=true
end,debug.traceback)
if not ok then r.error=err end
file.CreateDir('zc_fart_puff')
file.Write('zc_fart_puff/preflight_20260919t012630z.json',util.TableToJSON(r,true))
print('ZCFART_PREFLIGHT',r.passed,r.error or '')
