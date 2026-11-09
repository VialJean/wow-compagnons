-- Journal en mémoire (500 dernières lignes), affiché dans le chat si le debug est actif.
-- Base du futur panneau /cpg debug.
local _, ns = ...

local CAPACITE = 500
local COULEURS = { info = "ff9aa38f", warn = "ffe8a94f", erreur = "ffe8806a", sync = "ff7fb2ff" }

local Journal = { lignes = {}, debut = 1, n = 0 }
ns.Journal = Journal

--- ns.log(niveau, categorie, format, ...)
-- niveau : "info" | "warn" | "erreur" | "sync"
function ns.log(niveau, categorie, fmt, ...)
	local ok, texte = pcall(string.format, fmt, ...)
	if not ok then texte = fmt end
	local ligne = { t = date("%H:%M:%S"), niveau = niveau, cat = categorie, texte = texte }

	local index = (Journal.debut + Journal.n - 1) % CAPACITE + 1
	if Journal.n < CAPACITE then
		Journal.n = Journal.n + 1
	else
		Journal.debut = Journal.debut % CAPACITE + 1
	end
	Journal.lignes[index] = ligne

	local db = ns.db
	if (db and db.profile.debug) or niveau == "erreur" then
		Journal.imprimer(ligne)
	end
end

function Journal.imprimer(ligne)
	print(string.format("|cffe0b252Compagnons|r |c%s[%s] %s|r %s",
		COULEURS[ligne.niveau] or "ffffffff", ligne.t, ligne.cat, ligne.texte))
end

function Journal.afficher(nombre)
	if Journal.n == 0 then
		print(ns.L.JOURNAL_VIDE)
		return
	end
	local depart = math.max(1, Journal.n - nombre + 1)
	for i = depart, Journal.n do
		Journal.imprimer(Journal.lignes[(Journal.debut + i - 2) % CAPACITE + 1])
	end
end
