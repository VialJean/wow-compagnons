-- Petites annonces : des intentions permanentes de la guilde. Une offre (« je fabrique ça ») ou une demande (« je cherche ça »),
-- visibles de tous, qui durent jusqu'à leur retrait ou 30 jours sans reconduction. Lua pur, sans API WoW.
--
--   annonce = {
--     id = "Prénom Nom#1731180062#1",     -- unique : auteur, horodatage, compteur
--     auteur = "Prénom Nom",
--     genre = "offre" | "demande",
--     spell = nil | 2329,                 -- recette visée
--     item = nil | 2449,                  -- objet visé : une demande peut viser un simple composant (spell ou item, pas les deux)
--                                         -- ni spell ni item : annonce de texte seul, la note est alors obligatoire
--     mats = "tout" | "partie" | "crafteur",   -- conditions : qui fournit les composants (comme une commande)
--     note = "",                          -- 100 caractères au plus
--     rev = 0, maj = 1731180062,          -- révision (une par modification) et dernière reconduction
--     retire = nil | true,                -- annonce retirée : la pierre tombale se propage avant d'être oubliée
--   }
--
-- Seul l'auteur écrit : la révision la plus haute gagne. Cinq annonces actives au plus par auteur.
local _, ns = ...

local Annonces = {}
ns.Annonces = Annonces

Annonces.DUREE = 30 * 24 * 3600        -- une annonce expire 30 jours après sa dernière reconduction
Annonces.DUREE_RETIREE = 7 * 24 * 3600 -- une annonce retirée est oubliée après 7 jours
Annonces.MAX_PAR_AUTEUR = 5

local MAX_NOTE = 100
local MAX_ID = 96
local GENRES = { offre = true, demande = true }
local MATS = { tout = true, partie = true, crafteur = true }

local compteur = 0

local function texte(v, max)
	if type(v) ~= "string" then return nil end
	return v:sub(1, max)
end

-- Vrai si le texte contient autre chose que des espaces (une annonce sans cible vit de sa note).
local function renseigne(v)
	return type(v) == "string" and v:find("%S") ~= nil
end

function Annonces.hash(a)
	local morceaux = {
		a.id, a.auteur, a.genre, tostring(a.spell or ""), tostring(a.item or ""), a.mats, a.note or "",
		tostring(a.rev), tostring(a.maj), a.retire and "1" or "0",
	}
	return ns.Profil.adler(table.concat(morceaux, "\n"))
end

--- Crée une annonce. options : auteur, genre, spell, item, mats, note, maintenant. Renvoie nil et une raison si elle est
-- inutilisable.
function Annonces.nouvelle(o)
	if not GENRES[o.genre] then return nil, "genre" end
	if o.spell ~= nil and o.item ~= nil then return nil, "cible" end -- une recette ou un objet, pas les deux
	if o.spell == nil and o.item == nil and not renseigne(o.note) then return nil, "note" end -- texte seul : note obligatoire
	if o.genre == "offre" and o.item ~= nil then return nil, "cible" end
	compteur = compteur + 1
	local a = {
		id = string.format("%s#%d#%d", o.auteur, math.floor(o.maintenant), compteur),
		auteur = o.auteur, genre = o.genre, spell = o.spell, item = o.item,
		mats = MATS[o.mats] and o.mats or "partie",
		note = texte(o.note or "", MAX_NOTE),
		rev = 0, maj = o.maintenant,
	}
	a.hash = Annonces.hash(a)
	return a
end

--- Valide et normalise une annonce reçue du réseau. Renvoie nil si elle est inutilisable.
function Annonces.valider(brut, donnees)
	if type(brut) ~= "table" then return nil end
	local id, auteur = texte(brut.id, MAX_ID), texte(brut.auteur, 64)
	if not id or id == "" or not auteur or auteur == "" then return nil end
	if not GENRES[brut.genre] or not MATS[brut.mats] then return nil end
	if brut.spell ~= nil and brut.item ~= nil then return nil end
	if brut.spell ~= nil then
		if type(brut.spell) ~= "number" or not donnees.recettes[brut.spell] then return nil end
	elseif brut.item ~= nil then
		if brut.genre == "offre" then return nil end
		if type(brut.item) ~= "number" or not (donnees.objets and donnees.objets[brut.item]) then return nil end
	elseif not renseigne(brut.note) then
		return nil -- ni recette ni objet : la note est la seule chose à dire
	end
	for _, champ in ipairs({ "rev", "maj" }) do
		local v = brut[champ]
		if type(v) ~= "number" or v ~= v or v < 0 then return nil end
	end
	if brut.rev > 1000000 then return nil end
	-- L'identifiant commence par l'auteur : une annonce ne peut pas être écrite au nom d'un autre.
	if id:sub(1, #auteur + 1) ~= auteur .. "#" then return nil end
	local a = {
		id = id, auteur = auteur, genre = brut.genre,
		spell = brut.spell, item = brut.item,
		mats = brut.mats, note = texte(brut.note or "", MAX_NOTE) or "",
		rev = math.floor(brut.rev), maj = brut.maj,
		retire = brut.retire == true or nil,
	}
	a.hash = Annonces.hash(a)
	return a
end

--- Vrai si `a` l'emporte sur `b` : plus de révisions, puis reconduction la plus récente, puis hash.
function Annonces.meilleure(a, b)
	if a.rev ~= b.rev then return a.rev > b.rev end
	if a.maj ~= b.maj then return a.maj > b.maj end
	return a.hash > b.hash
end

--- À oublier : expirée (30 jours sans reconduction) ou retirée depuis plus de 7 jours.
function Annonces.perimee(a, maintenant)
	if a.retire then return maintenant - a.maj > Annonces.DUREE_RETIREE end
	return maintenant - a.maj > Annonces.DUREE
end

--- Copie de l'annonce après une action de son auteur. action : "reconduire", "modifier" (extra : note, mats) ou "retirer".
-- Renvoie nil et une raison si `par` n'est pas l'auteur.
function Annonces.appliquer(a, action, par, maintenant, extra)
	if par ~= a.auteur then return nil, "interdit" end
	if a.retire then return nil, "retiree" end
	local n = {}
	for k, v in pairs(a) do n[k] = v end
	n.rev = a.rev + 1
	n.maj = math.max(maintenant, a.maj)
	if action == "modifier" then
		extra = extra or {}
		if extra.note ~= nil then
			local note = texte(extra.note, MAX_NOTE) or ""
			if not a.spell and not a.item and not renseigne(note) then return nil, "note" end
			n.note = note
		end
		if MATS[extra.mats] then n.mats = extra.mats end
	elseif action == "retirer" then
		n.retire = true
	elseif action ~= "reconduire" then
		return nil, "inconnue"
	end
	n.hash = Annonces.hash(n)
	return n
end

--- Nombre d'annonces actives (non retirées, non expirées) d'un auteur.
function Annonces.nombreActives(annonces, auteur, maintenant)
	local n = 0
	for _, a in pairs(annonces) do
		if a.auteur == auteur and not a.retire and not Annonces.perimee(a, maintenant) then n = n + 1 end
	end
	return n
end

--- Annonces visibles d'un genre, triées : auteurs en ligne d'abord, puis les plus récentes.
-- options : genre, metier (skillLineID), estEnLigne, donnees.
function Annonces.liste(annonces, options, maintenant)
	local liste = {}
	for _, a in pairs(annonces) do
		if not a.retire and not Annonces.perimee(a, maintenant) and a.genre == options.genre then
			local garde = true
			if options.metier then
				local r = a.spell and options.donnees and options.donnees.recettes[a.spell] -- le texte seul n'a pas de métier
				garde = r ~= nil and r.metier == options.metier
			end
			if garde then liste[#liste + 1] = a end
		end
	end
	local enLigne = options.estEnLigne or function() return false end
	table.sort(liste, function(a, b)
		local ea, eb = enLigne(a.auteur), enLigne(b.auteur)
		if ea ~= eb then return ea end
		if a.maj ~= b.maj then return a.maj > b.maj end
		return a.id < b.id
	end)
	return liste
end

--- Retire les annonces des auteurs qui ne sont plus membres de la guilde. `estMembre(cle)` renvoie vrai ou faux.
-- Renvoie le nombre d'annonces retirées de la table.
function Annonces.purgerAbsents(annonces, estMembre)
	local n = 0
	for id, a in pairs(annonces) do
		if not estMembre(a.auteur) then
			annonces[id] = nil
			n = n + 1
		end
	end
	return n
end

return Annonces
