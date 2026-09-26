SwingDoors = SwingDoors or {}
SwingDoors.Settings = SwingDoors.Settings or {}

SwingDoors.Const = {
    springStrength     = 18,
    dragDamping        = 9,
    swingLimit         = 90,
    contactMargin      = 2.5,
    propCheckRadius    = 100,
    propEjectSpeed     = 120,
    bodyPushScanRadius = 90,
    bodyPushMaxAngVel  = 220,
    bounceMinSpeed     = 12,
    bounceRestitution  = 0.5,
    handleGrabMinAngle = 0,
    handleGrabMaxAngle = 45,

    -- US1 impact module (sv_impact.lua)
    impactDoorMass     = 35,
    impactMaxMass      = 250,
    impactMinSpeed     = 60,
    impactLatchBreak   = 45,
    impactAjarMin      = 6,
    ragdollDrag        = 6,    -- deg/s^2 of braking per kg of ragdoll in the leaf's way
    slamMinSurface     = 60,   -- u/s of leaf surface speed before a blocked player is thrown
    slamRagdollSurface = 120,  -- ... before they are dropped into a ragdoll
    damageMomentum     = 25,   -- momentum per point of damage
    bulletLatchMult    = 3,
    breakDoorHP        = 200,  -- same pool and default Z-City's kicks use (ent.HP)
    breakImpactDivisor = 600,  -- kg*u/s of momentum per point of damage
    breakSwingAway     = 0.35, -- a door free to swing away only soaks this share of a hit
    breakMinDamage     = 4,    -- ignore taps
    breakSlidingMaxDim = 140,  -- func_door: only person-sized ones, never gates / lifts / blast doors    -- bullets need this many times the latch-break kick to pop a CLOSED door
}

SwingDoors.Settings.Schema = {
    { realm = "cl", key = "dragKey",           cvar = "swingdoors_cl_drag_key",           label = "Drag key",           default = KEY_E,    kind = "key" },
    { realm = "cl", key = "fullSwingKey",      cvar = "swingdoors_cl_fullswing_key",      label = "Full swing key",     default = KEY_LALT, kind = "key" },
    { realm = "cl", key = "pushSensitivity",   cvar = "swingdoors_cl_push_sensitivity",   label = "Push sensitivity",   default = 1.0, min = 0.1, max = 5,   decimals = 1 },
    { realm = "cl", key = "cameraSensitivity", cvar = "swingdoors_cl_camera_sensitivity", label = "Camera sensitivity", default = 0.2, min = 0,   max = 1,   decimals = 1 },

    { realm = "sv", key = "reachDistance",    cvar = "swingdoors_sv_reach_distance",     label = "Reach distance",     default = 120, min = 50,  max = 200,  decimals = 0 },
    { realm = "sv", key = "coastResistance",  cvar = "swingdoors_sv_coast_resistance",   label = "Coast resistance",   default = 3.2, min = 0.5, max = 15,   decimals = 1 },
    { realm = "sv", key = "maxSwingSpeed",    cvar = "swingdoors_sv_max_swing_speed",    label = "Max swing speed",    default = 260, min = 60,  max = 500,  decimals = 0 },
    { realm = "sv", key = "closeLatchDelay",  cvar = "swingdoors_sv_close_latch_delay",  label = "Close-latch delay",  default = 0.5, min = 0,   max = 2,    decimals = 1 },
    { realm = "sv", key = "soundVolume",      cvar = "swingdoors_sv_sound_volume",       label = "Sound volume",       default = 1.0, min = 0,   max = 2,    decimals = 1 },
    { realm = "sv", key = "stealProofWindow", cvar = "swingdoors_sv_steal_proof_window", label = "Steal-proof window", default = 1.0, min = 0,   max = 5,    decimals = 1 },
    { realm = "sv", key = "bodyPushStrength", cvar = "swingdoors_sv_body_push_strength", label = "Body push strength", default = 900, min = 0,   max = 1500, decimals = 0 },
    { realm = "sv", key = "impactStrength",   cvar = "swingdoors_sv_impact_strength",    label = "Prop/ragdoll impact strength", default = 1.0, min = 0, max = 3, decimals = 1 },
    { realm = "sv", key = "kickSwingSpeed",   cvar = "swingdoors_sv_kick_swing_speed",   label = "Kicked door swing speed",      default = 240, min = 60, max = 500, decimals = 0 },
    { realm = "sv", key = "damageStrength",   cvar = "swingdoors_sv_damage_strength",    label = "Bullet/blast nudge strength",  default = 1.0, min = 0, max = 3, decimals = 1 },
    { realm = "sv", key = "slamStrength",     cvar = "swingdoors_sv_slam_strength",      label = "Door slam strength (0 = off)", default = 1.0, min = 0, max = 2, decimals = 1 },
    { realm = "sv", key = "breakStrength",    cvar = "swingdoors_sv_break_strength",     label = "Door breaking (0 = off)",      default = 1.0, min = 0, max = 3, decimals = 1 },
}

SwingDoors.Settings.ByKey = {}

-- US1: master switch. While 0 every door is left to native/Z-City door logic.
local enabledCvar = CreateConVar("swingdoors_sv_enabled", "0", FCVAR_ARCHIVE + FCVAR_REPLICATED,
    "Master switch for SwingDoors. 0 = all doors behave natively.", 0, 1)

-- Z-City: a ragdolled player lives in ply.FakeRagdoll; their eyes and reach follow the body.
function SwingDoors.PlayerBody(ply)
    local ragdoll = ply.FakeRagdoll
    if IsValid(ragdoll) then return ragdoll end
    return nil
end

function SwingDoors.PlayerPos(ply)
    local body = SwingDoors.PlayerBody(ply)
    return body and body:GetPos() or ply:GetPos()
end

-- returns the trace and the distance from the eye to what it hit
function SwingDoors.EyeTrace(ply, reach)
    if SwingDoors.PlayerBody(ply) and hg and hg.eyeTrace then
        local tr = hg.eyeTrace(ply, reach + 40)
        if tr then return tr, tr.StartPos:Distance(tr.HitPos) end
    end
    local tr = ply:GetEyeTrace()
    return tr, ply:GetShootPos():Distance(tr.HitPos)
end

function SwingDoors.Enabled()
    return enabledCvar:GetBool()
end

function SwingDoors.Settings.Sanitize(def, value)
    return math.Round(math.Clamp(value, def.min, def.max), def.decimals or 0)
end

function SwingDoors.Settings.SanitizeConVar(def, rawString)
    local raw = tonumber(rawString)
    if not raw then return nil end

    local clean = SwingDoors.Settings.Sanitize(def, raw)
    local text = SwingDoors.Settings.Format(def, clean)
    if rawString ~= text then
        RunConsoleCommand(def.cvar, text)
    end

    return clean
end

function SwingDoors.Settings.Format(def, value)
    return string.format("%g", math.Round(value, def.decimals or 0))
end

for _, def in ipairs(SwingDoors.Settings.Schema) do
    SwingDoors.Settings.ByKey[def.key] = def

    if def.realm == "sv" then
        CreateConVar(def.cvar, tostring(def.default), FCVAR_ARCHIVE + FCVAR_REPLICATED, "", def.min, def.max)
    elseif CLIENT then
        CreateClientConVar(def.cvar, tostring(def.default), true, false, "", def.min, def.max)

        if def.decimals then
            cvars.AddChangeCallback(def.cvar, function(_, _, new)
                SwingDoors.Settings.SanitizeConVar(def, new)
            end, "SwingDoors_CleanClientCvar_" .. def.key)
        end
    end
end
