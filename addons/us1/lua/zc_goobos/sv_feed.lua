if not SERVER then return end
local F = ZCGoobFeed
local enabled = CreateConVar("zc_goobos_feed", "1", FCVAR_ARCHIVE, "Enable CityLeak posts and profiles")
util.AddNetworkString("GoobOS.Feed.Request")
util.AddNetworkString("GoobOS.Feed.State")
util.AddNetworkString("GoobOS.Feed.Upload")
util.AddNetworkString("GoobOS.Feed.Photo")
util.AddNetworkString("GoobOS.Notify")
-- GoobOS push to a post's author when someone reacts or replies (zc_goobos_notify, created in the autorun; default 0).
-- One push per recipient every 5 s; never to yourself; only to players CityLeak is available to.
local function clip(text, chars)
    text = tostring(text or "")
    local cut = utf8.offset(text, chars + 1)
    return cut and string.sub(text, 1, cut - 1) .. "…" or text
end
local function notifyRow(p, tableName, id, title, body)
    local cv = GetConVar("zc_goobos_notify")
    if not (cv and cv:GetBool()) or not F.Integer(id, 1, 2147483647) then return end
    local row = F.Query("SELECT author FROM " .. tableName .. " WHERE id=" .. id)[1]
    if not row or row.author == p:SteamID64() then return end
    local target = player.GetBySteamID64(row.author)
    if not IsValid(target) or not F.Allowed(target) or (target.GoobNotifyNext or 0) > RealTime() then return end
    target.GoobNotifyNext = RealTime() + 5
    net.Start("GoobOS.Notify"); net.WriteString("feed"); net.WriteString(clip(title, 80)); net.WriteString(clip(body, 120)); net.Send(target)
end
local function notifyAuthor(p, id, title, body) notifyRow(p, "zc_feed_posts", id, title, body) end
-- B2: also push to the parent COMMENT's author on a reply-to-a-reply; the shared per-target
-- GoobNotifyNext throttle above means a post author who is also the parent-comment author is not double-pushed.
local function notifyParent(p, parentID, title, body) notifyRow(p, "zc_feed_comments", parentID, title, body) end
-- A hot reload (autorefresh) re-runs this file's top level; keep any in-flight uploads/downloads
-- and rate-limit buckets instead of wiping them out from under a player mid-transfer.
F.uploads, F.downloads, F.buckets = F.uploads or {}, F.downloads or {}, F.buckets or {}
-- 2026-09-26 background transfers (owner: "a budget that won't affect the server"). Every photo chunk the server sends
-- (downloads) and every upload chunk it acknowledges goes through this scheduler: a server-wide byte budget plus a
-- per-player budget, oldest job first, so CityLeak can never crowd out game traffic. Clients wait for each chunk or
-- acknowledgement before sending the next, so each player has at most one job queued.
local cvKbps = CreateConVar("zc_goobos_feed_kbps", "160", FCVAR_ARCHIVE, "CityLeak photo transfers for the whole server, KB/s (uploads + downloads)", 16, 4096)
local cvKbpsPlayer = CreateConVar("zc_goobos_feed_kbps_player", "48", FCVAR_ARCHIVE, "CityLeak photo transfers per player, KB/s", 8, 1024)
F.xfer = F.xfer or {jobs = {}, tokens = 0, time = RealTime(), players = {}}
local X = F.xfer
local function schedule(p, cost, run)
    for i = #X.jobs, 1, -1 do if X.jobs[i].p == p then table.remove(X.jobs, i) end end -- one job per player
    X.jobs[#X.jobs + 1] = {p = p, cost = cost, run = run}
end
hook.Add("Think", "GoobOS.Feed.Transfers", function()
    local now = RealTime()
    local rate, playerRate = cvKbps:GetInt() * 1024, cvKbpsPlayer:GetInt() * 1024
    X.tokens = math.min(rate * 0.25 + F.ChunkSize, X.tokens + rate * math.Clamp(now - X.time, 0, 0.5))
    X.time = now
    local jobs, i, ran = X.jobs, 1, 0
    while jobs[i] and ran < 32 do
        local job = jobs[i]
        if not IsValid(job.p) then
            table.remove(jobs, i)
        else
            local mine = X.players[job.p] or {tokens = playerRate * 0.25 + F.ChunkSize, time = now}
            mine.tokens = math.min(playerRate * 0.25 + F.ChunkSize, mine.tokens + playerRate * math.Clamp(now - mine.time, 0, 0.5))
            mine.time = now
            X.players[job.p] = mine
            if X.tokens < job.cost then break end
            if mine.tokens >= job.cost then
                mine.tokens, X.tokens = mine.tokens - job.cost, X.tokens - job.cost
                table.remove(jobs, i)
                ran = ran + 1
                local ok, err = pcall(job.run)
                if not ok then ErrorNoHalt("[GoobOS Feed] transfer job failed: " .. tostring(err) .. "\n") end
            else
                i = i + 1
            end
        end
    end
end)
local uploadSerial = 0
function F.Allowed(p)
    if not IsValid(p) or p:IsBot() or not F.Account(p:SteamID64()) or not enabled:GetBool() then return false end
    -- Deliberately unavailable beside an unintegrated SpecDM runtime. A domain check alone
    -- cannot revoke already queued packets; its generation barrier is a release prerequisite.
    if ZCSpecDM ~= nil then return false end
    local owner = ZCGoobArcade
    return not owner or not owner.ArcadeAudience or owner.ArcadeAudience(p) == "main"
end
local function send(p, request, data)
    if not IsValid(p) then return end
    if not F.Allowed(p) then data = {blocked = true, error = "CityLeak is unavailable in this world or while its isolation integration is pending."} end
    local json = util.TableToJSON(data)
    if not json or #json > 28000 then json = util.TableToJSON({error = "This page is too large. Refresh CityLeak."}) end
    net.Start("GoobOS.Feed.State"); net.WriteUInt(request, 32); net.WriteString(json); net.Send(p)
end
local function budget(p)
    local now = RealTime()
    local b = F.buckets[p] or {time = now, tokens = 4}
    b.tokens = math.min(4, b.tokens + (now - b.time) * 8); b.time = now; F.buckets[p] = b
    if b.tokens < 1 then return false end
    b.tokens = b.tokens - 1
    return true
end
local function photo(p, request, data)
    local post = F.Post(data.id)
    F.Require(post.photo and F.Integer(data.offset or 0, 0, F.PhotoLimit), "Photo unavailable.")
    local download = F.downloads[p]
    if not download or download.id ~= data.id or download.expires < RealTime() then
        F.Require((data.offset or 0) == 0, "Photo transfer expired. Open the photo again.")
        local row = F.Query("SELECT image FROM zc_feed_photos WHERE post=" .. data.id)[1]
        F.Require(row, "Photo unavailable.")
        local bytes = util.Base64Decode(row.image)
        F.Require(F.JPEG(bytes), "Stored photo unavailable.")
        download = {id = data.id, bytes = bytes, expires = RealTime() + 30}; F.downloads[p] = download
    end
    local offset = data.offset or 0
    F.Require(offset < #download.bytes and offset % F.ChunkSize == 0, "Invalid photo chunk.")
    local bytes = download.bytes:sub(offset + 1, offset + F.ChunkSize)
    if not F.Allowed(p) then F.downloads[p] = nil; return send(p, request, {}) end
    download.expires = RealTime() + 30 -- a queued transfer is still a live one
    schedule(p, #bytes + 32, function()
        if F.downloads[p] ~= download or not F.Allowed(p) then return end
        net.Start("GoobOS.Feed.Photo")
        net.WriteUInt(request, 32); net.WriteUInt(data.id, 32); net.WriteUInt(#download.bytes, 19)
        net.WriteUInt(offset, 19); net.WriteUInt(#bytes, 14); net.WriteData(bytes, #bytes); net.Send(p)
        if offset + #bytes == #download.bytes then F.downloads[p] = nil end
    end)
end
function F.Dispatch(p, request, data)
    F.Require(istable(data) and isstring(data.op), "Invalid request.")
    F.Storage()
    local sid = p:SteamID64()
    if data.op == "feed" then
        local result = F.Feed(sid, data.before, data.author, data.tab)
        result.kind, result.admin, result.self = "feed", F.Staff(p), sid
        return send(p, request, result)
    elseif data.op == "profile" then
        local author = data.author or sid
        for _, person in ipairs(player.GetHumans()) do
            if person:SteamID64() == author and F.Allowed(person) then
                if RealTime() >= (person.GoobFeedProfileNext or 0) then F.Snapshot(person); person.GoobFeedProfileNext = RealTime() + 60 end
                break
            end
        end
        return send(p, request, {kind = "profile", profile = F.Profile(author)})
    elseif data.op == "thread" then
        local result = F.Thread(sid, data.id, data.before); result.kind = "thread"
        return send(p, request, result)
    elseif data.op == "publish" then
        F.Require(F.Text(data.body, 1200, true) and isstring(data.nonce) and #data.nonce == 32 and data.nonce:match("^%x+$"), "Invalid post.")
        local previous = F.Query("SELECT id FROM zc_feed_posts WHERE author=" .. F.Quote(sid) .. " AND nonce=" .. F.Quote(data.nonce))[1]
        if previous then return send(p, request, {kind = "published", id = tonumber(previous.id)}) end
        F.Require(F.CanWrite(p), "You are muted and cannot publish to CityLeak.")
        -- B1 killcam-clip reference: F.Publish validates+stores data.clip when present. No client UI sets it
        -- yet (see REPLY: killcam has no share-to-CityLeak entry point today); the wire is ready regardless.
        if (data.bytes or 0) == 0 then return send(p, request, {kind = "published", id = F.Publish(p, data.body, data.nonce, nil, nil, data.clip)}) end
        F.Require(F.Integer(data.bytes, 16, F.PhotoLimit), "Photo exceeds the sharing limit.")
        -- 1800 raw bytes -> ceil(1800/3)*4 = 2400 base64 chars exactly; the client now encodes this
        -- inline (util.Base64Encode(..., true), no RFC 2045 newlines -- see feed.lua), so 2400 is the
        -- real ceiling, but keep small headroom rather than pinning to that exact arithmetic.
        F.Require(isstring(data.thumb) and #data.thumb <= 2432, "Invalid photo preview.")
        local thumb = util.Base64Decode(data.thumb)
        local valid, w, h = F.JPEG(thumb)
        F.Require(valid and #thumb <= 1800 and w <= 160 and h <= 90, "Invalid photo preview.")
        local count = 0; for person in pairs(F.uploads) do if person ~= p then count = count + 1 end end
        F.Require(count < 8, "Photo uploads are busy. Try again shortly.")
        uploadSerial = uploadSerial % 4294967294 + 1
        F.uploads[p] = {id = uploadSerial, request = request, body = data.body, nonce = data.nonce,
            size = data.bytes, thumb = thumb, received = 0, parts = {}, expires = RealTime() + 40}
        return send(p, request, {kind = "upload", upload = uploadSerial, offset = 0})
    elseif data.op == "cancel" then
        F.uploads[p], F.downloads[p] = nil, nil
    elseif data.op == "comment" then
        local repeated = isstring(data.nonce) and F.Query("SELECT id FROM zc_feed_comments WHERE author=" .. F.Quote(sid) .. " AND nonce=" .. F.Quote(data.nonce))[1]
        F.Comment(p, data.id, data.body, data.nonce, data.parent)
        if not repeated then
            notifyAuthor(p, data.id, p:Nick() .. " replied to your post", F.Text(data.body, 500, false) or "")
            if F.Integer(data.parent, 1, 2147483647) then notifyParent(p, data.parent, p:Nick() .. " replied to your comment", F.Text(data.body, 500, false) or "") end
        end
    elseif data.op == "react" then
        F.React(p, data.id, data.reaction)
        if (data.reaction or 0) > 0 then notifyAuthor(p, data.id, p:Nick() .. " reacted " .. tostring(F.Reactions[data.reaction] or "") .. " to your post", "Tap to open CityLeak") end
        return send(p, request, {kind = "post", post = F.Decorate(F.Post(data.id), sid)})
    elseif data.op == "remove" then F.Remove(p, data.kind, data.id)
    elseif data.op == "report" then F.Report(p, data.kind, data.id, data.reason)
    elseif data.op == "reports" then
        F.Require(F.Staff(p), "Staff only.")
        local rows = F.Query("SELECT * FROM zc_feed_reports WHERE closed=0 ORDER BY id DESC LIMIT 4")
        for _, row in ipairs(rows) do
            local tableName = row.kind == "post" and "zc_feed_posts" or "zc_feed_comments"
            local item = F.Query("SELECT author,name,body" .. (row.kind == "comment" and ",post" or "") .. " FROM " .. tableName .. " WHERE id=" .. tonumber(row.target))[1]
            row.item = item; row.id = tonumber(row.id); row.target = tonumber(row.target)
        end
        return send(p, request, {kind = "reports", reports = rows})
    elseif data.op == "dismiss" then
        F.Require(F.Staff(p) and F.Integer(data.id, 1, 2147483647), "Staff only.")
        F.Query("UPDATE zc_feed_reports SET closed=1 WHERE id=" .. data.id)
    elseif data.op == "photo" then return photo(p, request, data)
    else error("Unknown CityLeak action.", 0) end
    send(p, request, {kind = "saved", op = data.op, id = data.id})
end
net.Receive("GoobOS.Feed.Request", function(bits, p)
    if bits < 40 or bits > 65576 or not IsValid(p) or p:IsBot() then return end
    local request, raw = net.ReadUInt(32), net.ReadString()
    if #raw > 8192 then return end
    if not F.Allowed(p) then F.uploads[p], F.downloads[p] = nil, nil; return send(p, request, {}) end
    local data = util.JSONToTable(raw, false, true)
    local download = F.downloads[p]
    local continuing = istable(data) and data.op == "photo" and download and download.id == data.id and (tonumber(data.offset) or 0) > 0
    if not continuing and not budget(p) then return send(p, request, {error = "Please slow down and retry."}) end
    local ok, err = pcall(function() F.Dispatch(p, request, data) end)
    if not ok then send(p, request, {error = tostring(err):sub(1, 200)}) end
end)
net.Receive("GoobOS.Feed.Upload", function(bits, p)
    if bits < 78 or bits > (F.ChunkSize * 8 + 78) or not IsValid(p) then return end
    local id, offset, size = net.ReadUInt(32), net.ReadUInt(32), net.ReadUInt(14)
    local upload = F.uploads[p]
    if not upload or upload.id ~= id then return end
    if not F.Allowed(p) then F.uploads[p] = nil; return send(p, upload.request, {}) end
    if upload.expires < RealTime() or offset ~= upload.received or size < 1 or size > F.ChunkSize or size ~= math.min(F.ChunkSize, upload.size - offset) or bits ~= 78 + size * 8 then
        F.uploads[p] = nil; return send(p, upload.request, {error = "Photo transfer changed or expired. Retry publishing."})
    end
    local bytes = net.ReadData(size)
    if not bytes or #bytes ~= size then F.uploads[p] = nil; return end
    upload.parts[#upload.parts + 1] = bytes; upload.received = upload.received + size
    upload.expires = RealTime() + 40 -- a paced upload is still a live one
    if upload.received < upload.size then
        return schedule(p, size, function()
            if F.uploads[p] == upload then send(p, upload.request, {kind = "upload", upload = id, offset = upload.received}) end
        end)
    end
    F.uploads[p] = nil
    schedule(p, size, function()
        local ok, result = pcall(F.Publish, p, upload.body, upload.nonce, table.concat(upload.parts), upload.thumb)
        send(p, upload.request, ok and {kind = "published", id = result} or {error = tostring(result):sub(1, 200)})
    end)
end)
hook.Add("PlayerDisconnected", "GoobOS.Feed.Cleanup", function(p) F.uploads[p], F.downloads[p], F.buckets[p], X.players[p] = nil, nil, nil, nil end)
local nextSweep = 0
hook.Add("Think", "GoobOS.Feed.TransferExpiry", function()
    if RealTime() < nextSweep then return end
    nextSweep = RealTime() + 1
    for _, pool in ipairs({F.uploads, F.downloads}) do
        for p, transfer in pairs(pool) do if transfer.expires < RealTime() or not F.Allowed(p) then pool[p] = nil end end
    end
end)

-- B1 round auto-post: one system card per round ("Round N · MODE — winner · MVP name"), behind a
-- convar so it ships inert. Mirrors zc_round_summary.lua's ZB_EndRound/ZB_StartRound/ZB_PreRoundStart
-- guard shape (a named, cancellable timer) so a summary can never land after the next round has begun and
-- a second ZB_EndRound in the same intermission never posts twice -- but stays decoupled from that system's
-- own convar: it reads ZCRoundSummary.Last (mode/winner/MVP by ZP) when that system is ALSO on and had time
-- to populate it (we wait 3s, 0.5s after its own 2.5s), and otherwise falls back to zb.CROUND for the mode
-- and this file's own ZCKillcam_Death kill tally for MVP -- the same public hook zc_round_summary.lua uses,
-- so both may listen. roundNumber is a this-session ordinal (resets on server restart), not a global truth.
local roundPostsOn = CreateConVar("zc_goobos_feed_roundposts", "0", FCVAR_ARCHIVE, "Auto-post a round summary card to CityLeak: 0 off, 1 on")
local roundKillTally, roundNumber, roundAwaiting, roundPosted = {}, 0, false, false
hook.Add("ZCKillcam_Death", "GoobOS.Feed.RoundTally", function(victim, killer)
    if not roundPostsOn:GetBool() then return end
    if killer and killer.id then roundKillTally[killer.id] = (roundKillTally[killer.id] or 0) + 1 end
end)
local function roundMVP()
    local summary = rawget(_G, "ZCRoundSummary")
    local top = summary and summary.Last and summary.Last.top
    if top and top[1] and isstring(top[1].name) and top[1].name ~= "" then return top[1].name end
    local bestName, bestKills = nil, 0
    for kid, kills in pairs(roundKillTally) do
        if kills > bestKills then
            local killerPly = player.GetBySteamID64(kid)
            if IsValid(killerPly) then bestKills, bestName = kills, killerPly:Nick() end
        end
    end
    return bestName
end
local function postRoundEvent()
    roundAwaiting = false
    if not roundPostsOn:GetBool() or roundPosted then return end
    roundPosted = true
    F.Storage()
    local zbT = rawget(_G, "zb")
    local mode = (zbT and isstring(zbT.CROUND) and zbT.CROUND ~= "") and string.upper(zbT.CROUND) or "ROUND"
    local summary = rawget(_G, "ZCRoundSummary")
    local winner = (summary and summary.Last and isstring(summary.Last.winner)) and summary.Last.winner or ""
    local mvp = roundMVP()
    local text = "Round " .. roundNumber .. " · " .. mode
    if winner ~= "" then text = text .. " — " .. winner .. " wins" end
    if mvp then text = text .. " · MVP " .. mvp end
    local ok, err = pcall(F.PublishSystem, "event", text)
    if not ok then ErrorNoHalt("[GoobOS Feed] round post failed: " .. tostring(err) .. "\n") end
end
hook.Add("ZB_EndRound", "GoobOS.Feed.RoundEnd", function()
    if not roundPostsOn:GetBool() or roundAwaiting or roundPosted then return end
    roundAwaiting = true
    roundNumber = roundNumber + 1
    timer.Create("GoobOS.Feed.RoundPost", 3, 1, postRoundEvent)
end)
hook.Add("ZB_StartRound", "GoobOS.Feed.RoundStart", function()
    timer.Remove("GoobOS.Feed.RoundPost")
    roundAwaiting, roundPosted, roundKillTally = false, false, {}
end)
hook.Add("ZB_PreRoundStart", "GoobOS.Feed.RoundPre", function()
    timer.Remove("GoobOS.Feed.RoundPost")
    roundAwaiting = false
end)
