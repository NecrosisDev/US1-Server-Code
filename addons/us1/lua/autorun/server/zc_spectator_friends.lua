-- Dead players with a living Steam friend cannot scout for them (owner, 2026-09-21): while one or more of their friends is
-- alive they lose free roam and may only watch teammates, in first or third person.
--
-- Who is friends with whom comes from the exchange `ulx friends` already uses (ULX custom commands, net "ulxcc_friends"):
-- the server sends the message, the client answers with the names of the connected players its Steam client calls friends.
-- No new client code. This file takes over the server end of that message and still serves `ulx friends` the same way.
--   * a pair counts only when BOTH clients name each other: one client cannot lock somebody else by claiming them
--   * answers are accepted only within ASK_WINDOW of being asked
--   * nothing here is sent to any client except the locked player's own chat line
-- The gamemode owns spectating (gamemodes/zcity init.lua: ply.viewmode, ply.chosenspect, ply.chosenSpectEntity, read every
-- PlayerDeathThink into NWInt "viewmode" / NWEntity "spect"). This only corrects those fields; it never edits that file.
-- PROVISIONAL(2026-09-21, names not SteamIDs because the borrowed client code sends names; own message at next restart, ratify-by: 2026-10-21)
if not SERVER then return end

ZCSpecFriends = ZCSpecFriends or {}
local S = ZCSpecFriends
S.Version = "20260921.sf1"

local mode = CreateConVar("zc_specfriend_lock", "1", FCVAR_ARCHIVE, "Dead players with a living Steam friend: 0 off, 1 log what would happen, 2 lock them to watching teammates")
local NET = "ulxcc_friends"
local ASK_WINDOW = 15
local CHECK_EVERY = 0.1

S.reported = S.reported or {} -- [SteamID64] = {[SteamID64] = true}: who each client named
S.asked = S.asked or {} -- [player] = CurTime() of the open question

function S.Ask(p)
    if not IsValid(p) or p:IsBot() or util.NetworkStringToID(NET) == 0 then return end
    S.asked[p] = CurTime()
    net.Start(NET)
    net.WriteEntity(p)
    net.Send(p)
end

local function record(p, names)
    local mine = {}
    local seen = 0
    for _, name in pairs(names) do
        seen = seen + 1
        if seen > 128 then break end
        if isstring(name) then
            for _, q in ipairs(player.GetHumans()) do
                if q ~= p and q:Nick() == name then mine[q:SteamID64()] = true end
            end
        end
    end
    S.reported[p:SteamID64()] = mine
end

function S.Friends(a, b)
    local ia, ib = a:SteamID64(), b:SteamID64()
    local ra, rb = S.reported[ia], S.reported[ib]
    return ra ~= nil and rb ~= nil and ra[ib] == true and rb[ia] == true
end

-- The server end of "ulxcc_friends". An answer to S.Ask is kept; anything else is `ulx friends`, forwarded as before.
function S.Receive(_, p)
    local who = net.ReadEntity()
    local names = net.ReadTable()
    local askedAt = S.asked[p]
    if askedAt and who == p then
        S.asked[p] = nil
        if CurTime() - askedAt <= ASK_WINDOW and istable(names) then record(p, names) end
        return
    end
    if IsValid(p.expcall) and who == p.expcall and istable(names) then
        net.Start("ulxcc_sendfriends")
        net.WriteTable(names)
        net.WriteString(p:Nick())
        net.Send(p.expcall)
    end
    p.expcall = nil
end

function S.Install()
    if util.NetworkStringToID(NET) == 0 then return false end
    net.Receive(NET, S.Receive)
    return true
end

local function hiddenRoles()
    local m = zb and zb.modes and zb.modes[zb.CROUND]
    return zb ~= nil and (zb.CROUND == "hmcd" or (m ~= nil and m.SubRoles ~= nil))
end

-- Who a locked player may watch. Team modes: living teammates. Hidden-role modes have no teams to speak of, so: the
-- living friends themselves (watching a friend shows nothing the friend cannot already see). Same fallback when no
-- teammate is left.
function S.Allowed(p, alive)
    local friends, mates, any = {}, {}, false
    local hasFriend = false
    for _, q in ipairs(alive) do
        if q ~= p and q:IsPlayer() and not q:IsBot() and S.Friends(p, q) then friends[q] = true hasFriend = true end
    end
    if not hasFriend then return nil end
    if not hiddenRoles() then
        for _, q in ipairs(alive) do
            if q ~= p and q:Team() == p:Team() then mates[q] = true any = true end
        end
    end
    return any and mates or friends
end

local function evaluate(p)
    local m = mode:GetInt()
    if m == 0 or not zb or zb.ROUND_STATE ~= 1 or p:IsBot() then p.zcSFLocked = nil return end
    local alive = zb:CheckAlive()
    local allowed = #alive > 0 and S.Allowed(p, alive)
    if not allowed then
        if p.zcSFLocked == 2 then p:ChatPrint("Free roam is available again.") end
        p.zcSFLocked = nil
        return
    end
    if m == 1 then
        if not p.zcSFLocked then
            p.zcSFLocked = 1
            ServerLog("[zc_specfriends] would lock " .. p:Nick() .. " (" .. p:SteamID64() .. "): a Steam friend is alive\n")
        end
        return
    end
    local changed = false
    if p.viewmode ~= 1 and p.viewmode ~= 2 then p.viewmode = 1 changed = true end
    if not allowed[p.chosenSpectEntity] then
        local n = #alive
        local idx = math.Clamp(tonumber(p.chosenspect) or 1, 1, n)
        local last = p.zcSFIdx
        local dir = last and n > 2 and (idx == last - 1 or (last == 1 and idx == n)) and -1 or 1
        for i = 1, n do
            local j = (idx - 1 + dir * i) % n + 1
            if allowed[alive[j]] then
                p.chosenspect, p.chosenSpectEntity = j, alive[j]
                changed = true
                break
            end
        end
    end
    p.zcSFIdx = p.chosenspect
    if changed then -- the message the gamemode sends on a spectate key, so the client's own copy agrees
        net.Start("ZB_SpectatePlayer")
        net.WriteEntity(p.chosenSpectEntity or NULL)
        net.WriteEntity(NULL)
        net.WriteInt(p.viewmode, 4)
        net.Send(p)
    end
    if p.zcSFLocked ~= 2 then
        p.zcSFLocked = 2
        p:ChatPrint("A Steam friend of yours is still alive, so you can only watch teammates until they die or the round ends.")
        ServerLog("[zc_specfriends] locked " .. p:Nick() .. " (" .. p:SteamID64() .. ")\n")
    end
end

hook.Add("PlayerDeathThink", "ZCSpecFriends", function(p) -- returns nothing: the gamemode decides respawns
    if p:Alive() then return end
    local now = CurTime()
    if (p.zcSFNext or 0) > now then return end
    p.zcSFNext = now + CHECK_EVERY
    local ok, err = pcall(evaluate, p)
    if not ok and not S.erred then S.erred = true ErrorNoHalt("[zc_specfriends] " .. tostring(err) .. "\n") end
end)

hook.Add("PlayerInitialSpawn", "ZCSpecFriends", function(p)
    timer.Simple(20, function() S.Ask(p) end)
end)

hook.Add("ZB_StartRound", "ZCSpecFriends", function() -- friendships change and players join: ask again, spread over a few seconds
    for i, p in ipairs(player.GetHumans()) do
        p.zcSFLocked, p.zcSFIdx = nil, nil
        timer.Simple(i * 0.1, function() S.Ask(p) end)
    end
end)

hook.Add("PlayerDisconnected", "ZCSpecFriends", function(p)
    S.asked[p] = nil
    local id = p:SteamID64()
    if id then S.reported[id] = nil end
end)

hook.Add("InitPostEntity", "ZCSpecFriends", function() timer.Simple(5, S.Install) end)
S.Install()

concommand.Add("zc_specfriend_status", function(p) -- staff only: friendships are not public
    if IsValid(p) and not p:IsAdmin() then return end
    local out = {"[zc_specfriends] " .. S.Version .. " mode " .. mode:GetInt()}
    local humans = player.GetHumans()
    for i = 1, #humans do
        for j = i + 1, #humans do
            if S.Friends(humans[i], humans[j]) then out[#out + 1] = "  " .. humans[i]:Nick() .. " <-> " .. humans[j]:Nick() end
        end
    end
    for _, q in ipairs(humans) do
        if q.zcSFLocked then out[#out + 1] = "  " .. (q.zcSFLocked == 2 and "locked: " or "would lock: ") .. q:Nick() end
    end
    local text = table.concat(out, "\n")
    if IsValid(p) then p:PrintMessage(HUD_PRINTCONSOLE, text) else print(text) end
end)
