-- KO Reaper: players knocked unconscious for longer than KO_LIMIT are killed,
-- unless they're close to waking up (consciousness recovering).
-- Prevents rounds dragging on for someone who's been face-down for 5 minutes.
if not SERVER then return end

local KO_LIMIT       = 90    -- seconds unconscious before the reaper comes (1.5 min)
local WAKE_THRESHOLD = 0.75  -- consciousness at/above this = "close to getting up", spared
local CHECK_INTERVAL = 1

timer.Create("KOReaper_Check", CHECK_INTERVAL, 0, function()
    -- Only operate during an active round - never during intermission,
    -- round transitions, or any non-live state
    if not zb or zb.ROUND_STATE ~= 1 then
        for _, ply in player.Iterator() do
            ply.KOReaperStart = nil
        end
        return
    end

    for _, ply in player.Iterator() do
        if not IsValid(ply) or not ply:Alive() or ply:Team() == TEAM_SPECTATOR then
            ply.KOReaperStart = nil
            continue
        end

        local org = ply.organism
        if not org then
            ply.KOReaperStart = nil
            continue
        end

        if org.otrub then
            -- knocked out - start/continue the clock
            ply.KOReaperStart = ply.KOReaperStart or CurTime()

            if CurTime() - ply.KOReaperStart >= KO_LIMIT then
                -- spare them if they're on their way back up
                if (org.consciousness or 0) >= WAKE_THRESHOLD then
                    continue
                end

                ply.KOReaperStart = nil
                ply:ChatPrint("You succumbed to your injuries.")
                local justice=ZCJusticeV3Integration
                if justice and justice.enabled and justice.WithTerminal then
                    justice:WithTerminal(ply,"timeout",function()ply:Kill()end)
                else ply:Kill()end
            end
        else
            -- awake (or got back up) - reset the clock
            ply.KOReaperStart = nil
        end
    end
end)

hook.Add("ShutDown", "KOReaper_Shutdown", function()
    timer.Remove("KOReaper_Check")
end)

print("[KOReaper] Loaded - unconscious players die after " .. KO_LIMIT .. "s unless recovering")
