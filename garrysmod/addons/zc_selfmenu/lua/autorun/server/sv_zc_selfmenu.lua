-- Self-menu server relay: the crusher/torso/supercrusher context properties
-- block self-targeting (BaseFilter: ent ~= ply), so the self-menu asks the
-- server to run the underlying command on the caller. Admin-gated,
-- whitelisted commands only.
if not SERVER then return end

local ALLOWED = {
    give_crusher = true,
    give_supercrusher = true,
    make_torso = true,
    remove_crusher = true,
    remove_supercrusher = true,
}

concommand.Add("_zcself_relay", function(ply, _, args)
    if not IsValid(ply) or not ply:IsPlayer() then return end
    if not ply:IsAdmin() then return end

    local cmd = args[1]
    if not ALLOWED[cmd] then return end

    game.ConsoleCommand(cmd .. ' "' .. ply:Nick() .. '"\n')
    print("[ZCSelfMenu] " .. ply:Nick() .. " self-applied " .. cmd)
end)
