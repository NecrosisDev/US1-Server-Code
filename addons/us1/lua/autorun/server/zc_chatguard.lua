-- ZC ChatGuard (server only) 20260925.cg3
--
-- Unattended chat moderation: an operator wordlist, flood / repeat limits, an inline-media rate limit, an escalating
-- automatic timed mute, and a chat log staff can read after the fact.
--
-- SEAMS (all verified against US1 source, 2026-09-21):
--   * Send path owner is ZChat (addons/zcity/lua/homigrad/zchat/sh_chat.lua:215-269). Its net receive calls
--     hook.Run("PlayerSay", ply, text); its own PlayerSay handler at :227 does the fan-out. We hook PlayerSay at
--     HOOK_HIGH so we judge the RAW text, before HG_PlayerSay modifiers (furrify at sv_comunication.lua:133,
--     brain-damage garble at :127) rewrite it. Returning "" from PlayerSay stops the hook chain, so ZChat's handler
--     never runs and the message is dropped. Console "say" funnels through the same hook, so it is covered too.
--   * Mutes are owned by ULX tmute (addons/persistent_gags_and_mutes/lua/ulx/modules/sh/tmute.lua:14, PData "tmuted"
--     in MINUTES, decremented by its own 60 s timer) and enforced by ulx_zchat_bridge v1.2.0 at the hook.Call
--     dispatcher. We write that same PData key and nothing else: "!unmute"/"ulx untmute" and "ulx printtmutes" keep
--     working, and a player already muted never reaches us because the bridge returns before any PlayerSay hook.
--     tmute's timer only walks ONLINE players, so a mute counts down connected minutes, not wall-clock time. The
--     ladder is sized for that: "ulx tmute" itself caps an admin at 60.
--   * ULib_saycmd (ulib/server/concommand.lua:78) is also HOOK_HIGH, and order inside one bucket is pairs() order,
--     so we may see a chat command before or after ULib does. "@" (ulx asay, staff-only audience) is therefore
--     passed through by us explicitly rather than by luck, and staff are never blocked: both exist so that
--     reporting or actioning abuse can quote it.
--   * Inline GIFs (zc_chat_media, staged) are ordinary chat messages whose whole body is a direct .gif URL on an
--     allowlisted host. They must survive the filter, so they get their own rule instead of the text rules.
--
-- MODE: zc_chatguard 0 = off, 1 = shadow (judge and log, change nothing), 2 = enforce. Ships as 1 on purpose: the
-- wordlist has to be tuned against a real evening of this server's chat before it is allowed to block anything.
if not SERVER then return end

ZCChatGuard = ZCChatGuard or {}
local G = ZCChatGuard
G.Version = "20260925.cg3"

local DIR = "zc_chatguard"

local mode      = CreateConVar("zc_chatguard", "1", FCVAR_ARCHIVE, "ChatGuard: 0 off, 1 shadow (log only), 2 enforce", 0, 2)
local notify    = CreateConVar("zc_chatguard_notify", "1", FCVAR_ARCHIVE, "Tell online staff about blocks and automatic mutes", 0, 1)
local logDays   = CreateConVar("zc_chatguard_log_days", "14", FCVAR_ARCHIVE, "Days of chat log kept on disk", 1, 90)
local ladderCv  = CreateConVar("zc_chatguard_ladder", "0,10,30,60", FCVAR_ARCHIVE, "Mute minutes per strike, comma separated. 0 = warn only")
local mediaGap  = CreateConVar("zc_chatguard_media_gap", "15", FCVAR_ARCHIVE, "Seconds between inline media posts from one player", 0, 300)
local linkMode  = CreateConVar("zc_chatguard_links", "0", FCVAR_ARCHIVE, "Links: 0 allow (log only), 1 allowlisted hosts only, 2 block all", 0, 2)

-- PROVISIONAL(2026-09-21, starting numbers chosen without live data; retune from the shadow log, ratify-by: 2026-10-05)
local BUCKET, REFILL          = 5, 2          -- five messages in hand, one more every two seconds
local REPEAT_N, REPEAT_WINDOW = 3, 30         -- the same line three times inside thirty seconds
local SOFT_N, SOFT_WINDOW     = 8, 60         -- eight blocked lines in a minute earns a strike
local STRIKE_DECAY            = 2 * 3600      -- one strike forgiven per two clean hours
local MEDIA_STRIKE_BLOCK      = 2             -- at this many strikes a player loses inline media
local MAXLEN                  = 240           -- longer than ZChat's own cap; bounds both the scan and the log line

G.Stats = G.Stats or {seen = 0, blocked = 0, word = 0, flood = 0, repeated = 0, link = 0, media = 0, mutes = 0, maxUs = 0}
G.State = G.State or {}   -- sid64 -> {s = strikes, t = os.time of last strike}   (persisted)
G.Shadow = G.Shadow or {} -- same shape as State, used while in shadow mode       (memory only, never saved)
G.Live  = G.Live  or {}   -- sid64 -> rate-limit bookkeeping                      (memory only)
G.Words = G.Words or {word = {}, sub = {}, never = {}, n = 0}

local function stat(k, v) G.Stats[k] = (G.Stats[k] or 0) + (v or 1) end

----------------------------------------------------------------- text shapes
-- Three shapes of the same message, each used by a different rule:
--   plain  lowercase, every non-alphanumeric turned into a space. Word rules read its tokens.
--   soft   a token with common character swaps undone and non-letters dropped. Whole-word rules compare this.
--   tight  soft with runs of one letter collapsed ("aaa" -> "a"). Substring rules search this.
local SWAP = {["0"]="o",["1"]="i",["3"]="e",["4"]="a",["5"]="s",["7"]="t",["8"]="b",["@"]="a",["$"]="s",["!"]="i",["|"]="i",["+"]="t"}

-- Lookalike letters from other scripts, full-width forms and zero-width characters, folded back to ASCII before
-- anything else reads the text. Without this one Cyrillic "a" splits a word in two, because every byte of it is
-- "not a letter" to a Lua pattern, and no wordlist entry can be written to catch that.
local FOLD = {}
do
    local pairsOf = {
        a = "\208\176 \208\144 \206\177 \206\145", b = "\208\178 \208\146 \206\146", c = "\209\129 \208\161",
        e = "\208\181 \208\149 \209\145 \208\129 \206\181 \206\149", h = "\208\189 \208\157 \206\151",
        i = "\209\150 \208\134 \206\185 \206\153", k = "\208\186 \208\154 \206\186 \206\154",
        m = "\208\188 \208\156 \206\156", n = "\206\157", o = "\208\190 \208\158 \206\191 \206\159",
        p = "\209\128 \208\160 \207\129 \206\161", r = "\208\179 \208\147", s = "\209\149 \208\133",
        t = "\209\130 \208\162 \207\132 \206\164", u = "\207\133", v = "\206\189",
        x = "\209\133 \208\165 \207\135 \206\167", y = "\209\131 \208\163",
    }
    for ascii, list in pairs(pairsOf) do
        for seq in string.gmatch(list, "%S+") do FOLD[seq] = ascii end
    end
    for i = 0, 25 do
        FOLD[string.char(239, 189, 129 + i)] = string.char(97 + i) -- full-width a-z
        FOLD[string.char(239, 188, 161 + i)] = string.char(97 + i) -- full-width A-Z
    end
    -- zero-width space / non-joiner / joiner, word joiner, BOM, soft hyphen: removed outright
    for _, seq in ipairs({"\226\128\139", "\226\128\140", "\226\128\141", "\226\129\160", "\239\187\191", "\194\173"}) do
        FOLD[seq] = ""
    end
end

function G.Fold(text)
    return (string.gsub(text or "", "[\194-\244][\128-\191]*", FOLD))
end

function G.Plain(text)
    local s = string.lower(text or "")
    s = string.gsub(s, "[^%a%d]", " ")
    s = string.gsub(s, "%s+", " ")
    return (string.gsub(s, "^%s*(.-)%s*$", "%1"))
end

function G.Soft(token)
    local s = string.lower(token or "")
    s = string.gsub(s, ".", function(c) return SWAP[c] or c end)
    return (string.gsub(s, "[^%a]", ""))
end

function G.Tight(token)
    -- A Lua quantifier cannot follow a back-reference, so "(%a)%1+" silently matches nothing. Collapsing pairs
    -- repeatedly is the working form: "baaad" -> "baad" -> "bad".
    local s, n = G.Soft(token), 1
    while n > 0 do s, n = string.gsub(s, "(%a)%1", "%1") end
    return s
end

function G.Tokens(plain)
    local out = {}
    for w in string.gmatch(plain, "%S+") do out[#out + 1] = w end
    return out
end

----------------------------------------------------------------- wordlist
-- data/zc_chatguard/words.txt, one entry per line:
--     word     whole word (a trailing s / es still matches)
--     *word    matches inside a word, for padded and glued spellings
--     -word    exemption: drops that entry and stops the word being flagged at all
-- The file is the operator's; this source ships none. Reload with zc_chatguard_reload, no push needed.
local TEMPLATE = [[
# ZC ChatGuard wordlist. Lines starting with # are ignored.
#
#   word      whole word; a trailing s or es still matches
#   *word     matches inside a longer word (catches padding and glued spellings)
#   -word     exemption; removes an entry above and stops that word ever being flagged
#
# Matching ignores case, punctuation and the usual character swaps (0 for o, 3 for e, @ for a and so on).
# Substring entries also see the message with its spaces removed, so a term typed one letter at a time is caught.
# That last pass is the one that produces false positives: add a -exemption and it stops.
#
# Start in shadow mode (zc_chatguard 1), read data/zc_chatguard/chat-<date>.txt for a day, then set
# zc_chatguard 2 once the verdicts look right. zc_chatguard_test "<phrase>" judges a line without sending it.
]]

function G.LoadWords()
    local words = {word = {}, sub = {}, never = {}, n = 0}
    local raw = file.Read(DIR .. "/words.txt", "DATA")
    if not raw then
        file.CreateDir(DIR)
        file.Write(DIR .. "/words.txt", TEMPLATE)
        raw = TEMPLATE
    end
    for line in string.gmatch(raw .. "\n", "([^\r\n]*)\r?\n") do
        local entry = string.match(line, "^%s*(.-)%s*$")
        if entry ~= "" and string.sub(entry, 1, 1) ~= "#" then
            local head = string.sub(entry, 1, 1)
            if head == "-" then
                local key = G.Soft(string.sub(entry, 2))
                if key ~= "" then
                    words.never[key] = true
                    words.word[key] = nil
                    words.sub[G.Tight(key)] = nil
                end
            elseif head == "*" then
                local key = G.Tight(string.sub(entry, 2))
                if key ~= "" and not words.never[G.Soft(string.sub(entry, 2))] then
                    words.sub[key] = true
                    words.n = words.n + 1
                end
            else
                local key = G.Soft(entry)
                if key ~= "" and not words.never[key] then
                    words.word[key] = true
                    words.n = words.n + 1
                end
            end
        end
    end
    -- Counted at the end so an exemption that removed an earlier entry is reflected.
    words.n = 0
    for _ in pairs(words.word) do words.n = words.n + 1 end
    for _ in pairs(words.sub) do words.n = words.n + 1 end
    G.Words = words
    return words.n
end

-- Returns the entry that matched, or nil.
function G.ScanWords(plain)
    local W = G.Words
    if W.n == 0 then return nil end
    local tokens = G.Tokens(plain)
    for i = 1, #tokens do
        local soft = G.Soft(tokens[i])
        if soft ~= "" and not W.never[soft] then
            if W.word[soft] then return soft end
            local stem = string.match(soft, "^(.-)es$") or string.match(soft, "^(.-)s$")
            if stem and stem ~= "" and W.word[stem] and not W.never[stem] then return stem end
            local tight = G.Tight(soft)
            for entry in pairs(W.sub) do
                if string.find(tight, entry, 1, true) then return entry end
            end
        end
    end

    -- A term padded out one letter at a time ("x y z", "x.y.z"). Only runs of SINGLE-LETTER tokens are glued back
    -- together: joining everything would make an entry like *ass match "cl ass ic", and no exemption can be resolved
    -- once the word boundaries are gone. Two-letter tokens are excluded on purpose, because ordinary speech strings
    -- plenty of them together ("ok so we go to my car"). A run of single letters has no innocent reading.
    local run = {}
    local function testRun()
        local joined = table.concat(run)
        run = {}
        if #joined <= 2 then return nil end
        for entry in pairs(W.sub) do
            if #entry > 2 and string.find(joined, entry, 1, true) then return entry end
        end
        for entry in pairs(W.word) do
            if #entry > 2 and string.find(joined, G.Tight(entry), 1, true) then return entry end
        end
        return nil
    end
    for i = 1, #tokens do
        local soft = G.Soft(tokens[i])
        if #soft == 1 then
            run[#run + 1] = G.Tight(soft)
        else
            local found = testRun()
            if found then return found end
        end
    end
    return testRun()
end

----------------------------------------------------------------- inline media and links
local MEDIA_HOST = {["media.tenor.com"] = true, ["media.giphy.com"] = true, ["i.giphy.com"] = true}
for i = 0, 4 do MEDIA_HOST["media" .. i .. ".giphy.com"] = true end

-- A whole message that is one direct .gif URL on an allowlisted host: this is what zc_chat_media renders inline.
function G.IsMedia(text)
    local url = string.match(text or "", "^%s*(%S+)%s*$")
    if not url then return false end
    local host, path = string.match(url, "^https://([%w%.%-]+)/(.*)$")
    if not host or not MEDIA_HOST[string.lower(host)] then return false end
    local body = string.match(path, "^([^?]*)")
    return string.sub(string.lower(body or ""), -4) == ".gif"
end

-- A scheme, or a host-looking token: two or more characters, a dot, then a two-to-six letter ending. A hand-listed
-- set of endings missed evil.pw and evil.click entirely. This is only consulted when links are restricted, and a
-- false positive there costs a message, so the general shape is the safer choice.
function G.HasLink(text)
    local s = string.lower(text or "")
    if string.find(s, "https?://", 1, false) then return true end
    if string.find(s, "%f[%w][%w%-][%w%-]+%.[%w%-]+/") then return true end
    for host, tld in string.gmatch(s, "%f[%w]([%w%-][%w%-]+)%.(%a%a+)%f[%W]") do
        if #tld <= 6 and #host >= 2 then return true end
    end
    return false
end

function G.LinkAllowed(text)
    if G.IsMedia(text) then return true end
    local s, seen = string.lower(text or ""), false
    for host in string.gmatch(s, "https?://([%w%.%-]+)") do
        if not MEDIA_HOST[host] then return false end
        seen = true
    end
    if not seen then return false end -- a bare domain carries no scheme, so it can never be on the allowlist
    -- every full URL is allowed; whatever is left must not smuggle a bare domain in beside them
    return not G.HasLink((string.gsub(s, "https?://%S+", " ")))
end

----------------------------------------------------------------- hidden links (owner 2026-09-25)
-- A link the chat will not embed is removed before anyone receives it, unless it points at YouTube, Giphy or Steam
-- or staff posted it. The one link zc_chat_media embeds (the first direct GIF/image or YouTube video outside a
-- ||spoiler||) stays. A message that was nothing but hidden links is not sent at all. Both send paths call
-- G.FilterLinks: ZChat's PlayerSay handler (zchat/sh_chat.lua, before it keeps the copy spectators get) and group
-- chat (sv_zc_chat_groups.lua G.Send). Own switch, independent of zc_chatguard's mode: 0 off, 1 tester only (only
-- the tester's own messages, his staff exemption set aside so the owner can watch it work), 2 everyone but staff.
local hideMode   = CreateConVar("zc_chatguard_hidelinks", "1", FCVAR_ARCHIVE, "Hide links that do not embed: 0 off, 1 the tester's own messages only, 2 everyone but staff", 0, 2)
local hideTester = CreateConVar("zc_chatguard_hidelinks_tester", "76561198011536179", FCVAR_ARCHIVE, "SteamID64 whose messages are filtered while zc_chatguard_hidelinks is 1")

local LINK_ALLOW = {"youtube.com", "youtu.be", "giphy.com", "gph.is", "steamcommunity.com", "steampowered.com", "s.team"}
-- Endings that are file types in chat far more often than sites: "autoexec.cfg" is not a link.
local NOT_TLD = {txt = true, cfg = true, lua = true, exe = true, dll = true, bat = true, png = true, jpg = true, jpeg = true,
    gif = true, wav = true, mp3 = true, mp4 = true, json = true, vmt = true, vtf = true, mdl = true, bsp = true, ini = true,
    log = true, dat = true}
-- A bare "name.ending" (no scheme, no "www.", no path) is a link only with one of these endings: common site and
-- spam endings, leaving out the ones that are also everyday words, so "ok.so", "yes.no" and "for.me" stay text.
local BARE_TLD = {}
for tld in string.gmatch("com net org gg io co uk de ru fr nl pl br au ca eu xyz ly cc gl app dev info biz link site online " ..
    "store shop club live fun top icu pw click pro vip win bid stream gift ink zone space website tech tv gs sh gy ws su ua kz " ..
    "cn jp kr", "%a+") do BARE_TLD[tld] = true end
-- Dots, slashes and a colon that only look like the real ones, folded before a token is read as a link (on top of
-- G.Fold's letters and zero-width characters): "discord。gg" is a link.
local LINK_FOLD = {["\227\128\130"] = ".", ["\239\188\142"] = ".", ["\239\189\161"] = ".", ["\226\128\164"] = ".",
    ["\239\188\143"] = "/", ["\226\129\132"] = "/", ["\226\136\149"] = "/", ["\239\188\154"] = ":"}

local function linkFold(token)
    return (string.gsub(G.Fold(token), "[\226-\239][\128-\191][\128-\191]", LINK_FOLD))
end

-- The link inside one whitespace-separated token: host (lower case), scheme, and what follows the host - or nil.
-- A scheme anywhere in the token counts ("look:https://..."). Otherwise the first host-shaped run does - a label of
-- two or more characters, a dot, an ending - if it has a path, starts with "www." or has a BARE_TLD ending. Anything
-- up to an ellipsis is not part of a host ("wait...what" is two words; "hmm...discord.gg/x" still holds a link).
-- ".gg/abc" (split off "discord ") counts too.
function G.TokenLink(token)
    local t = string.lower(linkFold(token))
    local scheme, host, rest = string.match(t, "(%a[%w+.%-]*)://([^/?#%s]*)(.*)$")
    if scheme then
        return (string.gsub(string.gsub(host, "^.*@", ""), ":%d*$", "")), scheme, rest
    end
    -- A dotted-quad IPv4 address (a server ad), with or without a port or path. Not "v1.2.3.4" or "1.2.3.4.5".
    for a, b, c, d, e in string.gmatch(t, "%f[%w%.](%d+)%.(%d+)%.(%d+)%.(%d+)()%f[^%w%.]") do
        if tonumber(a) <= 255 and tonumber(b) <= 255 and tonumber(c) <= 255 and tonumber(d) <= 255 then
            return a .. "." .. b .. "." .. c .. "." .. d, nil, string.sub(t, e)
        end
    end
    local frag = string.match(t, "^%.(%a%a+)/")
    if frag and not NOT_TLD[frag] then return "." .. frag, nil, (string.match(t, "^%.%a+(.*)$")) end
    for run, e in string.gmatch(t, "([%w%-%.]+)()") do
        local h = string.gsub(string.gsub(string.gsub(run, "^.*%.%.+", ""), "^[%.%-]+", ""), "%.+$", "")
        local tld = string.match(h, "%.(%a+)$")
        if tld and #tld >= 2 and string.find(h, "[%w%-][%w%-]+%.")
            and (string.sub(t, e, e) == "/" or string.sub(h, 1, 4) == "www." or BARE_TLD[tld]) then
            return h, nil, string.sub(t, e)
        end
    end
end

local function allowedHost(host)
    for _, d in ipairs(LINK_ALLOW) do
        if host == d or string.sub(host, -(#d + 1)) == "." .. d then return true end
    end
    return false
end

-- An allowlisted site that forwards elsewhere (youtube.com/redirect?q=..., steamcommunity.com/linkfilter/?url=...,
-- steam://openurl/...) carries the other address after its host; such a link is judged as that other address.
local function forwards(rest)
    if string.find(rest, "://", 1, true) or string.find(rest, "%3a%2f%2f", 1, true) then return true end
    for value in string.gmatch(rest, "[?&][%w_%-]+=([^&#]+)") do
        local h = string.match(value, "^([%w%-%.]+)")
        local tld = h and string.match(h, "%.(%a+)$")
        if tld and #tld >= 2 and not NOT_TLD[tld] and string.find(h, "[%w%-][%w%-]+%.") then return true end
    end
    return false
end

-- zc_chat_media's M.GIFURL and M.VideoID (lua/zc_chat_media/client.lua), ported as they are - the same case
-- sensitivity included - because only a link those accept is embedded, and only an embedded link may pass
-- without being on the allowlist.
local EMBED_EXT = {gif = true, png = true, jpg = true, jpeg = true, webp = true}
local VIDEO_HOST = {["www.youtube.com"] = true, ["youtube.com"] = true, ["m.youtube.com"] = true, ["music.youtube.com"] = true}

function G.EmbedURL(url)
    if not isstring(url) or #url > 2048 then return false end
    local host, rest = string.match(url, "^https://([%w%.%-]+)(/[^%s]+)$")
    if host then
        local giphy = host == "media.giphy.com" or host == "i.giphy.com" or string.match(host, "^media[0-4]%.giphy%.com$")
        if host == "media.tenor.com" or giphy or host == "i.imgur.com" then
            local path, query = string.match(rest, "^([^?]+)%?(.*)$")
            if not path then path = rest end
            local ext = string.match(path, "^/[%w_/%-%.]+%.(%w+)$")
            if ext and not string.find(path, "..", 1, true) and EMBED_EXT[string.lower(ext)]
                and not (query and (not giphy or query == "" or string.find(query, "[^%w_%%&=%.~+%-]"))) then
                return true
            end
        end
    end
    host, rest = string.match(url, "^https://([%w%.%-]+)(/[^%s]*)$")
    if not host then return false end
    host = string.lower(host)
    local path, query = string.match(rest, "^([^?]*)%?(.*)$")
    if not path then path = rest end
    local id
    if host == "youtu.be" then
        id = string.match(path, "^/([%w_%-]+)$")
    elseif VIDEO_HOST[host] then
        id = string.match(path, "^/embed/([%w_%-]+)$") or string.match(path, "^/shorts/([%w_%-]+)$") or string.match(path, "^/live/([%w_%-]+)$")
        if not id and path == "/watch" then
            for pair in string.gmatch(query or "", "[^&]+") do
                local k, v = string.match(pair, "^([%w_%-]+)=([%w_%-]+)$")
                if k == "v" then id = v; break end
            end
        end
    end
    return id ~= nil and #id == 11
end

-- The link zc_chat_media will embed: the first https URL (trailing ),]!;. trimmed) that is embeddable and not
-- between the first and last "||" (M.MaskSpoilers never embeds a spoiled link).
function G.EmbeddedURL(text)
    local first, last = string.find(text, "||", 1, true), nil
    local scan = first
    while scan do
        local at = string.find(text, "||", scan, true)
        if not at then break end
        last, scan = at, at + 2
    end
    for at, url in string.gmatch(text, "()(https://[^%s<>\"']+)") do
        url = string.gsub(url, "[%)%],!;%.]+$", "")
        local spoiled = first and last > first and at >= first and at <= last + 1
        if not spoiled and G.EmbedURL(url) then return url end
    end
end

-- "@name" naming a player on the server is a mention, dots and all ("@john.smith"); any other "@..." is read like
-- any other token, so "@evil.com" is a link.
local function isMention(token)
    if string.sub(token, 1, 1) ~= "@" then return false end
    local name = string.lower(string.sub(token, 2))
    local bare = string.gsub(name, "%p+$", "")
    for _, p in player.Iterator() do
        local nick = string.lower(p:Nick() or "")
        if nick ~= "" and (nick == name or nick == bare) then return true end
    end
    return false
end

-- The text with every link that may not be shown taken out (whole whitespace-separated tokens), and how many were
-- taken. A lookalike or zero-width character inside an allowlisted address makes it a different address, so it is
-- hidden.
function G.HideLinks(text)
    local embedded = G.EmbeddedURL(text)
    local out, hidden, last = {}, 0, 1
    for s, token, e in string.gmatch(text, "()(%S+)()") do
        local host, scheme, rest = G.TokenLink(token)
        rest = rest or ""
        if host and isMention(token) then host = nil end
        local keep = not host
            or (embedded ~= nil and string.find(token, embedded, 1, true) ~= nil)
            or ((scheme == "steam" or allowedHost(host)) and not forwards(rest) and linkFold(token) == token)
        if keep then
            out[#out + 1] = string.sub(text, last, e - 1)
        else
            hidden = hidden + 1
            out[#out + 1] = string.sub(text, last, s - 1)
        end
        last = e
    end
    out[#out + 1] = string.sub(text, last)
    local shown = table.concat(out)
    if hidden > 0 then
        -- a spoiler that only held the hidden link would otherwise be sent as an empty "|| ||"
        shown = string.gsub(string.gsub(shown, "||%s*||", ""), "  +", " ")
        shown = string.Trim(shown)
    end
    return shown, hidden
end

----------------------------------------------------------------- strikes
function G.Ladder()
    local out = {}
    for n in string.gmatch(ladderCv:GetString(), "[^,%s]+") do out[#out + 1] = math.max(tonumber(n) or 0, 0) end
    if #out == 0 then out = {0} end
    return out
end

-- Strikes are stamped with WALL CLOCK time, never CurTime. CurTime restarts at zero on every map change, which would
-- make "now - row.t" negative and stop a strike ever decaying. Only the in-memory rate limiter uses CurTime.
--
-- Shadow mode keeps its own table. Strikes earned against a wordlist nobody has tuned yet must not be waiting for
-- players on the day enforcement is switched on.
function G.Store() return mode:GetInt() == 2 and G.State or G.Shadow end

function G.Strikes(sid, when, peek, store)
    store = store or G.Store()
    local row = store[sid]
    if not row then return 0 end
    when = when or os.time()
    local decay = math.max(math.floor((when - (row.t or when)) / STRIKE_DECAY), 0)
    local left = math.max((row.s or 0) - decay, 0)
    if peek then return left end -- a staff test reads the count without advancing anyone's decay clock
    if decay > 0 then
        row.s, row.t = left, when
        if left == 0 then store[sid] = nil return 0 end
    end
    return row.s or 0
end

function G.AddStrike(sid, when, store)
    when = when or os.time()
    store = store or G.Store()
    -- Decay first: G.Strikes may drop the row entirely, so the row is fetched only after it has settled.
    local carried = G.Strikes(sid, when, false, store)
    local row = store[sid]
    if not row then row = {} store[sid] = row end
    row.s, row.t = carried + 1, when
    local ladder = G.Ladder()
    return row.s, ladder[math.min(row.s, #ladder)] or 0
end

function G.SaveState()
    -- Records fully decayed are dropped here, otherwise state.json would only ever grow: a player who never comes
    -- back is never judged again, so nothing else would ever clear their row.
    local now, keep = os.time(), {}
    for sid, row in pairs(G.State) do
        local left = (row.s or 0) - math.floor((now - (row.t or now)) / STRIKE_DECAY)
        if left > 0 then keep[sid] = row end
    end
    G.State = keep
    file.CreateDir(DIR)
    file.Write(DIR .. "/state.json", util.TableToJSON(keep))
end

function G.LoadState()
    local raw = file.Read(DIR .. "/state.json", "DATA")
    G.State = (raw and util.JSONToTable(raw)) or {}
    return G.State
end

----------------------------------------------------------------- the judgement
-- Returns verdict, detail. verdict is "ok" or one of the rule names. dry = do not touch any counter or timer.
function G.Judge(ply, text, now, dry)
    local sid = ply.__sid or ply:SteamID64() or "unknown"
    local live = G.Live[sid]
    if not live then
        -- media stays nil until the first post: a zero would block the first GIF of a map, when CurTime is still near zero
        live = {tokens = BUCKET, seen = now, said = {}, soft = {}}
        if not dry then G.Live[sid] = live end -- a staff test must never create or disturb rate state
    end

    if G.IsMedia(text) then
        if G.Strikes(sid, nil, dry) >= MEDIA_STRIKE_BLOCK then return "media", "posting media while on strikes" end
        if live.media and now - live.media < mediaGap:GetInt() then return "media", "media posted too quickly" end
        if not dry then live.media = now end
        return "ok", "media"
    end

    if #text > MAXLEN then text = string.sub(text, 1, MAXLEN) end -- caps the cost of the wordlist pass
    local plain = G.Plain(G.Fold(text))
    local hit = G.ScanWords(plain)
    if hit then return "word", hit end

    if G.HasLink(text) then
        local policy = linkMode:GetInt()
        if policy == 2 then return "link", "links are not allowed" end
        if policy == 1 and not G.LinkAllowed(text) then return "link", "that host is not allowed" end
    end

    -- Token bucket. Refilled from elapsed time so it costs nothing between messages.
    local tokens = math.min((live.tokens or BUCKET) + (now - (live.seen or now)) / REFILL, BUCKET)
    -- Banked before the check: dropping the refill on a refused message meant anyone who kept typing never recovered.
    if not dry then live.seen, live.tokens = now, tokens end
    if tokens < 1 then return "flood", "sending too fast" end
    if not dry then live.tokens = tokens - 1 end

    if plain ~= "" then
        local said = live.said
        local row = said[plain]
        if row and now - row.t <= REPEAT_WINDOW then
            if row.n + 1 >= REPEAT_N then return "repeated", "same message repeated" end
            if not dry then row.n, row.t = row.n + 1, now end
        elseif not dry then
            said[plain] = {n = 1, t = now}
            if table.Count(said) > 24 then live.said = {[plain] = said[plain]} end
        end
    end

    return "ok", nil
end

----------------------------------------------------------------- log
-- Buffered: chat is bursty and a disk write per message puts file IO on the send path. Flushed every few seconds and
-- on map shutdown, so at worst a handful of lines are lost to a crash.
G.LogBuf = G.LogBuf or {}

-- Control characters and the column separator are stripped, otherwise a client sending a literal newline could
-- write extra rows into the staff log and attribute them to someone else.
local function safe(text)
    return (string.gsub(string.sub(text, 1, MAXLEN), "[%c|]", " "))
end

local function logLine(line)
    G.LogBuf[#G.LogBuf + 1] = line
    if #G.LogBuf >= 64 then G.FlushLog() end
end

function G.FlushLog()
    if #G.LogBuf == 0 then return end
    local body = table.concat(G.LogBuf, "\n") .. "\n"
    G.LogBuf = {}
    file.CreateDir(DIR)
    file.Append(DIR .. "/chat-" .. os.date("%Y-%m-%d") .. ".txt", body)
end

timer.Create("ZCChatGuard.Flush", 5, 0, function() G.FlushLog() end)
hook.Add("ShutDown", "ZCChatGuard", function() G.FlushLog() G.SaveState() end)

function G.PruneLogs()
    local days = logDays:GetInt()
    local cutoff = os.time() - days * 86400
    local files = file.Find(DIR .. "/chat-*.txt", "DATA")
    for _, name in ipairs(files or {}) do
        local y, m, d = string.match(name, "^chat%-(%d+)%-(%d+)%-(%d+)%.txt$")
        if y then
            local stamp = os.time({year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12})
            if stamp and stamp < cutoff then file.Delete(DIR .. "/" .. name) end
        end
    end
end

local function isStaff(p)
    return p:IsAdmin() or (p.CheckGroup and p:CheckGroup("operator") == true) or false
end

local function tellStaff(msg)
    if not notify:GetBool() then return end
    for _, a in player.Iterator() do
        if isStaff(a) then a:ChatPrint("[ChatGuard] " .. msg) end
    end
end

-- "@..." is ulx asay: only staff read it. A player reporting abuse has to be able to quote it, so it is logged and
-- left alone - but only while the player really has asay, otherwise the line would fall through to public chat.
local function isAsay(ply, text)
    if string.sub(text, 1, 1) ~= "@" then return false end
    local ucl = ULib and ULib.ucl
    return (ucl and ucl.query and ucl.query(ply, "ulx asay")) and true or false
end

local function hideFor(ply)
    local m = hideMode:GetInt()
    if m == 1 then return (ply:SteamID64() or "") == string.Trim(hideTester:GetString()) end
    return m == 2 and not isStaff(ply)
end

-- The send paths' filter. Returns the text to send ("" = nothing left to send). Staff can read what was hidden in
-- the ChatGuard log; the sender is told privately, at most once per 20 s (a group send that loses everything gets
-- the group's own status line instead).
function G.FilterLinks(ply, text, where)
    if hideMode:GetInt() == 0 or not IsValid(ply) or not isstring(text) or not hideFor(ply) then return text end
    local shown, hidden = G.HideLinks(text)
    if hidden == 0 then return text end
    where = where or ""
    logLine(string.format("%s | %s | %s | hidelink%s %d | %s", os.date("%H:%M:%S"), ply:SteamID64() or "unknown",
        safe(ply:Nick()), where, hidden, safe(text)))
    stat("hidden", hidden)
    if not (where ~= "" and shown == "") and (ply.ZCChatGuardLinkNote or 0) <= CurTime() then
        ply.ZCChatGuardLinkNote = CurTime() + 20
        ply:ChatPrint("Your link was hidden: chat only shows links to YouTube, Giphy and Steam.")
    end
    return shown
end

----------------------------------------------------------------- enforcement
function G.Mute(ply, minutes, why)
    ply:SetPData("tmuted", tostring(math.floor(minutes)))
    stat("mutes")
    local pretty = minutes >= 1440 and (math.floor(minutes / 1440) .. "d") or (minutes >= 60 and (math.floor(minutes / 60) .. "h") or (minutes .. "m"))
    ply:ChatPrint("You have been muted for " .. pretty .. ": " .. why .. ". Staff can review this.")
    tellStaff(ply:Nick() .. " muted " .. pretty .. " (" .. why .. ")")
end

local TOLD = {word = "that word is not allowed here",
              flood = "you are sending messages too fast",
              repeated = "stop repeating yourself",
              link = "links are restricted here",
              media = "wait a moment before posting more media"}

hook.Add("PlayerSay", "ZCChatGuard", function(ply, text)
    if mode:GetInt() == 0 then return end
    if not IsValid(ply) or not ply:IsPlayer() or not isstring(text) then return end

    local t0 = SysTime()
    local now = CurTime()
    local sid = ply:SteamID64() or "unknown"
    local enforcing = mode:GetInt() == 2

    if isAsay(ply, text) then
        stat("seen")
        logLine(string.format("%s | %s | %s | asay | %s", os.date("%H:%M:%S"), sid, safe(ply:Nick()), safe(text)))
        return
    end

    local ok, verdict, detail = pcall(G.Judge, ply, text, now, false)
    if not ok then
        if not G.errOnce then G.errOnce = true print("[ChatGuard] judge failed: " .. tostring(verdict)) end
        return
    end

    stat("seen")
    local us = (SysTime() - t0) * 1e6
    if us > G.Stats.maxUs then G.Stats.maxUs = us end

    if verdict == "ok" then
        if detail == "media" then stat("media") end
        logLine(string.format("%s | %s | %s | ok | %s", os.date("%H:%M:%S"), sid, safe(ply:Nick()), safe(text)))
        return
    end

    -- Staff are judged and logged, never blocked or struck: "!ban x said <word>" has to go through.
    if isStaff(ply) then
        logLine(string.format("%s | %s | %s | staff:%s%s | %s", os.date("%H:%M:%S"), sid, safe(ply:Nick()),
            string.upper(verdict), detail and (" " .. detail) or "", safe(text)))
        return
    end

    stat(verdict)
    stat("blocked")

    -- A wordlist hit strikes immediately. The rate rules only strike once a player has been blocked repeatedly,
    -- so a burst of enthusiasm costs nothing and a sustained flood does.
    local strikes, minutes
    if verdict == "word" then
        strikes, minutes = G.AddStrike(sid)
    else
        local live = G.Live[sid]
        local soft = live and live.soft or {}
        soft[#soft + 1] = now
        while soft[1] and now - soft[1] > SOFT_WINDOW do table.remove(soft, 1) end
        if live then live.soft = soft end
        if #soft >= SOFT_N then
            strikes, minutes = G.AddStrike(sid)
            if live then live.soft = {} end
        end
    end

    local outcome = ""
    if strikes then
        outcome = " [strike " .. strikes .. ((minutes or 0) > 0 and (", mute " .. minutes .. "m]") or ", warn]")
    end
    logLine(string.format("%s | %s | %s | %s%s%s%s | %s", os.date("%H:%M:%S"), sid, safe(ply:Nick()),
        enforcing and "" or "shadow:", string.upper(verdict), detail and (" " .. detail) or "", outcome,
        safe(text)))

    hook.Run("ZC_ChatGuardVerdict", ply, text, verdict, detail, enforcing)

    if not enforcing then return end

    if strikes then
        if minutes and minutes > 0 then
            G.Mute(ply, minutes, TOLD[verdict] or verdict)
        else
            ply:ChatPrint("Warning: " .. (TOLD[verdict] or verdict) .. ". This is on your record.")
            tellStaff(ply:Nick() .. " warned (" .. verdict .. (detail and " " .. detail or "") .. ")")
        end
        G.SaveState()
    else
        ply:ChatPrint("Message not sent: " .. (TOLD[verdict] or verdict) .. ".")
    end
    return ""
end, HOOK_HIGH or -1)

hook.Add("PlayerDisconnected", "ZCChatGuard", function(ply)
    local sid = ply:SteamID64()
    if sid then G.Live[sid] = nil end
end)

----------------------------------------------------------------- console
local function staffOnly(ply) return not IsValid(ply) or ply:IsAdmin() end

concommand.Add("zc_chatguard_reload", function(ply)
    if not staffOnly(ply) then return end
    local n = G.LoadWords()
    local msg = "[ChatGuard] wordlist reloaded: " .. n .. " entries"
    if IsValid(ply) then ply:ChatPrint(msg) else print(msg) end
end, nil, "Admin: reload the ChatGuard wordlist.")

concommand.Add("zc_chatguard_stats", function(ply)
    if not staffOnly(ply) then return end
    local s = G.Stats
    local lines = {
        "[ChatGuard] " .. G.Version .. "  mode=" .. mode:GetInt() .. " (" .. (({[0]="off", [1]="shadow", [2]="enforce"})[mode:GetInt()]) .. ")  words=" .. G.Words.n,
        string.format("seen %d  blocked %d  (word %d, flood %d, repeat %d, link %d, media %d)  links hidden %d (hidelinks=%d)", s.seen, s.blocked, s.word, s.flood, s.repeated, s.link, s.media, s.hidden or 0, hideMode:GetInt()),
        string.format("mutes %d  worst judge %.0f us", s.mutes, s.maxUs),
    }
    local strikes = {}
    for sid, row in pairs(G.State) do strikes[#strikes + 1] = sid .. "=" .. (row.s or 0) end
    lines[#lines + 1] = "strikes: " .. (#strikes > 0 and table.concat(strikes, " ", 1, math.min(#strikes, 12)) or "none")
    for _, l in ipairs(lines) do if IsValid(ply) then ply:ChatPrint(l) else print(l) end end
end, nil, "Admin: print ChatGuard counters.")

concommand.Add("zc_chatguard_test", function(ply, _, _, raw)
    if not staffOnly(ply) then return end
    local text = string.match(raw or "", '^%s*"?(.-)"?%s*$')
    local subject = IsValid(ply) and ply or {__sid = "console", SteamID64 = function() return "console" end}
    local verdict, detail = G.Judge(subject, text, CurTime(), true)
    local shown, hidden = G.HideLinks(text)
    local msg = "[ChatGuard] " .. verdict .. (detail and (" (" .. detail .. ")") or "") .. "  <- " .. text
        .. (hidden > 0 and ("  | links: " .. hidden .. " hidden -> " .. (shown ~= "" and shown or "(not sent)")) or "  | links: none hidden")
    if IsValid(ply) then ply:ChatPrint(msg) else print(msg) end
end, nil, "Admin: show what ChatGuard would do with a message: zc_chatguard_test \"text\".")

concommand.Add("zc_chatguard_forgive", function(ply, _, args)
    if not staffOnly(ply) then return end
    local sid = args[1]
    if not sid then return end
    G.State[sid] = nil
    G.SaveState()
    local msg = "[ChatGuard] strikes cleared for " .. sid
    if IsValid(ply) then ply:ChatPrint(msg) else print(msg) end
end, nil, "Admin: clear ChatGuard strikes: zc_chatguard_forgive <steamid64>.")

----------------------------------------------------------------- boot
file.CreateDir(DIR)
G.LoadState()
G.LoadWords()
G.PruneLogs()
print("[ChatGuard] " .. G.Version .. " loaded: mode " .. mode:GetInt() .. ", " .. G.Words.n .. " wordlist entries")
