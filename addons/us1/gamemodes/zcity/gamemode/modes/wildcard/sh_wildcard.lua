MODE.name = "wildcard"
MODE.PrintName = "Wildcard"

MODE.Chance = 0.05

MODE.LootSpawn = false
MODE.ForBigMaps = false

function MODE.GuiltCheck(Attacker, Victim, add, harm, amt)
	return 1, true
end
