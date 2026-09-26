if CLIENT then return end

PersistentProps = PersistentProps or {}
PersistentProps.Spawned = PersistentProps.Spawned or {}
PersistentProps.DataFile = "persistent_props"

util.AddNetworkString("PersistentProps_RequestList")
util.AddNetworkString("PersistentProps_SendList")
util.AddNetworkString("PersistentProps_RemoveID")
util.AddNetworkString("PersistentProps_TeleportTo")
util.AddNetworkString("PersistentProps_ReloadAll")
util.AddNetworkString("PersistentProps_WipeMap")
util.AddNetworkString("PersistentProps_ChatNotify")

local function ensureDir()
    if not file.IsDir(PersistentProps.DataFile, "DATA") then
        file.CreateDir(PersistentProps.DataFile)
    end
end

local function mapFile()
    return string.format("%s/%s.json", PersistentProps.DataFile, game.GetMap())
end

local function vecToTbl(v)
    return {x = v.x, y = v.y, z = v.z}
end

local function angToTbl(a)
    return {p = a.p, y = a.y, r = a.r}
end

local function tblToVec(t)
    return Vector(t.x or 0, t.y or 0, t.z or 0)
end

local function tblToAng(t)
    return Angle(t.p or 0, t.y or 0, t.r or 0)
end

local function serializeColor(c)
    return {r = c.r, g = c.g, b = c.b, a = c.a}
end

local function deserializeColor(t)
    return Color(t.r or 255, t.g or 255, t.b or 255, t.a or 255)
end

local function captureBodygroups(ent)
    local out = {}
    local count = ent:GetNumBodyGroups() or 0
    for i = 0, count - 1 do
        out[i] = ent:GetBodygroup(i)
    end
    return out
end

local function applyBodygroups(ent, bodygroups)
    if not bodygroups then return end
    for id, val in pairs(bodygroups) do
        ent:SetBodygroup(tonumber(id) or id, tonumber(val) or 0)
    end
end

local function isFrozen(ent)
    local phys = ent:GetPhysicsObject()
    if not IsValid(phys) then return false end
    return not phys:IsMotionEnabled()
end

local function canManage(ply)
    return IsValid(ply) and ply:IsAdmin()
end

local function notify(ply, msg)
    if not IsValid(ply) then return end
    ply:ChatPrint("[Persistent Props] " .. msg)
end

function PersistentProps:LoadData()
    ensureDir()

    if not file.Exists(mapFile(), "DATA") then
        return {}
    end

    local raw = file.Read(mapFile(), "DATA")
    if not raw or raw == "" then
        return {}
    end

    local data = util.JSONToTable(raw)
    if not istable(data) then
        return {}
    end

    return data
end

function PersistentProps:SaveData(data)
    ensureDir()

    local json = util.TableToJSON(data, true)
    if not json then
        ErrorNoHalt("[PersistentProps] Failed to encode JSON for " .. mapFile() .. "\n")
        return false
    end

    file.Write(mapFile(), json)
    return true
end

function PersistentProps:GetAll()
    return self:LoadData()
end

function PersistentProps:GetNetList()
    local out = {}
    for _, v in ipairs(self:LoadData()) do
        out[#out + 1] = {
            id = tostring(v.id or ""),
            model = tostring(v.model or ""),
            pos = v.pos or {x = 0, y = 0, z = 0},
            ang = v.ang or {p = 0, y = 0, r = 0},
            frozen = v.frozen and true or false
        }
    end
    return out
end

function PersistentProps:FindByID(id)
    local data = self:LoadData()
    for k, v in ipairs(data) do
        if tostring(v.id) == tostring(id) then
            return k, v, data
        end
    end
end

function PersistentProps:MakeID()
    return util.CRC(game.GetMap() .. "_" .. SysTime() .. "_" .. math.random(1, 99999999))
end

function PersistentProps:EntityToData(ent)
    if not IsValid(ent) then return nil, "invalid entity" end
    if ent:GetClass() ~= "prop_physics" then return nil, "not prop_physics" end

    local mdl = ent:GetModel()
    if not mdl or mdl == "" then return nil, "missing model" end

    return {
        id = ent.PersistentPropID or self:MakeID(),
        model = mdl,
        pos = vecToTbl(ent:GetPos()),
        ang = angToTbl(ent:GetAngles()),
        skin = ent:GetSkin() or 0,
        material = ent:GetMaterial() or "",
        color = serializeColor(ent:GetColor()),
        bodygroups = captureBodygroups(ent),
        collisiongroup = ent:GetCollisionGroup() or COLLISION_GROUP_NONE,
        frozen = isFrozen(ent)
    }
end

function PersistentProps:SpawnFromData(entry)
    if not entry or not entry.model then return end
    if not util.IsValidModel(entry.model) then
        ErrorNoHalt("[PersistentProps] Invalid model skipped: " .. tostring(entry.model) .. "\n")
        return
    end

    local ent = ents.Create("prop_physics")
    if not IsValid(ent) then return end

    ent:SetModel(entry.model)
    ent:SetPos(tblToVec(entry.pos or {}))
    ent:SetAngles(tblToAng(entry.ang or {}))
    ent:Spawn()
    ent:Activate()

    ent:SetSkin(tonumber(entry.skin) or 0)
    ent:SetMaterial(entry.material or "")
    ent:SetColor(deserializeColor(entry.color or {}))
    ent:SetCollisionGroup(tonumber(entry.collisiongroup) or COLLISION_GROUP_NONE)
    applyBodygroups(ent, entry.bodygroups)

    if entry.frozen then
        local phys = ent:GetPhysicsObject()
        if IsValid(phys) then
            phys:EnableMotion(false)
            phys:Sleep()
        end
    end

    ent.PersistentProp = true
    ent.PersistentPropID = entry.id

    self.Spawned[entry.id] = ent
    return ent
end

function PersistentProps:RemoveSpawned()
    for id, ent in pairs(self.Spawned) do
        if IsValid(ent) then
            ent:Remove()
        end
    end
    self.Spawned = {}
end

function PersistentProps:RespawnAll()
    self:RemoveSpawned()

    for _, entry in ipairs(self:LoadData()) do
        self:SpawnFromData(entry)
    end
end

function PersistentProps:AddEntity(ent)
    local entry, err = self:EntityToData(ent)
    if not entry then
        return false, err or "invalid entity"
    end

    local data = self:LoadData()
    data[#data + 1] = entry

    if not self:SaveData(data) then
        return false, "save failed"
    end

    ent.PersistentProp = true
    ent.PersistentPropID = entry.id
    self.Spawned[entry.id] = ent

    return true, entry.id
end

function PersistentProps:UpdateEntity(ent)
    if not IsValid(ent) or not ent.PersistentPropID then
        return false, "not persistent"
    end

    local idx, _, data = self:FindByID(ent.PersistentPropID)
    if not idx then
        return false, "missing saved data"
    end

    local entry, err = self:EntityToData(ent)
    if not entry then
        return false, err or "invalid entity"
    end

    data[idx] = entry

    if not self:SaveData(data) then
        return false, "save failed"
    end

    return true
end

function PersistentProps:RemoveByID(id)
    local idx, entry, data = self:FindByID(id)
    if not idx then
        return false, "missing saved data"
    end

    local spawned = self.Spawned[entry.id]
    if IsValid(spawned) then
        spawned:Remove()
    end

    table.remove(data, idx)

    if not self:SaveData(data) then
        return false, "save failed"
    end

    self.Spawned[entry.id] = nil
    return true
end

function PersistentProps:RemoveByEntity(ent)
    if not IsValid(ent) or not ent.PersistentPropID then
        return false, "not persistent"
    end

    return self:RemoveByID(ent.PersistentPropID)
end

function PersistentProps:WipeMap()
    self:RemoveSpawned()
    self:SaveData({})
end

function PersistentProps:SendList(ply)
    if not canManage(ply) then return end

    net.Start("PersistentProps_SendList")
    net.WriteString(game.GetMap())
    net.WriteUInt(#self:GetNetList(), 16)

    for _, v in ipairs(self:GetNetList()) do
        net.WriteString(v.id)
        net.WriteString(v.model)
        net.WriteVector(tblToVec(v.pos))
        net.WriteAngle(tblToAng(v.ang))
        net.WriteBool(v.frozen)
    end

    net.Send(ply)
end

hook.Add("InitPostEntity", "PersistentProps_LoadMapProps", function()
    timer.Simple(1, function()
        if not PersistentProps then return end
        PersistentProps:RespawnAll()
    end)
end)

hook.Add("PostCleanupMap", "PersistentProps_ReloadAfterCleanup", function()
    timer.Simple(0.5, function()
        if not PersistentProps then return end
        PersistentProps:RespawnAll()
    end)
end)

concommand.Add("persistent_props_reload", function(ply)
    if IsValid(ply) and not canManage(ply) then return end
    PersistentProps:RespawnAll()
    if IsValid(ply) then notify(ply, "Reloaded all persistent props.") end
end, nil, "Admin: respawn every persistent prop on this map.")

concommand.Add("persistent_props_wipe", function(ply)
    if IsValid(ply) and not ply:IsSuperAdmin() then return end
    PersistentProps:WipeMap()
    if IsValid(ply) then notify(ply, "Wiped all persistent props for this map.") end
end, nil, "Superadmin: delete every persistent prop saved for this map.")

concommand.Add("persistent_props_menu", function(ply)
    if not canManage(ply) then return end
    PersistentProps:SendList(ply)
end, nil, "Admin: send the persistent prop list to your manager window (!pprops).")

net.Receive("PersistentProps_RequestList", function(_, ply)
    if not canManage(ply) then return end
    PersistentProps:SendList(ply)
end)

net.Receive("PersistentProps_RemoveID", function(_, ply)
    if not canManage(ply) then return end

    local id = net.ReadString()
    local ok, err = PersistentProps:RemoveByID(id)

    if not ok then
        notify(ply, "Remove failed: " .. tostring(err))
        return
    end

    notify(ply, "Removed persistent prop " .. id)
    PersistentProps:SendList(ply)
end)

net.Receive("PersistentProps_TeleportTo", function(_, ply)
    if not canManage(ply) then return end

    local id = net.ReadString()
    local _, entry = PersistentProps:FindByID(id)
    if not entry then
        notify(ply, "Prop not found.")
        return
    end

    local targetPos = tblToVec(entry.pos) + Vector(0, 0, 32)
    ply:SetPos(targetPos)
    notify(ply, "Teleported to prop " .. id)
end)

net.Receive("PersistentProps_ReloadAll", function(_, ply)
    if not canManage(ply) then return end
    PersistentProps:RespawnAll()
    notify(ply, "Reloaded all persistent props.")
    PersistentProps:SendList(ply)
end)

net.Receive("PersistentProps_WipeMap", function(_, ply)
    if not IsValid(ply) or not ply:IsSuperAdmin() then return end
    PersistentProps:WipeMap()
    notify(ply, "Wiped all persistent props for this map.")
    PersistentProps:SendList(ply)
end)