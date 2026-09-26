-- Pure presentation shared by the real HUD and local behavior checks.
local M = {}
function M.View(s)
    local unit = s.guard and "National Guard" or "Police"
    local v = {title="REINFORCEMENTS", fraction=0, tone="waiting"}
    if s.phase == 1 then
        v.main = s.deathsLeft .. (s.deathsLeft == 1 and " more death" or " more deaths") .. " until voting opens"
        v.detail = s.dead .. " / " .. s.total .. " dead  |  85% required"
        v.fraction = s.total > 0 and s.dead / math.ceil(s.total * 0.85) or 0
    elseif s.phase == 2 then
        local left = math.max(0, s.required - s.yes)
        v.main = left .. (left == 1 and " more vote" or " more votes") .. " needed"
        if not s.eligible then v.detail = "Spectating only - you cannot vote"
        elseif s.voted then v.detail = "Your vote: Yes"
        else v.detail = "Vote for reinforcements" end
        if s.eligible then v.controls = "Press 1 to vote Yes  |  Press 2 to vote No" end
        v.detail = s.yes .. " / " .. s.required .. " votes  |  " .. v.detail
        v.fraction = s.required > 0 and s.yes / s.required or 0
        v.tone = "ready"
    elseif s.phase == 3 then
        v.main = "New vote available in " .. s.seconds .. "s"
        v.detail = "Previous vote expired"
    elseif s.phase == 4 or s.phase == 5 then
        v.main = unit .. " deployed: " .. s.spawned .. " / " .. s.planned
        v.detail = s.phase == 4 and "Reinforcements are arriving" or
            (s.stopped and "Deployment stopped" or "Deployment complete")
        if s.phase == 5 and not s.stopped and s.spawned < s.planned then
            v.detail = "Deployment complete - unavailable players skipped"
        end
        v.fraction = s.planned > 0 and s.spawned / s.planned or 0
        v.tone = "ready"
    else
        v.main = "Reinforcements unavailable"
        v.detail = "The round is no longer contested"
    end
    v.fraction = math.max(0, math.min(1, v.fraction))
    return v
end
return M
