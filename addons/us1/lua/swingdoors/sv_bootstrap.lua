SwingDoors = SwingDoors or {}
SwingDoors.Debug = SwingDoors.Debug or { enabled = false }

SwingDoors.Config = SwingDoors.Config or {}
for _, def in ipairs(SwingDoors.Settings.Schema) do
    if def.realm == "sv" and SwingDoors.Config[def.key] == nil then SwingDoors.Config[def.key] = def.default end
end

util.AddNetworkString("SwingDoors_Grab")
util.AddNetworkString("SwingDoors_Nudge")
util.AddNetworkString("SwingDoors_LetGo")
util.AddNetworkString("SwingDoors_Tune")
util.AddNetworkString("SwingDoors_FullSwing")
util.AddNetworkString("SwingDoors_ForceRelease")
util.AddNetworkString("SwingDoors_Status")
util.AddNetworkString("SwingDoors_ResetClient")
util.AddNetworkString("SwingDoors_Print")

function SwingDoors.PrintTo(ply, text)
    if IsValid(ply) then
        net.Start("SwingDoors_Print")
            net.WriteString(text)
        net.Send(ply)
    else
        print(text)
    end
end

function SwingDoors.DBG(fmt, ...)
    if not SwingDoors.Debug.enabled then return end
    MsgC(Color(90, 200, 255), "[SwingDoors:SV] ", Color(255, 255, 255), string.format(fmt, ...), "\n")
end

SwingDoors.Sounds = {
    swing  = "doors/door1_move.wav",
    open   = "doors/door_latch3.wav",
    close  = "doors/door_wood_close1.wav",
    thud   = "doors/door1_stop.wav",
    denied = "doors/door_locked2.wav",
}

for _, path in pairs(SwingDoors.Sounds) do
    util.PrecacheSound(path)
end

SwingDoors.SWOOSH_START_SPEED       = 35
SwingDoors.SWOOSH_RETRIGGER_INTERVAL = 0.5

local SWOOSH_MIN_VOL      = 0.18
local SWOOSH_MAX_VOL      = 0.75
local SWOOSH_MIN_PITCH    = 55
local SWOOSH_MAX_PITCH    = 175

function SwingDoors.ComputeSwoosh(speed, maxSpeed)
    local t = math.Clamp(speed / maxSpeed, 0, 1)

    local eased = t * t
    local vol = Lerp(eased, SWOOSH_MIN_VOL, SWOOSH_MAX_VOL)
    local pitch = Lerp(eased, SWOOSH_MIN_PITCH, SWOOSH_MAX_PITCH)
    return vol, pitch
end

SwingDoors.DOOR_STINGERS = {
    open  = { sound = SwingDoors.Sounds.open,  minPitch = 88,  maxPitch = 118, minVol = 0.35, maxVol = 0.85 },
    close = { sound = SwingDoors.Sounds.close, minPitch = 88,  maxPitch = 125, minVol = 0.4,  maxVol = 1.0  },
    stop  = { sound = SwingDoors.Sounds.thud,  minPitch = 88,  maxPitch = 118, minVol = 0.4,  maxVol = 0.9  },
}

SwingDoors.OPEN_STINGER_BASELINE_SPEED = 70
SwingDoors.OPEN_SOUND_THRESHOLD = 1

function SwingDoors.PlayDoorStinger(door, kind, speed)
    local def = SwingDoors.DOOR_STINGERS[kind]
    if not def or not IsValid(door) then return end

    local t = math.Clamp((speed or 0) / SwingDoors.Config.maxSwingSpeed, 0, 1)
    local pitch = Lerp(t, def.minPitch, def.maxPitch)
    local vol = Lerp(t, def.minVol, def.maxVol)

    if door.SwingDoors_Quiet then vol = vol * 0.3 end
    door:EmitSound(def.sound, 70, pitch, vol * SwingDoors.Config.soundVolume)

    -- loudness 0..1; listeners: bot hearing, anything that reacts to door noise
    hook.Run("SwingDoors_Noise", door, kind, vol)
end
