-- DÉMO du jeudi 15 (8 minutes) : un rôle, une vue, un index, un trigger.
-- À lancer ligne par ligne (TablePlus : Ctrl/Cmd+Entrée sur la ligne), connecté en postgres.
-- Base fraîche : lancez avant 01, 02, 03 puis 04.

-- ===== 1. UN RÔLE =====
SET ROLE agent_alice;
SELECT id, marque, modele, statut FROM v_etat_flotte LIMIT 3;    -- autorisé
SELECT * FROM clients LIMIT 1;                                   -- ERREUR : permission denied for table clients
RESET ROLE;

SET ROLE controleur_bob;
SELECT * FROM v_stats_flotte;                                    -- autorisé (lecture seule)
CALL louer(50, 1, current_date, current_date + 1);               -- ERREUR : permission denied for procedure louer
RESET ROLE;

-- ===== 2. UNE VUE =====
SELECT * FROM clients WHERE id = 1;                              -- en postgres : e-mail, ville, préférence visibles
SET ROLE agent_alice;
SELECT * FROM v_clients_agent WHERE id = 1;                      -- l'agent : seulement id, nom, prénom, permis
RESET ROLE;

-- ===== 3. UN INDEX (voir tests/mesures_index.sql pour la version complète) =====
DROP INDEX IF EXISTS locations_vehicule_id_idx;
EXPLAIN ANALYZE SELECT * FROM v_etat_flotte;                     -- 2 fois, garder la 2e : Seq Scan, temps AVANT
CREATE INDEX locations_vehicule_id_idx ON locations (vehicule_id);
ANALYZE locations;
EXPLAIN ANALYZE SELECT * FROM v_etat_flotte;                     -- 2 fois, garder la 2e : Index Scan, temps APRÈS

-- ===== 4. UN TRIGGER =====
SET ROLE agent_alice;
CALL louer(50, 1, current_date, current_date + 2);               -- OK : le trigger calcule le prix et passe le véhicule à « loue »
CALL louer(50, 2, current_date, current_date + 1);               -- ERREUR : Véhicule 50 indisponible (état : loue)
CALL louer(51, 10, current_date, current_date + 1);              -- ERREUR : Client 10 : permis non valide, location refusée
RESET ROLE;
SELECT id, statut FROM vehicules WHERE id = 50;                  -- loue
SELECT id FROM locations WHERE vehicule_id = 50 AND statut = 'en_cours';   -- noter le numéro, puis :
-- CALL retourner(<numéro>);                                     -- le véhicule redevient disponible
SELECT action, nouveau_statut, fait_par FROM journal_locations ORDER BY id DESC LIMIT 3;   -- fait_par = agent_alice
