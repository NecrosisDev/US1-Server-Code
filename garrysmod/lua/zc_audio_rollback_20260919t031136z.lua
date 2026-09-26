-- Called only after the guarded installer restores its owned server source.
local r={time=os.time(),restored=false}
local ok,err=xpcall(function()
 local s=assert(file.Read('autorun/server/zc_urine.lua','LUA'))
 assert(util.SHA256(s)=='ab01c1228ceaafbe09f5bfdb3b5b79a5a4455df5c669fd366bb6f2b83ccb335c','rollback source differs')
 include('autorun/server/zc_urine.lua')
 assert(ZCityUrine.Version=='20260919.drips1','rollback version differs');r.restored=true
end,debug.traceback)
if not ok then r.error=err end
file.Write('zc_audio_repair/rollback_20260919t031136z.json',util.TableToJSON(r,true))
print('ZC_AUDIO_ROLLBACK',r.restored,r.error or '')
