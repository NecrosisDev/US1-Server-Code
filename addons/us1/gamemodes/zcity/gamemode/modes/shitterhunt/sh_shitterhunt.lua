local MODE = MODE or (zb and zb.modes and zb.modes.shitterhunt) -- nil outside the loader: a lone autorefresh patches the registered mode
if not MODE then return end
MODE.name = "shitterhunt"
MODE.PrintName = "Shitterhunt"
MODE.Version = "20260920.2"
MODE.Chance = 0 -- Selected by the round owner when the lobby qualifies; no random weight.
MODE.ForBigMaps = false
MODE.randomSpawns = true
MODE.OverrideSpawn = true
MODE.LootSpawn = false
MODE.noBoxes = true
MODE.GuiltDisabled = true
MODE.start_time = 5
MODE.Consolation = 25 -- karma paid to each Shitter at round end
MODE.end_time = 8
MODE.Headstart = 20
MODE.HuntTime = 300
MODE.FartInterval = 30
MODE.ROUND_TIME = MODE.Headstart + MODE.HuntTime
MODE.RoleShitter = 1
MODE.RoleHunter = 2

function MODE:BlindRemaining(ply, now)
    if not IsValid(ply) or ply:GetNWInt("ZCShitterhuntRole", 0) ~= self.RoleHunter then return 0 end
    return math.max(0, ply:GetNWFloat("ZCShitterhuntBlindUntil", 0) - now)
end

-- The hiding window also disallows blind gunfire. Movement remains available.
function MODE:StartCommand(ply, cmd)
    if zb.ROUND_STATE ~= 1 or self:BlindRemaining(ply, CurTime()) <= 0 then return end
    cmd:RemoveKey(IN_ATTACK)
    cmd:RemoveKey(IN_ATTACK2)
end

function MODE:PlayerCanLegAttack(ply)
    if zb.ROUND_STATE == 1 and self:BlindRemaining(ply, CurTime()) > 0 then return false end
end
