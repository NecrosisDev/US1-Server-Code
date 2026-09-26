-- Civil War bayonets: every player gets the 6Kh5 bayonet knife at round
-- start (and on respawn during the round). Companion addon - the workshop
-- mode stays untouched.
if not SERVER then return end

local BLADE = "weapon_eft_melee_6x5"

local function IsCivilWar()
    return zb and zb.CROUND == "civilwar"
end

local function GiveBlade(ply)
    if not IsValid(ply) or not ply:Alive() then return end
    if ply:Team() == TEAM_SPECTATOR then return end
    if ply:HasWeapon(BLADE) then return end
    ply:Give(BLADE)
end

-- no bandages in the war: strip any medical that arrived via the
-- workshop mode's kit or default loadout paths
local function StripBandages(ply)
    if not IsValid(ply) or not ply:Alive() then return end
    if ply:Team() == TEAM_SPECTATOR then return end
    for _, wep in ipairs(ply:GetWeapons()) do
        local cls = wep:GetClass()
        if cls:find("bandage") then ply:StripWeapon(cls) end
    end
end

hook.Add("ZB_StartRound", "CWBayonet_RoundStart", function()
    -- sweep the opening seconds so slow spawns can't slip through;
    -- the HasWeapon guard makes repeat passes free
    for _, delay in ipairs({1, 3, 6}) do
        timer.Simple(delay, function()
            if not IsCivilWar() then return end
            for _, ply in player.Iterator() do
                GiveBlade(ply)
                StripBandages(ply)
            end
            if delay == 1 then print("[CWBayonet] Bayonets issued.") end
        end)
    end
end)

-- respawns mid-round (tdm-style modes respawn players)
hook.Add("PlayerSpawn", "CWBayonet_Respawn", function(ply)
    if not IsCivilWar() then return end
    timer.Simple(0.5, function()
        if IsCivilWar() then GiveBlade(ply)
            StripBandages(ply) end
    end)
end)
