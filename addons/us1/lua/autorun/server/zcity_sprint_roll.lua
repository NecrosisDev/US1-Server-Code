-- Input adapter only. The existing stealth owner admits, charges, moves and
-- interrupts the roll. A held crouch cannot repeat when its animation ends.
local duckDown=setmetatable({}, {__mode="k"})
local landing=setmetatable({}, {__mode="k"})
local function direction(cmd,fallback)
    local forward,side=cmd:GetForwardMove(),cmd:GetSideMove()
    if math.abs(forward)+math.abs(side)<1 then return fallback end
    return math.abs(side)>math.abs(forward) and (side>0 and "right" or "left")
        or (forward>=0 and "forward" or "back")
end
local function install()
    local S=ZCityStealth
    if not S then return end
    -- Above an ordinary jump landing, and at/through the point where the native
    -- fallStun owner starts doing real harm (speed > 600 in
    -- homigrad/fake/sv_input.lua), so the roll is usable as a save rather than
    -- firing on every hop.
    -- PROVISIONAL(2026-09-21, threshold derived from the native fall thresholds
    -- rather than measured play; ratify-by: 2026-10-21)
    S.RollLandingSpeed=S.RollLandingSpeed or 450
    -- The landing arrives during movement, after this tick's StartCommand, so
    -- the crouch that answers it is read on a later tick.
    S.RollLandingWindow=S.RollLandingWindow or .3
    function S.NoteHardLanding(p,speed)
        if not IsValid(p) or not p:IsPlayer() then return false end
        if (tonumber(speed) or 0)<S.RollLandingSpeed then return false end
        landing[p]=CurTime()
        return true
    end
    function S.TrySprintRoll(p,cmd)
        if not IsValid(p) or not p:IsPlayer() then return end
        local down=cmd:KeyDown(IN_DUCK)
        local wasDown=duckDown[p]
        duckDown[p]=down
        if not down or cmd:KeyDown(IN_JUMP) or not p:Alive() or not p:OnGround()
            or ZCityInteractions.Session(p) then return end
        -- A hard landing accepts a HELD crouch: bracing before impact is the
        -- natural input, so no rising edge is required here. The landing is
        -- consumed so one impact cannot roll twice while the key stays down.
        local landed=landing[p]
        if landed and CurTime()-landed<=S.RollLandingWindow then
            landing[p]=nil
            return S.Begin(p,nil,"roll_"..direction(cmd,"forward"))
        end
        if wasDown or not cmd:KeyDown(IN_SPEED) or p:GetVelocity():Length2D()<64 then return end
        local dir=direction(cmd)
        if not dir then return end
        -- Quiet rejection preserves ordinary crouching when this mode, role,
        -- equipment or body state cannot roll. Begin rechecks all authority.
        return S.Begin(p,nil,"roll_"..dir)
    end
    S.SprintRollRevision="20260921.rollinput2"
end
install()
hook.Add("InitPostEntity","ZCityStealth.SprintRoll",install)
-- Separate named hook: the native fallStun owner in homigrad/fake/sv_input.lua
-- keeps its own damage/stun behaviour untouched. Water is not a hard landing,
-- and a fake-ragdolled player is already being handled natively.
hook.Add("OnPlayerHitGround","ZCityStealth.SprintRoll",function(p,inwater,onfloater,speed)
    if inwater or IsValid(p.FakeRagdoll) then return end
    if ZCityStealth and ZCityStealth.NoteHardLanding then ZCityStealth.NoteHardLanding(p,speed) end
end)
hook.Add("PlayerDisconnected","ZCityStealth.SprintRoll",function(p) duckDown[p]=nil landing[p]=nil end)
-- Keep held state across deaths/rounds: a real key-up is required to rearm.
