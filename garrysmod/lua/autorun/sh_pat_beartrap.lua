if SERVER then
    AddCSLuaFile()

    local files = {
        "materials/vgui/weapon_beartrap_homigrad.png",
        "materials/vgui/weapon_beartrap_homigrad.vmt",
        "materials/models/freeman/beartrap_diffuse.vtf",
        "materials/models/freeman/beartrap_specular.vtf",
        "materials/models/freeman/trap_dif.vmt",
        "sound/beartrap.wav",
        "models/stiffy360/beartrap.dx80.vtx",
        "models/stiffy360/beartrap.dx90.vtx",
        "models/stiffy360/beartrap.mdl",
        "models/stiffy360/beartrap.phy",
        "models/stiffy360/beartrap.sw.vtx",
        "models/stiffy360/beartrap.vvd",
        "models/stiffy360/beartrap.xbox.vtx",
        "models/stiffy360/c_beartrap.dx80.vtx",
        "models/stiffy360/c_beartrap.dx90.vtx",
        "models/stiffy360/c_beartrap.mdl",
        "models/stiffy360/c_beartrap.sw.vtx",
        "models/stiffy360/c_beartrap.vvd",
        "models/stiffy360/c_beartrap.xbox.vtx"
    }

    for _, path in ipairs(files) do
        resource.AddFile(path)
    end
end

PAT_BEARTRAP = PAT_BEARTRAP or {}
PAT_BEARTRAP.Model = "models/stiffy360/beartrap.mdl"
PAT_BEARTRAP.ViewModel = "models/stiffy360/c_beartrap.mdl"
PAT_BEARTRAP.Sound = Sound("beartrap.wav")

PAT_BEARTRAP.RearmTime = ConVarExists("pat_beartrap_rearm_time") and GetConVar("pat_beartrap_rearm_time") or CreateConVar("pat_beartrap_rearm_time", "3.5", FCVAR_ARCHIVE + FCVAR_NOTIFY, "Seconds before the bear trap reopens after triggering.", 0.5, 15)
PAT_BEARTRAP.StunTime = ConVarExists("pat_beartrap_stun_time") and GetConVar("pat_beartrap_stun_time") or CreateConVar("pat_beartrap_stun_time", "3.0", FCVAR_ARCHIVE + FCVAR_NOTIFY, "How long the trap briefly stuns the victim for after amputation.", 0, 15)
PAT_BEARTRAP.NPCDamage = ConVarExists("pat_beartrap_npc_damage") and GetConVar("pat_beartrap_npc_damage") or CreateConVar("pat_beartrap_npc_damage", "65", FCVAR_ARCHIVE + FCVAR_NOTIFY, "Fallback damage dealt to non-player victims.", 0, 200)

function PAT_BEARTRAP.GetCharacterEntity(ent)
    if not IsValid(ent) then return end

    if ent:IsPlayer() then
        if hg and hg.GetCurrentCharacter then
            return hg.GetCurrentCharacter(ent) or ent
        end

        return IsValid(ent.FakeRagdoll) and ent.FakeRagdoll or ent
    end

    if ent:IsRagdoll() and hg and hg.RagdollOwner then
        local owner = hg.RagdollOwner(ent)
        if IsValid(owner) then
            return PAT_BEARTRAP.GetCharacterEntity(owner)
        end
    end

    return ent
end

