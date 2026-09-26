-- One-use console operation for the owner's explicit empty-server restart.
-- Reuse the installed controller's countdown and restart handoff; keep daily settings.
local receipt="zsf_authorized_restart_2f242e95.json"
assert(not file.Exists(receipt,"DATA"),"This restart request was already submitted")
local R=assert(ZC_RESTART_WARNING,"Restart controller missing")
local before=R.Status()
assert(R.Version=="2.1.0" and before.canChange and not R.warningEnd and not R.triggered,"Controller not ready")
assert(not before.manual and before.left>120,"A restart is already pending")
assert(GetConVar("zsf_trial_steamid"):GetString()=="76561198011536179")
assert(not GetConVar("zsf_enabled"):GetBool())
local settings=file.Read("restart_warning/settings.json","DATA")
file.Write(receipt,util.TableToJSON({time=os.time(),before=before,uptime=CurTime(),map=game.GetMap(),players=#player.GetHumans(),
    settingsCRC=util.CRC(settings or ""),authorized=true,seconds=30},true))
assert(file.Exists(receipt,"DATA"),"Restart receipt could not be saved")
-- RequestManual requires an online staff player. The trusted server console can
-- arm the same existing scheduler directly without impersonating a player.
R.due=os.time()+30
R.noticeStage=nil
R.nextNotice=nil
print("[ZCity Stealth] Authorized restart armed through Restart Warning 2.1.0")
