SwingDoors = SwingDoors or {}

local Geometry = SwingDoors.Geometry
local Portals = SwingDoors.Portals

local function RunDoorCheck(ply)
    if not IsValid(ply) then return end
    local eye = ply:GetEyeTrace()
    local ent = eye.Entity

    local out = {}
    local function P(fmt, ...) out[#out + 1] = string.format(fmt, ...) end

    P("=== swingdoors_sv_check by %s ===", ply:Nick())
    P("Looking at: %s", tostring(ent))
    if IsValid(ent) then
        P("Class: %s", ent:GetClass())
        P("Model: %s", tostring(ent:GetModel()))
        P("World Angles: %s", tostring(ent:GetAngles()))
        local authored = Geometry.GetAuthoredClosedAngle(ent)
        P("Authored Closed Angle: %s", authored and tostring(authored) or "nil (using live angle)")
        local lo, hi, dist, opendir, spawnflags, distSource = Geometry.GetDoorMotionBounds(ent)
        P("Native distance (m_flDistance): %s", tostring(ent.GetInternalVariable and ent:GetInternalVariable("m_flDistance")))
        P("opendir: %d, spawnflags: %d", opendir, spawnflags)
        P("Computed Motion Bounds: lo=%.1f deg, hi=%.1f deg (max dist=%.1f, SOURCE=%s%s)",
            lo, hi, dist, distSource,
            distSource == "fallback" and " <- NOT reading per-door value, using SwingDoors.Const.swingLimit!" or "")
        P("m_eDoorState: %s", tostring(ent.GetInternalVariable and ent:GetInternalVariable("m_eDoorState")))
        P("m_bLocked: %s", tostring(ent.GetInternalVariable and ent:GetInternalVariable("m_bLocked")))
        P("IsSwingable: %s", tostring(Geometry.IsSwingable(ent, "check")))
        P("IsLatched: %s", tostring(Geometry.IsLatched(ent)))
        P("Sanity check (angle + phys object OK): %s", tostring(Geometry.IsSafeToSwing(ent)))

        P("-- portal link probe --")
        P("Door targetname: %s", tostring(ent:GetName()))
        for _, portal in ipairs(ents.FindByClass("func_areaportal")) do
            local linkedName, via = Portals.GetPortalLinkedDoorName(portal)
            P("  portal %s: m_target-probe=%s (via %s)", tostring(portal), tostring(linkedName), tostring(via))
        end
        local portals = Portals.ResolveDoorPortal(ent)
        P("ResolveDoorPortal result: %d portal(s) (method=%s)", portals and #portals or 0, tostring(ent.SwingDoors_PortalMatchMethod))
        for _, p in ipairs(portals or {}) do
            P("  -> %s", tostring(p))
        end
    end
    P("=== end check ===")

    SwingDoors.PrintTo(ply, table.concat(out, "\n"))
end

concommand.Add("swingdoors_sv_check", function(ply)
    if not IsValid(ply) then
        print("[SwingDoors] swingdoors_sv_check needs a player looking at a door; run it from the game console.")
        return
    end
    if not ply:IsAdmin() then return end
    RunDoorCheck(ply)
end)

concommand.Add("swingdoors_sv_debug", function(ply, _, args)
    if not (game.SinglePlayer() or not IsValid(ply) or ply:IsAdmin()) then return end
    if args[1] ~= nil then
        SwingDoors.Debug.enabled = tobool(args[1])
    else
        SwingDoors.Debug.enabled = not SwingDoors.Debug.enabled
    end
    local msg = "[SwingDoors] server debug logging " .. (SwingDoors.Debug.enabled and "ENABLED" or "DISABLED")
    SwingDoors.PrintTo(ply, msg)
end)
