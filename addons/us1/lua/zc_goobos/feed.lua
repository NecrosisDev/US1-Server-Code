if not CLIENT then return end
local A, F = ZCGoobApps, ZCGoobFeed
local C = {serial = math.random(1, 1000000000), draft = {body = ""}, cache = {}, order = {}, downloads = {}}
F.Client = C
-- 2026-09-26 background transfers (owner: "let uploads/downloads occur in the background, with a budget that won't
-- affect the server"). C.pending is the one CityLeak action in flight; C.upload and C.download are photo transfers
-- that run beside it. The server paces every chunk under a server-wide budget (sv_feed.lua scheduler), so the
-- client sends the next chunk as soon as the server asks for it. Busy() no longer counts transfers.
function C.Busy() return C.pending ~= nil or C.preparing ~= nil end
function C.Uploading() return C.upload ~= nil end
function C.Available() return ZCSpecDM == nil and util.NetworkStringToID("GoobOS.Feed.Request") ~= 0 end
function C.Nonce() return util.SHA256(tostring(SysTime()) .. ":" .. tostring(math.random()) .. ":" .. tostring(C.serial)):sub(1, 32) end
function C.Note(text) C.message = text; C.changed = true end
local function nextSerial() C.serial = C.serial % 4294967294 + 1; return C.serial end
local function sendRequest(id, json)
    net.Start("GoobOS.Feed.Request"); net.WriteUInt(id, 32); net.WriteString(json); net.SendToServer()
end
-- fail(message), optional (U2 share sheet): called instead of done when the server refuses or the request times out.
function C.Request(data, done, fail)
    if C.Busy() then return false end
    if not C.Available() then C.Note("CityLeak is waiting for its server or isolation integration."); return false end
    local json = util.TableToJSON(data)
    if not json or #json > 8192 then C.Note("This request is too large."); return false end
    local id = nextSerial()
    C.pending = {id = id, sent = RealTime(), data = data, done = done, fail = fail}
    sendRequest(id, json)
    return true
end
local function dropTransfers() C.upload, C.download, C.downloads = nil, nil, {} end
local function blockedReset()
    C.cache, C.order, C.page, C.profile, C.thread, C.reports = {}, {}, nil, nil, nil, nil
    dropTransfers()
    C.blocked = true
    if IsValid(C.photoSheet) then C.photoSheet:Remove() end
    if IsValid(C.preparing) then C.preparing:Remove() end
    if C.Purge then C.Purge() end
end
local function finish(result)
    local pending = C.pending
    C.pending = nil
    if result.blocked then blockedReset() end
    if result.error then
        C.Note(result.error)
        if pending and pending.fail then pending.fail(result.error) end
        return
    end
    C.blocked = false
    if result.kind == "published" then
        if pending and C.draft.nonce == pending.data.nonce then C.draft = {body = ""} end
        C.Note("Posted to CityLeak.")
    end
    if pending and pending.done then pending.done(result) end
end
local function finishUpload(result)
    local up = C.upload
    C.upload = nil
    if not up then return end
    if result.blocked then blockedReset() end
    if result.error then C.Note(result.error); return end
    C.blocked = false
    if result.kind == "published" then
        if C.draft.nonce == up.nonce then C.draft = {body = ""} end
        C.Note("Posted to CityLeak.")
        -- Jump to the new post only if the player is still on the composer; otherwise the note is enough.
        if up.done and C.view == "compose" then up.done(result) end
    end
end
local function failDownload(message)
    C.download = nil
    if message then C.Note(message) end
end
net.Receive("GoobOS.Feed.State", function(bits)
    if bits > 224040 then return end
    local id, raw = net.ReadUInt(32), net.ReadString()
    if #raw > 28000 or not C.Available() then return end
    local up, down, pending = C.upload, C.download, C.pending
    local forUpload, forDownload = up and up.request == id, down and down.request == id
    if not forUpload and not forDownload and not (pending and pending.id == id) then return end
    local data = util.JSONToTable(raw, false, true)
    if not istable(data) then return end
    if forUpload then
        if data.kind == "upload" then
            if data.upload ~= up.upload or not F.Integer(data.offset, 0, #up.jpeg - 1) or data.offset % F.ChunkSize ~= 0 then
                return finishUpload({error = "Photo upload lost its place. Retry publishing."})
            end
            up.offset, up.sent, up.ready = data.offset, RealTime(), true
            C.Note("Uploading photo · " .. math.floor(100 * data.offset / #up.jpeg) .. "%")
            return
        end
        return finishUpload(data)
    end
    if forDownload then
        if data.blocked then return blockedReset() end
        return failDownload(data.error or "Photo unavailable.")
    end
    if data.kind == "upload" then
        local jpeg = pending.jpeg
        if not jpeg or not F.Integer(data.offset, 0, #jpeg - 1) or data.offset % F.ChunkSize ~= 0 or not F.Integer(data.upload, 1, 4294967295) then
            return finish({error = "Photo upload lost its place. Retry publishing."})
        end
        -- Hand the upload to the background: the composer and the rest of CityLeak stay usable.
        C.upload = {request = id, upload = data.upload, offset = data.offset, jpeg = jpeg, nonce = pending.data.nonce,
            done = pending.done, sent = RealTime(), ready = true}
        C.pending = nil
        C.Note("Uploading photo · 0%")
        return
    end
    finish(data)
end)
function C.Publish(done)
    if C.Busy() then return false end
    if C.upload then C.Note("A photo is still uploading; it will post on its own."); return false end
    local draft = C.draft
    local body = F.Text(draft.body or "", 1200, draft.jpeg ~= nil)
    if not body then C.Note("Add a photo or write up to 1200 bytes of text."); return false end
    draft.nonce = draft.nonce or C.Nonce()
    if not C.Request({op = "publish", body = body, nonce = draft.nonce, bytes = draft.jpeg and #draft.jpeg or 0,
        thumb = draft.thumb and util.Base64Encode(draft.thumb, true)}, done) then return false end
    C.pending.jpeg = draft.jpeg
    return true
end
-- Photos download one at a time in the background, newest request first; done(bytes) runs when one arrives.
-- Closing a photo does not cancel it: an active download finishes into the cache, a queued one is dropped.
function C.Photo(id, done)
    if C.cache[id] then done(C.cache[id]); return true end
    if C.download and C.download.id == id then C.download.done = done; return true end
    for i, queued in ipairs(C.downloads) do if queued.id == id then table.remove(C.downloads, i); break end end
    table.insert(C.downloads, 1, {id = id, done = done})
    while #C.downloads > 6 do table.remove(C.downloads) end
    return true
end
function C.ForgetPhoto(id)
    for i, queued in ipairs(C.downloads) do if queued.id == id then table.remove(C.downloads, i); return end end
    if C.download and C.download.id == id then C.download.done = nil end
end
local function requestChunk(down)
    down.request, down.sent = nextSerial(), RealTime()
    sendRequest(down.request, util.TableToJSON({op = "photo", id = down.id, offset = #down.bytes}))
end
net.Receive("GoobOS.Feed.Photo", function(bits)
    if bits < 116 or bits > 116 + F.ChunkSize * 8 then return end
    local request, id, total, offset, size = net.ReadUInt(32), net.ReadUInt(32), net.ReadUInt(19), net.ReadUInt(19), net.ReadUInt(14)
    local down = C.download
    if not C.Available() or not down or down.request ~= request or down.id ~= id then return end
    if total < 16 or total > F.PhotoLimit or offset ~= #down.bytes or size ~= math.min(F.ChunkSize, total - offset) or size < 1 or bits ~= 116 + size * 8 then
        return failDownload("Photo transfer failed. Open it again.")
    end
    local bytes = net.ReadData(size)
    if not bytes or #bytes ~= size then return failDownload("Photo transfer interrupted.") end
    down.bytes = down.bytes .. bytes
    if #down.bytes < total then return requestChunk(down) end
    C.download = nil
    if not F.JPEG(down.bytes) then return C.Note("Photo could not be decoded.") end
    if not C.cache[id] then C.order[#C.order + 1] = id end
    C.cache[id] = down.bytes
    while #C.order > 8 do C.cache[table.remove(C.order, 1)] = nil end
    if down.done then down.done(down.bytes) end
end)
hook.Add("Think", "GoobOS.Feed.Transport", function()
    if ZCSpecDM ~= nil then
        if not C.blocked or C.pending or C.upload or C.download or C.downloads[1] or C.page or C.thread or C.profile or C.reports or next(C.cache) or IsValid(C.preparing) then
            C.pending = nil
            C.page, C.thread, C.profile, C.reports, C.cache, C.order = nil, nil, nil, nil, {}, {}
            dropTransfers()
            C.blocked = true; C.Note("CityLeak is paused until world isolation is integrated.")
            if IsValid(C.preparing) then C.preparing:Remove() end
            if C.Purge then C.Purge() end
        end
        if IsValid(C.photoSheet) then C.photoSheet:Remove() end
        return
    end
    local now = RealTime()
    if C.pending and now - C.pending.sent > 12 then finish({error = "Connection timed out. Your draft is kept; retrying will not duplicate a post."}) end
    -- Transfers wait on the server's budget, so they get a longer leash than a normal action.
    local up = C.upload
    if up then
        if now - up.sent > 25 then
            finishUpload({error = "Photo upload timed out. Your draft is kept; retrying will not duplicate a post."})
        elseif up.ready then
            up.ready, up.sent = false, now
            local bytes = up.jpeg:sub(up.offset + 1, up.offset + F.ChunkSize)
            net.Start("GoobOS.Feed.Upload"); net.WriteUInt(up.upload, 32); net.WriteUInt(up.offset, 32)
            net.WriteUInt(#bytes, 14); net.WriteData(bytes, #bytes); net.SendToServer()
        end
    end
    if C.download and now - C.download.sent > 25 then failDownload("Photo download timed out. Open it again.") end
    if not C.download and C.downloads[1] and C.Available() and not C.blocked then
        local queued = table.remove(C.downloads, 1)
        if C.cache[queued.id] then
            queued.done(C.cache[queued.id])
        else
            C.download = {id = queued.id, bytes = "", done = queued.done}
            requestChunk(C.download)
        end
    end
end)
-- One offline canvas resizes a selected local image. No remote page, URL, or arbitrary Lua.
function C.PreparePhoto(parent, name, done)
    if C.Busy() then return false end
    local camera = A.Camera
    if not camera or not camera.ValidName(name) then return false end
    local path = camera.Directory .. "/" .. name
    local size = file.Size(path, "DATA") or -1
    if size < 16 or size > 12 * 1024 * 1024 then C.Note("This local photo is unavailable."); return false end
    local bytes = file.Read(path, "DATA")
    if not bytes or #bytes ~= size then return false end
    local browser = vgui.Create("DHTML", parent)
    browser:Dock(FILL); browser:SetAllowLua(false)
    C.preparing = browser
    -- Root cause of "stuck on Preparing photo": the old timeout ran off browser.Think, which stops
    -- pumping if this panel is hidden (app switch) without being removed, so Busy() never cleared.
    -- timer.Create fires independent of panel visibility, so preparation is never silently stuck.
    local function release(message)
        timer.Remove("GoobOS.Feed.PreparePhoto")
        if C.preparing == browser then C.preparing = nil end
        if IsValid(browser) then browser:Remove() end
        if message then C.Note(message) end
    end
    browser.OnRemove = function()
        if C.preparing == browser then C.preparing = nil end
        timer.Remove("GoobOS.Feed.PreparePhoto")
    end
    timer.Create("GoobOS.Feed.PreparePhoto", 12, 1, function()
        if C.preparing == browser then release("Photo preparation timed out. Reopen the gallery and retry.") end
    end)
    browser.OnDocumentReady = function(s)
        if s.goobReady then return end
        s.goobReady = true
        s:AddFunction("goobphoto", "ready", function(encoded, thumb)
            if C.preparing ~= s or not isstring(encoded) or not isstring(thumb) or #encoded > 350000 or #thumb > 2400 then return release("Photo preparation failed.") end
            local jpeg, small = util.Base64Decode(encoded), util.Base64Decode(thumb)
            local valid, w, h = F.JPEG(small)
            if not F.JPEG(jpeg) or not valid or #small > 1800 or w > 160 or h > 90 then return release("Photo preparation failed.") end
            C.draft.jpeg, C.draft.thumb, C.draft.photoName, C.draft.nonce = jpeg, small, name, nil
            release(); done()
        end)
        s:AddFunction("goobphoto", "failed", function() release("The saved image could not be opened.") end)
        s:QueueJavascript([[var img=new Image();img.onload=function(){try{
            var c=document.createElement('canvas'),scale=Math.min(1,1280/img.width,720/img.height);
            c.width=Math.max(16,Math.round(img.width*scale));c.height=Math.max(16,Math.round(img.height*scale));
            var x=c.getContext('2d');x.drawImage(img,0,0,c.width,c.height);
            var full=c.toDataURL('image/jpeg',0.8).split(',')[1];
            if(full.length>349528)full=c.toDataURL('image/jpeg',0.55).split(',')[1];
            if(full.length>349528){c.width=Math.max(16,Math.round(c.width*0.75));c.height=Math.max(16,Math.round(c.height*0.75));c.getContext('2d').drawImage(img,0,0,c.width,c.height);full=c.toDataURL('image/jpeg',0.55).split(',')[1];}
            var t=document.createElement('canvas');t.width=96;t.height=54;t.getContext('2d').drawImage(c,0,0,96,54);
            var small=t.toDataURL('image/jpeg',0.45).split(',')[1];
            if(small.length>2400)small=t.toDataURL('image/jpeg',0.2).split(',')[1];
            goobphoto.ready(full,small);
        }catch(e){goobphoto.failed();}};img.onerror=function(){goobphoto.failed();};img.src='data:image/jpeg;base64,]] .. util.Base64Encode(bytes, true) .. "';")
    end
    browser:SetHTML('<!doctype html><meta charset="utf-8"><meta http-equiv="Content-Security-Policy" content="default-src \'none\'; img-src data:; script-src \'unsafe-inline\'; style-src \'unsafe-inline\'"><body style="background:#171e2b;color:#e3edfa;font:16px sans-serif;padding:20px">Preparing your photo…</body>')
    return true
end
