hg.organism = hg.organism or {}
local male = {}
male["ValveBiped.Bip01_Spine1"] = {}

male["ValveBiped.Bip01_Spine"] = {
	{"liver", nil, Vector(4, 3, -2.5), Angle(0, 0, 0), Vector(2, 2, 3.5), Color(125, 50, 0)},
	{"stomach", nil, Vector(3, 2, 2), Angle(0, 0, 0), Vector(2.5, 2, 3), Color(255, 125, 0)}
}
male["ValveBiped.Bip01_Head1"] = {
	{
		"skull", --bone
		0.5,
		Vector(5.5, -1.5, 0),
		Angle(0, 0, 0),
		Vector(2.5, 4.8, 3.2),
		Color(0, 255, 0)
	},
	{
		"skull", --bone niz
		0.5,
		Vector(1, 1.5, 0),
		Angle(0, 0, 0),
		Vector(2, 1.4, 2.5),
		Color(0, 255, 0)
	},
	{
		"jaw", --jaw
		0.5,
		Vector(1, -3, 0),
		Angle(0, 0, 0),
		Vector(2, 3, 2),
		Color(0, 255, 0)
	},
	{
		"brain", --brain
		nil,
		Vector(5.4, -1.5, 0),
		Angle(0, 0, 0),
		Vector(2.5, 4.3, 2.8),
		Color(255, 0, 255)
	},
	{
		"brain", --brain niz
		nil,
		Vector(1.7, 0, 0),
		Angle(0, 0, 0),
		Vector(1.6, 2.1, 1.7),
		Color(255, 0, 255)
	},
}

local spine = 0.25
male["ValveBiped.Bip01_Neck1"] = {
	{
		"spine3", --spine3 neck
		spine,
		Vector(1, 1, 0),
		Angle(0, 0, 0),
		Vector(2, 0.5, 0.5),
		Color(0, 125, 0)
	},
	{"trachea", nil, Vector(2, -2, 0), Angle(0, 0, 0), Vector(2, 0.5, 0.5), Color(0, 125, 255)},
	{
		"arteria", --right artery
		nil,
		Vector(3.5, -2, 2.3),
		Angle(0, 0, 0),
		Vector(2.5, 0.25, 0.25),
		Color(200, 0, 0)
	},
	{
		"arteria", --left artery
		nil,
		Vector(3.5, -2, -2.3),
		Angle(0, 0, 0),
		Vector(2.5, 0.25, 0.25),
		Color(200, 0, 0)
	},
}

local bone = 0.5
male["ValveBiped.Bip01_Spine2"] = {
	{"spine2", spine, Vector(4, -1, 0), Angle(0, 0, 0), Vector(8, 0.5, 0.5), Color(0, 125, 0)},
	{"spineartery", 0, Vector(2, -1, 1), Angle(0, 0, 0), Vector(6, 0.4, 0.4), Color(255, 0, 0)},
	{
		"chest", --right
		bone,
		Vector(5, 6.5, -3.25),
		Angle(0, 0, 0),
		Vector(5, 0.3, 2.5),
		Color(0, 255, 0)
	},
	{
		"chest", --left
		bone,
		Vector(5, 6.25, 3.25),
		Angle(0, 0, 0),
		Vector(5, 0.3, 2.5),
		Color(0, 255, 0)
	},
	{
		"chest", --mid
		bone,
		Vector(6, 6.25, 0),
		Angle(0, 0, 0),
		Vector(4, 0.3, 0.75),
		Color(0, 255, 0)
	},
	{
		"chest", --left side
		bone,
		Vector(4, 3, 5.5),
		Angle(0, 0, 0),
		Vector(6, 4, 0.3),
		Color(0, 255, 0)
	},
	{
		"chest", --right side
		bone,
		Vector(4, 3, -6.2),
		Angle(0, 0, 0),
		Vector(6, 4, 0.3),
		Color(0, 255, 0)
	},
	{
		"chest", --back
		bone,
		Vector(4, -1, 0),
		Angle(0, 0, 0),
		Vector(6, 0.3, 6),
		Color(0, 255, 0)
	},
	{"lungsR", nil, Vector(4, 3, -3), Angle(0, 0, 0), Vector(4, 2, 2), Color(0, 255, 255)},
	{"lungsL", nil, Vector(4, 3, 3), Angle(0, 0, 0), Vector(4, 2, 2), Color(0, 255, 255)},
	{"trachea", nil, Vector(6, 3, 0), Angle(0, 0, 0), Vector(6, 0.75, 0.75), Color(0, 125, 255)},
	{"heart", nil, Vector(1, 2, 1), Angle(0, 0, 0), Vector(1.5, 1.5, 1.5), Color(200, 0, 0)}
}

local bone = 0.5
male["ValveBiped.Bip01_Pelvis"] = {
	{"spine1", spine, Vector(0, 2, -5), Angle(0, 0, 0), Vector(0.5, 5, 0.5), Color(0, 125, 0)},
	{"spineartery", 0, Vector(1, 2, -5), Angle(0, 0, 0), Vector(0.4, 5, 0.4), Color(255, 0, 0)},
	{
		"pelvis", --back
		bone,
		Vector(-4, 1, -4),
		Angle(0, 0, 0),
		Vector(3, 4, 0.5),
		Color(0, 255, 0)
	},
	{
		"pelvis", --back
		bone,
		Vector(4, 1, -4),
		Angle(0, 0, 0),
		Vector(3, 4, 0.5),
		Color(0, 255, 0)
	},
	{
		"pelvis", --left
		bone,
		Vector(6.5, 1, -0.5),
		Angle(0, 0, 0),
		Vector(0.5, 3, 3.5),
		Color(0, 255, 0)
	},
	{
		"pelvis", --right
		bone,
		Vector(-6.5, 1, -0.5),
		Angle(0, 0, 0),
		Vector(0.5, 3, 3.5),
		Color(0, 255, 0)
	},
	{"intestines", nil, Vector(0, 2, 0), Angle(0, 0, 0), Vector(5, 3.5, 3), Color(250, 120, 120)}
}

local bone = 0.5
male["ValveBiped.Bip01_L_UpperArm"] = {{"larmup", bone, Vector(6, 0, 0), Angle(0, 0, 0), Vector(6, 0.8, 0.8), Color(0, 255, 0)}, {"larmartery", 0, Vector(6, 0, -1), Angle(0, 0, 0), Vector(6, 0.1, 0.1), Color(255, 0, 0)},}
male["ValveBiped.Bip01_R_UpperArm"] = {{"rarmup", bone, Vector(6, 0, 0), Angle(0, 0, 0), Vector(6, 0.8, 0.8), Color(0, 255, 0)}, {"rarmartery", 0, Vector(6, 0, 1), Angle(0, 0, 0), Vector(6, 0.1, 0.1), Color(255, 0, 0)},}
male["ValveBiped.Bip01_L_Forearm"] = {{"larmdown", bone, Vector(6, -1, 0), Angle(0, 5, 0), Vector(6, 0.5, 0.5), Color(0, 255, 0)}, {"larmdown", bone, Vector(6, 1, 0), Angle(0, -5, 0), Vector(6, 0.5, 0.5), Color(0, 255, 0)}, {"larmartery", 0, Vector(6, -0.8, 0), Angle(0, 0, 0), Vector(6, 0.1, 0.1), Color(255, 0, 0)}, {"larmartery", 0, Vector(6, 0.8, 0), Angle(0, 0, 0), Vector(6, 0.1, 0.1), Color(255, 0, 0)},}
male["ValveBiped.Bip01_R_Forearm"] = {{"rarmdown", bone, Vector(6, -1, 0), Angle(0, 5, 0), Vector(6, 0.5, 0.5), Color(0, 255, 0)}, {"rarmdown", bone, Vector(6, 1, 0), Angle(0, -5, 0), Vector(6, 0.5, 0.5), Color(0, 255, 0)}, {"rarmartery", 0, Vector(6, -0.8, 0), Angle(0, 0, 0), Vector(6, 0.1, 0.1), Color(255, 0, 0)}, {"rarmartery", 0, Vector(6, 0.8, 0), Angle(0, 0, 0), Vector(6, 0.1, 0.1), Color(255, 0, 0)},}
male["ValveBiped.Bip01_L_Thigh"] = {{"llegup", bone, Vector(9, 0, 0), Angle(0, 0, 0), Vector(9, 1.5, 1.5), Color(0, 255, 0)}, {"llegartery", 0, Vector(9, 2, -1), Angle(0, 0, 0), Vector(9, 0.2, 0.2), Color(255, 0, 0)},}
male["ValveBiped.Bip01_R_Thigh"] = {{"rlegup", bone, Vector(9, 0, 0), Angle(0, 0, 0), Vector(9, 1.5, 1.5), Color(0, 255, 0)}, {"rlegartery", 0, Vector(9, 2, 1), Angle(0, 0, 0), Vector(9, 0.2, 0.2), Color(255, 0, 0)},}
male["ValveBiped.Bip01_L_Calf"] = {{"llegdown", bone, Vector(8, 0, 0), Angle(0, 0, 0), Vector(8, 1.5, 1.5), Color(0, 255, 0)}, {"llegartery", 0, Vector(6, 2, -1), Angle(0, 0, 0), Vector(6, 0.2, 0.2), Color(255, 0, 0)},}
male["ValveBiped.Bip01_R_Calf"] = {{"rlegdown", bone, Vector(8, 0, 0), Angle(0, 0, 0), Vector(8, 1.5, 1.5), Color(0, 255, 0)}, {"rlegartery", 0, Vector(6, 2, 1), Angle(0, 0, 0), Vector(6, 0.2, 0.2), Color(255, 0, 0)},}
local models_female = {
	["models/player/group01/female_01.mdl"] = true,
	["models/player/group01/female_02.mdl"] = true,
	["models/player/group01/female_03.mdl"] = true,
	["models/player/group01/female_04.mdl"] = true,
	["models/player/group01/female_05.mdl"] = true,
	["models/player/group01/female_06.mdl"] = true,
	["models/player/group03/female_01.mdl"] = true,
	["models/player/group03/female_02.mdl"] = true,
	["models/player/group03/female_03.mdl"] = true,
	["models/player/group03/female_04.mdl"] = true,
	["models/player/group03/female_05.mdl"] = true,
	["models/player/group03/police_fem.mdl"] = true
}

table.insert(male["ValveBiped.Bip01_Spine2"],1,{"vest1", 1, Vector(3, 7, 0), Angle(0, 0, 0), Vector(7, 2, 6), Color(250, 255, 0), true, hg.armor.torso["vest1"].protection})
table.insert(male["ValveBiped.Bip01_Spine2"],1,{"vest1", 1, Vector(3, -2.5, 0), Angle(0, 0, 0), Vector(7, 1, 6), Color(250, 255, 0), true, hg.armor.torso["vest1"].protection})

table.insert(male["ValveBiped.Bip01_Spine1"],1,{"vest2", 1, Vector(-4, 2, 0), Angle(0, 0, 0), Vector(5, 7, 7), Color(140, 0, 255), true, hg.armor.torso["vest2"].protection})
table.insert(male["ValveBiped.Bip01_Spine2"],1,{"vest2", 1, Vector(2, 3, 0), Angle(0, 0, 0), Vector(8, 7, 6), Color(183, 0, 255), true, hg.armor.torso["vest2"].protection})

table.insert(male["ValveBiped.Bip01_Spine2"],1,{"vest3", 1, Vector(3, 8, 0), Angle(0, 0, 0), Vector(7, 2, 6), Color(47, 0, 255), true, hg.armor.torso["vest3"].protection})
table.insert(male["ValveBiped.Bip01_Spine2"],1,{"vest3", 1, Vector(3, -2.5, 0), Angle(0, 0, 0), Vector(7, 2, 6), Color(0, 17, 255), true, hg.armor.torso["vest3"].protection})

table.insert(male["ValveBiped.Bip01_Spine2"],1,{"vest4", 1, Vector(3, 8, 0), Angle(0, 0, 0), Vector(7, 2, 6), Color(55, 0, 255), true, hg.armor.torso["vest4"].protection})
table.insert(male["ValveBiped.Bip01_Spine2"],1,{"vest4", 1, Vector(3, -2.5, 0), Angle(0, 0, 0), Vector(7, 2, 6), Color(68, 0, 255), true, hg.armor.torso["vest4"].protection})


table.insert(male["ValveBiped.Bip01_Spine1"],1,{"vest5", 1, Vector(-6, 7, 0), Angle(0, 0, 0), Vector(4, 2, 4), Color(140, 0, 255), true, hg.armor.torso["vest5"].protection})

table.insert(male["ValveBiped.Bip01_Spine2"],1,{"vest5", 1, Vector(3, 7, 0), Angle(0, 0, 0), Vector(8, 2, 5), Color(183, 0, 255), true, hg.armor.torso["vest5"].protection})
table.insert(male["ValveBiped.Bip01_Spine2"],1,{"vest5", 1, Vector(3, -2.5, 0), Angle(0, 0, 0), Vector(8, 2, 5), Color(183, 0, 255), true, hg.armor.torso["vest5"].protection})

table.insert(male["ValveBiped.Bip01_Spine2"],1,{"vest5", 1, Vector(13, 3, 0), Angle(0, 15, 0), Vector(1.5, 4, 4), Color(183, 0, 255), true, hg.armor.torso["vest5"].protection})


table.insert(male["ValveBiped.Bip01_L_UpperArm"],1,{"vest5", 1, Vector(3, -1, 2), Angle(0, 0, 0), Vector(5, 2, 1), Color(183, 0, 255), true, hg.armor.torso["vest5"].protection})
table.insert(male["ValveBiped.Bip01_R_UpperArm"],1,{"vest5", 1, Vector(3, -1, -2), Angle(0, 0, 0), Vector(5, 2, 1), Color(183, 0, 255), true, hg.armor.torso["vest5"].protection})

table.insert(male["ValveBiped.Bip01_Head1"],1,{"helmet1", 1, Vector(6.5, -0.9, 0), Angle(0, 12, 0), Vector(2.7, 7, 4.5), Color(250, 255, 0), true, hg.armor.head["helmet1"].protection})
table.insert(male["ValveBiped.Bip01_Head1"],1,{"helmet2", 1, Vector(3.5, -0.9, 0), Angle(0, 0, 0), Vector(5, 6, 5.5), Color(255, 255, 0), true, hg.armor.head["helmet2"].protection})
table.insert(male["ValveBiped.Bip01_Head1"],1,{"helmet3", 1, Vector(3.5, -0.9, 0), Angle(0, 0, 0), Vector(5, 6, 5.5), Color(255, 255, 0), true, hg.armor.head["helmet3"].protection})

table.insert(male["ValveBiped.Bip01_Head1"],1,{"helmet5", 1, Vector(6.5, -1, 0), Angle(0, 20, 0), Vector(2.7, 6, 4.5), Color(250, 255, 0), true, hg.armor.head["helmet5"].protection})
table.insert(male["ValveBiped.Bip01_Head1"],1,{"helmet5", 1, Vector(1, 2, 0), Angle(0, 0, 0), Vector(1.5, 1.7, 4.5), Color(250, 255, 0), true, hg.armor.head["helmet5"].protection})

table.insert(male["ValveBiped.Bip01_Head1"],1,{"helmet7", 1, Vector(6.5, -0.9, 0), Angle(0, 12, 0), Vector(2.7, 7, 4.5), Color(250, 255, 0), true, hg.armor.head["helmet1"].protection})

table.insert(male["ValveBiped.Bip01_Head1"],1,{"mask1", 1, Vector(3.5, -4, 0), Angle(0, 0, 0), Vector(5, 3, 4.5), Color(255, 0, 221), true, hg.armor.face["mask1"].protection})

table.insert(male["ValveBiped.Bip01_Head1"],1,{"mask3", 1, Vector(3.5, -4, 0), Angle(0, 0, 0), Vector(5, 3, 4.5), Color(255, 0, 221), true, hg.armor.face["mask3"].protection})
-- Vest 6
table.insert(male["ValveBiped.Bip01_Spine2"],1,{"vest6", 1, Vector(3, 8, 0), Angle(0, 0, 0), Vector(7, 1, 6), Color(55, 0, 255), true, hg.armor.torso["vest6"].protection})
table.insert(male["ValveBiped.Bip01_Spine2"],1,{"vest6", 1, Vector(3, -2.5, 0), Angle(0, 0, 0), Vector(7, 1, 6), Color(68, 0, 255), true, hg.armor.torso["vest6"].protection})
table.insert(male["ValveBiped.Bip01_Spine2"],1,{"vest6", 1, Vector(-2, 3, 6), Angle(0, 0, 90), Vector(3, 0.5, 4), Color(255, 242, 0), true, hg.armor.torso["vest6"].protection})
table.insert(male["ValveBiped.Bip01_Spine2"],1,{"vest6", 1, Vector(-2, 3, -6), Angle(0, 0, 90), Vector(3, 0.5, 4), Color(255, 242, 0), true, hg.armor.torso["vest6"].protection})
-- Vest 7
table.insert(male["ValveBiped.Bip01_Spine2"],1,{"vest7", 1, Vector(3, 8, 0), Angle(0, 0, 0), Vector(7, 1, 6), Color(55, 0, 255), true, hg.armor.torso["vest7"].protection})
table.insert(male["ValveBiped.Bip01_Spine2"],1,{"vest7", 1, Vector(3, -2.5, 0), Angle(0, 0, 0), Vector(7, 1, 6), Color(68, 0, 255), true, hg.armor.torso["vest7"].protection})
table.insert(male["ValveBiped.Bip01_Spine2"],1,{"vest7", 1, Vector(-2, 3, 6), Angle(0, 0, 90), Vector(3, 0.5, 4), Color(255, 242, 0), true, hg.armor.torso["vest7"].protection})
table.insert(male["ValveBiped.Bip01_Spine2"],1,{"vest7", 1, Vector(-2, 3, -6), Angle(0, 0, 90), Vector(3, 0.5, 4), Color(255, 242, 0), true, hg.armor.torso["vest7"].protection})
-- Vest 8 
table.insert(male["ValveBiped.Bip01_Spine2"],1,{"vest8", 1, Vector(3, 8, 0), Angle(0, 0, 0), Vector(7, 2, 6), Color(55, 0, 255), true, hg.armor.torso["vest8"].protection})
table.insert(male["ValveBiped.Bip01_Spine2"],1,{"vest8", 1, Vector(3, -2.5, 0), Angle(0, 0, 0), Vector(7, 2, 6), Color(68, 0, 255), true, hg.armor.torso["vest8"].protection})
table.insert(male["ValveBiped.Bip01_Spine2"],1,{"vest8", 1, Vector(-2, 3, 6), Angle(0, 0, 90), Vector(3, 2, 4), Color(255, 242, 0), true, hg.armor.torso["vest8"].protection})
table.insert(male["ValveBiped.Bip01_Spine2"],1,{"vest8", 1, Vector(-2, 3, -6), Angle(0, 0, 90), Vector(3, 2, 4), Color(255, 242, 0), true, hg.armor.torso["vest8"].protection})

table.insert(male["ValveBiped.Bip01_Spine1"],1,{"vest8", 1, Vector(-5, 7, 0), Angle(0, 0, 0), Vector(3, 2, 7), Color(55, 0, 255), true, hg.armor.torso["vest8"].protection})
table.insert(male["ValveBiped.Bip01_Spine2"],1,{"vest8", 1, Vector(-7, -2.5, 0), Angle(0, 0, 0), Vector(3, 2, 6), Color(68, 0, 255), true, hg.armor.torso["vest8"].protection})

table.insert(male["ValveBiped.Bip01_Head1"],1,{"helmet6", 1, Vector(6.5, -1, 0), Angle(0, 15, 0), Vector(2.7, 6, 4.5), Color(250, 255, 0), true, hg.armor.head["helmet6"].protection})
--table.insert(male["ValveBiped.Bip01_Head1"],1,{"helmet6", 1, Vector(1, 2, 0), Angle(0, 0, 0), Vector(1.5, 1.7, 4.5), Color(250, 255, 0), true, hg.armor.head["helmet6"].protection})
local female = {}
table.CopyFromTo(male, female)

female["ValveBiped.Bip01_Head1"] = {
	{
		"skull", --bone
		0.5,
		Vector(4.5, 0, 0),
		Angle(0, 0, 0),
		Vector(2.5, 4.8, 3.2),
		Color(0, 255, 0)
	},
	{
		"skull", --bone niz
		0.5,
		Vector(0, 3, 0),
		Angle(0, 0, 0),
		Vector(2, 1.4, 2.5),
		Color(0, 255, 0)
	},
	{
		"jaw", --jaw
		0.4, -- owner 2026-09-23: was 0.05; ballistics v2 walks >= 0.2 as bone
		Vector(0, -1.5, 0),
		Angle(0, 0, 0),
		Vector(2, 3, 2),
		Color(0, 255, 0)
	},
	{
		"brain", --brain
		nil,
		Vector(4.4, -0, 0),
		Angle(0, 0, 0),
		Vector(2.1, 4.3, 2.8),
		Color(255, 0, 255)
	},
	{
		"brain", --brain niz
		nil,
		Vector(0.5, 2, 0),
		Angle(0, 0, 0),
		Vector(1.6, 2.1, 1.7),
		Color(255, 0, 255)
	},
}

female["ValveBiped.Bip01_Neck1"] = {
	{
		"spine3", --spine3 neck
		spine,
		Vector(1, 1, 0),
		Angle(0, 0, 0),
		Vector(2, 0.5, 0.5),
		Color(0, 125, 0)
	},
	{"trachea", nil, Vector(2, -2, 0), Angle(0, 0, 0), Vector(2, 0.5, 0.5), Color(0, 125, 255)},
	{
		"arteria", --right artery
		nil,
		Vector(1.5, -2, 2.3),
		Angle(0, 0, 0),
		Vector(2.5, 0.25, 0.25),
		Color(200, 0, 0)
	},
	{
		"arteria", --left artery
		nil,
		Vector(1.5, -2, -2.3),
		Angle(0, 0, 0),
		Vector(2.5, 0.25, 0.25),
		Color(200, 0, 0)
	},
}

table.insert(female["ValveBiped.Bip01_Head1"],1,{"helmet1", 1, Vector(6.5, -0.9, 0), Angle(0, 12, 0), Vector(2.7, 7, 4.5), Color(250, 255, 0), true, hg.armor.head["helmet1"].protection})
table.insert(female["ValveBiped.Bip01_Head1"],1,{"helmet2", 1, Vector(3.5, -0.9, 0), Angle(0, 0, 0), Vector(5, 6, 5.5), Color(255, 255, 0), true, hg.armor.head["helmet2"].protection})
table.insert(female["ValveBiped.Bip01_Head1"],1,{"helmet3", 1, Vector(3.5, -0.9, 0), Angle(0, 0, 0), Vector(5, 6, 5.5), Color(255, 255, 0), true, hg.armor.head["helmet3"].protection})
table.insert(female["ValveBiped.Bip01_Head1"],1,{"helmet5", 1, Vector(5.5, 0.4, 0), Angle(0, 10, 0), Vector(2.7, 6, 4.5), Color(250, 255, 0), true, hg.armor.head["helmet5"].protection})
table.insert(female["ValveBiped.Bip01_Head1"],1,{"helmet5", 1, Vector(1, 3.5, 0), Angle(0, 0, 0), Vector(1.5, 1.7, 4.5), Color(250, 255, 0), true, hg.armor.head["helmet5"].protection})

table.insert(female["ValveBiped.Bip01_Head1"],1,{"mask1", 1, Vector(3.5, -4, 0), Angle(0, 0, 0), Vector(5, 3, 4.5), Color(255, 0, 221), true, hg.armor.face["mask1"].protection})

--[[for i,tbl in pairs(male) do
	for i,tbl2 in pairs(tbl) do
		print('["'..tbl2[1]..'"] = ,')
	end
end--]]

hg.organism.translationTbl = {
	["vest5"] = "Armored vest",
	["vest4"] = "Armored vest",
	["vest4"] = "Armored vest",
	["vest3"] = "Armored vest",
	["vest3"] = "Armored vest",
	["vest2"] = "Armored vest",
	["vest1"] = "Armored vest",
	["vest1"] = "Armored vest",
	["spine2"] = "Upper spine",
	["spineartery"] = "Spine artery",
	["chest"] = "Ribs",
	["lungsR"] = "Left lung",
	["lungsL"] = "Right lung",
	["trachea"] = "Trachea",
	["heart"] = "Heart",
	["llegup"] = "Left thigh",
	["llegartery"] = "Left leg artery",
	["spine3"] = "Neck",
	["mask1"] = "Mask",
	["helmet3"] = "Helmet",
	["helmet2"] = "Helmet",
	["helmet1"] = "Helmet",
	["skull"] = "Skull",
	["jaw"] = "Jaw",
	["brain"] = "Brain",
	["arteria"] = "Carotid artery",
	["larmdown"] = "Left forearm",
	["larmartery"] = "Left arm artery",
	["larmup"] = "Left upperarm",
	["rlegdown"] = "Right calf",
	["liver"] = "Liver",
	["stomach"] = "Stomach",
	["llegdown"] = "Left calf",
	["rlegup"] = "Right thigh",
	["rlegartery"] = "Right leg artery",
	["spine1"] = "Lower spine",
	["pelvis"] = "Pelvis",
	["intestines"] = "Intestines",
	["rarmdown"] = "Right forearm",
	["rarmup"] = "Right upperarm",
	["rarmartery"] = "Right arm artery",
	["kidneyR"] = "Right kidney",
	["kidneyL"] = "Left kidney",
	["spleen"] = "Spleen",
	["bladder"] = "Bladder",
}

--[[local gordon = {}
gordon["ValveBiped.Bip01_Spine1"] = table.Copy(male["ValveBiped.Bip01_Spine1"])
gordon["ValveBiped.Bip01_Head1"] = table.Copy(male["ValveBiped.Bip01_Head1"])
gordon["ValveBiped.Bip01_Neck1"] = table.Copy(male["ValveBiped.Bip01_Neck1"])
gordon["ValveBiped.Bip01_Spine2"] = table.Copy(male["ValveBiped.Bip01_Spine2"])
gordon["ValveBiped.Bip01_Pelvis"] = table.Copy(male["ValveBiped.Bip01_Pelvis"])
gordon["ValveBiped.Bip01_L_UpperArm"] = table.Copy(male["ValveBiped.Bip01_L_UpperArm"])
gordon["ValveBiped.Bip01_R_UpperArm"] = table.Copy(male["ValveBiped.Bip01_R_UpperArm"])
gordon["ValveBiped.Bip01_L_Forearm"] = table.Copy(male["ValveBiped.Bip01_L_Forearm"])
gordon["ValveBiped.Bip01_R_Forearm"] = table.Copy(male["ValveBiped.Bip01_R_Forearm"])
gordon["ValveBiped.Bip01_L_Thigh"] = table.Copy(male["ValveBiped.Bip01_L_Thigh"])
gordon["ValveBiped.Bip01_R_Thigh"] = table.Copy(male["ValveBiped.Bip01_R_Thigh"])
gordon["ValveBiped.Bip01_L_Calf"] = table.Copy(male["ValveBiped.Bip01_L_Calf"])
gordon["ValveBiped.Bip01_R_Calf"] = table.Copy(male["ValveBiped.Bip01_R_Calf"])
--]]
table.insert(male["ValveBiped.Bip01_Head1"],1,{"gordon_helmet", 1, Vector(3, -1.5, 0), Angle(0, 0, 0), Vector(6, 6, 4), Color(250, 255, 0), true, 9})
table.insert(male["ValveBiped.Bip01_Spine2"],1,{"gordon_armor", 1, Vector(3,2,0), Angle(0, 0, 90), Vector(11,7,6), Color(255, 242, 0), true, 10})

table.insert(male["ValveBiped.Bip01_L_Forearm"], 1, {"gordon_armor", 1, Vector(3, -1, 0), Angle(0, 0, 90), Vector(5, 4, 4), Color(255, 242, 0), true, 11})
table.insert(male["ValveBiped.Bip01_R_Forearm"], 1, {"gordon_armor", 1, Vector(3, -1, 0), Angle(0, 0, 90), Vector(5, 4, 4), Color(255, 242, 0), true, 12})

table.insert(male["ValveBiped.Bip01_L_Thigh"], 1, {"gordon_armor", 1, Vector(4, 0, 0), Angle(0, 0, 90), Vector(8, 6, 5), Color(255, 242, 0), true, 13})
table.insert(male["ValveBiped.Bip01_R_Thigh"], 1, {"gordon_armor", 1, Vector(4, 0, 0), Angle(0, 0, 90), Vector(8, 6, 5), Color(255, 242, 0), true, 14})

table.insert(male["ValveBiped.Bip01_L_Calf"], 1, {"gordon_armor", 1, Vector(4, -1, 0), Angle(0, 0, 90), Vector(6, 5, 4), Color(255, 242, 0), true, 15})
table.insert(male["ValveBiped.Bip01_R_Calf"], 1, {"gordon_armor", 1, Vector(4, -1, 0), Angle(0, 0, 90), Vector(6, 5, 4), Color(255, 242, 0), true, 16})
--не нужно добавлять в female потому что гордон это не female

--[[local combine = {}
combine["ValveBiped.Bip01_Spine1"] = table.Copy(male["ValveBiped.Bip01_Spine1"])
combine["ValveBiped.Bip01_Head1"] = table.Copy(male["ValveBiped.Bip01_Head1"])
combine["ValveBiped.Bip01_Neck1"] = table.Copy(male["ValveBiped.Bip01_Neck1"])
combine["ValveBiped.Bip01_Spine2"] = table.Copy(male["ValveBiped.Bip01_Spine2"])
combine["ValveBiped.Bip01_Pelvis"] = table.Copy(male["ValveBiped.Bip01_Pelvis"])
combine["ValveBiped.Bip01_L_UpperArm"] = table.Copy(male["ValveBiped.Bip01_L_UpperArm"])
combine["ValveBiped.Bip01_R_UpperArm"] = table.Copy(male["ValveBiped.Bip01_R_UpperArm"])
combine["ValveBiped.Bip01_L_Forearm"] = table.Copy(male["ValveBiped.Bip01_L_Forearm"])
combine["ValveBiped.Bip01_R_Forearm"] = table.Copy(male["ValveBiped.Bip01_R_Forearm"])
combine["ValveBiped.Bip01_L_Thigh"] = table.Copy(male["ValveBiped.Bip01_L_Thigh"])
combine["ValveBiped.Bip01_R_Thigh"] = table.Copy(male["ValveBiped.Bip01_R_Thigh"])
combine["ValveBiped.Bip01_L_Calf"] = table.Copy(male["ValveBiped.Bip01_L_Calf"])
combine["ValveBiped.Bip01_R_Calf"] = table.Copy(male["ValveBiped.Bip01_R_Calf"])--]]

table.insert(male["ValveBiped.Bip01_Head1"],1,{"cmb_helmet", 1, Vector(3, -1.5, 0), Angle(0, 0, 0), Vector(6, 6, 4), Color(250, 255, 0), true, 7})
table.insert(male["ValveBiped.Bip01_Spine2"],1,{"cmb_armor", 1, Vector(3,2,0), Angle(0, 0, 90), Vector(11,7,6), Color(255, 242, 0), true, 7})

table.insert(male["ValveBiped.Bip01_L_Forearm"], 1, {"cmb_armor", 1, Vector(3, -1, 0), Angle(0, 0, 90), Vector(5, 4, 4), Color(255, 242, 0), true, 7})
table.insert(male["ValveBiped.Bip01_R_Forearm"], 1, {"cmb_armor", 1, Vector(3, -1, 0), Angle(0, 0, 90), Vector(5, 4, 4), Color(255, 242, 0), true, 8})

table.insert(male["ValveBiped.Bip01_L_UpperArm"], 1, {"cmb_armor", 1, Vector(3, -1, 0), Angle(0, 0, 90), Vector(5, 4, 4), Color(255, 242, 0), true, 8})
table.insert(male["ValveBiped.Bip01_R_UpperArm"], 1, {"cmb_armor", 1, Vector(3, -1, 0), Angle(0, 0, 90), Vector(5, 4, 4), Color(255, 242, 0), true, 8})

table.insert(male["ValveBiped.Bip01_L_Thigh"], 1, {"cmb_armor", 1, Vector(4, 0, 0), Angle(0, 0, 90), Vector(8, 6, 5), Color(255, 242, 0), true, 7})
table.insert(male["ValveBiped.Bip01_R_Thigh"], 1, {"cmb_armor", 1, Vector(4, 0, 0), Angle(0, 0, 90), Vector(8, 6, 5), Color(255, 242, 0), true, 7})

table.insert(male["ValveBiped.Bip01_Head1"],1,{"protovisor", 1, Vector(3, -1.5, 0), Angle(0, 0, 0), Vector(6, 6, 4), Color(20, 135, 155), true, 7})

--table.insert(combine["ValveBiped.Bip01_L_Calf"], 1, {"cmb_calf_armor_left", 1, Vector(4, -1, 0), Angle(0, 0, 90), Vector(6, 5, 4), Color(255, 242, 0), false, 15})
--table.insert(combine["ValveBiped.Bip01_R_Calf"], 1, {"cmb_calf_armor_right", 1, Vector(4, -1, 0), Angle(0, 0, 90), Vector(6, 5, 4), Color(255, 242, 0), false, 16})

table.insert(male["ValveBiped.Bip01_Head1"],1,{"metrocop_helmet", 1, Vector(3, -1.5, 0), Angle(0, 0, 0), Vector(6, 6, 4), Color(250, 255, 0), true, 7})
table.insert(male["ValveBiped.Bip01_Spine2"],1,{"metrocop_armor", 1, Vector(3,2,0), Angle(0, 0, 90), Vector(11,7,6), Color(255, 242, 0), true, 7})

local cmb_mdls = {
	["models/romka/player/combine_super_soldier.mdl"] = true,
	["models/romka/player/combine_soldier.mdl"] = true
}

-- ORGANS V2 (organs_20260925, 2026-09-25): torso organs fitted to the ValveBiped bones as dumped from the live player
-- models (idle male_04 / eli: Spine2 chest hitbox X -2.75..11.75 up, Y -2.5..7.5 forward, Z +-7 = left; the Spine bone
-- sits 7.5 in below Spine2 with the same axes; Pelvis X = left, Y = up, Z = forward). Places and sizes are the
-- anatomical proportions of a 72 in male; every number is PROVISIONAL(2026-09-25, fitted offline against the bone
-- dump, not yet seen in game with hg_show_hitbox, ratify-by: 2026-10-09). The legacy rows above stay untouched:
-- hg_organs_v2 0 hands them back without a reload (replicated, so client previews and the killcam agree).
-- Rows keep the legacy shape {name, hardness, offset, angle, half-extents, colour, armor?, protection?}; `label` is a
-- string key nothing indexes by number (display name for the killcam / statistics screens).
local cvOrgans = ConVarExists("hg_organs_v2") and GetConVar("hg_organs_v2") or CreateConVar("hg_organs_v2", "1", FCVAR_ARCHIVE + FCVAR_REPLICATED, "Organ hitboxes: 0 legacy boxes, 1 fitted organ shapes (ellipsoids / capsules) with kidneys, spleen, bladder", 0, 1)
-- ORGANS V3 (organs2_20260925): the same fitted places, now with shapes (V2.RayShape): soft organs are ellipsoids of
-- anatomical size (adult male, inches: heart 4.8 x 3.4 x 2.6, lung 10 x 6 x 4.6, liver 6 x 5.4 x 5.2 ...), bones /
-- vessels / airway are capsules, rib and pelvis plates stay boxes. One ellipsoid per lung: two stacked lobes either
-- leave a gap at their waist or overlap, and an overlap fires the organ's handler twice for one round.
-- Limb bones, limb arteries, the neck rows and the legacy head rows keep their legacy cross-section AREA as capsules
-- (r = 2 sqrt(hy hz / pi)), so how often a limb shot breaks a bone or opens an artery stays as it was; anatomical
-- limb sizes would cut those rates by about two thirds and are the owner's call.
-- PROVISIONAL(2026-09-25, fitted offline against the live bone dump with the organ gate's reach / overlap / landmark
-- shots, not yet seen in game with hg_show_hitbox, ratify-by: 2026-10-09)
local E, CAP = "ellipsoid", "capsule"
local function row(shape, name, hardness, x, y, z, hx, hy, hz, color, label, p, yaw, r)
	local t = {name, hardness, Vector(x, y, z), Angle(p or 0, yaw or 0, r or 0), Vector(hx, hy, hz), color}
	t.label, t.shape = label, shape
	return t
end
local C_BONE, C_LUNG, C_HEART, C_ART, C_TRACH = Color(0, 255, 0), Color(0, 255, 255), Color(200, 0, 0), Color(255, 0, 0), Color(0, 125, 255)
local C_LIVER, C_STOM, C_GUT, C_KID, C_SPL, C_BLAD = Color(125, 50, 0), Color(255, 125, 0), Color(250, 120, 120), Color(160, 60, 90), Color(120, 30, 60), Color(230, 200, 80)
local C_BRAIN = Color(255, 0, 255)
local ORGANS2 = {}
-- Spine2 frame: X up, Y forward, Z left (chest hitbox X -2.75..11.75, Y -2.5..7.5, Z +-7)
ORGANS2["ValveBiped.Bip01_Spine2"] = {
	row(CAP, "spine2", spine, 4, -0.5, 0, 8, 0.7, 0.7, C_BONE, "Upper spine"),
	row(CAP, "spineartery", 0, 1, 1, 0.8, 5, 0.5, 0.5, C_ART, "Aorta"),
	row(CAP, "spineartery", 0, 7.5, 2.2, 0.3, 1, 1, 1, C_ART, "Aortic arch"),
	-- the front plates stop short of the side walls: plates of one organ that overlap fire its handler twice
	row(nil, "chest", bone, 5, 6.5, -3.2, 5, 0.3, 2.45, C_BONE, "Ribs, right front"),
	row(nil, "chest", bone, 5, 6.25, 3.0, 5, 0.3, 2.25, C_BONE, "Ribs, left front"),
	row(nil, "chest", bone, 6, 6.25, 0, 4, 0.3, 0.75, C_BONE, "Sternum"),
	-- the side walls: full depth above the costal margin, shallower below it (the cage closes toward the front)
	row(nil, "chest", bone, 6, 3, 5.6, 4, 4, 0.3, C_BONE, "Ribs, left side"),
	row(nil, "chest", bone, -0.5, 1.75, 5.6, 2.5, 2.75, 0.3, C_BONE, "Ribs, left side, lower"),
	row(nil, "chest", bone, 6, 3, -6.2, 4, 4, 0.3, C_BONE, "Ribs, right side"),
	row(nil, "chest", bone, -0.5, 1.75, -6.2, 2.5, 2.75, 0.3, C_BONE, "Ribs, right side, lower"),
	row(nil, "chest", bone, 4, -1.3, 0, 6, 0.3, 6, C_BONE, "Ribs, back"),
	row(E, "lungsR", nil, 5.5, 3, -3.6, 5, 3, 2.3, C_LUNG, "Right lung"),
	row(E, "lungsL", nil, 5.6, 2.9, 3.9, 4.8, 2.8, 2, C_LUNG, "Left lung"),
	row(CAP, "trachea", nil, 8.75, 3.2, 0, 1.75, 0.45, 0.45, C_TRACH, "Trachea"),
	-- base up and to the right, apex down, left and forward (pitch +35 = top toward the right, yaw -15 = top toward the
	-- back), behind the sternum, two thirds left of the midline; ONE shape (an overlap would double-fire the handler)
	row(E, "heart", nil, 2.2, 4, 0.9, 2.4, 1.3, 1.7, C_HEART, "Heart", 35, -15, 0),
}
-- Spine frame: the same axes, 7.5 in below Spine2
ORGANS2["ValveBiped.Bip01_Spine"] = {
	row(E, "liver", nil, 4.3, 3.6, -3.2, 2.7, 2.6, 3, C_LIVER, "Liver, right lobe"),
	row(E, "liver", nil, 5, 4.3, 1.4, 1.6, 1.5, 1.8, C_LIVER, "Liver, left lobe"),
	row(E, "stomach", nil, 3.2, 3.6, 4.2, 2.3, 1.9, 2, C_STOM, "Stomach"),
	row(E, "spleen", nil, 4.2, 0.8, 5.3, 2.2, 1.3, 0.8, C_SPL, "Spleen"),
	row(E, "kidneyR", nil, 0.4, 0.4, -2.7, 2.1, 0.7, 1.1, C_KID, "Right kidney"),
	row(E, "kidneyL", nil, 1.1, 0.4, 2.7, 2.1, 0.7, 1.1, C_KID, "Left kidney"),
}
-- Pelvis frame: X left, Y up, Z forward
ORGANS2["ValveBiped.Bip01_Pelvis"] = {
	row(CAP, "spine1", spine, 0, 2, -5, 0.7, 5, 0.7, C_BONE, "Lower spine"),
	row(CAP, "spineartery", 0, 1, 2, -4, 0.5, 5, 0.5, C_ART, "Aorta, abdominal"),
	row(nil, "pelvis", bone, -4, 1, -4, 3, 4, 0.5, C_BONE, "Pelvis, back right"),
	row(nil, "pelvis", bone, 4, 1, -4, 3, 4, 0.5, C_BONE, "Pelvis, back left"),
	row(nil, "pelvis", bone, 6.5, 1, 0.1, 0.5, 3, 2.9, C_BONE, "Hip, left"), -- clear of the back plates
	row(nil, "pelvis", bone, -6.5, 1, 0.1, 0.5, 3, 2.9, C_BONE, "Hip, right"),
	row(E, "intestines", nil, 0, 2.8, 1, 5, 3.4, 2.5, C_GUT, "Intestines"),
	row(E, "bladder", nil, 0, -1.8, 2.6, 1.5, 1.2, 1.3, C_BLAD, "Bladder"),
}
-- Head1 frame (male): X up, Y back, Z right. The skull and jaw stay the legacy boxes; the brain is an ellipsoid of
-- brain size (7 in front to back, the legacy box ran 8.6) with the brainstem / cerebellum as a second one below it.
ORGANS2["ValveBiped.Bip01_Head1"] = {
	row(nil, "skull", 0.5, 5.5, -1.5, 0, 2.5, 4.8, 3.2, Color(0, 255, 0), "Skull"),
	row(nil, "skull", 0.5, 1, 1.5, 0, 2, 1.4, 2.5, Color(0, 255, 0), "Skull, base"),
	row(nil, "jaw", 0.5, 1, -3, 0, 2, 3, 2, Color(0, 255, 0), "Jaw"),
	row(E, "brain", nil, 5.4, -1.5, 0, 2.6, 3.4, 2.8, C_BRAIN, "Brain"),
	row(E, "brain", nil, 1.6, 0.4, 0, 1.4, 1.7, 1.5, C_BRAIN, "Brainstem and cerebellum"),
}
local SHAPE_BY_NAME = {
	brain = E, spine1 = CAP, spine2 = CAP, spine3 = CAP, spineartery = CAP, trachea = CAP, arteria = CAP,
	larmup = CAP, rarmup = CAP, larmdown = CAP, rarmdown = CAP, llegup = CAP, rlegup = CAP, llegdown = CAP, rlegdown = CAP,
	larmartery = CAP, rarmartery = CAP, llegartery = CAP, rlegartery = CAP,
}
local LABEL_BY_NAME = {spine3 = "Neck vertebrae", arteria = "Carotid artery", trachea = "Trachea", brain = "Brain"}
-- legacy rows trimmed so one organ's shapes never overlap: the thigh arteries stop at the knee, where the calf rows begin
-- (male thigh 17.9 in, female 15.9 in: the idle dumps)
local TRIM = {
	["ValveBiped.Bip01_L_Thigh"] = {llegartery = {8.5, 8.5}}, ["ValveBiped.Bip01_R_Thigh"] = {rlegartery = {8.5, 8.5}},
}
local TRIM_F = {
	["ValveBiped.Bip01_L_Thigh"] = {llegartery = {7.5, 7.5}}, ["ValveBiped.Bip01_R_Thigh"] = {rlegartery = {7.5, 7.5}},
}
-- a legacy row as a shape: capsules keep the box's cross-section area; ellipsoids keep the box's extents
local function shapedCopy(r, boneName, trims)
	local t = table.Copy(r)
	trims = trims or TRIM
	local trim = trims[boneName] and trims[boneName][r[1]]
	if trim then t[3] = Vector(trim[1], r[3].y, r[3].z) t[5] = Vector(trim[2], r[5].y, r[5].z) end
	local shape = SHAPE_BY_NAME[r[1]]
	if not shape or r[7] then return t end
	t.shape = shape
	t.label = t.label or LABEL_BY_NAME[r[1]]
	if shape == CAP then
		local hx, hy, hz = t[5].x, t[5].y, t[5].z
		if hx >= hy and hx >= hz then t[5] = Vector(hx, 2 * math.sqrt(hy * hz / math.pi), 2 * math.sqrt(hy * hz / math.pi))
		elseif hy >= hz then t[5] = Vector(2 * math.sqrt(hx * hz / math.pi), hy, 2 * math.sqrt(hx * hz / math.pi))
		else t[5] = Vector(2 * math.sqrt(hx * hy / math.pi), 2 * math.sqrt(hx * hy / math.pi), hz) end
	end
	return t
end
local function armorRows(rows)
	local out = {}
	for _, r in ipairs(rows) do if r[7] then out[#out + 1] = r end end
	return out
end
-- every bone: armor rows kept as they are; ORGANS2's bones get their new rows, the rest become shaped copies
local function withOrgans(base, torso, trims)
	local out = {}
	for boneName, rows in pairs(base) do
		local list = armorRows(rows)
		local own = torso[boneName]
		if own then
			for _, r in ipairs(own) do list[#list + 1] = r end
		else
			for _, r in ipairs(rows) do if not r[7] then list[#list + 1] = shapedCopy(r, boneName, trims) end end
		end
		out[boneName] = list
	end
	for boneName, rows in pairs(torso) do
		if not out[boneName] then out[boneName] = rows end
	end
	return out
end
-- the female frame (slav/f models, idle dump): chest hitbox 9 x 10 x 12 against the male 14.5 x 10 x 14, Spine2->Spine4
-- 7.5 in against 8.9, pelvis 11 wide against 15: organ offsets and extents scale with the frame, armor rows do not
local function scaledRows(rows, sx, sy, sz)
	local out = {}
	for i, r in ipairs(rows) do
		if r[7] then
			out[i] = r
		else
			local t = table.Copy(r)
			t[3] = Vector(r[3].x * sx, r[3].y * sy, r[3].z * sz)
			t[5] = Vector(r[5].x * sx, r[5].y * sy, r[5].z * sz)
			out[i] = t
		end
	end
	return out
end
local male2 = withOrgans(male, ORGANS2)
local female2 = withOrgans(female, {}, TRIM_F)
female2["ValveBiped.Bip01_Spine2"] = scaledRows(male2["ValveBiped.Bip01_Spine2"], 0.86, 1, 0.86)
female2["ValveBiped.Bip01_Spine"] = scaledRows(male2["ValveBiped.Bip01_Spine"], 0.95, 1, 0.9)
female2["ValveBiped.Bip01_Pelvis"] = scaledRows(male2["ValveBiped.Bip01_Pelvis"], 0.75, 0.9, 0.75) -- the female lower back sits further forward (Spine1 hitbox reaches 2.7 in behind the bone, the male chest box 2.5 + a deeper pelvis box)
for _, r in ipairs(female2["ValveBiped.Bip01_Pelvis"]) do
	if r[1] == "spine1" then r[3] = Vector(r[3].x, r[3].y, r[3].z * 0.88) end -- her lumbar column a little further forward still (the gate's reach check)
end
-- her head: the legacy female rows are the male rows 1 in lower and 1.5 in further back at the same sizes, so the
-- refined male head moves the same way (her jaw keeps its 0.4 hardness, owner 2026-09-23)
do
	local list = armorRows(female["ValveBiped.Bip01_Head1"] or {})
	for _, r in ipairs(ORGANS2["ValveBiped.Bip01_Head1"]) do
		local t = table.Copy(r)
		t[3] = Vector(r[3].x - 1, r[3].y + 1.5, r[3].z)
		if t[1] == "jaw" then t[2] = 0.4 end
		list[#list + 1] = t
	end
	female2["ValveBiped.Bip01_Head1"] = list
end
-- US1's player models live under models/slav/m/ and models/slav/f/: the group01/group03 list above never matched them,
-- so every female model has used the male table until now (legacy path unchanged when hg_organs_v2 is 0).
local function isFemaleModel(model)
	if models_female[model] then return true end
	if not isstring(model) then return false end
	return string.find(model, "female", 1, true) ~= nil or string.find(model, "/f/", 1, true) ~= nil
end
hg.organism.OrganTables = {male = male, female = female, male2 = male2, female2 = female2} -- read-only, for gates and tools
function hg.organism.IsFemaleModel(model) return isFemaleModel(model) end
function hg.organism.GetHitBoxOrgans(model, ent)
	if cvOrgans:GetBool() then return isFemaleModel(model) and female2 or male2 end
	return (models_female[model] and female) or male
end
-- Display name of an organ row: its label, else the translation table, else the raw name.
function hg.organism.OrganLabel(organ)
	if not istable(organ) then return "?" end
	if isstring(organ.label) then return organ.label end
	local tbl = hg.organism.translationTbl
	return (istable(tbl) and tbl[organ[1]]) or tostring(organ[1])
end