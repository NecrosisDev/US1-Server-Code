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
LUA = ROOT / 'addons' / 'us1' / 'lua'

STUB = r'''
SERVER = true
FCVAR_ARCHIVE, HUD_PRINTCONSOLE = 128, 2
local now = 100
function CurTime() return now end
function SysTime() return now end
function SetNow(t) now = t end
local convars = {}
CONVARS = convars
function CreateConVar(name, default)
    local cv = {v = tostring(default)}
    function cv:GetInt() return math.floor(tonumber(self.v) or 0) end
    function cv:GetFloat() return tonumber(self.v) or 0 end
    function cv:GetBool() return (tonumber(self.v) or 0) ~= 0 end
    function cv:GetString() return self.v end
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
TIMERS = {}
timer = {Create = function(name, _, _, fn) TIMERS[name] = fn end, Simple = function(_, fn) fn() end, Remove = function() end}
MASK_SHOT = 1174421507
local grace = 0
function GetGlobalFloat(_, d) return grace end
function SetGrace(t) grace = t end
function math.AngleDifference(a, b) local d = (a - b + 180) % 360 - 180 return d end
local V = {}
V.__index = V
function Vector(x, y, z) return setmetatable({x = x or 0, y = y or 0, z = z or 0}, V) end
V.__sub = function(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end
V.__div = function(a, n) return Vector(a.x / n, a.y / n, a.z / n) end
function V:Length() return math.sqrt(self.x * self.x + self.y * self.y + self.z * self.z) end
function V:Dot(b) return self.x * b.x + self.y * b.y + self.z * b.z end
function V:Distance(b) return (self - b):Length() end
WALL = false
weapons = {GetStored = function() return {Category = "Melee"} end}
util = {AddNetworkString = function() end, TableToJSON = function() return "{}" end, JSONToTable = function() return {} end,
    TraceLine = function(t) return {Hit = WALL, Entity = nil} end,
    Compress = function(s) return s end,
    DistanceToLine = function(a, b, p)
        local ab, ap = b - a, p - a
        local len2 = ab:Dot(ab)
        local t = len2 > 0 and math.max(0, math.min(1, ap:Dot(ab) / len2)) or 0
        local c = Vector(a.x + ab.x * t, a.y + ab.y * t, a.z + ab.z * t)
        return (p - c):Length(), c, t
    end}
NETRECV = {}
net = {Receive = function(name, fn) NETRECV[name] = fn end, Start = function() end, WriteUInt = function() end,
    WriteData = function(d) NETSENT = d end, Send = function() end}
function GetConVar(name) return CONVARS[name] end
file = {Read = function() end, Write = function() end, CreateDir = function() end, Exists = function() return false end, Find = function() return {} end}
game = {GetMap = function() return "test_map" end}
string.Trim = string.Trim or function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
table.remove = table.remove
math.Round = function(x) return math.floor(x + 0.5) end
function ErrorNoHalt(m) print(m) end
function isstring(x) return type(x) == "string" end
function istable(x) return type(x) == "table" end
function isnumber(x) return type(x) == "number" end
function isfunction(x) return type(x) == "function" end
function IsValid(x) return type(x) == "table" and x.valid ~= false end

LOG = {}
local players = {}
local function mkPlayer(uid, sid, traitor, bot)
    local p = {valid = true, uid = uid, sid = sid, isTraitor = traitor, bot = bot, alive = true, chat = {},
        pos = Vector(uid * 100, 0, 0), aim = Vector(1, 0, 0), ang = {p = 0, y = 0}, vel = 0}
    function p:EyePos() return self.pos end
    function p:WorldSpaceCenter() return self.pos end
    function p:GetPos() return self.pos end
    function p:GetAimVector() return self.aim end
    function p:EyeAngles() return self.ang end
    function p:GetVelocity() return Vector(self.vel, 0, 0) end
    function p:GetActiveWeapon() return self.wep end
    function p:GetClass() return "player" end
    function p:Team() return 1 end
    function p:SteamID() return "STEAM_" .. self.uid end
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
INCIDENTS = {}
hook.Add("ZCKillcam_Incident", "test", function(kind, a, b, info)
    INCIDENTS[#INCIDENTS + 1] = kind .. ":" .. (a and a.uid or "?") .. ">" .. (b and b.uid or "?") .. (info.kind and ("/" .. info.kind) or "")
end)
-- A missed bullet from `a` past `v`, about `off` units to one side of them (it keeps going the same distance again).
function MissNear(t, a, v, off)
    SetNow(t)
    local from = a.pos
    hook.Run("PostEntityFireBullets", {}, {Attacker = a, Trace = {StartPos = from, HitPos = Vector(2 * v.pos.x - from.x, 2 * off, 0)}})
end
GUN = {valid = true, ishgweapon = true, Primary = {Ammo = "9x19"}}
function Tick(t) SetNow(t) TIMERS["ZCKillcam.IntentTick"]() end
-- Point `a` straight at `v` (they sit on the x axis, 100 units per UserID).
function AimAt(a, v) local d = v.pos - a.pos a.aim = d / d:Length() a.wep = GUN end
function Box() local b = {valid = true, pos = Vector(0, 0, 0)} function b:GetClass() return "prop_physics" end
    function b:GetPos() return self.pos end function b:IsPlayer() return false end return b end
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
            hook.Run("ZB_StartRound")
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

    # ------------------------------------------------------------------ baiting, ambushes, loot
    def test_holding_a_gun_on_someone_counts_as_starting_it(self):
        got = self.run_lua('''
            local baiter, target = MakePlayer(1, "s1"), MakePlayer(2, "s2")
            local fired, conduct = nil, {}
            hook.Add("ZCKillcam_Conduct", "t", function(kind, off) conduct[#conduct + 1] = kind .. ":" .. off.uid end)
            hook.Run("ZB_PreRoundStart") hook.Run("ZB_StartRound")
            AimAt(baiter, target)
            for t = 10, 14, 0.25 do Tick(t) end          -- 4 s steady aim
            Hit(14.5, target, baiter)                     -- the bait works: target fires first
            Hit(15, baiter, target) Kill(15.5, baiter, target)
            return K.KillIntent(1, 2), conduct[1]
        ''')
        self.assertEqual(tuple(got), ('unprovoked', 'bait:1'))

    def test_shooting_someone_who_held_a_gun_on_you_is_not_starting_it(self):
        got = self.run_lua('''
            local aimer, target = MakePlayer(1, "s1"), MakePlayer(2, "s2")
            hook.Run("ZB_PreRoundStart") hook.Run("ZB_StartRound")
            AimAt(aimer, target)
            for t = 10, 14, 0.25 do Tick(t) end
            Hit(14.5, target, aimer) Kill(15, target, aimer)
            return K.KillIntent(2, 1)
        ''')
        self.assertEqual(got, 'threatened')

    def test_a_glance_or_aim_through_a_wall_or_during_grace_is_not_a_threat(self):
        got = self.run_lua('''
            local a, b = MakePlayer(1, "s1"), MakePlayer(2, "s2")
            local function trial(setup, from, to)
                hook.Run("ZB_PreRoundStart") hook.Run("ZB_StartRound")
                setup()
                for t = from, to, 0.25 do Tick(t) end
                Hit(to + 0.5, b, a) Kill(to + 1, b, a)
                return K.KillIntent(2, 1)
            end
            local glance = trial(function() AimAt(a, b) end, 10, 11.5)
            local wall = trial(function() AimAt(a, b) WALL = true end, 20, 25)
            WALL = false
            local graced = trial(function() AimAt(a, b) SetGrace(1000) end, 30, 35)
            SetGrace(0)
            return glance, wall, graced
        ''')
        self.assertEqual(tuple(got), ('unprovoked',) * 3)

    def test_aiming_at_an_attacker_is_stopping_them_not_threatening(self):
        got = self.run_lua('''
            local hero, rdm, victim = MakePlayer(1, "s1"), MakePlayer(2, "s2"), MakePlayer(3, "s3")
            hook.Run("ZB_PreRoundStart") hook.Run("ZB_StartRound")
            Hit(10, rdm, victim)
            AimAt(hero, rdm)
            for t = 10, 14, 0.25 do Tick(t) Hit(t, rdm, victim) end
            Hit(14.5, rdm, hero) Kill(15, rdm, hero)     -- the RDMer turns and kills the player covering them
            return K.KillIntent(2, 1)
        ''')
        self.assertEqual(got, 'unprovoked')

    def test_kicking_an_idle_player_is_an_ambush_and_its_traitor_kill_earns_nothing(self):
        self.load_highlight()
        got = self.run_lua('''
            local kicker, afk = MakePlayer(1, "s1"), MakePlayer(2, "s2", true)
            local conduct = {}
            hook.Add("ZCKillcam_Conduct", "t", function(kind, off, vic, d) conduct[#conduct + 1] = kind .. (d and d.traitor and "+T" or "") end)
            hook.Run("ZB_PreRoundStart") ClearEvents()
            SetNow(0) hook.Run("ZB_StartRound")
            Tick(5) Tick(12)                              -- the traitor gives no input for 12 s
            Hit(20, kicker, afk)                          -- kicked to the ground
            SetNow(22) hook.Run("ZB_InventoryOpened", kicker, afk)
            Hit(24, kicker, afk) Kill(25, kicker, afk)
            local _, _, s = K.Highlight.Score(19, 26)
            return table.concat(conduct, ","), s.pay, s.lawful
        ''')
        self.assertEqual(tuple(got), ('ambush+T,search+T', 0, 0))

    def test_hitting_an_active_player_is_not_an_ambush(self):
        got = self.run_lua('''
            local a, b = MakePlayer(1, "s1"), MakePlayer(2, "s2")
            local n = 0
            hook.Add("ZCKillcam_Conduct", "t", function() n = n + 1 end)
            hook.Run("ZB_PreRoundStart") SetNow(0) hook.Run("ZB_StartRound")
            Tick(5)
            b.ang = {p = 0, y = 45} Tick(15)              -- looking around counts as input
            Hit(20, a, b)
            b.vel = 200 Tick(40) Tick(48)                 -- so does moving
            Hit(50, a, b)
            return n
        ''')
        self.assertEqual(got, 0)

    def test_breaking_a_box_someone_is_looting_flags_and_only_trips_if_a_fight_follows(self):
        got = self.run_lua('''
            local looter, thief, other = MakePlayer(1, "s1"), MakePlayer(2, "s2"), MakePlayer(3, "s3")
            local conduct = {}
            hook.Add("ZCKillcam_Conduct", "t", function(kind, off) conduct[#conduct + 1] = kind .. ":" .. off.uid end)
            hook.Run("ZB_PreRoundStart") hook.Run("ZB_StartRound")
            local box, far, own = Box(), Box(), Box()
            looter.pos = Vector(50, 0, 0)
            SetNow(10) hook.Run("ZB_InventoryOpened", looter, box)
            SetNow(15) hook.Run("PropBreak", thief, box)                 -- under the looter: flagged
            local afterFlag = #conduct
            SetNow(20) hook.Run("ZB_InventoryOpened", looter, far) far.pos = Vector(5000, 0, 0)
            SetNow(21) hook.Run("PropBreak", other, far)                  -- looter walked away: not even a flag
            SetNow(30) hook.Run("ZB_InventoryOpened", looter, own)
            SetNow(31) hook.Run("PropBreak", looter, own)                 -- breaking your own box: nothing
            Hit(35, looter, thief) Kill(36, looter, thief)                -- the looter goes for the thief: it trips
            return afterFlag, table.concat(conduct, ","), K.KillIntent(1, 2)
        ''')
        self.assertEqual(tuple(got), (0, 'loot:2', 'provoked'))

    def test_a_flag_that_nothing_follows_costs_nothing(self):
        got = self.run_lua('''
            local a, b = MakePlayer(1, "s1"), MakePlayer(2, "s2")
            local n = 0
            hook.Add("ZCKillcam_Conduct", "t", function() n = n + 1 end)
            hook.Run("ZB_PreRoundStart") hook.Run("ZB_StartRound")
            AimAt(a, b)
            for t = 10, 14, 0.25 do Tick(t) end
            Hit(40, b, a)                                 -- long after the flag went stale
            return n, INCIDENTS[1], K.Intent.pairs[2][1].first
        ''')
        self.assertEqual(tuple(got), (0, 'flag:1>2/aim', True))

    def test_a_lowered_gun_is_not_aiming_at_anyone(self):
        got = self.run_lua('''
            local a, b = MakePlayer(1, "s1"), MakePlayer(2, "s2")
            hook.Run("ZB_PreRoundStart") hook.Run("ZB_StartRound")
            AimAt(a, b)
            a.wep = {valid = true, ishgweapon = true, Primary = {Ammo = "9x19"}, ReadyStance = function() return true end}
            for t = 10, 14, 0.25 do Tick(t) end
            return #INCIDENTS
        ''')
        self.assertEqual(got, 0)

    def test_squaring_up_with_fists_at_arms_reach_is_a_flag(self):
        got = self.run_lua('''
            local a, b = MakePlayer(1, "s1"), MakePlayer(2, "s2")
            hook.Run("ZB_PreRoundStart") hook.Run("ZB_StartRound")
            b.pos = Vector(160, 0, 0)                     -- 60 units away
            AimAt(a, b)
            a.wep = {valid = true, GetClass = function() return "weapon_hands_sh" end, GetFists = function() return true end}
            for t = 10, 14, 0.25 do Tick(t) end
            Hit(14.5, b, a) Kill(15, b, a)
            return INCIDENTS[1], K.KillIntent(2, 1)
        ''')
        self.assertEqual(tuple(got), ('flag:1>2/melee', 'threatened'))

    def test_a_missed_shot_counts_as_going_first(self):
        got = self.run_lua('''
            local shooter, target, bystander = MakePlayer(1, "s1"), MakePlayer(2, "s2"), MakePlayer(9, "s9")
            hook.Run("ZB_PreRoundStart") hook.Run("ZB_StartRound")
            MissNear(10, shooter, target, 40)             -- misses, 40 units from the target
            Hit(11, target, shooter) Kill(12, target, shooter)
            local first = K.KillIntent(2, 1)
            MissNear(20, bystander, target, 400)          -- nowhere near: nothing
            Hit(21, target, bystander) Kill(22, target, bystander)
            return first, K.KillIntent(2, 9)
        ''')
        self.assertEqual(tuple(got), ('defense', 'unprovoked'))

    def test_traitors_are_not_charged_with_conduct(self):
        got = self.run_lua('''
            local traitor, afk = MakePlayer(1, "s1", true), MakePlayer(2, "s2")
            local n = 0
            hook.Add("ZCKillcam_Conduct", "t", function() n = n + 1 end)
            hook.Run("ZB_PreRoundStart") SetNow(0) hook.Run("ZB_StartRound")
            Tick(12) Hit(20, traitor, afk)
            return n
        ''')
        self.assertEqual(got, 0)

    # ------------------------------------------------------------------ per-life timeline
    def load_timeline(self):
        self.run_lua('''
            Include("zc_killcam/sv_karma.lua")
            Include("zc_killcam/sv_timeline.lua")
            SetConVar("zc_killcam_karma", 1)
            SetConVar("zc_killcam_timeline", 2)
            LOCKED = false
            ZCityMetaSafety = {Locked = function() return LOCKED end}
            json = {}
            util.TableToJSON = function(t) LASTTABLE = t return "x" end
        ''')

    def test_timeline_explains_what_counted_and_why(self):
        self.load_timeline()
        got = self.run_lua('''
            local baiter, target = MakePlayer(1, "s1"), MakePlayer(2, "s2")
            hook.Run("ZB_PreRoundStart") SetNow(0) hook.Run("ZB_StartRound")
            hook.Run("PlayerSpawn", baiter) hook.Run("PlayerSpawn", target)
            AimAt(baiter, target)
            for t = 10, 14, 0.25 do Tick(t) end
            Hit(14.5, target, baiter) Kill(15, target, baiter)
            hook.Run("PlayerDeath", baiter, nil, target)
            local mine = K.Timeline.lives["s1"][1]
            local lines = {}
            for _, e in ipairs(mine.events) do lines[#lines + 1] = e.text .. " [" .. (e.tag or "") .. "]" end
            local theirs = {}
            for _, e in ipairs(K.Timeline.live[2].events) do theirs[#theirs + 1] = e.text .. " [" .. (e.tag or "") .. "]" end
            return table.concat(lines, "|"), table.concat(theirs, "|"), mine.ended
        ''')
        baiter, target, ended = got
        self.assertIn('You held a gun on P2 [flag - only counts if a fight follows]', baiter)
        self.assertIn('P2 fought back after you held a gun on them [counts as baiting (0.5)]', baiter)
        self.assertIn('Killed by P2 - you held a gun on them / squared up first', baiter)
        self.assertIn('You fought back after P1 held a gun on you [provoked - doesn\'t count against you]', target)
        self.assertIn("You killed P1 - they held a gun on you / squared up first [doesn't count]", target)
        self.assertEqual(ended, 'died')

    def test_timeline_holds_back_role_revealing_verdicts_until_round_end(self):
        self.load_timeline()
        got = self.run_lua('''
            local hero, traitor = MakePlayer(1, "s1"), MakePlayer(2, "s2", true)
            hook.Run("ZB_PreRoundStart") SetNow(0) hook.Run("ZB_StartRound")
            hook.Run("PlayerSpawn", hero) hook.Run("PlayerSpawn", traitor)
            Hit(10, traitor, hero) Hit(11, hero, traitor) Kill(12, hero, traitor)
            hook.Run("ZB_EndRound")                       -- the hero survived
            local life = K.Timeline.lives["s1"][1]
            LOCKED = true
            local during = K.Timeline.View(life).events
            LOCKED = false
            local after = K.Timeline.View(life).events
            return during[#during].text, during[#during].tag, after[#after].text, after[#after].tag, life.ended
        ''')
        self.assertEqual(tuple(got), ('You killed P2', 'verdict at round end', 'You killed P2, a traitor', 'good kill', 'survived'))

    def test_karma_app_only_sends_your_own_lives_and_your_record(self):
        self.load_timeline()
        got = self.run_lua('''
            local a, b = MakePlayer(1, "s1"), MakePlayer(2, "s2")
            hook.Run("ZB_PreRoundStart") SetNow(0) hook.Run("ZB_StartRound")
            hook.Run("PlayerSpawn", a) hook.Run("PlayerSpawn", b)
            Hit(10, a, b) Kill(11, a, b)
            hook.Run("PlayerDeath", b, nil, a)
            hook.Run("ZB_EndRound")
            SetNow(20) NETRECV["zckc_timeline"](0, b)
            local forB = LASTTABLE
            SetConVar("zc_killcam_timeline", 1)          -- tester only: b is not the tester
            SetNow(30) NETRECV["zckc_timeline"](0, b)
            return #forB.lives, forB.lives[1].events[#forB.lives[1].events].text, LASTTABLE.allowed, #LASTTABLE.lives
        ''')
        self.assertEqual(tuple(got), (1, 'Killed by P1 - they started it - counted against them', False, 0))

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

    def test_conduct_is_recorded_for_staff_and_weighs_half_a_teamkill(self):
        self.load_karma()
        got = self.run_lua('''
            local kicker, afk = MakePlayer(1, "s1"), MakePlayer(2, "s2", true)
            hook.Run("ZB_PreRoundStart") SetNow(0) hook.Run("ZB_StartRound")
            Tick(12) Hit(20, kicker, afk)
            SetNow(22) hook.Run("ZB_InventoryOpened", kicker, afk)
            Kill(25, kicker, afk)
            hook.Run("ZC_RoundStars_RecordForgive", afk, kicker)   -- forgiveness clears kills, not conduct
            hook.Run("ZB_EndRound")
            local e = K.Karma.ledger["s1"]
            local inc = e.i[#e.i]
            return e.xa, e.g, inc.k, inc.s, inc.tr, K.KarmaRate("s1"), e.b
        ''')
        self.assertEqual(tuple(got), (1, 0, 'ambush', True, True, 0.5, 0))

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
    def test_clean_round_bonus_goes_to_active_players_with_nothing_counted(self):
        self.load_highlight()
        got = self.run_lua('''
            Include("zc_killcam/sv_points.lua")
            CurrentRound = function() return {name = "hmcd"} end
            local good, rdm, victim, afk = MakePlayer(1, "s1"), MakePlayer(2, "s2"), MakePlayer(3, "s3"), MakePlayer(4, "s4")
            hook.Run("ZB_PreRoundStart") SetNow(0) hook.Run("ZB_StartRound")
            good.vel, rdm.vel, victim.vel = 200, 200, 200
            Tick(20)                                      -- three of them are playing; afk never moves
            Hit(30, rdm, victim) Kill(31, rdm, victim)    -- unprovoked
            local printed
            print = function(s) printed = s end
            hook.Run("ZB_EndRound")
            local R = K.Points.round
            return R["s1"] and R["s1"].clean or 0, R["s2"] and R["s2"].clean or 0, R["s4"] and R["s4"].clean or 0, printed
        ''')
        good, rdm, afk, line = got
        self.assertEqual((good, rdm, afk), (3, 0, 0))
        self.assertIn('mode=hmcd humans=4', line)
        self.assertIn('P1 3 ZP (combat 0/40, 0 heals, clean)', line)

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
