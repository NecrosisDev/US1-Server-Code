if not SERVER then return end
local existing = ZCReinforcementVoteSpawn
if existing then
    assert(existing.Version == 1 and existing.BodySHA256 == "8c352c16b2d5c58913e767c7a44674de5614811789a2fcc92cea35d5e0069541", "Reinforcement spawn adapter version conflict")
    return
end
local candidate = {}
do
    local MODE = candidate
-- Optional candidates/context are used by the paced spectator vote only.
MODE.ZCReinforcementVoteSpawnVersion = 1
local function eligible(ply)
    return IsValid(ply) and not ply:Alive() and not ply.isTraitor
        and ply:Team() ~= TEAM_SPECTATOR and (tonumber(ply.afkTime2) or 0) <= 60
end

-- An automatic wave (no candidates, no wave context) used to Spawn() and equip up to six players inside one
-- Think: measured 78 ms for four police on US1 (about 19 ms each). Pick the same players now, spawn the first
-- at once so the announcement still lands with an officer, and hand the rest to the single-player path the
-- vote dispatcher already uses, one per PACE seconds. The count promised to the caller is corrected if a
-- queued player can no longer spawn, because homicide compares deadPoliceCount against it to call SWAT.
-- PROVISIONAL(2026-09-21, 0.1 s spacing is a guess - one spawn per 5 ticks, ratify-by: 2026-10-19)
local PACE = 0.1
local function pacedForce(self, teamtype, count)
    local picked = {}
    for _, ply in RandomPairs(player.GetAll()) do
        if #picked >= count then break end
        if eligible(ply) then picked[#picked + 1] = ply end
    end
    if #picked == 0 then return 0 end

    local ctx, roundStart = {}, zb.ROUND_START
    local promised = self:SpawnForce(teamtype, 1, {picked[1]}, ctx)
    local floor = promised
    for n = 2, #picked do
        promised = promised + 1
        timer.Simple((n - 1) * PACE, function()
            local got = 0
            if zb.ROUND_STATE == 1 and zb.ROUND_START == roundStart then
                got = self:SpawnForce(teamtype, 1, {picked[n]}, ctx)
            end
            if got == 0 and teamtype == "police" and (tonumber(self.spawnedPoliceCount) or 0) > floor then
                self.spawnedPoliceCount = self.spawnedPoliceCount - 1
            end
        end)
    end
    return promised
end

function MODE:SpawnForce(teamtype, count, candidates, wave)
    if not candidates and not wave and count > 1 then return pacedForce(self, teamtype, count) end
    local spawned = 0
    local basepos = wave and wave.basepos or nil

    for i, ply in RandomPairs(candidates or player.GetAll()) do
        if eligible(ply) then
            if spawned >= count then break end
            local forceIndex = (wave and wave.spawned or 0) + spawned + 1
            local priorPolice, priorGunner = ply.isPolice, ply.isGunner

            ply.isPolice = true
            ply.isTraitor = false
            ply.isGunner = false
            ply:Spawn()

            if not wave or ply:Alive() then
                if not basepos then
                    basepos = zb:GetRandomSpawn()
                    ply:SetPos(basepos)
                else
                    hg.tpPlayer(basepos, ply, wave and forceIndex or i)
                end

                if teamtype == "police" then
                    self.Types[self.Type].PoliceEquipment(ply)
                elseif teamtype == "swat" then
                    self:EquipSWAT(ply, forceIndex)
                elseif teamtype == "nationalguard" then
                    self:EquipNationalGuard(ply, forceIndex)
                end

                spawned = spawned + 1
            else
                -- A denied/failed vote respawn must not equip a corpse or mark it police.
                ply.isPolice, ply.isGunner = priorPolice, priorGunner
            end
        end
    end

    if wave then
        wave.basepos = basepos
        wave.spawned = (wave.spawned or 0) + spawned
    end
    return spawned
end

end
local I = {Version=1, BodySHA256="8c352c16b2d5c58913e767c7a44674de5614811789a2fcc92cea35d5e0069541", slots={}, fn=candidate.SpawnForce}
ZCReinforcementVoteSpawn = I
local sourcePath = "addons/zcity/gamemodes/zcity/gamemode/modes/homicide/sv_homicide.lua"
local sourceSHA = "daef11eb180c917df15888bdf5d205d10aa10d80f045d6a23b261768c9924f08"
local RETRY = "ZCReinforcementVoteSpawn_Retry"

function I.IsOwned(mode)
    return I.active == true and mode.SpawnForce == I.fn and mode.ZCReinforcementVoteSpawnVersion == 1
        and (mode == zb.modes.hmcd or mode == zb.modes.activeshooter or mode == zb.modes.masscasualty)
end

function I.Install()
    if not zb or not zb.modes then return false, "modes not loaded" end
    local targets = {zb.modes.hmcd, zb.modes.activeshooter, zb.modes.masscasualty}
    if not targets[1] or not targets[2] or not targets[3] then return false, "supported modes not loaded" end
    local source = file.Read(sourcePath, "GAME")
    if not source or util.SHA256(source) ~= sourceSHA then return false, "homicide source changed; review required" end
    if I.active then
        for _, mode in ipairs(targets) do if not I.IsOwned(mode) then return false, "spawn owner changed; review required" end end
        return true
    end
    local slots = {}
    for _, mode in ipairs(targets) do
        local fn = mode.SpawnForce
        if not isfunction(fn) then return false, "spawn method missing" end
        local info = debug.getinfo(fn, "S")
        if info.what ~= "Lua" or info.linedefined ~= 1478 or info.lastlinedefined ~= 1510
            or not string.find(info.source, "modes/homicide/sv_homicide.lua", 1, true) then
            return false, "unreviewed spawn method owner"
        end
        slots[#slots+1] = {mode=mode, old=rawget(mode,"SpawnForce"),
            marker=rawget(mode,"ZCReinforcementVoteSpawnVersion")}
    end
    I.slots=slots
    for _, slot in ipairs(slots) do
        slot.mode.SpawnForce=I.fn
        slot.mode.ZCReinforcementVoteSpawnVersion=1
    end
    I.active=true
    timer.Remove(RETRY)
    return true
end

function I.Rollback()
    for _, slot in ipairs(I.slots) do
        if slot.mode.SpawnForce~=I.fn or slot.mode.ZCReinforcementVoteSpawnVersion~=1 then
            return false, "spawn owner changed; refusing partial rollback"
        end
    end
    if ZCReinforcementVote then ZCReinforcementVote.EndRound() end
    for _, slot in ipairs(I.slots) do
        slot.mode.SpawnForce=slot.old
        slot.mode.ZCReinforcementVoteSpawnVersion=slot.marker
    end
    I.active=false
    timer.Remove(RETRY)
    for _, event in ipairs({"InitPostEntity","OnReloaded"}) do
        if (hook.GetTable()[event]or{}).ZCReinforcementVoteSpawn==I.TryInstall then
            hook.Remove(event,"ZCReinforcementVoteSpawn")
        end
    end
    return true
end

function I.TryInstall()
    local ok, reason=I.Install()
    if not ok then I.lastError=reason end
    return nil -- do not stop other lifecycle hooks
end
hook.Add("InitPostEntity","ZCReinforcementVoteSpawn",I.TryInstall)
hook.Add("OnReloaded","ZCReinforcementVoteSpawn",I.TryInstall)
local attempts=0
timer.Create(RETRY,1,30,function()
    attempts=attempts+1
    local ok, reason=I.Install()
    if not ok and attempts==30 then ErrorNoHalt("[Reinforcements] "..tostring(reason).."\n") end
end)
I.TryInstall()
