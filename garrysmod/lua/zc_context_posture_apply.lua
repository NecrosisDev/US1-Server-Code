if not SERVER then return end
local path="addons/zcity_hostage/lua/zcity_interactions/sv_context.lua"
local hash=util.SHA256(file.Read(path,"GAME"))
assert(hash=="5e901b6a23d0341455a1c1b1cd4ca71722806cb4b031ace29cd51b1521cc752d")
local ok,err=xpcall(function() include("zcity_interactions/sv_context.lua") end,debug.traceback)
file.Write("zci_context_posture_applied.json",util.TableToJSON({ok=ok,error=tostring(err),hash=hash,time=os.time(),source=debug.getinfo(ZCityInteractions.ContextOffers,"S").source}))
