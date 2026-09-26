local info=debug.getinfo(ZCityMetaSafety.Public,"S")
assert(info.short_src:find("zc_guilt_justice/meta.lua",1,true),"Unexpected live karma reader owner")
assert(hook.GetULibTable,"ULib priority support unavailable")
local M=assert(ZCityMetaSafety)
local function isPlayer(p)return IsValid(p)and p:IsPlayer()end
function M.Public(p)
    if not isPlayer(p) then return end
    if M.Locked() then
        local r=M.Account(p)
        -- A prior-round/boot transaction may await loading, persistence or review.
        -- Keep that transaction intact, but never use its old public snapshot to
        -- apply current-life penalties against a newly loaded player score.
        if r and r.round==M.Round() then return r.public end
    end
    return p.Karma
end
M.PublicRevision="20260923.1"

include("autorun/server/zc_karma_seizure_guard.lua")
include("autorun/server/zc_scoreboard_self_status.lua")
local h=hook.GetULibTable()
local stand=h["Should Fake Up"]and h["Should Fake Up"][-2]
local org=h["Org Think"]and h["Org Think"][-2]
assert(stand and stand["ZCKarmaSeizureGuard.Stand"],"Seizure stand priority missing")
assert(org and org["ZCKarmaSeizureGuard.Expiry"],"Seizure expiry priority missing")
for _,p in ipairs(player.GetHumans())do ZCScoreboardSelf.Publish(p)end
file.Write("zc_scoreboard_penalty_activation.json",util.TableToJSON({ok=true,meta=ZCityMetaSafety.PublicRevision,seizure=ZCKarmaSeizureGuard.Version,self=ZCScoreboardSelf.Version,humans=#player.GetHumans()},true))
