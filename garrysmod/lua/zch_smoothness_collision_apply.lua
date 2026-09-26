timer.Create("ZCHSmoothness.CollisionCorrection",1,60,function()
 if next(ZCityHostage.Gameplay.Sessions)~=nil then return end
 timer.Remove("ZCHSmoothness.CollisionCorrection")
 local ok,err=xpcall(function() include("zcity_hostage/sv_gameplay.lua") end,debug.traceback)
 file.Write("zch_smoothness_collision_active.json",util.TableToJSON({time=os.time(),loaded=ok,error=err},true))
end)
