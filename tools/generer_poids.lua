-- Génère Core/Poids.lua à partir de Pawn_Forever/Weights.lua (https://github.com/turlockmike/pawn-forever, licence MIT).
-- Usage : luajit tools/generer_poids.lua <Pawn_Forever/Weights.lua>
-- Pawn Forever donne des poids par spécialisation tirés de GearQuest Forever (Henrik8210) : par point de stat, et par 1 % pour
-- le critique, le toucher, la hâte, l'esquive, la parade et le blocage. On les ramène au point de score (rating) avec les valeurs
-- relevées sur les infobulles de Forever, et on les indexe par ItemStatType (les numéros de Core/Ameliorations.lua).
local PF = {}
assert(loadfile(assert(arg[1])))("Pawn_Forever", PF)

local PAR_POURCENT = { CritRating = 14, HitRating = 10, HasteRating = 10, DodgeRating = 12, ParryRating = 15, BlockRating = 5,
	ExpertiseRating = 14 } -- expertise : même budget que le critique (voir le README de Pawn Forever)
-- clé de Pawn → types d'ItemStatType qui la portent
local TYPES = {
	Strength = { 4 }, Agility = { 3 }, Stamina = { 7 }, Intellect = { 5 }, Spirit = { 6 }, Ap = { 38 }, Rap = { 39 },
	CritRating = { 19, 20, 21, 32 }, HitRating = { 16, 17, 18, 31 }, HasteRating = { 36 }, ExpertiseRating = { 37 },
	DefenseRating = { 12 }, DodgeRating = { 13 }, ParryRating = { 14 }, BlockRating = { 15 }, BlockValue = { 48 },
	Mp5 = { 43 }, SpellDamage = { 42, 45 }, Healing = { 41, 45 }, -- la puissance des sorts (45) compte pour les deux
}
local FR = {
	arms = "Armes", fury = "Fureur", protection = "Protection", holy = "Sacré", retribution = "Vindicte", shockadin = "Paladin choc",
	beast_mastery = "Maîtrise des bêtes", marksmanship = "Précision", survival = "Survie", assassination = "Assassinat",
	combat = "Combat", subtlety = "Finesse", discipline = "Discipline", shadow = "Ombre", elemental = "Élémentaire",
	enhancement = "Amélioration", restoration = "Restauration", enhancement_tank = "Amélioration (tank)", arcane = "Arcanes",
	fire = "Feu", frost = "Givre", battlemage_arcane = "Mage de bataille (Arcanes)", battlemage_fire = "Mage de bataille (Feu)",
	battlemage_frost = "Mage de bataille (Givre)", affliction = "Affliction", demonology = "Démonologie", destruction = "Destruction",
	balance = "Équilibre", feral = "Féral (chat)", bear = "Féral (ours)",
}
local EN = { beast_mastery = "Beast Mastery", restoration = "Restoration", enhancement_tank = "Enhancement (tank)",
	battlemage_arcane = "Battle Mage (Arcane)", battlemage_fire = "Battle Mage (Fire)", battlemage_frost = "Battle Mage (Frost)",
	bear = "Feral (bear)", feral = "Feral (cat)", shockadin = "Shockadin" }

local function convertir(poids)
	local sortie = {}
	for cle, valeur in pairs(poids) do
		for _, t in ipairs(TYPES[cle] or {}) do
			sortie[t] = (sortie[t] or 0) + valeur / (PAR_POURCENT[cle] or 1)
		end
	end
	local types = {}
	for t, v in pairs(sortie) do if v > 0 then types[#types + 1] = t end end
	table.sort(types)
	local morceaux = {}
	for _, t in ipairs(types) do morceaux[#morceaux + 1] = string.format("[%d] = %.4f", t, sortie[t]) end
	return "{ " .. table.concat(morceaux, ", ") .. " }"
end

local classes, ordre = {}, {}
for _, s in ipairs(PF.Weights) do
	if not classes[s.class] then classes[s.class] = {}; ordre[#ordre + 1] = s.class end
	table.insert(classes[s.class], s)
end
local sortie = {
	"-- GÉNÉRÉ par tools/generer_poids.lua : ne pas modifier à la main. Poids des stats par spécialisation, d'après Pawn Forever",
	"-- (https://github.com/turlockmike/pawn-forever, licence MIT) qui reprend les tables de GearQuest Forever (Henrik8210).",
	"-- Poids par point de score (rating), indexés par ItemStatType ; `id` : numéro de l'arbre de talents (nil pour les spécialisations en plus de Forever), `niveau` : poids avant le niveau 60, `max` : au niveau 60.",
	"local _, ns = ...",
	"ns.Poids = {",
}
for _, classe in ipairs(ordre) do
	sortie[#sortie + 1] = ("\t%s = {"):format(classe)
	for _, s in ipairs(classes[classe]) do
		local en = EN[s.key] or (s.key:gsub("^%l", string.upper))
		sortie[#sortie + 1] = ('\t\t{ cle = %q, id = %s, en = %q, fr = %q,'):format(s.key, tostring(s.specID), en, FR[s.key] or en)
		sortie[#sortie + 1] = "\t\t\tniveau = " .. convertir(s.leveling) .. ","
		sortie[#sortie + 1] = "\t\t\tmax = " .. convertir(s.max) .. " },"
	end
	sortie[#sortie + 1] = "\t},"
end
sortie[#sortie + 1] = "}"
local f = assert(io.open("Core/Poids.lua", "wb"))
f:write(table.concat(sortie, "\n") .. "\n")
f:close()
print("Core/Poids.lua écrit")
