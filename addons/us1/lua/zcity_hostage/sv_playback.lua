-- Thin, finite-play adapter over the server's existing custom-animation owner.
-- Paired choreography, movement, damage and restraints remain gameplay-owned.
local H = ZCityHostage
local active = setmetatable({}, {__mode = "k"})

local function owns(ply, state)
    return IsValid(ply) and ply:GetNWString("hg_CustomAnim", "") == state.sequence
        and ply:GetNWFloat("hg_CustomAnimStartTime", -1) == state.start
end

function H.Stop(ply)
    local state = active[ply]
    if not state then return false end
    active[ply] = nil
    if owns(ply, state) and ply.PlayCustomAnims then
        ply:PlayCustomAnims("")
        return true
    end
    return false
end

function H.Play(ply, sequence)
    local clip = H.BySequence[sequence]
    if not clip then return false, "Unknown Hostage Set sequence" end
    if not IsValid(ply) or not ply:IsPlayer() or not ply:Alive() then return false, "A living player is required" end
    if not ply.PlayCustomAnims then return false, "ZCity animation API is unavailable" end
    if ply:InVehicle() or not ply:OnGround() or ply:GetVelocity():LengthSqr() > 25 then return false, "Stand still on the ground" end
    if ply:KeyDown(IN_ATTACK) or ply:KeyDown(IN_ATTACK2) then return false, "Release the attack buttons" end
    if IsValid(ply:GetNWEntity("FakeRagdoll")) then return false, "Player is ragdolled" end
    if clip.paired or clip.root_motion or clip.locomotion or clip.pose_sample or clip.requires_positioning then
        return false, "This clip needs a gameplay controller; inspect it with zch_preview"
    end
    local current = ply:GetNWString("hg_CustomAnim", "")
    if current ~= "" then return false, "Another custom animation is active" end
    local id, duration = ply:LookupSequence(sequence)
    if not id or id < 0 or not duration or duration <= 0 then return false, "Animation content is not mounted on this player model" end
    ply:PlayCustomAnims(sequence, true, duration)
    active[ply] = {
        sequence = sequence,
        start = ply:GetNWFloat("hg_CustomAnimStartTime"),
        finish = CurTime() + duration,
        model = ply:GetModel(),
        weapon = ply:GetActiveWeapon()
    }
    return true, duration
end

-- Only iterates players currently using this adapter. No per-player bone work.
hook.Add("Think", "ZCityHostage.PlaybackLifetime", function()
    for ply, state in pairs(active) do
        if not owns(ply, state) then
            active[ply] = nil
        elseif CurTime() >= state.finish or not ply:Alive() or ply:InVehicle()
            or not ply:OnGround() or ply:GetVelocity():LengthSqr() > 25
            or ply:KeyDown(IN_ATTACK) or ply:KeyDown(IN_ATTACK2) or ply:GetActiveWeapon() ~= state.weapon
            or ply:GetModel() ~= state.model or IsValid(ply:GetNWEntity("FakeRagdoll")) then
            H.Stop(ply)
        end
    end
end)

hook.Add("PlayerDisconnected", "ZCityHostage.Disconnect", function(ply) active[ply] = nil end)
hook.Add("PlayerDeath", "ZCityHostage.Death", function(ply) H.Stop(ply) end)
hook.Add("PlayerSpawn", "ZCityHostage.Spawn", function(ply) if OverrideSpawn then return end H.Stop(ply) end)

-- An admin may test only their own consenting player, never another player.
concommand.Add("zch_play", function(ply, _, args)
    if not IsValid(ply) or not ply:IsAdmin() then return end
    local ok, reason = H.Play(ply, args[1])
    if not ok then ply:ChatPrint("Hostage Set: " .. reason) end
end)
concommand.Add("zch_stop", function(ply)
    if IsValid(ply) then H.Stop(ply) end
end)
