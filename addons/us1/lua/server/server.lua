concommand.Add('Strength', function(ply)
if IsValid(ply) and not ply:IsSuperAdmin() then return end




local wp = ply:GetWeapon("weapon_hands_sh")

wp.BreakBoneMul = 8000
wp.Penetration = 8000
wp.DamageMul = 8000

end)


concommand.Add('StrengthNo', function(ply)
if IsValid(ply) and not ply:IsSuperAdmin() then return end




local wp = ply:GetWeapon("weapon_hands_sh")

wp.BreakBoneMul = 0.33
wp.Penetration = 1
wp.DamageMul = 1

end)