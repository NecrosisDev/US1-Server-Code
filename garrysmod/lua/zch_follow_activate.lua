local tag="9231cc0728a9"
timer.Create("ZCHFollowReview.Activate",1,60,function()
 if next(ZCityHostage.Gameplay.Sessions)~=nil then return end
 timer.Remove("ZCHFollowReview.Activate")
 local ok,err=xpcall(function()
  include("zcity_hostage/sh_gameplay.lua")
  include("zcity_hostage/sv_gameplay.lua")
 end,debug.traceback)
 if not ok then RunConsoleCommand("zch_gameplay_enabled","0") end
 file.Write("zch_follow_"..tag.."_active.json",util.TableToJSON({time=os.time(),tag=tag,loaded=ok,error=err,
  enabled=GetConVar("zch_gameplay_enabled"):GetBool(),revision=ZCityHostage.Gameplay.MotionRevision},true))
 print("ZCH_MOTION_ACTIVE",ok,err)
end)
