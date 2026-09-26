TOOL.Category = "Construction"
TOOL.Name = "#Persistent Prop"
TOOL.Command = nil
TOOL.ConfigName = ""

if CLIENT then
    language.Add("tool.persistent_prop.name", "Persistent Prop")
    language.Add("tool.persistent_prop.desc", "Spawn and save props permanently for this map")
    language.Add("tool.persistent_prop.0", "Left: spawn/save prop, Right: remove saved prop, Reload: update saved prop")

    language.Add("tool.persistent_prop.model", "Model")
    language.Add("tool.persistent_prop.frozen", "Spawn frozen")
    language.Add("tool.persistent_prop.offset", "Surface offset")
end

TOOL.ClientConVar["model"] = "models/props_junk/wood_crate001a.mdl"
TOOL.ClientConVar["frozen"] = "1"
TOOL.ClientConVar["offset"] = "0"

local function canUse(ply)
    return IsValid(ply) and ply:IsAdmin()
end

function TOOL:LeftClick(trace)
    if CLIENT then return true end
    if not canUse(self:GetOwner()) then return false end
    if not trace.Hit then return false end

    local mdl = self:GetClientInfo("model")
    if not util.IsValidModel(mdl) then return false end

    local ent = ents.Create("prop_physics")
    if not IsValid(ent) then return false end

    ent:SetModel(mdl)

    local mins, maxs = ent:GetModelBounds()
    local offset = self:GetClientNumber("offset", 0)

    local ang = Angle(0, self:GetOwner():EyeAngles().y, 0)
    local pos = trace.HitPos - mins.z * trace.HitNormal + trace.HitNormal * offset

    ent:SetPos(pos)
    ent:SetAngles(ang)
    ent:Spawn()
    ent:Activate()

    if self:GetClientNumber("frozen", 1) == 1 then
        local phys = ent:GetPhysicsObject()
        if IsValid(phys) then
            phys:EnableMotion(false)
            phys:Sleep()
        end
    end

    local ok = PersistentProps:AddEntity(ent)
    if not ok then
        ent:Remove()
        return false
    end

    undo.Create("Persistent Prop")
        undo.AddEntity(ent)
        undo.SetPlayer(self:GetOwner())
        undo.SetCustomUndoText("Persistent prop removed")
    undo.Finish()

    self:GetOwner():ChatPrint("Persistent prop saved for map: " .. game.GetMap())
    return true
end

function TOOL:RightClick(trace)
    if CLIENT then return true end
    if not canUse(self:GetOwner()) then return false end

    local ent = trace.Entity
    if not IsValid(ent) or ent:GetClass() ~= "prop_physics" then return false end
    if not ent.PersistentProp then return false end

    local ok, err = PersistentProps:RemoveByEntity(ent)
    if not ok then
        self:GetOwner():ChatPrint("Remove failed: " .. tostring(err))
        return false
    end

    ent:Remove()
    self:GetOwner():ChatPrint("Persistent prop removed.")
    return true
end

function TOOL:Reload(trace)
    if CLIENT then return true end
    if not canUse(self:GetOwner()) then return false end

    local ent = trace.Entity
    if not IsValid(ent) or ent:GetClass() ~= "prop_physics" then return false end
    if not ent.PersistentProp then return false end

    local ok, err = PersistentProps:UpdateEntity(ent)
    if not ok then
        self:GetOwner():ChatPrint("Update failed: " .. tostring(err))
        return false
    end

    self:GetOwner():ChatPrint("Persistent prop updated.")
    return true
end

function TOOL.BuildCPanel(panel)
    panel:AddControl("Header", {
        Description = "Spawn props and save them permanently for the current map."
    })

    panel:TextEntry("Model", "persistent_prop_model")
    panel:CheckBox("Spawn Frozen", "persistent_prop_frozen")
    panel:NumSlider("Surface Offset", "persistent_prop_offset", 0, 64, 0)

    panel:Button("Reload Persistent Props", "persistent_props_reload")
end