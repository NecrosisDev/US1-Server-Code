-- ZCJ3 medical observation taps v1 (server-only)
-- Fiberwire Extras (overlay for "ZCITY Fiber Wire Mod (standalone)")
-- Adds on top of the workshop mod WITHOUT modifying it:
--   1. Strangled players cannot use voice or text chat
--   2. After 15 seconds of CONTINUOUS strangling, an arterial bleed opens
--      in the victim's neck (persists after release - they need treatment)
-- Strangle time resets whenever the wire is released.
if not SERVER then return end

local ARTERY_TIME  = 15    -- seconds of continuous strangling
local ARTERY_BLEED = 400   -- bleed per wound (arterial tier)
local ARTERY_WOUNDS = 2

-- A player counts as strangled when their ZCity fake-ragdoll is locked by
-- the fiberwire (the mod sets these fields on the ragdoll while choking)
local function IsStrangled(ply)
    local rag = ply.FakeRagdoll
    return IsValid(rag) and rag.StrangleLocked == true and IsValid(rag.Strangler)
end

-- Exposed for the ULX-ZChat bridge (voice/text blocking)
function Fiberwire_IsStrangled(ply)
    return IsValid(ply) and ply.FiberwireStrangled == true
end

local function OpenArteryNative(ply)
    local org = ply.organism
    if not org then return end
    if not (hg and hg.organism and hg.organism.AddWoundManual) then return end

    local rag = ply.FakeRagdoll
    local ent = IsValid(rag) and rag or ply
    local neckBone = ent:LookupBone("ValveBiped.Bip01_Neck1") or ent:LookupBone("ValveBiped.Bip01_Head1")

    for i = 1, ARTERY_WOUNDS do
        hg.organism.AddWoundManual(ply, ARTERY_BLEED, vector_origin, angle_zero, neckBone or 0, CurTime() + math.Rand(0, 1))
    end

    ent:EmitSound("physics/flesh/flesh_squishy_impact_hard" .. math.random(1, 4) .. ".wav", 75, 90)

    -- Tell the victim, using the mod's own notify style if available
    local ok = pcall(function()
        ply:Notify("The wire bites deep. Something tears in your neck - hot blood pours down your chest.", true, "fiberwire_artery", 4)
    end)
    if not ok then
        ply:ChatPrint("The wire bites deep. Something tears in your neck.")
    end
end

local function OpenArtery(ply)
    local r=ZCJusticeV3Integration
    if r and r.enabled and r.WithWireMedical then
        return r:WithWireMedical(ply,OpenArteryNative,ply)
    end
    return OpenArteryNative(ply)
end

timer.Create("FiberwireExtras_Check", 0.25, 0, function()
    for _, ply in player.Iterator() do
        if not IsValid(ply) or not ply:Alive() then
            ply.FiberwireStrangleStart = nil
            ply.FiberwireStrangled = nil
            ply.FiberwireArteryDone = nil
            continue
        end

        if IsStrangled(ply) then
            ply.FiberwireStrangled = true
            ply.FiberwireStrangleStart = ply.FiberwireStrangleStart or CurTime()

            if not ply.FiberwireArteryDone
                and CurTime() - ply.FiberwireStrangleStart >= ARTERY_TIME then
                ply.FiberwireArteryDone = true
                OpenArtery(ply)
            end
        else
            -- released - everything resets (bleed, if opened, stays)
            ply.FiberwireStrangled = nil
            ply.FiberwireStrangleStart = nil
            ply.FiberwireArteryDone = nil
        end
    end
end)

hook.Add("ShutDown", "FiberwireExtras_Shutdown", function()
    timer.Remove("FiberwireExtras_Check")
end)

print("[FiberwireExtras] Loaded - strangle silence + " .. ARTERY_TIME .. "s arterial bleed")
