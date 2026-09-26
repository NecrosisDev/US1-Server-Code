-- Kill Zones: admin-defined boxes that kill players who enter
-- Zones are saved per-map and reload automatically
--
-- Commands (admin only, run in-game or from server console with a name arg):
--   zkill_corner1          - set first corner at your feet
--   zkill_corner2          - set second corner and CREATE the zone
--   zkill_list             - list zones on this map
--   zkill_remove <id>      - remove zone by id (from zkill_list)
--   zkill_clear            - remove ALL zones on this map
if not SERVER then return end

KillZones = KillZones or {}
KillZones.Zones = KillZones.Zones or {}

local DATA_DIR = "killzones"

local function DataPath()
    return DATA_DIR .. "/" .. game.GetMap() .. ".json"
end

local function SaveZones()
    if not file.Exists(DATA_DIR, "DATA") then
        file.CreateDir(DATA_DIR)
    end
    local out = {}
    for i, z in ipairs(KillZones.Zones) do
        out[i] = {
            min = { z.min.x, z.min.y, z.min.z },
            max = { z.max.x, z.max.y, z.max.z },
        }
    end
    file.Write(DataPath(), util.TableToJSON(out, true))
end

local function LoadZones()
    KillZones.Zones = {}
    local raw = file.Read(DataPath(), "DATA")
    if not raw then return end
    local tbl = util.JSONToTable(raw)
    if not tbl then return end
    for _, z in ipairs(tbl) do
        table.insert(KillZones.Zones, {
            min = Vector(z.min[1], z.min[2], z.min[3]),
            max = Vector(z.max[1], z.max[2], z.max[3]),
        })
    end
    print("[KillZones] Loaded " .. #KillZones.Zones .. " zone(s) for " .. game.GetMap())
end

hook.Add("InitPostEntity", "KillZones_Load", LoadZones)
hook.Add("PostCleanupMap", "KillZones_Reload", LoadZones)

local function IsAdmin(ply)
    -- server console (NULL ply) counts as admin
    if not IsValid(ply) then return true end
    return ply:IsAdmin() or ply:IsSuperAdmin()
end

concommand.Add("zkill_corner1", function(ply)
    if not IsAdmin(ply) then return end
    if not IsValid(ply) then print("[KillZones] Run in-game (needs your position).") return end
    ply.KillZoneCorner1 = ply:GetPos()
    ply:ChatPrint("[KillZones] Corner 1 set at " .. tostring(ply.KillZoneCorner1) .. ". Move to the opposite corner and run zkill_corner2.")
end)

concommand.Add("zkill_corner2", function(ply)
    if not IsAdmin(ply) then return end
    if not IsValid(ply) then print("[KillZones] Run in-game (needs your position).") return end
    if not ply.KillZoneCorner1 then
        ply:ChatPrint("[KillZones] Set corner 1 first with zkill_corner1.")
        return
    end

    local c1, c2 = ply.KillZoneCorner1, ply:GetPos()
    local zone = {
        min = Vector(math.min(c1.x, c2.x), math.min(c1.y, c2.y), math.min(c1.z, c2.z)),
        max = Vector(math.max(c1.x, c2.x), math.max(c1.y, c2.y), math.max(c1.z, c2.z)),
    }
    -- Give the box vertical padding so falls/landings still catch
    zone.max.z = zone.max.z + 100

    table.insert(KillZones.Zones, zone)
    SaveZones()
    ply.KillZoneCorner1 = nil
    ply:ChatPrint("[KillZones] Zone #" .. #KillZones.Zones .. " created and saved for " .. game.GetMap() .. ".")
end)

concommand.Add("zkill_list", function(ply)
    if not IsAdmin(ply) then return end
    local say = IsValid(ply) and function(s) ply:ChatPrint(s) end or print
    if #KillZones.Zones == 0 then say("[KillZones] No zones on this map.") return end
    for i, z in ipairs(KillZones.Zones) do
        say(string.format("[KillZones] #%d  min(%d %d %d)  max(%d %d %d)",
            i, z.min.x, z.min.y, z.min.z, z.max.x, z.max.y, z.max.z))
    end
end)

concommand.Add("zkill_remove", function(ply, cmd, args)
    if not IsAdmin(ply) then return end
    local say = IsValid(ply) and function(s) ply:ChatPrint(s) end or print
    local id = tonumber(args[1])
    if not id or not KillZones.Zones[id] then say("[KillZones] Invalid id. Use zkill_list.") return end
    table.remove(KillZones.Zones, id)
    SaveZones()
    say("[KillZones] Zone #" .. id .. " removed.")
end)

concommand.Add("zkill_clear", function(ply)
    if not IsAdmin(ply) then return end
    local say = IsValid(ply) and function(s) ply:ChatPrint(s) end or print
    KillZones.Zones = {}
    SaveZones()
    say("[KillZones] All zones cleared for " .. game.GetMap() .. ".")
end)

-- The actual killing
local function InZone(pos, z)
    return pos.x >= z.min.x and pos.x <= z.max.x
       and pos.y >= z.min.y and pos.y <= z.max.y
       and pos.z >= z.min.z and pos.z <= z.max.z
end

timer.Create("KillZones_Check", 0.25, 0, function()
    if #KillZones.Zones == 0 then return end
    for _, ply in player.Iterator() do
        if not ply:Alive() then continue end
        if ply:Team() == TEAM_SPECTATOR then continue end
        if ply:IsAdmin() or ply:IsSuperAdmin() then continue end
        local pos = ply:GetPos()
        local rag = ply.FakeRagdoll
        local ragPos = IsValid(rag) and rag:GetPos() or nil
        for _, z in ipairs(KillZones.Zones) do
            if InZone(pos, z) or (ragPos and InZone(ragPos, z)) then
                ply:Kill()
                break
            end
        end
    end
end)

print("[KillZones] Loaded")

-- =========================================================================
-- MENU SUPPORT
-- =========================================================================
util.AddNetworkString("zkill_zonelist")
util.AddNetworkString("zkill_action")

local function SendZoneList(ply)
    if not IsValid(ply) or not IsAdmin(ply) then return end
    local out = {}
    for i, z in ipairs(KillZones.Zones) do
        out[i] = { min = z.min, max = z.max }
    end
    net.Start("zkill_zonelist")
        net.WriteTable(out)
        net.WriteBool(ply.KillZoneCorner1 ~= nil)
    net.Send(ply)
end

concommand.Add("zkill_menu", function(ply)
    if not IsValid(ply) or not IsAdmin(ply) then return end
    SendZoneList(ply)
end)

net.Receive("zkill_action", function(len, ply)
    if not IsValid(ply) or not IsAdmin(ply) then return end
    local action = net.ReadString()

    if action == "corner1" then
        ply.KillZoneCorner1 = ply:GetPos()
        ply:ChatPrint("[KillZones] Corner 1 set. Move to the opposite corner and hit Create Zone.")

    elseif action == "corner2" then
        if not ply.KillZoneCorner1 then
            ply:ChatPrint("[KillZones] Set corner 1 first.")
        else
            local c1, c2 = ply.KillZoneCorner1, ply:GetPos()
            local zone = {
                min = Vector(math.min(c1.x, c2.x), math.min(c1.y, c2.y), math.min(c1.z, c2.z)),
                max = Vector(math.max(c1.x, c2.x), math.max(c1.y, c2.y), math.max(c1.z, c2.z)),
            }
            zone.max.z = zone.max.z + 100
            table.insert(KillZones.Zones, zone)
            SaveZones()
            ply.KillZoneCorner1 = nil
            ply:ChatPrint("[KillZones] Zone #" .. #KillZones.Zones .. " created.")
        end

    elseif action == "remove" then
        local id = net.ReadInt(16)
        if KillZones.Zones[id] then
            table.remove(KillZones.Zones, id)
            SaveZones()
            ply:ChatPrint("[KillZones] Zone #" .. id .. " removed.")
        end

    elseif action == "clear" then
        KillZones.Zones = {}
        SaveZones()
        ply:ChatPrint("[KillZones] All zones cleared.")
    end

    SendZoneList(ply)
end)

-- Stand down during map change / server shutdown so no timer callback
-- runs mid-teardown (crash prevention)
hook.Add("ShutDown", "KillZones_Shutdown", function()
    timer.Remove("KillZones_Check")
end)
