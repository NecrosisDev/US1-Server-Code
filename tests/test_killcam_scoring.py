"""Offline behaviour tests for the killcam's scoring: intent, karma ledger, highlight score and points.

Runs the real Lua files under LuaJIT (the runtime Garry's Mod uses) through lupa, against a small stub of the
GMod API. Skips cleanly when lupa is not installed (pip install lupa).
"""
import pathlib
import unittest

try:
    import lupa.luajit21 as lupa_rt
except ImportError:  # pragma: no cover - depends on the machine
    try:
        import lupa as lupa_rt
    except ImportError:
        lupa_rt = None

ROOT = pathlib.Path(__file__).resolve().parents[1]
LUA = ROOT / 'garrysmod' / 'lua'

STUB = r'''
SERVER = true
FCVAR_ARCHIVE, HUD_PRINTCONSOLE = 128, 2
local now = 100
function CurTime() return now end
function SysTime() return now end
function SetNow(t) now = t end
local convars = {}
function CreateConVar(name, default)
    local cv = {v = tostring(default)}
    function cv:GetInt() return math.floor(tonumber(self.v) or 0) end
    function cv:GetFloat() return tonumber(self.v) or 0 end
    function cv:GetBool() return (tonumber(self.v) or 0) ~= 0 end
    convars[name] = cv
    return cv
end
function SetConVar(name, v) convars[name].v = tostring(v) end
local hooks = {}
hook = {}
function hook.Add(ev, id, fn) hooks[ev] = hooks[ev] or {} hooks[ev][id] = fn end
function hook.Run(ev, ...)
    for _, fn in pairs(hooks[ev] or {}) do local r = fn(...) if r ~= nil then return r end end
end
concommand = {Add = function(name, fn) _G["CMD_" .. name] = fn end}
timer = {Create = function() end, Simple = function() end, Remove = function() end}
weapons = {GetStored = function() return {Category = "Melee"} end}
util = {AddNetworkString = function() end, TableToJSON = function() return "{}" end, JSONToTable = function() return {} end}
net = {Receive = function() end}
file = {Read = function() end, Write = function() end, CreateDir = function() end, Exists = function() return false end, Find = function() return {} end}
game = {GetMap = function() return "test_map" end}
string.Trim = string.Trim or function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
table.remove = table.remove
math.Round = function(x) return math.floor(x + 0.5) end
function ErrorNoHalt(m) print(m) end
function isstring(x) return type(x) == "string" end
function istable(x) return type(x) == "table" end
function isnumber(x) return type(x) == "number" end
function IsValid(x) return type(x) == "table" and x.valid ~= false end

LOG = {}
local players = {}
local function mkPlayer(uid, sid, traitor, bot)
    local p = {valid = true, uid = uid, sid = sid, isTraitor = traitor, bot = bot, alive = true, chat = {}}
    function p:UserID() return self.uid end
    function p:SteamID64() return self.sid end
    function p:IsBot() return self.bot == true end
    function p:IsPlayer() return true end
    function p:Alive() return self.alive end
    function p:Nick() return "P" .. self.uid end
    function p:EntIndex() return self.uid end
    function p:IsAdmin() return true end
    function p:ChatPrint(m) self.chat[#self.chat + 1] = m end
    function p:PrintMessage(_, m) LOG[#LOG + 1] = m end
    players[#players + 1] = p
    return p
end
MakePlayer = mkPlayer
player = {GetAll = function() return players end, GetHumans = function() return players end}
function Player(uid) for _, p in ipairs(players) do if p.uid == uid then return p end end end
function Entity(i) return Player(i) end

zb = {ROUND_STATE = 1}
local events = {}
function AddEvent(t, kind, a, b, dmg, hitgroup, los) events[#events + 1] = {t, kind, a, b, dmg or 0, hitgroup or 0, 1, los == nil and 1 or los} end
function ClearEvents() events = {} end
K = {Root = "zc_killcam", Kinds = {hit = 1, death = 2}}
ZCKillcam = K
function K.Identity(slot)
    local p = Player(slot)
    if not p then return nil end
    return {slot = slot, uid = p.uid, id = (not p.bot) and p.sid or nil, name = p:Nick(), traitor = p.isTraitor}
end
function K.DisplayName(p) return p:Nick() end
function K.TraitorRound() return true end
function K.IsOperator(p) return p.staff == true end
function K.InstanceTag(traitorRound, a, v)
    if not traitorRound then return "other" end
    if a then return v and "tvt" or "tvi" end
    return v and "ivt" or "ivi"
end
function K.Classify(kt, vt) if kt then return nil end return vt and "t_killed" or "ivi" end
function K.EachEvent(t0, t1, fn)
    for _, e in ipairs(events) do if e[1] >= t0 and e[1] <= t1 then fn(e[1], e[2], e[3], e[4], e[5], e[6], e[7], e[8]) end end
end
function K.Work(_, fn) fn(function() end) end
K.Cut, K.SendBlob, K.Life = function() end, function() return false end, {}
K.EachSample = function() end
K.WeaponName = function() return "weapon_test" end
K.Drops = {}
-- Fire a hit through the intent layer the way sv_recorder does.
function Hit(t, a, v) SetNow(t) hook.Run("ZCKillcam_Hit", a, v, a.uid, v.uid, 1) AddEvent(t, 1, a.uid, v.uid, 40, 0, 1) end
function Kill(t, a, v)
    SetNow(t)
    local tag = K.Classify(a.isTraitor, v.isTraitor)
    AddEvent(t, 2, a.uid, v.uid)
    hook.Run("ZCKillcam_Death", v, {slot = a.uid, uid = a.uid, id = (not a.bot) and a.sid or nil, name = a:Nick(), traitor = a.isTraitor}, tag)
    return tag
end
function Include(path) return dofile(LUA_ROOT .. "/" .. path) end
'''


@unittest.skipIf(lupa_rt is None, 'lupa is not installed')
class KillcamScoringTests(unittest.TestCase):
    def setUp(self):
        self.L = lupa_rt.LuaRuntime(unpack_returned_tuples=True)
        self.L.globals().LUA_ROOT = str(LUA)
        self.L.execute(STUB)
        self.L.execute('Include("zc_killcam/sv_intent.lua")')

    def run_lua(self, code):
        return self.L.execute(code)

    # ------------------------------------------------------------------ intent
    def test_intent_classifies_who_started_it(self):
        got = self.run_lua('''
            local a, b, c, d = MakePlayer(1, "s1"), MakePlayer(2, "s2"), MakePlayer(3, "s3"), MakePlayer(4, "s4")
            hook.Run("ZB_PreRoundStart")
            -- b shoots a first, a shoots back and wins: self-defence
            Hit(10, b, a) Hit(11, a, b) Kill(12, a, b)
            -- c attacks d, a steps in and drops c: stopping an attacker
            Hit(20, c, d) Hit(21, a, c) Kill(22, a, c)
            -- a attacks d out of nowhere and d shoots back before dying: unprovoked
            Hit(40, a, d) Hit(41, d, a) Kill(42, a, d)
            return K.KillIntent(1, 2), K.KillIntent(1, 3), K.KillIntent(1, 4)
        ''')
        self.assertEqual(tuple(got), ('defense', 'stopped', 'unprovoked'))

    def test_old_scuffle_does_not_excuse_a_fresh_attack(self):
        got = self.run_lua('''
            local a, b = MakePlayer(1, "s1"), MakePlayer(2, "s2")
            hook.Run("ZB_PreRoundStart")
            Hit(10, b, a)            -- b hit a once, long ago
            Hit(100, a, b) Kill(101, a, b)
            return K.KillIntent(1, 2)
        ''')
        self.assertEqual(got, 'unprovoked')

    # ------------------------------------------------------------------ karma ledger
    def load_karma(self):
        self.run_lua('''
            Include("zc_killcam/sv_karma.lua")
            SetConVar("zc_killcam_karma", 2)
            SetConVar("zc_killcam_karma_rounds", 1)
        ''')

    def test_karma_counts_only_unprovoked_and_honours_forgiveness(self):
        self.load_karma()
        got = self.run_lua('''
            local a, b, c = MakePlayer(1, "s1"), MakePlayer(2, "s2"), MakePlayer(3, "s3")
            hook.Run("ZB_PreRoundStart")
            Hit(10, b, a) Kill(11, a, b)      -- self-defence
            Hit(20, a, c) Kill(21, a, c)      -- unprovoked
            local e = K.Karma.ledger["s1"]
            local b1, d1 = e.b, e.d
            hook.Run("ZC_RoundStars_RecordForgive", c, a)
            return b1, d1, e.b, e.fg, e.pb
        ''')
        self.assertEqual(tuple(got), (1, 1, 0, 1, 0))

    def test_rate_recovers_with_clean_play_and_staff_told_once(self):
        self.load_karma()
        got = self.run_lua('''
            local a, v, staff = MakePlayer(1, "s1"), MakePlayer(2, "s2"), MakePlayer(9, "s9")
            staff.staff = true
            local t = 0
            local function round(bad)
                hook.Run("ZB_PreRoundStart")
                hook.Run("ZB_StartRound")
                if bad then t = t + 10 Hit(t, a, v) Kill(t + 1, a, v) v.alive = true end
                hook.Run("ZB_EndRound")
            end
            round(true) round(true)
            local high = K.KarmaRate("s1")
            round(true)
            local told = #staff.chat
            for i = 1, 60 do round(false) end
            local low = K.KarmaRate("s1")
            return high, told, low, K.KarmaFlagged("s1")
        ''')
        high, told, low, flagged = got
        self.assertGreaterEqual(high, 0.5)
        self.assertEqual(told, 1, 'staff should be told once on crossing, not every round')
        self.assertLess(low, 0.2)
        self.assertFalse(flagged)

    # ------------------------------------------------------------------ highlight score
    def load_highlight(self):
        self.run_lua('Include("zc_killcam/sv_highlight.lua")')

    def test_teamkill_spree_gets_no_multikill_bonus_and_pays_nothing(self):
        self.load_highlight()
        got = self.run_lua('''
            local rdm, v1, v2, v3 = MakePlayer(1, "s1"), MakePlayer(2, "s2"), MakePlayer(3, "s3"), MakePlayer(4, "s4")
            hook.Run("ZB_PreRoundStart") ClearEvents()
            Hit(10, rdm, v1) Kill(10.5, rdm, v1)
            Hit(11, rdm, v2) Kill(11.5, rdm, v2)
            Hit(12, rdm, v3) Kill(12.5, rdm, v3)
            local score, star, s = K.Highlight.Score(5, 13)
            return score, s.lawful, s.pay
        ''')
        score, lawful, pay = got
        self.assertEqual(lawful, 0)
        self.assertEqual(pay, 0)
        self.assertLess(score, 120, 'a three-teammate spree must not clear the highlight floor')

    def test_self_defence_scores_and_pays_like_a_clean_kill(self):
        self.load_highlight()
        got = self.run_lua('''
            local hero, attacker = MakePlayer(1, "s1"), MakePlayer(2, "s2")
            hook.Run("ZB_PreRoundStart") ClearEvents()
            Hit(10, attacker, hero) Hit(10.5, hero, attacker) Kill(11, hero, attacker)
            local _, star, s = K.Highlight.Score(5, 12)
            return star, s.lawful, s.pay, s.worth
        ''')
        star, lawful, pay, worth = got
        self.assertEqual(star, 1)
        self.assertEqual(lawful, 1)
        self.assertGreater(pay, 100)
        self.assertEqual(pay, worth)

    def test_unprovoked_melee_teamkill_is_never_the_funny_moment(self):
        self.load_highlight()
        got = self.run_lua('''
            local a, b, c = MakePlayer(1, "s1"), MakePlayer(2, "s2"), MakePlayer(3, "s3")
            hook.Run("ZB_PreRoundStart") ClearEvents()
            Hit(10, a, b) Kill(10.5, a, b)                  -- unprovoked melee teamkill
            local first = K.Highlight.Funny(5, 11)
            Hit(20, c, a) Hit(20.5, a, c) Kill(21, a, c)    -- melee kill in self-defence
            local second = K.Highlight.Funny(15, 22)
            return first == nil, second and second.victim
        ''')
        self.assertEqual(tuple(got), (True, 3))

    # ------------------------------------------------------------------ points
    def test_healing_someone_you_hurt_does_not_pay(self):
        self.load_highlight()
        got = self.run_lua('''
            Include("zc_killcam/sv_points.lua")
            local a, b, c = MakePlayer(1, "s1"), MakePlayer(2, "s2"), MakePlayer(3, "s3")
            hook.Run("ZB_PreRoundStart") hook.Run("ZB_StartRound")
            Hit(10, a, b)
            SetNow(20) hook.Run("ZCity_MedicineUsed", a, b, 1, true)   -- a patches up their own victim
            SetNow(21) hook.Run("ZCity_MedicineUsed", c, b, 1, true)   -- c helps: pays
            local P = K.Points
            return P.round["s1"] and P.round["s1"].heals or 0, P.round["s3"] and P.round["s3"].heals or 0, P.stats.healsSelfInflicted
        ''')
        self.assertEqual(tuple(got), (0, 1, 1))


if __name__ == '__main__':
    unittest.main()
