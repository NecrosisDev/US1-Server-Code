    local function EnsureFakeAndSplit(ply, force, fromExplosion)
        if not IsValid(ply) or not ply:IsPlayer() or not ply:Alive() then return false end
        if ply:GetNWBool("ZCityTorsoSevered", false) or (ply.organism and ply.organism.torsoamputated) then return false end
        if ply.__zcGoreTorsoPending then return false end
        ply.__zcGoreTorsoPending = true

        if not IsValid(ply.FakeRagdoll) then
            if not hg or not hg.Fake then
                ply.__zcGoreTorsoPending = nil
                return false
            end
            hg.Fake(ply, nil, nil, true)
        end

        local rag = IsValid(ply.FakeRagdoll) and ply.FakeRagdoll or (hg and hg.GetCurrentCharacter and hg.GetCurrentCharacter(ply) or nil)
        if not IsValid(rag) or not rag:IsRagdoll() then
            ply.__zcGoreTorsoPending = nil
            return false
        end
        local state = BuildSplitRagdolls(ply, rag, force or vector_origin)
        if not state then
            ply.__zcGoreTorsoPending = nil
            return false
        end
        AddTorsoTrauma(ply, rag, fromExplosion)
        ply.__zcGoreTorsoPending = nil
        return true
    end

    hg = hg or {}
    hg.ZCityGore_AmputateTorso = function(ent, force, fromExplosion)
        local ply = ResolvePlayer(ent)
        if not IsValid(ply) then return false end
        return EnsureFakeAndSplit(ply, force or VectorRand(-250, 250), fromExplosion == true)
    end

