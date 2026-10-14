-- =====================================================================
-- PARTIE D · Index (mesurés avant / après : voir tests/mesures_index.sql)
-- À lancer en DERNIER.
-- =====================================================================

-- a. Les locations d'un véhicule : utilisé par v_etat_flotte (retour prévu de chaque véhicule),
--    par la procédure remettre_en_service et par les jointures des statistiques.
CREATE INDEX IF NOT EXISTS locations_vehicule_id_idx ON locations (vehicule_id);

-- b. Les locations EN COURS, triées par date de fin : index partiel.
--    Seules 20 locations sur 12 000 sont en cours : l'index est minuscule et très sélectif.
--    (Un index sur statut seul serait inutile : 99 % des lignes valent 'terminee'.)
CREATE INDEX IF NOT EXISTS locations_en_cours_idx ON locations (date_fin_prevue)
    WHERE statut = 'en_cours';

ANALYZE locations;
