local M = ZC_HMCD_MUTATORS
local MAX_BYTES = 131072
local folder = "zc_hmcd_mutators/points"
local map = game.GetMap()
local path = folder .. "/" .. map .. ".json"
local function groupOK(group) return type(group) == "string" and #group <= 40 and group:match("^[a-z][a-z0-9_]*$") end
local function rowOK(row)
    if type(row) ~= "table" then return false end
    for _, key in ipairs({"x", "y", "z", "yaw"}) do if not M.Finite(row[key]) then return false end end
    return math.abs(row.x) <= 32768 and math.abs(row.y) <= 32768 and math.abs(row.z) <= 32768
end
M.points = {}
local raw = file.Read(path, "DATA")
if raw and #raw <= MAX_BYTES then
    local decoded = util.JSONToTable(raw)
    if type(decoded) == "table" then
        local groups = 0
        for group, rows in pairs(decoded) do
            if groupOK(group) and type(rows) == "table" and groups < 32 then
                groups = groups + 1
                M.points[group] = {}
                for _, row in ipairs(rows) do
                    if rowOK(row) and #M.points[group] < 64 then M.points[group][#M.points[group] + 1] = row end
                end
            end
        end
    end
end
function M:GetPoints(group)
    local out = {}
    for _, row in ipairs(self.points[group] or {}) do
        out[#out + 1] = {pos = Vector(row.x, row.y, row.z), ang = Angle(0, row.yaw, 0)}
    end
    return out
end
function M:SavePoints()
    local data = util.TableToJSON(self.points, true)
    if type(data) ~= "string" or #data > MAX_BYTES then return false end
    file.CreateDir(folder)
    file.Write(path, data)
    return file.Read(path, "DATA") == data
end
function M:AddPoint(group, pos, yaw)
    if not groupOK(group) then return false, "Use a short group name such as altar." end
    if not rowOK({x = pos.x, y = pos.y, z = pos.z, yaw = yaw}) or not util.IsInWorld(pos) then return false, "Position is outside the map." end
    if not self.points[group] and table.Count(self.points) >= 32 then return false, "Map group limit reached." end
    local previous = self.points[group]
    local rows = previous or {}
    if #rows >= 64 then return false, "Point limit reached for this group." end
    self.points[group] = rows
    rows[#rows + 1] = {x = pos.x, y = pos.y, z = pos.z, yaw = yaw % 360}
    if not self:SavePoints() then
        table.remove(rows)
        if not previous then self.points[group] = nil end
        return false, "Could not save map points."
    end
    return true, "Saved " .. group .. " point " .. #rows .. " on " .. map .. "."
end
function M:RemovePoint(group, index)
    local rows = self.points[group]
    if not rows or not index or index ~= math.floor(index) or not rows[index] then return false, "Point does not exist." end
    local previous = table.remove(rows, index)
    if not self:SavePoints() then table.insert(rows, index, previous); return false, "Could not save map points." end
    return true, "Removed point " .. index .. "."
end

