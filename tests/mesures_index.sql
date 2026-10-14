-- Mesures des index : à lancer LIGNE PAR LIGNE (TablePlus : Ctrl/Cmd+Entrée sur la ligne).
-- Pour chaque EXPLAIN ANALYZE : lancez-le DEUX fois et notez le temps de la 2e fois
-- (la 1re lit le disque, la 2e la mémoire). Cherchez la ligne « Execution Time: ... ms ».
-- Les temps dépendent de votre machine : ce qui compte, c'est l'ordre de grandeur avant/après.

-- ===== 0. Repartir sans index =====
DROP INDEX IF EXISTS locations_vehicule_id_idx;
DROP INDEX IF EXISTS locations_en_cours_idx;
ANALYZE locations;

-- ===== 1. AVANT =====
-- Requête a : la page « État de la flotte » (une sous-requête par véhicule)
EXPLAIN ANALYZE SELECT * FROM v_etat_flotte;
-- Requête b : les locations en cours, triées par date de fin
EXPLAIN ANALYZE SELECT * FROM locations WHERE statut = 'en_cours' ORDER BY date_fin_prevue;
-- Notez : plan (Seq Scan sur locations ?) et Execution Time de chacune.

-- ===== 2. L'index a =====
CREATE INDEX locations_vehicule_id_idx ON locations (vehicule_id);
ANALYZE locations;
EXPLAIN ANALYZE SELECT * FROM v_etat_flotte;
-- Notez : plan (Index Scan / Bitmap Index Scan ?) et Execution Time.

-- ===== 3. L'index b =====
CREATE INDEX locations_en_cours_idx ON locations (date_fin_prevue) WHERE statut = 'en_cours';
ANALYZE locations;
EXPLAIN ANALYZE SELECT * FROM locations WHERE statut = 'en_cours' ORDER BY date_fin_prevue;
-- Notez : plan et Execution Time.

-- ===== 4. Contre-exemple (à dire à l'oral) =====
-- 97 % ou plus des locations sont 'terminee' : un index sur statut seul ne servirait à rien,
-- PostgreSQL préférerait lire toute la table.
SELECT statut, count(*) FROM locations GROUP BY statut;
