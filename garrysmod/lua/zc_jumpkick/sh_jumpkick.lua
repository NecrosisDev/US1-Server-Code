-- Nativized 2026-09-24 from addons/pat's_jump_kick/lua/autorun/sh_pat_jumpkick.lua (verbatim; only this header
-- added). Loaded by lua/autorun/zc_jumpkick.lua on both realms.
PAT_JumpKick = PAT_JumpKick or {}

PAT_JumpKick.Version = "1.1.0"
PAT_JumpKick.Anim = "kick_pistol_45_base"

if SERVER then
    local flags = {FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_REPLICATED}

    PAT_JumpKick.CVars = PAT_JumpKick.CVars or {}
    PAT_JumpKick.CVars.enable = CreateConVar("pat_jumpkick_enable", "1", flags, "Enable standalone airborne jump kicks for Z-City leg attacks.", 0, 1)
    PAT_JumpKick.CVars.damage = CreateConVar("pat_jumpkick_damage", "9", flags, "Base damage dealt by jump kicks.", 0, 100)
    PAT_JumpKick.CVars.force = CreateConVar("pat_jumpkick_force", "240", flags, "Horizontal knockback force applied by jump kicks.", 0, 4000)
    PAT_JumpKick.CVars.lift = CreateConVar("pat_jumpkick_lift", "90", flags, "Upward force added to jump kicks.", 0, 1000)
    PAT_JumpKick.CVars.cooldown = CreateConVar("pat_jumpkick_cooldown", "1.8", flags, "Cooldown between jump kicks.", 0.1, 10)
    PAT_JumpKick.CVars.min_speed = CreateConVar("pat_jumpkick_min_speed", "140", flags, "Minimum horizontal speed required to start a jump kick.", 0, 1000)
    PAT_JumpKick.CVars.recovery_hit = CreateConVar("pat_jumpkick_recovery_hit", "0.08", flags, "Landing recovery time after a successful jump kick.", 0, 5)
    PAT_JumpKick.CVars.recovery_miss = CreateConVar("pat_jumpkick_recovery_miss", "0.2", flags, "Landing recovery time after missing a jump kick.", 0, 5)
    PAT_JumpKick.CVars.wall_stun_speed = CreateConVar("pat_jumpkick_wall_stun_speed", "420", flags, "Minimum speed required for a failed jump kick wall slam to ragdoll-stun the kicker.", 0, 2000)
    PAT_JumpKick.CVars.wall_stun_time = CreateConVar("pat_jumpkick_wall_stun_time", "1.75", flags, "Stun duration applied after a hard failed jump kick wall slam.", 0, 10)
    PAT_JumpKick.CVars.wall_stun_delay = CreateConVar("pat_jumpkick_wall_stun_delay", "0.08", flags, "Delay before the wall slam turns into a ragdoll stun, letting the kicker bounce off first.", 0, 1)
    PAT_JumpKick.CVars.rebound_enable = CreateConVar("pat_jumpkick_rebound_enable", "1", flags, "Allow a timed jump press to rebound off a wall slam instead of getting stunned.", 0, 1)
    PAT_JumpKick.CVars.rebound_speed = CreateConVar("pat_jumpkick_rebound_speed", "360", flags, "Minimum speed required to perform a wall rebound.", 0, 2000)
    PAT_JumpKick.CVars.rebound_window = CreateConVar("pat_jumpkick_rebound_window", "0.18", flags, "How recently jump must be pressed before wall impact to trigger a rebound.", 0.01, 1)
    PAT_JumpKick.CVars.rebound_grace = CreateConVar("pat_jumpkick_rebound_grace", "0.10", flags, "Delay after starting the jump kick before rebound input is accepted.", 0, 1)
    PAT_JumpKick.CVars.rebound_push = CreateConVar("pat_jumpkick_rebound_push", "150", flags, "Horizontal push added by a successful wall rebound.", 0, 4000)
    PAT_JumpKick.CVars.rebound_up = CreateConVar("pat_jumpkick_rebound_up", "260", flags, "Upward boost added by a successful wall rebound.", 0, 2000)
    PAT_JumpKick.CVars.rebound_cooldown = CreateConVar("pat_jumpkick_rebound_cooldown", "0.05", flags, "Extra cooldown added after a successful wall rebound.", 0, 3)
    PAT_JumpKick.CVars.debug = CreateConVar("pat_jumpkick_debug", "0", flags, "Print jump kick state/debug information.", 0, 1)
end

local defaults = {
    damage = 9,
    force = 240,
    lift = 90,
    cooldown = 1.8,
    min_speed = 140,
    recovery_hit = 0.08,
    recovery_miss = 0.2,
    wall_stun_speed = 420,
    wall_stun_time = 1.75,
    wall_stun_delay = 0.08,
    rebound_enable = 1,
    rebound_speed = 360,
    rebound_window = 0.18,
    rebound_grace = 0.10,
    rebound_push = 150,
    rebound_up = 260,
    rebound_cooldown = 0.05,
    debug = 0
}

local function getValue(name)
    local cvars = PAT_JumpKick.CVars
    local cvar = cvars and cvars[name]

    if not cvar then
        return defaults[name]
    end

    return cvar:GetFloat()
end

function PAT_JumpKick:IsEnabled()
    local cvars = self.CVars
    local cvar = cvars and cvars.enable

    if not cvar then
        return true
    end

    return cvar:GetBool()
end

function PAT_JumpKick:GetNumber(name)
    return getValue(name)
end

function PAT_JumpKick:IsDebugEnabled()
    local cvars = self.CVars
    local cvar = cvars and cvars.debug

    if not cvar then
        return false
    end

    return cvar:GetBool()
end

function PAT_JumpKick:GetHandsClass(ply)
    if IsValid(ply) and ply:HasWeapon("weapon_hg_coolhands") then
        return "weapon_hg_coolhands"
    end

    return "weapon_hands_sh"
end

function PAT_JumpKick:GetHandsWeapon(ply)
    local class = self:GetHandsClass(ply)

    if not IsValid(ply) then
        return class, nil
    end

    return class, ply:GetWeapon(class)
end



