-- Shared, bounded content rules. Neither clients nor photo metadata provide player stats.
ZCGoobFeed = ZCGoobFeed or {}
local F = ZCGoobFeed
F.Version = 1
F.PhotoLimit, F.ChunkSize = 256 * 1024, 12000
F.Reactions = {"Like", "Love", "Laugh", "Wow"}
-- Reserved system identity for auto-posted cards (round events): not a valid SteamID64 (F.Account
-- requires 17 digits), so no real player row can ever match it through F.Account-gated paths
-- (comment/react/report/profile). Only F.PublishSystem (sv_feed_store.lua) may write it as author.
F.SystemAuthor, F.SystemName = "system:city", "City"
-- UI cohesion U2 (2026-09-26): one switch for sharing killcam clips and round moments - CityLeak clip posts, the
-- "!clip" / "!replay" chat links (links.lua) and any player watching a shared clip (zc_killcam/sv_net.lua). Created
-- here because this file runs in both realms first; replicated, so clients hide share actions while it is 0.
CreateConVar("zc_goobos_share", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Sharing killcam clips and round moments (CityLeak clip posts, !clip / !replay chat links): 0 off, 1 on")
function F.ShareOn()
    local cv = GetConVar("zc_goobos_share")
    return cv ~= nil and cv:GetBool()
end
function F.Text(value, limit, empty)
    if not isstring(value) or #value > limit or value:find("[%z\1-\8\11\12\14-\31\127]") then return nil end
    if utf8 and utf8.len and not utf8.len(value) then return nil end
    value = string.Trim(value)
    if not empty and value == "" then return nil end
    return value
end
function F.Integer(value, low, high)
    return isnumber(value) and value == math.floor(value) and value >= low and value <= high
end
function F.Account(value)
    return isstring(value) and #value == 17 and value:match("^%d+$") ~= nil
end
-- Check segment boundaries and decoded dimensions before storing or displaying a JPEG.
-- This is structural validation, not proof that an untrusted image came from Camera.
function F.JPEG(bytes)
    if not isstring(bytes) or #bytes < 16 or #bytes > F.PhotoLimit or bytes:sub(1, 2) ~= "\255\216" or bytes:sub(-2) ~= "\255\217" then return false end
    local i, width, height = 3
    while i < #bytes do
        if bytes:byte(i) ~= 255 then return false end
        while bytes:byte(i) == 255 do i = i + 1 end
        local marker = bytes:byte(i); i = i + 1
        if not marker or marker == 0 or marker == 216 or marker == 217 then return false end
        local a, b = bytes:byte(i, i + 1)
        if not b then return false end
        local length = a * 256 + b
        if length < 2 or i + length - 1 > #bytes then return false end
        if marker == 192 then
            if length < 8 or width then return false end
            local precision, h1, h2, w1, w2, components = bytes:byte(i + 2, i + 7)
            width, height = w1 * 256 + w2, h1 * 256 + h2
            if precision ~= 8 or (components ~= 1 and components ~= 3) or length ~= 8 + components * 3 then return false end
            if width < 16 or height < 16 or width > 1280 or height > 1280 or width * height > 1280 * 720 then return false end
        elseif marker >= 193 and marker <= 207 and marker ~= 196 and marker ~= 200 and marker ~= 204 then return false
        elseif marker == 218 then
            if not width or i + length >= #bytes then return false end
            -- Canvas exports baseline, single-scan JPEG. Reject new frames/dimensions
            -- hidden after the first scan, instead of handing them to the browser.
            local scan = i + length
            while scan < #bytes do
                local at = bytes:find("\255", scan, true)
                if not at then return false end
                local code = bytes:byte(at + 1)
                if code == 217 then return at == #bytes - 1, width, height end
                if code ~= 0 and not (code and code >= 208 and code <= 215) then return false end
                scan = at + 2
            end
            return false
        end
        i = i + length
    end
    return false
end
