if not SERVER then return end
local F = ZCGoobFeed
local function q(value) return sql.SQLStr(tostring(value)) end
F.Quote = q
function F.Query(query)
    local rows = sql.Query(query)
    if rows == false then error("CityLeak storage unavailable", 0) end
    return rows or {}
end
local function scalar(query, key) return tonumber((F.Query(query)[1] or {})[key or "n"]) or 0 end
F.Scalar = scalar
function F.Storage()
    if F.storageReady then return end
    for _, query in ipairs({
        "CREATE TABLE IF NOT EXISTS zc_feed_posts (id INTEGER PRIMARY KEY AUTOINCREMENT, author TEXT NOT NULL, name TEXT NOT NULL, body TEXT NOT NULL, thumb TEXT NOT NULL DEFAULT '', nonce TEXT NOT NULL, created INTEGER NOT NULL, removed INTEGER NOT NULL DEFAULT 0, UNIQUE(author,nonce))",
        "CREATE TABLE IF NOT EXISTS zc_feed_photos (post INTEGER PRIMARY KEY, bytes INTEGER NOT NULL, image TEXT NOT NULL)",
        "CREATE INDEX IF NOT EXISTS zc_feed_photos_size ON zc_feed_photos(bytes)",
        "CREATE TABLE IF NOT EXISTS zc_feed_comments (id INTEGER PRIMARY KEY AUTOINCREMENT, post INTEGER NOT NULL, author TEXT NOT NULL, name TEXT NOT NULL, body TEXT NOT NULL, nonce TEXT NOT NULL, created INTEGER NOT NULL, removed INTEGER NOT NULL DEFAULT 0, UNIQUE(author,nonce))",
        "CREATE TABLE IF NOT EXISTS zc_feed_reactions (post INTEGER NOT NULL, author TEXT NOT NULL, reaction INTEGER NOT NULL, PRIMARY KEY(post,author))",
        "CREATE TABLE IF NOT EXISTS zc_feed_profiles (author TEXT PRIMARY KEY, name TEXT NOT NULL, snapshot TEXT NOT NULL, updated INTEGER NOT NULL)",
        "CREATE TABLE IF NOT EXISTS zc_feed_reports (id INTEGER PRIMARY KEY AUTOINCREMENT, reporter TEXT NOT NULL, kind TEXT NOT NULL, target INTEGER NOT NULL, reason TEXT NOT NULL, created INTEGER NOT NULL, closed INTEGER NOT NULL DEFAULT 0, UNIQUE(reporter,kind,target))",
        "CREATE INDEX IF NOT EXISTS zc_feed_comments_post ON zc_feed_comments(post,id)",
        "CREATE INDEX IF NOT EXISTS zc_feed_posts_author ON zc_feed_posts(author,id)"
    }) do F.Query(query) end
    -- Additive schema migrations, guarded by PRAGMA table_info (KIT_API: no bare ALTER TABLE).
    -- kind/clip: killcam-clip and round-event post cards (B1). parent: one-level threaded replies (B2).
    local function hasColumn(tableName, column)
        for _, row in ipairs(F.Query("PRAGMA table_info(" .. tableName .. ")")) do
            if row.name == column then return true end
        end
        return false
    end
    if not hasColumn("zc_feed_posts", "kind") then F.Query("ALTER TABLE zc_feed_posts ADD COLUMN kind TEXT NOT NULL DEFAULT 'post'") end
    if not hasColumn("zc_feed_posts", "clip") then F.Query("ALTER TABLE zc_feed_posts ADD COLUMN clip TEXT NOT NULL DEFAULT ''") end
    if not hasColumn("zc_feed_comments", "parent") then F.Query("ALTER TABLE zc_feed_comments ADD COLUMN parent INTEGER") end
    F.storageReady = true
end
function F.Transaction(fn)
    F.Storage()
    F.Query("BEGIN IMMEDIATE")
    local ok, result = pcall(fn)
    if ok then ok = sql.Query("COMMIT") ~= false end
    if not ok then sql.Query("ROLLBACK"); error("CityLeak could not save this change. Refresh and retry.", 0) end
    return result
end
function F.Require(ok, message) if not ok then error(message, 0) end end
function F.PruneEvents(need)
    local rows = F.Query("SELECT id FROM zc_feed_posts WHERE kind='event' ORDER BY id ASC LIMIT " .. math.floor(need))
    if #rows == 0 then return 0 end
    local ids = {}
    for _, row in ipairs(rows) do ids[#ids + 1] = tostring(tonumber(row.id)) end
    local idList = table.concat(ids, ",")
    F.Transaction(function()
        F.Query("DELETE FROM zc_feed_comments WHERE post IN (" .. idList .. ")")
        F.Query("DELETE FROM zc_feed_reactions WHERE post IN (" .. idList .. ")")
        F.Query("DELETE FROM zc_feed_photos WHERE post IN (" .. idList .. ")")
        F.Query("DELETE FROM zc_feed_posts WHERE id IN (" .. idList .. ")")
    end)
    return #ids
end
function F.Staff(p)
    if ZCChatModeration and ZCChatModeration.CanDelete then return ZCChatModeration.CanDelete(p) == true end
    return p:IsAdmin()
end
function F.CanWrite(p) return not p:GetNWBool("ulx_muted", false) end
local function identity(p) return p:SteamID64(), F.Text(p:Nick(), 128, false) or "Player" end
function F.Snapshot(p)
    local sid, name = identity(p)
    local stats = {achievements = {}, captured = os.time()}
    local total = p:GetNWInt("ZCPlaytimeTotal", -1)
    if total >= 0 then stats.playtime = total end
    local owner = hg and hg.achievements
    local data = owner and owner.achievements_data
    local records = data and data.player_achievements and data.player_achievements[sid]
    if owner and owner.SqlActive and records then
        stats.completed, stats.available = 0, 0
        for key, def in SortedPairs(data.created_achevements or {}) do
            stats.available = stats.available + 1
            local target = tonumber(def.needed_value) or 0
            if target > 0 and (tonumber(records[key] and records[key].value) or 0) >= target then
                stats.completed = stats.completed + 1
                if #stats.achievements < 24 then stats.achievements[#stats.achievements + 1] = {name = F.Text(def.name or key, 160, false) or "Achievement"} end
            end
        end
    end
    F.Query("INSERT OR REPLACE INTO zc_feed_profiles VALUES (" .. q(sid) .. "," .. q(name) .. "," .. q(util.TableToJSON(stats)) .. "," .. os.time() .. ")")
end
function F.Profile(sid)
    F.Require(F.Account(sid), "Invalid profile.")
    local row = F.Query("SELECT * FROM zc_feed_profiles WHERE author=" .. q(sid))[1]
    local out = row and util.JSONToTable(row.snapshot, false, true) or {achievements = {}}
    out.author, out.name, out.updated = sid, row and row.name or "Player", row and tonumber(row.updated)
    out.posts = scalar("SELECT COUNT(*) n FROM zc_feed_posts WHERE removed=0 AND author=" .. q(sid))
    out.comments = scalar("SELECT COUNT(*) n FROM zc_feed_comments WHERE removed=0 AND author=" .. q(sid))
    out.reactions = scalar("SELECT COUNT(*) n FROM zc_feed_reactions r JOIN zc_feed_posts p ON p.id=r.post WHERE p.removed=0 AND p.author=" .. q(sid))
    return out
end
function F.Post(id)
    F.Require(F.Integer(id, 1, 2147483647), "Invalid post.")
    local row = F.Query("SELECT id,author,name,body,thumb,created,kind,clip FROM zc_feed_posts WHERE removed=0 AND id=" .. id)[1]
    F.Require(row, "This post was removed or is unavailable.")
    row.id, row.created, row.photo = tonumber(row.id), tonumber(row.created), row.thumb ~= ""
    row.kind = (row.kind ~= nil and row.kind ~= "") and row.kind or "post"
    row.clip = row.clip or ""
    return row
end
function F.Decorate(row, sid)
    row.reactions = {0, 0, 0, 0}
    for _, r in ipairs(F.Query("SELECT reaction,COUNT(*) n FROM zc_feed_reactions WHERE post=" .. row.id .. " GROUP BY reaction")) do row.reactions[tonumber(r.reaction)] = tonumber(r.n) end
    row.mine = scalar("SELECT reaction n FROM zc_feed_reactions WHERE post=" .. row.id .. " AND author=" .. q(sid))
    row.comments = scalar("SELECT COUNT(*) n FROM zc_feed_comments WHERE removed=0 AND post=" .. row.id)
    return row
end
function F.Feed(sid, before, author, tab)
    F.Require(F.Integer(before or 0, 0, 2147483647), "Invalid page.")
    F.Require(not author or F.Account(author), "Invalid profile.")
    local kindWhere = tab == "events" and " AND kind='event'" or " AND kind IN ('post','clip')"
    local where = "removed=0" .. kindWhere .. ((before or 0) > 0 and " AND id<" .. before or "") .. (author and " AND author=" .. q(author) or "")
    local rows = F.Query("SELECT id FROM zc_feed_posts WHERE " .. where .. " ORDER BY id DESC LIMIT 5")
    local out = {posts = {}, more = #rows > 4}
    for i = 1, math.min(4, #rows) do out.posts[i] = F.Decorate(F.Post(tonumber(rows[i].id)), sid) end
    return out
end
function F.Thread(sid, id, before)
    local post = F.Decorate(F.Post(id), sid)
    F.Require(F.Integer(before or 0, 0, 2147483647), "Invalid comment page.")
    local rows = F.Query("SELECT id,author,name,body,created,parent FROM zc_feed_comments WHERE removed=0 AND post=" .. id .. ((before or 0) > 0 and " AND id<" .. before or "") .. " ORDER BY id DESC LIMIT 9")
    local more = #rows > 8
    if more then table.remove(rows) end
    for _, row in ipairs(rows) do row.id, row.created, row.parent = tonumber(row.id), tonumber(row.created), tonumber(row.parent) end
    return {post = post, comments = rows, more = more}
end
local function nonce(value) return isstring(value) and #value == 32 and value:match("^%x+$") end
function F.Publish(p, body, token, jpeg, thumb, clip)
    local sid, name = identity(p)
    body = F.Text(body, 1200, jpeg ~= nil or clip ~= nil) -- a clip-only post, like a photo-only post, needs no caption
    F.Require(body and nonce(token), "Write up to 1200 bytes of text or attach a photo.")
    F.Require(not jpeg or F.JPEG(jpeg), "Invalid or oversized JPEG.")
    if jpeg then
        local valid, w, h = F.JPEG(thumb)
        F.Require(valid and #thumb <= 1800 and w <= 160 and h <= 90, "Invalid photo preview.")
    end
    -- B1 killcam-clip reference: read-side only today (no client compose path exists yet; see REPLY).
    F.Require(not clip or (not jpeg and isstring(clip) and #clip <= 24 and clip:match("^%d+_%d+$") ~= nil), "Invalid clip reference.")
    local old = F.Query("SELECT id FROM zc_feed_posts WHERE author=" .. q(sid) .. " AND nonce=" .. q(token))[1]
    if old then return tonumber(old.id) end
    F.Require(F.CanWrite(p), "You are muted and cannot publish to CityLeak.")
    if scalar("SELECT COUNT(*) n FROM zc_feed_posts") >= 4800 then F.PruneEvents(500) end
    F.Require(scalar("SELECT COUNT(*) n FROM zc_feed_posts") < 5000, "CityLeak archive is full. Contact staff.")
    F.Require(scalar("SELECT COALESCE(SUM(bytes),0) n FROM zc_feed_photos") + (jpeg and math.ceil(#jpeg / 3) * 4 or 0) <= 512 * 1024 * 1024, "Photo storage is full. You can still post text.")
    F.Require(scalar("SELECT COUNT(*) n FROM zc_feed_posts WHERE author=" .. q(sid) .. " AND created>" .. (os.time() - 60)) < 2, "Please wait a minute before posting again.")
    return F.Transaction(function()
        F.Query("INSERT INTO zc_feed_posts(author,name,body,thumb,nonce,created,kind,clip) VALUES (" .. q(sid) .. "," .. q(name) .. "," .. q(body) .. "," .. q(jpeg and util.Base64Encode(thumb) or "") .. "," .. q(token) .. "," .. os.time() .. "," .. q(clip and "clip" or "post") .. "," .. q(clip or "") .. ")")
        local id = scalar("SELECT last_insert_rowid() n")
        if jpeg then
            local encoded = util.Base64Encode(jpeg)
            F.Query("INSERT INTO zc_feed_photos VALUES (" .. id .. "," .. #encoded .. "," .. q(encoded) .. ")")
        end
        F.Snapshot(p)
        return id
    end)
end
function F.Comment(p, id, body, token, parent)
    F.Post(id)
    local sid, name = identity(p)
    body = F.Text(body, 500, false)
    F.Require(body and nonce(token), "Comments need 1–500 bytes of text.")
    -- B2: threaded replies, ONE level -- a reply may only target a top-level comment (parent IS NULL),
    -- never another reply, so the thread never grows a second level.
    if parent ~= nil then
        F.Require(F.Integer(parent, 1, 2147483647), "Invalid reply target.")
        local target = F.Query("SELECT id FROM zc_feed_comments WHERE removed=0 AND id=" .. parent .. " AND post=" .. id .. " AND parent IS NULL")[1]
        F.Require(target, "That comment is no longer available to reply to.")
    end
    local old = F.Query("SELECT id FROM zc_feed_comments WHERE author=" .. q(sid) .. " AND nonce=" .. q(token))[1]
    if old then return tonumber(old.id) end
    F.Require(F.CanWrite(p), "You are muted and cannot comment.")
    F.Require(scalar("SELECT COUNT(*) n FROM zc_feed_comments WHERE post=" .. id) < 100, "This conversation has reached 100 comments.")
    F.Require(scalar("SELECT COUNT(*) n FROM zc_feed_comments WHERE author=" .. q(sid) .. " AND created>" .. (os.time() - 60)) < 8, "Please slow down before commenting again.")
    return F.Transaction(function()
        F.Query("INSERT INTO zc_feed_comments(post,author,name,body,nonce,created,parent) VALUES (" .. id .. "," .. q(sid) .. "," .. q(name) .. "," .. q(body) .. "," .. q(token) .. "," .. os.time() .. "," .. (parent and tostring(parent) or "NULL") .. ")")
        local result = scalar("SELECT last_insert_rowid() n"); F.Snapshot(p); return result
    end)
end

-- Round-event / system card (B1), inserted directly: bypasses F.CanWrite/identity because it is not
-- a real player action. kind is "event" today; "clip" is reserved for a future system highlight.
local systemNonceSerial = 0
function F.PublishSystem(kind, body, clip)
    body = F.Text(body, 1200, false)
    F.Require(body and (kind == "event" or kind == "clip"), "Invalid system post.")
    if scalar("SELECT COUNT(*) n FROM zc_feed_posts") >= 4800 then F.PruneEvents(500) end
    F.Require(scalar("SELECT COUNT(*) n FROM zc_feed_posts") < 5000, "CityLeak archive is full.")
    systemNonceSerial = systemNonceSerial + 1
    local token = "sys:" .. kind .. ":" .. os.time() .. ":" .. systemNonceSerial
    return F.Transaction(function()
        F.Query("INSERT INTO zc_feed_posts(author,name,body,thumb,nonce,created,kind,clip) VALUES (" .. q(F.SystemAuthor) .. "," .. q(F.SystemName) .. "," .. q(body) .. ",''," .. q(token) .. "," .. os.time() .. "," .. q(kind) .. "," .. q(clip or "") .. ")")
        return scalar("SELECT last_insert_rowid() n")
    end)
end
function F.React(p, id, reaction)
    F.Post(id); F.Require(F.Integer(reaction, 0, 4), "Invalid reaction.")
    F.Require(F.CanWrite(p), "You are muted and cannot react.")
    local sid = p:SteamID64()
    F.Transaction(function()
        F.Query("DELETE FROM zc_feed_reactions WHERE post=" .. id .. " AND author=" .. q(sid))
        if reaction > 0 then F.Query("INSERT INTO zc_feed_reactions VALUES (" .. id .. "," .. q(sid) .. "," .. reaction .. ")") end
    end)
end
function F.Remove(p, kind, id)
    F.Require((kind == "post" or kind == "comment") and F.Integer(id, 1, 2147483647), "Invalid item.")
    local name = kind == "post" and "zc_feed_posts" or "zc_feed_comments"
    local row = F.Query("SELECT author FROM " .. name .. " WHERE id=" .. id)[1]
    F.Require(row and (row.author == p:SteamID64() or F.Staff(p)), "Only the author or staff can remove this item.")
    F.Transaction(function()
        F.Query("UPDATE " .. name .. " SET removed=1,body=''" .. (kind == "post" and ",thumb=''" or "") .. " WHERE id=" .. id)
        if kind == "post" then
            F.Query("DELETE FROM zc_feed_photos WHERE post=" .. id)
            F.Query("UPDATE zc_feed_comments SET removed=1,body='' WHERE post=" .. id)
            F.Query("DELETE FROM zc_feed_reactions WHERE post=" .. id)
        end
        F.Query("UPDATE zc_feed_reports SET closed=1 WHERE kind=" .. q(kind) .. " AND target=" .. id)
    end)
end
function F.Report(p, kind, id, reason)
    F.Require((kind == "post" or kind == "comment") and F.Integer(id, 1, 2147483647), "Invalid report.")
    reason = F.Text(reason, 300, false); F.Require(reason, "Describe the problem in up to 300 bytes.")
    local tableName = kind == "post" and "zc_feed_posts" or "zc_feed_comments"
    F.Require(F.Query("SELECT id FROM " .. tableName .. " WHERE removed=0 AND id=" .. id)[1], "Item no longer available.")
    local sid = p:SteamID64()
    F.Require(scalar("SELECT COUNT(*) n FROM zc_feed_reports WHERE reporter=" .. q(sid) .. " AND created>" .. (os.time() - 86400)) < 10, "Daily report limit reached.")
    F.Require(scalar("SELECT COUNT(*) n FROM zc_feed_reports") < 10000, "Report archive full. Contact staff.")
    F.Query("INSERT OR IGNORE INTO zc_feed_reports(reporter,kind,target,reason,created) VALUES (" .. q(sid) .. "," .. q(kind) .. "," .. id .. "," .. q(reason) .. "," .. os.time() .. ")")
end
