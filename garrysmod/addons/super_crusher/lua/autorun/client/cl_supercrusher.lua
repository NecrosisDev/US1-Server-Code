-- Super Crusher (client): suppresses the berserk screen effect, music,
-- camera roll and sky/glow rendering for players flagged SilentBerserk.
if not CLIENT then return end

local silentUntil = 0

local function IsSilent()
    local lp = LocalPlayer()
    if IsValid(lp) and lp:GetNWBool("SilentBerserk", false) then
        -- hysteresis: bridge any single-frame flicker of the NWBool
        -- (fake/get-up transitions) so the intro can never sneak through
        silentUntil = CurTime() + 1
    end
    return CurTime() < silentUntil
end

local WRAP_TARGETS = {
    { "RenderScreenspaceEffects",       "berserkEffect" },
    { "Post Post Processing",           "berserkEffect" },
    { "PostDrawTranslucentRenderables", "berserkSky" },
    { "HG_CalcView",                    "InsaneRollCam" },
}

local function WrapBerserkHooks()
    for _, target in ipairs(WRAP_TARGETS) do
        local event, name = target[1], target[2]
        local tbl = hook.GetTable()[event]
        local fn = tbl and tbl[name]
        if fn and not (SuperCrusherWrapped and SuperCrusherWrapped[event .. name]) then
            SuperCrusherWrapped = SuperCrusherWrapped or {}
            SuperCrusherWrapped[event .. name] = true

            hook.Add(event, name, function(...)
                if IsSilent() then
                    if event == "RenderScreenspaceEffects" then
                        -- mark the intro as already-done so a stray
                        -- unsuppressed frame can never trigger it
                        hg.underberserk = false
                        hg.underberserk2 = true
                        if IsValid(hg.berserkStation) then
                            hg.berserkStation:Stop()
                            hg.berserkStation = nil
                        end
                        hg.berserkIntensity = 0
                        hg.notificationFont = "HuyFont"
                    end
                    return
                end
                return fn(...)
            end)
        end
    end
end

hook.Add("InitPostEntity", "SuperCrusher_Wrap", function()
    timer.Simple(5, WrapBerserkHooks)
    timer.Simple(30, WrapBerserkHooks)
end)
