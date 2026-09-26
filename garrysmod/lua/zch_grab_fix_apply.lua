local deadline=CurTime()+60
timer.Create("ZCHGrabFix.Activate",1,60,function()
 if next(ZCityHostage.Gameplay.Sessions)~=nil then return end
 timer.Remove("ZCHGrabFix.Activate")
 include("zcity_hostage/sv_gameplay.lua")
 file.Write("zch_grab_applied.json",util.TableToJSON({time=os.time(),loaded=true,enabled=GetConVar("zch_gameplay_enabled"):GetBool()},true))
 print("ZCH_GRAB_FIX_ACTIVE")
end)
