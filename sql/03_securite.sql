-- Agent : locations en cours (nom du client, jamais ses coordonnées)
CREATE OR REPLACE VIEW v_locations_en_cours AS
SELECT l.id,
       ma.nom || ' ' || mo.nom                      AS vehicule,
       v.immatriculation,
       cl.prenom || ' ' || cl.nom                   AS client,
       l.date_debut,
       l.date_fin_prevue,
       (l.date_fin_prevue < current_date)           AS en_retard,
       duree_jours(l.date_debut, l.date_fin_prevue) AS duree_jours,
       l.prix_total
FROM locations l
JOIN vehicules v  ON v.id  = l.vehicule_id
JOIN modeles   mo ON mo.id = v.modele_id
JOIN marques   ma ON ma.id = mo.marque_id
JOIN clients   cl ON cl.id = l.client_id
WHERE l.statut = 'en_cours';

-- Agent : locations en cours (nom du client, jamais ses coordonnées)
CREATE OR REPLACE VIEW v_locations_en_cours AS
SELECT l.id,
       ma.nom || ' ' || mo.nom             AS vehicule,
       v.immatriculation,
       cl.prenom || ' ' || cl.nom          AS client,
       l.date_debut,
       l.date_fin_prevue,
       (l.date_fin_prevue < current_date)  AS en_retard,
       (l.date_fin_prevue - l.date_debut)  AS duree_jours,
       l.prix_total
FROM locations l
JOIN vehicules v  ON v.id  = l.vehicule_id
JOIN modeles   mo ON mo.id = v.modele_id
JOIN marques   ma ON ma.id = mo.marque_id
JOIN clients   cl ON cl.id = l.client_id
WHERE l.statut = 'en_cours';

-- Agent : recherche client. CACHE email, ville, catégorie préférée.
CREATE OR REPLACE VIEW v_clients_agent AS
SELECT id, nom, prenom, permis_valide
FROM clients;

-- Contrôleur : agrégats par catégorie, aucune donnée personnelle
CREATE OR REPLACE VIEW v_stats_flotte AS
SELECT c.libelle                        AS categorie,
       count(DISTINCT v.id)             AS nb_vehicules,
       count(l.id)                      AS nb_locations,
       coalesce(sum(l.prix_total), 0)   AS chiffre_affaires
FROM categories c
LEFT JOIN modeles    mo ON mo.categorie_id = c.id
LEFT JOIN vehicules  v  ON v.modele_id = mo.id
LEFT JOIN locations  l  ON l.vehicule_id = v.id AND l.statut = 'terminee'
GROUP BY c.libelle;

-- Contrôleur : journal d'audit
CREATE OR REPLACE VIEW v_journal AS
SELECT id, location_id, action, ancien_statut, nouveau_statut, fait_par, fait_le
FROM journal_locations;

-- ---------------------------------------------------------------------
-- 6. RÔLES
-- Les rôles existent pour tout le serveur : on teste avant de créer.
-- Mots de passe factices : les vrais se mettent à la main
-- (ALTER ROLE agent_alice PASSWORD '...'), jamais dans le dépôt public.
-- ---------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'role_agent') THEN
    CREATE ROLE role_agent NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'role_controleur') THEN
    CREATE ROLE role_controleur NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'agent_alice') THEN
    CREATE ROLE agent_alice LOGIN PASSWORD 'a_changer_alice' IN ROLE role_agent;
  END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'controleur_bob') THEN
    CREATE ROLE controleur_bob LOGIN PASSWORD 'a_changer_bob' IN ROLE role_controleur;
  END IF;
END $$;

-- 1) On part de zéro : aucun droit direct sur les tables
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM role_agent, role_controleur;

-- 2) Les procédures sont exécutables par PUBLIC par défaut : on le retire,
--    sinon le contrôleur pourrait appeler louer()
REVOKE EXECUTE ON PROCEDURE louer(int, int, date, date),
                            retourner(int),
                            declarer_panne(int),
                            remettre_en_service(int)
  FROM PUBLIC;

-- 3) Droits donnés aux rôles-métiers, jamais à alice ou bob
GRANT USAGE ON SCHEMA public TO role_agent, role_controleur;

GRANT SELECT ON v_etat_flotte, v_locations_en_cours, v_clients_agent
  TO role_agent;
GRANT EXECUTE ON PROCEDURE louer(int, int, date, date),
                           retourner(int),
                           declarer_panne(int),
                           remettre_en_service(int)
  TO role_agent;

GRANT SELECT ON v_etat_flotte, v_stats_flotte, v_journal
  TO role_controleur;
-- Le contrôleur : lecture seule, aucun EXECUTE, aucune table.