-- ZC Spit: pure disrespect.
-- Bind a key to "zc_spit" (e.g.  bind v zc_spit)
--
--  - Spits where you're looking (short range)
--  - Wet splash decal on whatever/whoever it lands on
--  - Victims get a brief, easy-to-see-through blur that fades fast
--  - Spitter's camera bobs from the effort
--  - 3 second cooldown
if not SERVER then return end

local SPIT_RANGE    = 200
local SPIT_COOLDOWN = 3

concommand.Add("zc_spit", function(ply)
    if not IsValid(ply) or not ply:Alive() then return end
    if ply.organism and ply.organism.otrub then return end  -- can't spit unconscious

    if (ply.NextSpit or 0) > CurTime() then return end
    ply.NextSpit = CurTime() + SPIT_COOLDOWN

    -- Camera bob for the spitter (head snaps forward slightly)
    ply:ViewPunch(Angle(math.Rand(2.5, 4), math.Rand(-1, 1), 0))

    -- Wet mouth sound
    ply:EmitSound("player/footsteps/mud" .. math.random(1, 4) .. ".wav", 70, math.random(170, 190), 0.8)

    local trace = util.TraceHull({
        start = ply:EyePos(),
        endpos = ply:EyePos() + ply:GetAimVector() * SPIT_RANGE,
        filter = { ply, ply.FakeRagdoll },
        mins = Vector(-10, -10, -10),
        maxs = Vector(10, 10, 10),
        mask = MASK_SHOT,
    })

    if not trace.Hit then return end

    -- Impact drip sound at landing spot
    sound.Play("ambient/water/drip" .. math.random(1, 4) .. ".wav", trace.HitPos, 65, math.random(85, 100))

    -- Resolve a player victim (direct hit or their ragdoll)
    local victim = nil
    local ent = trace.Entity
    if IsValid(ent) then
        if ent:IsPlayer() then
            victim = ent
        elseif ent:GetClass() == "prop_ragdoll" then
            local owner = ent.ply
            if IsValid(owner) and owner:IsPlayer() then victim = owner end
        end
    end

    if IsValid(victim) and victim:Alive() and victim ~= ply then
        -- Light blue splash - subtle, brief, no damage
        victim:ScreenFade(SCREENFADE.IN, Color(150, 200, 235, 90), 0.7, 0.15)

        -- Bottom-screen notification (ZCity style, chat fallback) - anonymous
        local ok = pcall(function()
            victim:Notify("You were spat on.", true, "zcspit_hit_msg", 3)
        end)
        if not ok then
            victim:ChatPrint("You were spat on.")
        end

        victim:EmitSound("ambient/water/drip" .. math.random(1, 4) .. ".wav", 70, 110)

        for i = 0, 3 do
            timer.Simple(i * 0.2, function()
                if IsValid(victim) and victim:Alive() then
                    local dir = (i % 2 == 0) and 1 or -1
                    victim:ViewPunch(Angle(math.Rand(0.2, 0.45), dir * math.Rand(0.4, 0.8), dir * math.Rand(0.15, 0.35)))
                end
            end)
        end
    end
end)

print("[ZCSpit] Loaded - bind a key to zc_spit")
