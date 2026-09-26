MODE.name = "homelanderhns"
MODE.PrintName = "Homelander: Hide & Seek"

MODE.ForBigMaps = false
MODE.ROUND_TIME = 330  -- 30s freeze + 5min hunt

MODE.Chance = 0  -- admin start only

local HOMELANDER_MODEL = "models/theboys/homelander.mdl"
local FREEZE_TIME = 30

function MODE.GuiltCheck(Attacker, Victim, add, harm, amt)
    return 0, false
end

local function shuffle(tbl)
    local len = #tbl
    for i = len, 2, -1 do
        local j = math.random(i)
        tbl[i], tbl[j] = tbl[j], tbl[i]
    end
end

function MODE:AssignTeams()
    local players = {}
    for _, ply in player.Iterator() do
        if ply:Team() ~= TEAM_SPECTATOR then
            table.insert(players, ply)
        end
    end

    -- Check if an admin forced a Homelander via traitor admin panel
    local forcedPly = nil
    if TraitorAdmin and TraitorAdmin.ForcedHomelander then
        for _, p in ipairs(players) do
            if p:SteamID() == TraitorAdmin.ForcedHomelander then
                forcedPly = p
                break
            end
        end
    end

    if forcedPly then
        forcedPly:SetTeam(0)
        for _, ply in ipairs(players) do
            if ply ~= forcedPly then ply:SetTeam(1) end
        end
        print("[HnS] Using forced Homelander: " .. forcedPly:Nick())
    else
        shuffle(players)
        if IsValid(players[1]) then
            players[1]:SetTeam(0)
        end
        for i = 2, #players do
            if IsValid(players[i]) then
                players[i]:SetTeam(1)
            end
        end
    end
end

util.AddNetworkString("homelanderhns_start")
function MODE:Intermission()
    game.CleanUpMap()

    self:AssignTeams()

    for _, ply in player.Iterator() do
        if ply:Team() == TEAM_SPECTATOR then continue end
        if ply:Team() == 0 then
            -- Homelander doesn't spawn yet - arrives in FREEZE_TIME seconds
            self.HomelanderPlayer = ply
            ply:KillSilent()
            continue
        end
        ply:SetupTeam(ply:Team())
    end

    net.Start("homelanderhns_start")
        net.WriteEntity(self.HomelanderPlayer or NULL)
    net.Broadcast()
end

function MODE:CheckAlivePlayers()
    local homelanderPlayers = {}
    local hiderPlayers = {}

    for _, ply in ipairs(team.GetPlayers(0)) do
        if ply:Alive() then
            table.insert(homelanderPlayers, ply)
        end
    end

    for _, ply in ipairs(team.GetPlayers(1)) do
        if ply:Alive() then
            table.insert(hiderPlayers, ply)
        end
    end

    return {homelanderPlayers, hiderPlayers}
end

function MODE:ShouldRoundEnd()
    -- Don't end during freeze/arrival period
    if zb.ROUND_START + FREEZE_TIME + 3 > CurTime() then return end

    -- Check if all hiders dead
    local aliveTeams = self:CheckAlivePlayers()
    if #aliveTeams[1] == 0 then return true end  -- No homelander
    if #aliveTeams[2] == 0 then return true end  -- All hiders dead

    -- Check timer expired
    if zb.ROUND_START + self.ROUND_TIME < CurTime() then
        if not self.BoredAnnounced then
            self.BoredAnnounced = true
            PrintMessage(HUD_PRINTTALK, "Homelander grows bored.")
        end
        return true
    end

    return false
end

function MODE:RoundStart()
end

function MODE:GiveEquipment()
    timer.Simple(0.5, function()
        for _, ply in player.Iterator() do
            if not IsValid(ply) then continue end
            if ply:Team() == TEAM_SPECTATOR then continue end

            if ply:Team() == 0 then
                -- HOMELANDER - dead right now, spawns in FREEZE_TIME seconds
                -- Send controls immediately so they can read while waiting
                ply:ChatPrint("===== HOMELANDER CONTROLS =====")
                ply:ChatPrint("RMB - Laser eyes (dismembers limbs)")
                ply:ChatPrint("LMB - Punch")
                ply:ChatPrint("ALT + E - Grab a player (Crusher abilities active)")
                ply:ChatPrint("While grabbing: [ = Crush head, ] = Snap neck, hold RMB = Laser execute")
                ply:ChatPrint("Double-tap SPACE - Toggle flight")
                ply:ChatPrint("H - Toggle X-Ray vision")
                ply:ChatPrint("Kick while looking down - Stomp limb / forward = Blast door")
                ply:ChatPrint("[You will arrive in " .. FREEZE_TIME .. " seconds]")

                -- Delayed spawn
                local hlPly = ply
                timer.Create("HomelanderHNS_Spawn_" .. ply:EntIndex(), FREEZE_TIME, 1, function()
                    if not IsValid(hlPly) or hlPly:Team() == TEAM_SPECTATOR then return end

                    hlPly:Spawn()
                    hlPly:SetSuppressPickupNotices(true)
                    hlPly.noSound = true

                    hlPly:SetupTeam(hlPly:Team())

                    hlPly:SetModel(HOMELANDER_MODEL)
                    hlPly.HomelanderHNSModel = HOMELANDER_MODEL

                    hlPly:StripWeapons()
                    hlPly:StripAmmo()

                    -- Give Homelander SWEP + hands
                    hlPly:Give("weapon_hands_sh")
                    local wep = hlPly:Give("weapon_homelander")
                    timer.Simple(0.2, function()
                        if IsValid(hlPly) and IsValid(wep) then
                            hlPly:SelectWeapon("weapon_homelander")
                        end
                    end)

                    zb.GiveRole(hlPly, "Homelander", Color(190, 0, 0))

                    local inv = hlPly:GetNetVar("Inventory") or {}
                    inv["Weapons"] = inv["Weapons"] or {}
                    inv["Weapons"]["hg_flashlight"] = true
                    hlPly:SetNetVar("Inventory", inv)

                    hlPly:SetSuppressPickupNotices(false)
                    hlPly.noSound = false

                    -- Assign crusher role shortly after spawn
                    timer.Simple(1, function()
                        if not IsValid(hlPly) then return end
                        game.ConsoleCommand("give_crusher " .. hlPly:Nick() .. "\n")
                        hlPly:ChatPrint("[Homelander] Crusher abilities activated.")
                    end)

                    hlPly:ChatPrint("[Homelander] You've arrived. Hunt them down.")
                    PrintMessage(HUD_PRINTTALK, "The Homelander has arrived.")
                end)
            else
                -- HIDER
                ply:SetSuppressPickupNotices(true)
                ply.noSound = true

                ply:StripWeapons()
                ply:StripAmmo()

                zb.GiveRole(ply, "Civilian", Color(0, 120, 190))

                ply:Give("weapon_hands_sh")
                ply:Give("weapon_hg_flashlight")
                ply:Give("weapon_ducttape")
                ply:Give("weapon_hammer")
                ply:Give("weapon_hg_nails")
                timer.Simple(0.2, function()
                    if IsValid(ply) then ply:SelectWeapon("weapon_hands_sh") end
                end)

                local inv = ply:GetNetVar("Inventory") or {}
                inv["Weapons"] = inv["Weapons"] or {}
                inv["Weapons"]["hg_flashlight"] = true
                ply:SetNetVar("Inventory", inv)

                ply:SetSuppressPickupNotices(false)
                ply.noSound = false
            end

            timer.Simple(0.5, function()
                if IsValid(ply) then ply.noSound = false end
            end)
        end
    end)
end

function MODE:RoundThink()
end

function MODE:GetTeamSpawn()
    return {zb:GetRandomSpawn()}, {zb:GetRandomSpawn()}
end

function MODE:CanSpawn()
end

-- Keep Homelander model locked during round
hook.Add("PlayerSetModel", "HomelanderHNS_ForceModel", function(ply)
    if zb.CROUND ~= "homelanderhns" then return end
    if ply.HomelanderHNSModel then
        timer.Simple(0, function()
            if IsValid(ply) then ply:SetModel(ply.HomelanderHNSModel) end
        end)
    end
end)

-- Block damage during freeze
hook.Add("EntityTakeDamage", "HomelanderHNS_FreezeDamageBlock", function(ent, dmg)
    if zb.CROUND ~= "homelanderhns" then return end
    if not ent:IsPlayer() then return end
    if zb.ROUND_START + FREEZE_TIME > CurTime() then
        dmg:SetDamage(0)
        return true
    end
end)

util.AddNetworkString("homelanderhns_roundend")
function MODE:EndRound()
    -- Cleanup
    for _, ply in player.Iterator() do
        if timer.Exists("HomelanderHNS_Spawn_" .. ply:EntIndex()) then
            timer.Remove("HomelanderHNS_Spawn_" .. ply:EntIndex())
        end
        if timer.Exists("HomelanderHNS_Unfreeze_" .. ply:EntIndex()) then
            timer.Remove("HomelanderHNS_Unfreeze_" .. ply:EntIndex())
        end
        ply:Freeze(false)
        ply.HomelanderHNSModel = nil
    end

    -- Determine winner
    local aliveTeams = self:CheckAlivePlayers()
    local winner

    if #aliveTeams[2] == 0 then
        winner = 0  -- Homelander wins
    else
        winner = 1  -- Hiders win
    end

    self.BoredAnnounced = false

    timer.Simple(2, function()
        net.Start("homelanderhns_roundend")
            net.WriteInt(winner, 8)
        net.Broadcast()
    end)

    for _, ply in player.Iterator() do
        if ply:Team() == winner then
            ply:GiveExp(math.random(15, 30))
            ply:GiveSkill(math.Rand(0.1, 0.15))
        else
            ply:GiveSkill(-math.Rand(0.05, 0.1))
        end
    end
end

function MODE:PlayerDeath(ply)
end
