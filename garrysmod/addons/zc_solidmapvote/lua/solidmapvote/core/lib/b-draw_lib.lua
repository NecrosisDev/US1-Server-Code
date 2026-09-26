--[[
    A Simple Garry's mod drawing library
    Copyright (C) 2016 Bull [STEAM_0:0:42437032] [76561198045139792]
    You can use this anywhere for any purpose as long as you acredit the work to the original author with this notice.
    Optionally, if you choose to use this within your own software, it would be much appreciated if you could inform me of it.
    I love to see what people have done with my code! :)
]]--
local fallback = Material("vgui/white")
local entries, total, active = {}, 0, 0
local directory = "solidmapvote/images"
file.CreateDir(directory)
local function validImage(body)
    return type(body) == "string" and #body <= 2097152 and
        (body:sub(1, 8) == "\137PNG\13\10\26\10" or body:sub(1, 3) == "\255\216\255")
end
local function trimCache()
    local files = file.Find(directory .. "/*", "DATA") or {}
    table.sort(files, function(a, b) return file.Time(directory .. "/" .. a, "DATA") < file.Time(directory .. "/" .. b, "DATA") end)
    for i = 1, math.max(0, #files - 63) do file.Delete(directory .. "/" .. files[i]) end
end
function SolidMapVote.ImageMaterial(url)
    if type(url) ~= "string" or #url > 2048 or not url:match("^https://[^/]+/.+") then return fallback end
    local item = entries[url]
    if not item then
        if total >= 64 then return fallback end
        total = total + 1
        item = {attempts=0, retryAt=0, path=directory .. "/" .. util.CRC(url) .. ".png"}
        entries[url] = item
        if file.Exists(item.path, "DATA") and validImage(file.Read(item.path, "DATA")) then
            local mat = Material("data/" .. item.path, "smooth")
            if not mat:IsError() then item.mat = mat end
        end
    end
    if item.mat then return item.mat end
    if item.pending or item.attempts >= 3 or RealTime() < item.retryAt or active >= 4 then return fallback end
    item.pending, item.attempts, active = true, item.attempts + 1, active + 1
    local function done()
        item.pending, active = false, active - 1
        item.retryAt = RealTime() + 30 * item.attempts
    end
    http.Fetch(url, function(body, _, _, code)
        done()
        if code ~= 200 or not validImage(body) then return end
        trimCache()
        file.Write(item.path, body)
        local mat = Material("data/" .. item.path, "smooth")
        if not mat:IsError() then item.mat = mat end
    end, done)
    return fallback
end
function SolidMapVote.DrawWebImage(url, x, y, width, height, color, angle, cornerorigin)
    local mat = SolidMapVote.ImageMaterial(url)
    color = mat == fallback and Color(45, 48, 53) or color or color_white
    surface.SetDrawColor(color.r, color.g, color.b, color.a)
    surface.SetMaterial(mat)
    if not angle then surface.DrawTexturedRect(x, y, width, height)
    elseif cornerorigin then surface.DrawTexturedRectRotated(x + width / 2, y + height / 2, width, height, angle)
    else surface.DrawTexturedRectRotated(x, y, width, height, angle) end
end
