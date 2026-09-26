-- Self-menu server relay: the crusher/torso/supercrusher context properties
-- block self-targeting (BaseFilter: ent ~= ply), so the self-menu asks the
-- server to run the underlying command on the caller. Whitelisted commands
-- only, gated by the "zc staff playertools" ULX right (zc_goobos/sv_staff.lua;
-- IsAdmin() only when ULib is not installed) and written to the ULX log.
if not SERVER then return end
if not ZCStaff then include("zc_goobos/sv_staff.lua") end

-- command -> how it runs on the caller:
--   console = the crusher addon's own command, run as the server console on the caller's name (as before)
--   caller  = a US1 command run with the caller itself (it checks the right and logs the action on its own)
--   torso   = MakeTorso_Apply on the caller: make_torso works on a carried body, which the console does not have
local ALLOWED = {
    give_crusher = {console = true, log = "#A made themselves a crusher"},
    remove_crusher = {console = true, log = "#A removed their crusher"},
    give_supercrusher = {caller = true},
    remove_supercrusher = {caller = true},
    make_torso = {torso = true, log = "#A made themselves a torso"},
}

concommand.Add("_zcself_relay", function(ply, _, args)
    if not IsValid(ply) or not ply:IsPlayer() then return end
    if not ZCStaff.Can(ply, "playertools") then return end

    local cmd = args[1]
    local how = ALLOWED[cmd]
    if not how then return end

    local ok
    if how.torso then
        ok = isfunction(MakeTorso_Apply) and MakeTorso_Apply(ply, ply:Nick()) or false
    elseif how.caller then
        ok = concommand.Run(ply, cmd, {}, "")
    else
        ok = ZCStaff.RunOn(cmd, ply)
    end
    if not ok then
        ply:ChatPrint("[ZCSelfMenu] " .. cmd .. " is not available right now.")
        return
    end
    if how.log then ZCStaff.Log(ply, how.log) end
    print("[ZCSelfMenu] " .. ply:Nick() .. " self-applied " .. cmd)
end, nil, "Internal (zc_selfmenu): run one whitelisted player tool on yourself - give_crusher, give_supercrusher, make_torso, remove_crusher or remove_supercrusher. Needs the 'zc staff playertools' ULX right.")
