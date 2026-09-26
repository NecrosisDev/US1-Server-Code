function hg.SyncWeapons()
    if ZCTickBudget then return ZCTickBudget.SyncWeapons(hg.weapons) end
    SetNetVar("weapons",hg.weapons)
end
function hg.GetArmorPlacement(armor)
	if istable(armor) then return end
	armor = string.Replace(armor,"ent_armor_","")
	
	local found
	for i,armplc in pairs(hg.armor) do
		if armplc[armor] ~= nil then found = i end
	end
	return found
end

local base=weapons.GetStored("homigrad_base")
if base then
    local oldRemove,oldSync=base.OnRemove,base.SyncAtts
    local function removed(self)
        if CLIENT and self.VM_RemoveAllEvents then self:VM_RemoveAllEvents() end
        if SERVER then table.RemoveByValue(hg.weapons,self);hg.SyncWeapons() end
    end
    local function sync(self,ply)self:SetNetVar("attachments",self.attachments)end
    local function update(t)
        if t.OnRemove==oldRemove then t.OnRemove=removed end
        if t.SyncAtts==oldSync then t.SyncAtts=sync end
    end
    for _,entry in ipairs(weapons.GetList())do
        local stored=weapons.GetStored(entry.ClassName)
        if stored then update(stored)end
    end
    for _,e in ipairs(ents.GetAll())do if e:IsWeapon()then update(e:GetTable())end end
    update(base)
end
