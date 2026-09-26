timer.Create("ZCHScale.Activate",1,60,function()
 if next(ZCityHostage.Gameplay.Sessions)~=nil then return end
 timer.Remove("ZCHScale.Activate")
 local ok,err=xpcall(function() include("zcity_hostage/sh_gameplay.lua") include("zcity_hostage/sv_gameplay.lua") end,debug.traceback)
 if not ok then RunConsoleCommand("zch_gameplay_enabled","0") end
 file.Write("zch_scale_e553fe786691_active.json",util.TableToJSON({time=os.time(),loaded=ok,error=err,scale=ZCityHostage.Gameplay.ScaleRevision,
  motion=ZCityHostage.Gameplay.MotionRevision,enabled=GetConVar("zch_gameplay_enabled"):GetBool()},true))
 print("ZCH_SCALE_ACTIVE",ok,err)
end)
