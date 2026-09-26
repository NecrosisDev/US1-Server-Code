if not SERVER then return end
local MODE = MODE or (zb and zb.modes and zb.modes.shitterhunt) -- nil outside the loader: a lone autorefresh patches the registered mode
if not MODE then return end
local primaryWeapons = {"weapon_akm", "weapon_m4a1", "weapon_mp5", "weapon_remington870", "weapon_sks"}
local function finite(n) return type(n) == "number" and n == n and math.abs(n) < math.huge end
local function eligible(p)
    return IsValid(p) and p:IsPlayer() and p:Alive() and p:Team() ~= TEAM_SPECTATOR and p:Team() ~= TEAM_UNASSIGNED
end
local function karma(p)
    local value = ZCityMetaSafety and ZCityMetaSafety.Public and ZCityMetaSafety.Public(p) or p.Karma
    if not finite(value) and p.guilt_GetValue then value = p:guilt_GetValue() end
    return finite(value) and value or 100
end

-- At the next-round boundary dead participants count too: the round owner
-- respawns them. Spectators, unassigned players and bots cannot trigger a hunt.
function MODE:HuntRoster(aliveOnly)
    local roster, shitters, hunters = {}, {}, 0
    local bounty = false
    local K = ZCityKarmaBounties
    local enabled = GetConVar("zc_karma_bounties")
    for _, p in ipairs(player.GetHumans()) do
        if IsValid(p) and p:Team() ~= TEAM_SPECTATOR and p:Team() ~= TEAM_UNASSIGNED
            and (not aliveOnly or p:Alive()) then
            roster[#roster + 1] = p
            local value = karma(p)
            if value < 50 then
                shitters[#shitters + 1] = p
                -- Use the bounty owner's public-karma curve. Current-round
                -- claims expire at transition; do not read its private balance.
                local price = enabled and enabled:GetBool() and K and K.Value and K.Value(value)
                bounty = bounty or (finite(price) and price > 0)
            else
                hunters = hunters + 1
            end
        end
    end
    return roster, shitters, hunters, bounty
end

function MODE:CanLaunch()
    local _, shitters, hunters = self:HuntRoster(false)
    return #shitters > 0 and hunters > 0
end

function MODE:ShouldAutoLaunch()
    local _, shitters, hunters, bounty = self:HuntRoster(false)
    local dev = GetConVar("zb_dev")
    return not (dev and dev:GetBool()) and hunters > 0 and (bounty or #shitters > 3)
end

function MODE:ClearHunt()
    for _, p in ipairs(player.GetAll()) do
        p:SetNWInt("ZCShitterhuntRole", 0)
        p:SetNWFloat("ZCShitterhuntBlindUntil", 0)
    end
    SetGlobalFloat("ZCShitterhuntEnd", 0)
    SetGlobalString("ZCShitterhuntName", "")
    SetGlobalInt("ZCShitterhuntRemaining", 0)
    SetGlobalString("ZCShitterhuntResult", "")
    self.saved = {}
end

function MODE:Intermission()
    self:ClearHunt()
    game.CleanUpMap()
    for _, p in ipairs(player.GetAll()) do
        if p:Team() ~= TEAM_SPECTATOR and p:Team() ~= TEAM_UNASSIGNED then
            ApplyAppearance(p)
            p:SetupTeam(0)
        end
    end
end

function MODE:GiveEquipment() end
function MODE:GiveWeapons() end
function MODE:CanSpawn() return false end

local function giveGun(p, class)
    if not weapons.GetStored(class) then return false end
    local gun = p:Give(class)
    if not IsValid(gun) then return false end
    local clip, ammo = gun:GetMaxClip1(), gun:GetPrimaryAmmoType()
    if clip > 0 then gun:SetClip1(clip) end
    if ammo >= 0 then p:GiveAmmo(math.max(clip, 10) * 3, ammo, true) end
    return true
end

function MODE:GiveHuntLoadout(p, isShitter)
    p:StripWeapons()
    p:StripAmmo()
    hg.CreateInv(p)
    p.armors = {}; p.armors_health = {}
    p:SyncArmor()
    p:Give("weapon_hands_sh") -- Bare hands retain ordinary movement/ragdoll interactions.
    if not isShitter then
        local inv = p:GetNetVar("Inventory")
        if inv and inv.Weapons then inv.Weapons.hg_sling = true; p:SetNetVar("Inventory", inv) end
        local available = {}
        for _, class in ipairs(primaryWeapons) do
            if weapons.GetStored(class) then available[#available + 1] = class end
        end
        if #available > 0 then giveGun(p, available[math.random(#available)]) end
        giveGun(p, "weapon_glock17")
        if weapons.GetStored("weapon_pocketknife") then p:Give("weapon_pocketknife") end
    end
    p:SelectWeapon("weapon_hands_sh")
end

function MODE:RoundStart()
    self:ClearHunt()
    local roster, shitters, hunters = self:HuntRoster(true)
    local targets = {}
    for _, p in ipairs(shitters) do targets[p] = true end
    local s = {players = {}, started = CurTime(), finished = false}
    self.saved = s
    if #shitters == 0 or hunters == 0 then
        s.result = "Shitterhunt cancelled: both teams need participants."
        return
    end
    s.blindUntil = s.started + self.Headstart
    s.ends = s.blindUntil + self.HuntTime
    s.nextFart = s.started + self.FartInterval
    SetGlobalFloat("ZCShitterhuntEnd", s.ends)
    SetGlobalString("ZCShitterhuntName", #shitters == 1 and shitters[1]:Nick() or (#shitters .. " Shitters"))
    SetGlobalInt("ZCShitterhuntRemaining", #shitters)
    for _, p in ipairs(roster) do
        local isShitter = targets[p] == true
        s.players[p] = {role = isShitter and self.RoleShitter or self.RoleHunter}
        p:SetTeam(isShitter and 1 or 0)
        p:SetNWInt("ZCShitterhuntRole", s.players[p].role)
        p:SetNWFloat("ZCShitterhuntBlindUntil", isShitter and 0 or s.blindUntil)
        self:GiveHuntLoadout(p, isShitter)
        zb.GiveRole(p, isShitter and "Shitter" or "Hunter", isShitter and Color(155, 115, 55) or Color(70, 170, 220))
        p:ChatPrint(isShitter and "[Shitterhunt] You are on the Shitter team! Hide now: hunters are blind for 20 seconds. You fart every 30 seconds."
            or "[Shitterhunt] Hunt all " .. #shitters .. " Shitter team members. Your sight and weapons unlock in 20 seconds.")
    end
end

function MODE:HuntOutcome()
    local s = self.saved or {}
    if s.result then return s.result end
    if not s.players then return "Shitterhunt cancelled." end
    local hunters, shitters = 0, 0
    for p, row in pairs(s.players) do
        if not row.eliminated and eligible(p) then
            if row.role == self.RoleHunter then hunters = hunters + 1
            elseif row.role == self.RoleShitter then shitters = shitters + 1 end
        end
    end
    if GetGlobalInt("ZCShitterhuntRemaining", 0) ~= shitters then
        SetGlobalInt("ZCShitterhuntRemaining", shitters)
    end
    if shitters == 0 then return hunters > 0 and "Hunters win! All Shitters are out." or "Draw: nobody survived." end
    if hunters == 0 then return "Shitter team wins! No hunters remain." end
    if s.ends and CurTime() >= s.ends then return "Shitter team wins by surviving the hunt!" end
end

function MODE:ShouldRoundEnd()
    local outcome = self:HuntOutcome()
    if outcome then self.saved = self.saved or {}; self.saved.result = outcome; return true end
    return false
end

function MODE:RoundThink()
    local s = self.saved or {}
    if s.finished or self:HuntOutcome() or not s.nextFart or CurTime() < s.nextFart then return end
    for p, row in pairs(s.players) do
        if row.role == self.RoleShitter and not row.eliminated and eligible(p) then
            local body = IsValid(p.FakeRagdoll) and p.FakeRagdoll or p
            body:EmitSound("snd_jack_hmcd_fart.wav", 90, 100, 1, CHAN_BODY)
        end
    end
    s.nextFart = CurTime() + self.FartInterval -- Never catch up with a burst after a stall.
end

function MODE:PostPlayerDeath(p)
    local row = self.saved and self.saved.players and self.saved.players[p]
    if row then row.eliminated = true end
end

function MODE:PlayerDisconnected(p)
    self:PostPlayerDeath(p)
end

function MODE:EndRound()
    local result = self:HuntOutcome() or "Shitterhunt ended."
    self.saved = self.saved or {}
    -- Owner rule 2026-09-21: every Shitter, win or lose, leaves the hunt with +25 karma.
    -- Once per round; a cancelled hunt has no players table rows and pays nothing.
    if not self.saved.consoled then
        self.saved.consoled = true
        for p, row in pairs(self.saved.players or {}) do
            if row.role == self.RoleShitter and IsValid(p) and p.guilt_SetValue and finite(p.Karma) then
                p.Karma = math.Clamp(p.Karma + self.Consolation, -60, zb.MaxKarma or 120)
                p:SetNetVar("Karma", p.Karma)
                p:guilt_SetValue(p.Karma)
                p:ChatPrint("[Shitterhunt] Hunt served: +" .. self.Consolation .. " karma.")
            end
        end
    end
    self.saved.finished = true
    self.saved.result = result
    for _, p in ipairs(player.GetAll()) do p:SetNWFloat("ZCShitterhuntBlindUntil", 0) end
    SetGlobalString("ZCShitterhuntResult", result)
    PrintMessage(HUD_PRINTTALK, "[Shitterhunt] " .. result)
end

function MODE:ZB_PreRoundStart() self:ClearHunt() end
function MODE:PostCleanupMap() self:ClearHunt() end
