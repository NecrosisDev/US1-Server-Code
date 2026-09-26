-- ZCity / installed FPV Drone 1.8 compatibility. No player teleport or camera seizure.
if SERVER then AddCSLuaFile("autorun/zcity_drones_compat.lua") end
ZCityDronesCompat = ZCityDronesCompat or {}
local D = ZCityDronesCompat
D.Version = "20260915.6"
function D.Active(ply)
    if not IsValid(ply) then return end
    for _, key in ipairs({ "kamikaze_", "active_mavic" }) do
        local drone = ply:GetNWEntity(key)
        if IsValid(drone) and isfunction(drone.GetDriver) and drone:GetDriver() == ply then
            return drone
        end
    end
end
if SERVER then
    -- Remove the original patch's unconditional reset of other addons' cameras.
    hook.Remove("PlayerPostThink", "ZCityDronesCompat_ViewEntity")
    hook.Add("SetupPlayerVisibility", "ZCityDronesCompat_PVS", function(ply)
        local drone = D.Active(ply)
        if IsValid(drone) then AddOriginToPVS(drone:GetPos()) end
    end)
    function D.Eject(ply)
        local drone = D.Active(ply)
        if not IsValid(drone) then return end
        local ok, err = pcall(function()
            if isfunction(drone.EjectDriver) then drone:EjectDriver()
            elseif isfunction(drone.SetDriver) then drone:SetDriver(NULL) end
        end)
        if not ok then ErrorNoHalt("[ZCityDronesCompat] eject: " .. tostring(err) .. "\n") end
    end
    local function ejectAll()
        for _, ply in ipairs(player.GetAll()) do D.Eject(ply) end
    end
    hook.Add("ZB_EndRound", "ZCityDronesCompat_RoundReset", ejectAll)
    hook.Add("ZB_PreRoundStart", "ZCityDronesCompat_RoundReset", ejectAll)
    hook.Add("PostPlayerDeath", "ZCityDronesCompat_DeathEject", D.Eject)
    hook.Add("PlayerDisconnected", "ZCityDronesCompat_Disconnect", D.Eject)
else
    -- The native drone owns offsets, gimbal pitch and zoom. ZCity yields in both
    -- CalcView and RenderScene via the shared arbiter below, independent of hook order.
    hook.Add("CalcView", "Drones_View", function(ply, pos, ang, fov)
        local drone = D.Active(ply)
        if IsValid(drone) and isfunction(drone.CalcView) then
            return drone:CalcView(ply, pos, ang, fov)
        end
    end)
end
print("[ZCityDronesCompat] " .. D.Version .. " loaded (" .. (SERVER and "server" or "client") .. ")")

-- Shared camera arbiter; identical in both compatibility addons.
if CLIENT then
    ZCityCompatView = ZCityCompatView or { hooks = {} }
    function ZCityCompatView.Active()
        local p = LocalPlayer()
        if not IsValid(p) then return false end
        return (ZCityDronesCompat and IsValid(ZCityDronesCompat.Active(p)))
            or (ZCityPillCompat and IsValid(ZCityPillCompat.Morph(p)))
    end
    function ZCityCompatView.Install()
        for event, name in pairs({ CalcView = "homigrad-view", RenderScene = "jopa" }) do
            local t = hook.GetTable()[event]
            local current = t and t[name]
            local old = ZCityCompatView.hooks[event]
            if isfunction(current) and (not old or current ~= old.wrapper) then
                local original = current
                local wrapper = function(...)
                    if ZCityCompatView.Active() then return end
                    return original(...)
                end
                ZCityCompatView.hooks[event] = { original = original, wrapper = wrapper }
                hook.Add(event, name, wrapper)
            end
        end
    end
    timer.Create("ZCityCompatView.Install", 1, 0, ZCityCompatView.Install)
    ZCityCompatView.Install()
end

-- Mouse attitude controls for this server's installed FPV Drone 1.8 entities.
-- Input travels in CUserCmd; no client-supplied entity or force messages.
local D = ZCityDronesCompat
D.Controls = D.Controls or { states = setmetatable({}, { __mode = "k" }),
    attached = setmetatable({}, { __mode = "k" }), inputHooks = {} }
local C = D.Controls
if C.Version ~= "20260915.6" then
    C.states = setmetatable({}, { __mode = "k" }) -- Do not reuse old steering targets.
end
C.Version = "20260915.6"
local supported = { drone_kamikaze_entity = true, kamikaze = true,
    fpv_at = true, dji_mavic3 = true }
function D.ControlDrone(ply)
    local drone = D.Active(ply)
    if not IsValid(drone) or not ply:Alive() or not supported[drone:GetClass()]
        or not drone.Enabled or drone.IsCrashed or drone.IsDestroyed then return end
    return drone
end
local function finite(n, default)
    return isnumber(n) and n == n and n > -math.huge and n < math.huge and n or default
end
local function limited(v, maximum)
    local length = v:Length()
    if length > maximum then return v * (maximum / length) end
    return v
end
function D.ControlState(drone, ply)
    local state = C.states[drone]
    if not state or state.pilot ~= ply then
        local a = drone:GetAngles()
        state = { pilot = ply, pitch = math.Clamp(math.NormalizeAngle(a.p), -80, 80),
            yaw = math.NormalizeAngle(a.y), roll = 0, lastInput = CurTime() }
        C.states[drone] = state
    end
    return state
end
function D.ReadFlightCommand(ply, cmd)
    local drone = D.ControlDrone(ply)
    if not IsValid(drone) then return end
    D.AttachFlight(drone)
    local state = D.ControlState(drone, ply)
    local number = cmd:CommandNumber()
    cmd:ClearMovement() -- Keep button bits for native thrust, climb and exit.
    if number <= 0 or cmd:IsForced() or state.command == number then return end
    local first = state.command == nil
    state.command = number
    state.lastInput = CurTime()
    state.roll = (cmd:KeyDown(IN_MOVERIGHT) and 1 or 0)
        - (cmd:KeyDown(IN_MOVELEFT) and 1 or 0)
    if first then return end -- Adopt current attitude; no entry-camera snap.
    local sensitivity = finite(ply:GetInfoNum("zc_drone_mouse_sensitivity", 1), 1)
    if sensitivity <= 0 then sensitivity = 1 end -- Missing userinfo (bots / joining clients).
    local gain = math.Clamp(sensitivity, 0.1, 5) * 0.06
    local invert = ply:GetInfoNum("zc_drone_invert_pitch", 0) == 1 and -1 or 1
    local dx = math.Clamp(finite(cmd:GetMouseX(), 0), -2048, 2048)
    local dy = math.Clamp(finite(cmd:GetMouseY(), 0), -2048, 2048)
    state.yaw = math.NormalizeAngle(state.yaw - dx * gain)
    state.pitch = math.Clamp(state.pitch + dy * gain * invert, -80, 80)
end
-- Shortest local axis-angle error: handles yaw wrap and banked flight correctly.
function D.FlightAngularAcceleration(current, target, velocity)
    local _, relative = WorldToLocal(vector_origin, target, vector_origin, current)
    local p, y, r = math.rad(relative.p) / 2, math.rad(relative.y) / 2, math.rad(relative.r) / 2
    local sp, cp, sy, cy, sr, cr = math.sin(p), math.cos(p), math.sin(y), math.cos(y), math.sin(r), math.cos(r)
    local w = cr * cp * cy + sr * sp * sy
    local axis = Vector(sr * cp * cy - cr * sp * sy, cr * sp * cy + sr * cp * sy,
        cr * cp * sy - sr * sp * cy)
    if w < 0 then w = -w; axis = -axis end
    local size = axis:Length()
    local error = size > 0.000001 and axis * (math.deg(2 * math.atan2(size, w)) / size) or Vector()
    local desiredRate = limited(error * 8, 180)
    local accel = limited((desiredRate - velocity) * 20, 2400)
    -- The attitude error and angular velocity are both in the physics-local frame.
    return accel
end
function D.AttachFlight(drone)
    local row = C.attached[drone]
    if row and drone.PhysicsSimulate == row.wrapper and row.version == C.Version then return end
    local original = row and drone.PhysicsSimulate == row.wrapper and row.original or drone.PhysicsSimulate
    if not isfunction(original) then return end
    local wrapper = function(self, phys, delta)
        local angular, linear, mode = original(self, phys, delta)
        local ply = self:GetDriver()
        if mode ~= SIM_GLOBAL_ACCELERATION or not isvector(linear)
            or D.ControlDrone(ply) ~= self then
            C.states[self] = nil
            return angular, linear, mode
        end
        local state = D.ControlState(self, ply)
        local roll = CurTime() - state.lastInput <= 0.25 and state.roll * 45 or 0
        local target = Angle(state.pitch, state.yaw, roll)
        -- Convert native world thrust, not local angular feedback. Both outputs are local.
        local current = phys:GetAngles()
        local localLinear = WorldToLocal(linear, angle_zero, vector_origin, current)
        return D.FlightAngularAcceleration(current, target, phys:GetAngleVelocity()), localLinear, SIM_LOCAL_ACCELERATION
    end
    C.attached[drone] = { original = original, wrapper = wrapper, version = C.Version }
    drone.PhysicsSimulate = wrapper
end
if SERVER then
    for drone in pairs(C.attached) do
        if IsValid(drone) then D.AttachFlight(drone) end
    end
    hook.Add("StartCommand", "ZCityDronesCompat_MouseFlight", D.ReadFlightCommand)
    hook.Add("EntityRemoved", "ZCityDronesCompat_ControlCleanup", function(ent)
        C.states[ent], C.attached[ent] = nil, nil
    end)
    hook.Add("PlayerDisconnected", "ZCityDronesCompat_ControlCleanup", function(ply)
        for ent, state in pairs(C.states) do
            if state.pilot == ply then C.states[ent] = nil end
        end
    end)
else
    CreateClientConVar("zc_drone_mouse_sensitivity", "1", true, true,
        "FPV drone mouse yaw/pitch sensitivity multiplier", 0.1, 5)
    CreateClientConVar("zc_drone_invert_pitch", "0", true, true,
        "Invert FPV drone mouse pitch", 0, 1)
    function D.ApplyFlightMouse(cmd, x, y, angle)
        if not IsValid(D.ControlDrone(LocalPlayer())) then return end
        local blocked = gui.IsGameUIVisible() or gui.IsConsoleVisible() or vgui.CursorVisible()
        cmd:SetMouseX(blocked and 0 or math.Clamp(math.Round(finite(x, 0)), -32767, 32767))
        cmd:SetMouseY(blocked and 0 or math.Clamp(math.Round(finite(y, 0)), -32767, 32767))
        cmd:SetViewAngles(angle) -- Drone attitude, not the hidden body, consumes mouse.
        return true
    end
    function D.InstallFlightInput()
        -- Replace only the conflicting callbacks, preserving their normal behavior.
        for event, name in pairs({ InputMouseApply = "fakeCameraAngles", CreateMove = "asdasdas22" }) do
            local current = (hook.GetTable()[event] or {})[name]
            local row = C.inputHooks[event]
            if isfunction(current) and (not row or current ~= row.wrapper) then
                local original, kind = current, event
                local wrapper = function(...)
                    if IsValid(D.ControlDrone(LocalPlayer())) then
                        if kind == "InputMouseApply" then return D.ApplyFlightMouse(...) end
                        return -- Do not run ZCity's synthetic zero-mouse callback.
                    end
                    return original(...)
                end
                C.inputHooks[event] = { original = original, wrapper = wrapper }
                hook.Add(event, name, wrapper)
            end
        end
    end
    hook.Add("InputMouseApply", "ZCityDronesCompat_MouseFlight", D.ApplyFlightMouse)
    timer.Create("ZCityDronesCompat_FlightInput", 1, 0, D.InstallFlightInput)
    D.InstallFlightInput()
end
