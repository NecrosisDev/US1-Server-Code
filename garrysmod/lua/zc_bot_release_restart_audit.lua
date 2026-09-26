local R=ZC_RESTART_WARNING
local S=R and R.Status and R.Status() or nil
local out={
  time=os.time(),
  players=#player.GetHumans(),
  version=R and R.Version,
  status=S,
  crashScreen=PhysgunCrashHandler and type(PhysgunCrashHandler.RestartWithCrashScreen)=="function" or false,
  clientSource=file.Exists("autorun/client/cl_restart_warning.lua","LUA"),
  serverSource=file.Exists("autorun/server/sv_restart_warning.lua","LUA")
}
file.Write("zc_bot_release_restart_audit.json",util.TableToJSON(out,true))
print("ZC_BOT_RELEASE_RESTART_AUDIT",util.TableToJSON(out))
