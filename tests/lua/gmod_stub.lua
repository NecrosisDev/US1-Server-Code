-- Minimal Garry's Mod client stubs for headless LuaJIT tests of UI code (painters, layout maths, data shaping).
-- Text metrics are deterministic: width = characters * size * 0.5, height = size. Nothing is drawn; draw calls are
-- recorded in STUB.calls so tests can assert on what a painter did.
STUB = {calls = {}, convars = {}, fonts = {}, hooks = {}, nets = {}}
CLIENT, SERVER = true, false
local function record(name, ...) STUB.calls[#STUB.calls + 1] = {name, ...} end
function Color(r, g, b, a) return {r = r or 255, g = g or 255, b = b or 255, a = a or 255} end
function isstring(v) return type(v) == "string" end
function isnumber(v) return type(v) == "number" end
function istable(v) return type(v) == "table" end
function isfunction(v) return type(v) == "function" end
function IsValid(v) return type(v) == "table" and v.valid ~= false and (not v.IsValid or v:IsValid()) end
function tobool(v) return v and v ~= 0 and v ~= "0" and v ~= "false" end
function Lerp(t, a, b) return a + (b - a) * t end
math.Clamp = function(v, lo, hi) return math.min(math.max(v, lo), hi) end
math.Round = function(v, d) local m = 10 ^ (d or 0) return math.floor(v * m + 0.5) / m end
string.FormattedTime = function(s, fmt)
    local m, sec = math.floor(s / 60), math.floor(s % 60)
    return string.format(fmt, m, sec)
end
utf8 = utf8 or {}
utf8.len = utf8.len or function(s) return #s end
utf8.offset = utf8.offset or function(s, n) if n > #s + 1 then return nil end return n end
TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP, TEXT_ALIGN_BOTTOM = 0, 1, 2, 3, 4
local currentFont = "default"
surface = {
    CreateFont = function(name, spec) STUB.fonts[name] = spec end,
    SetFont = function(name) currentFont = name end,
    GetTextSize = function(text)
        local spec = STUB.fonts[currentFont] or {size = 10}
        return math.floor(#tostring(text) * spec.size * 0.5), spec.size
    end,
    SetDrawColor = function(...) record("SetDrawColor", ...) end,
    DrawRect = function(...) record("DrawRect", ...) end,
    DrawOutlinedRect = function(...) record("DrawOutlinedRect", ...) end,
    SetTexture = function() end, DrawTexturedRect = function() end,
    GetTextureID = function() return 1 end,
}
draw = {
    SimpleText = function(text, font, x, y, color, ax, ay)
        record("SimpleText", text, font, x, y, color, ax, ay)
        surface.SetFont(font)
        return surface.GetTextSize(text)
    end,
    RoundedBox = function(...) record("RoundedBox", ...) end,
}
function GetConVar(name) return STUB.convars[name] end
function ConVarExists(name) return STUB.convars[name] ~= nil end
function CreateClientConVar(name, default)
    local cv = {value = tostring(default)}
    function cv:GetString() return self.value end
    function cv:GetInt() return math.floor(tonumber(self.value) or 0) end
    function cv:GetFloat() return tonumber(self.value) or 0 end
    function cv:GetBool() return (tonumber(self.value) or 0) ~= 0 end
    STUB.convars[name] = cv
    return cv
end
cvars = {AddChangeCallback = function() end}
hook = {Add = function(ev, id, fn) STUB.hooks[ev .. "/" .. id] = fn end, Remove = function() end, Run = function() end}
timer = {Simple = function() end, Create = function() end, Remove = function() end, Exists = function() return false end}
net = {Receive = function(name, fn) STUB.nets[name] = fn end}
local now = 0
function RealTime() return now end
function CurTime() return now end
function FrameTime() return 1 / 60 end
function STUB.SetTime(t) now = t end
function ScrW() return 1920 end
function ScrH() return 1080 end
function LocalPlayer() return {valid = false} end
concommand = {Add = function() end, GetTable = function() return {} end}
function RunConsoleCommand(...) record("RunConsoleCommand", ...) end
