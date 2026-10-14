-- =====================================================================
-- projet.sql : parc de location de véhicules (PostgreSQL)
-- Ordre : tables, données, fonctions/procédures, triggers, vues, rôles, index
-- S'exécute sans erreur sur une base vide.
-- =====================================================================

-- ##### sql/01_tables_donnees.sql #####

-- =====================================================================
-- PARTIE A (version de secours) · Tables et données
-- À lancer AVANT 02_logique_metier.sql (les données sont chargées avant les triggers).
-- =====================================================================

-- Rejouable : on repart de zéro (DROP ... CASCADE supprime aussi les vues de la partie C,
-- qui sont recréées par 03_securite.sql)
DROP TABLE IF EXISTS journal_locations CASCADE;
DROP TABLE IF EXISTS locations CASCADE;
DROP TABLE IF EXISTS vehicules CASCADE;
DROP TABLE IF EXISTS modeles CASCADE;
DROP TABLE IF EXISTS marques CASCADE;
DROP TABLE IF EXISTS categories CASCADE;
DROP TABLE IF EXISTS agences CASCADE;
DROP TABLE IF EXISTS clients CASCADE;

-- ---------------------------------------------------------------------
-- 1. LES TABLES
-- ---------------------------------------------------------------------
CREATE TABLE agences (
    id     serial PRIMARY KEY,
    nom    text NOT NULL,
    ville  text NOT NULL
);

-- Motorisés ou non : voitures, scooters, trottinettes électriques, vélos...
CREATE TABLE categories (
    id         serial PRIMARY KEY,
    libelle    text NOT NULL UNIQUE,
    motorise   boolean NOT NULL,
    prix_base  numeric(8,2) NOT NULL CHECK (prix_base >= 0)
);

CREATE TABLE marques (
    id   serial PRIMARY KEY,
    nom  text NOT NULL UNIQUE
);

CREATE TABLE modeles (
    id            serial PRIMARY KEY,
    marque_id     int NOT NULL REFERENCES marques(id),
    categorie_id  int NOT NULL REFERENCES categories(id),
    nom           text NOT NULL
);

CREATE TABLE vehicules (
    id               serial PRIMARY KEY,
    immatriculation  text NOT NULL UNIQUE,
    modele_id        int NOT NULL REFERENCES modeles(id),
    agence_id        int NOT NULL REFERENCES agences(id),
    prix_jour        numeric(8,2) NOT NULL CHECK (prix_jour >= 0),
    statut           text NOT NULL DEFAULT 'disponible'
                     CHECK (statut IN ('disponible', 'loue', 'maintenance', 'hors_service'))
);

CREATE TABLE clients (
    id                    serial PRIMARY KEY,
    nom                   text NOT NULL,
    prenom                text NOT NULL,
    email                 text NOT NULL,
    ville                 text,
    permis_valide         boolean NOT NULL DEFAULT true,
    categorie_preferee_id int REFERENCES categories(id)   -- préférence du client
);

CREATE TABLE locations (
    id               serial PRIMARY KEY,
    vehicule_id      int NOT NULL REFERENCES vehicules(id),
    client_id        int NOT NULL REFERENCES clients(id),
    date_debut       date NOT NULL,
    date_fin_prevue  date NOT NULL,
    date_retour      date,
    prix_total       numeric(10,2) NOT NULL,
    statut           text NOT NULL DEFAULT 'en_cours'
                     CHECK (statut IN ('en_cours', 'terminee')),
    CHECK (date_fin_prevue >= date_debut)
);

CREATE TABLE journal_locations (
    id              serial PRIMARY KEY,
    location_id     int NOT NULL REFERENCES locations(id),
    action          text NOT NULL,
    ancien_statut   text,
    nouveau_statut  text NOT NULL,
    fait_par        text NOT NULL,
    fait_le         timestamptz NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------
-- 2. LES DONNÉES
-- ---------------------------------------------------------------------
INSERT INTO agences (nom, ville) VALUES
    ('Agence Paris Centre', 'Paris'),
    ('Agence Lyon Part-Dieu', 'Lyon'),
    ('Agence Marseille Vieux-Port', 'Marseille'),
    ('Agence Lille Flandres', 'Lille'),
    ('Agence Bordeaux Saint-Jean', 'Bordeaux'),
    ('Agence Toulouse Capitole', 'Toulouse');

INSERT INTO categories (libelle, motorise, prix_base) VALUES
    ('Voiture', true, 45),
    ('Utilitaire', true, 70),
    ('Scooter', true, 30),
    ('Trottinette électrique', true, 12),
    ('Vélo', false, 10),
    ('Vélo électrique', true, 18);

INSERT INTO marques (nom) VALUES
    ('Renault'), ('Peugeot'), ('Tesla'), ('Citroën'), ('Piaggio'),
    ('Yamaha'), ('Xiaomi'), ('Decathlon'), ('Giant'), ('Cowboy');

-- 16 modèles (l'ordre compte : la génération des véhicules en dépend)
INSERT INTO modeles (marque_id, categorie_id, nom) VALUES
    (1, 1, 'Clio'),
    (2, 1, '208'),
    (3, 1, 'Model 3'),
    (4, 1, 'C3'),
    (1, 2, 'Master'),
    (2, 2, 'Partner'),
    (5, 3, 'Vespa Primavera'),
    (6, 3, 'NMAX'),
    (7, 4, 'Mi Pro 2'),
    (7, 4, 'Mi 4'),
    (8, 5, 'Riverside 500'),
    (9, 5, 'Escape 3'),
    (8, 6, 'E-ST 500'),
    (10, 6, 'Cowboy 4'),
    (9, 6, 'Explore E+'),
    (6, 3, 'XMAX');

-- 300 véhicules
INSERT INTO vehicules (immatriculation, modele_id, agence_id, prix_jour)
SELECT 'VH-' || lpad(i::text, 4, '0'),
       m.id,
       1 + (i % 6),
       c.prix_base + (i % 5) * 2
FROM generate_series(1, 300) AS i
JOIN modeles m ON m.id = 1 + (i % 16)
JOIN categories c ON c.id = m.categorie_id
ORDER BY i;

-- 2 000 clients (1 sur 10 a un permis non valide)
INSERT INTO clients (nom, prenom, email, ville, permis_valide, categorie_preferee_id)
SELECT 'Nom' || i,
       (ARRAY['Alice','Bob','Chloé','David','Emma','Farid','Gaëlle','Hugo'])[1 + (i % 8)],
       'client' || i || '@exemple.fr',
       (ARRAY['Paris','Lyon','Marseille','Lille','Bordeaux','Toulouse'])[1 + (i % 6)],
       (i % 10 <> 0),
       1 + (i % 6)
FROM generate_series(1, 2000) AS i
ORDER BY i;

-- 12 000 locations terminées (la plus grosse table) : de 1 à 6 jours, prix = jours x prix/jour
INSERT INTO locations (vehicule_id, client_id, date_debut, date_fin_prevue, date_retour, prix_total, statut)
SELECT v.id,
       1 + (x.i % 2000),
       x.debut,
       x.debut + (x.i % 6),
       x.debut + (x.i % 6),
       (1 + x.i % 6) * v.prix_jour,
       'terminee'
FROM (SELECT i, date '2026-01-01' + (i % 250) AS debut
      FROM generate_series(1, 12000) AS i) x
JOIN vehicules v ON v.id = 1 + (x.i % 300)
ORDER BY x.i;

-- 20 locations en cours (véhicules 101 à 120), dont certaines en retard
INSERT INTO locations (vehicule_id, client_id, date_debut, date_fin_prevue, prix_total, statut)
SELECT x.vid, x.cid, x.debut, x.fin, (x.fin - x.debut + 1) * v.prix_jour, 'en_cours'
FROM (SELECT 100 + i AS vid,
             1 + (i % 2000) AS cid,
             current_date - 2 - (i % 3) AS debut,
             GREATEST(current_date - 2 - (i % 3), current_date + (i % 5) - 3) AS fin
      FROM generate_series(1, 20) AS i) x
JOIN vehicules v ON v.id = x.vid;

-- États cohérents avec les locations
UPDATE vehicules SET statut = 'loue'         WHERE id BETWEEN 101 AND 120;
UPDATE vehicules SET statut = 'maintenance'  WHERE id BETWEEN 121 AND 125;
UPDATE vehicules SET statut = 'hors_service' WHERE id = 126;

ANALYZE;


-- ##### sql/02_logique_metier.sql #####

-- =====================================================================
-- PARTIE B · Logique métier : fonctions, procédures, triggers
-- À lancer APRÈS 01 (tables + données) et AVANT 03 (sécurité).
-- Convention : durée d'une location = fin - début + 1 (jours inclus).
-- =====================================================================

-- ---------------------------------------------------------------------
-- 3. FONCTIONS
-- ---------------------------------------------------------------------

-- Nombre de jours d'une location (début et fin inclus)
CREATE OR REPLACE FUNCTION duree_jours(p_debut date, p_fin date)
RETURNS int
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT p_fin - p_debut + 1;
$$;

-- Prix d'une location : prix/jour x durée, -10 % dès 7 jours, -20 % dès 30 jours
CREATE OR REPLACE FUNCTION calculer_prix(p_vehicule_id int, p_debut date, p_fin date)
RETURNS numeric
LANGUAGE plpgsql
AS $$
DECLARE
    v_prix_jour numeric;
    v_jours     int;
    v_total     numeric;
BEGIN
    SELECT prix_jour INTO v_prix_jour FROM vehicules WHERE id = p_vehicule_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Véhicule % inconnu', p_vehicule_id;
    END IF;

    v_jours := duree_jours(p_debut, p_fin);
    v_total := v_jours * v_prix_jour;

    IF v_jours >= 30 THEN
        v_total := v_total * 0.80;
    ELSIF v_jours >= 7 THEN
        v_total := v_total * 0.90;
    END IF;

    RETURN round(v_total, 2);
END;
$$;

-- ---------------------------------------------------------------------
-- 3 bis. PROCÉDURES (appelées par l'API FastAPI avec CALL)
-- SECURITY DEFINER : l'agent n'a aucun droit direct sur les tables,
-- il passe uniquement par ces procédures et par les vues.
-- ---------------------------------------------------------------------

CREATE OR REPLACE PROCEDURE louer(p_vehicule_id int, p_client_id int, p_debut date, p_fin date)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM vehicules WHERE id = p_vehicule_id) THEN
        RAISE EXCEPTION 'Véhicule % inconnu', p_vehicule_id;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM clients WHERE id = p_client_id) THEN
        RAISE EXCEPTION 'Client % inconnu', p_client_id;
    END IF;

    -- Les règles (dates, permis, disponibilité, prix) sont vérifiées par le trigger
    INSERT INTO locations (vehicule_id, client_id, date_debut, date_fin_prevue)
    VALUES (p_vehicule_id, p_client_id, p_debut, p_fin);
END;
$$;

CREATE OR REPLACE PROCEDURE retourner(p_location_id int)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM locations WHERE id = p_location_id) THEN
        RAISE EXCEPTION 'Location % inconnue', p_location_id;
    END IF;
    IF EXISTS (SELECT 1 FROM locations WHERE id = p_location_id AND statut = 'terminee') THEN
        RAISE EXCEPTION 'Location % déjà terminée', p_location_id;
    END IF;

    UPDATE locations
    SET statut = 'terminee', date_retour = current_date
    WHERE id = p_location_id;
END;
$$;

CREATE OR REPLACE PROCEDURE declarer_panne(p_vehicule_id int)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_statut text;
BEGIN
    SELECT statut INTO v_statut FROM vehicules WHERE id = p_vehicule_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Véhicule % inconnu', p_vehicule_id;
    END IF;
    IF v_statut NOT IN ('disponible', 'loue') THEN
        RAISE EXCEPTION 'Véhicule % : impossible de déclarer une panne (état : %)', p_vehicule_id, v_statut;
    END IF;

    UPDATE vehicules SET statut = 'maintenance' WHERE id = p_vehicule_id;
END;
$$;

CREATE OR REPLACE PROCEDURE remettre_en_service(p_vehicule_id int)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_statut text;
BEGIN
    SELECT statut INTO v_statut FROM vehicules WHERE id = p_vehicule_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Véhicule % inconnu', p_vehicule_id;
    END IF;
    IF v_statut <> 'maintenance' THEN
        RAISE EXCEPTION 'Véhicule % n''est pas en maintenance (état : %)', p_vehicule_id, v_statut;
    END IF;

    -- Si une location est encore en cours (panne pendant la location), le véhicule reste loué
    IF EXISTS (SELECT 1 FROM locations WHERE vehicule_id = p_vehicule_id AND statut = 'en_cours') THEN
        UPDATE vehicules SET statut = 'loue' WHERE id = p_vehicule_id;
    ELSE
        UPDATE vehicules SET statut = 'disponible' WHERE id = p_vehicule_id;
    END IF;
END;
$$;

-- ---------------------------------------------------------------------
-- 4. TRIGGERS sur locations
-- ---------------------------------------------------------------------

-- 4.1 Avant une location : on vérifie TOUTES les règles, quel que soit le programme
CREATE OR REPLACE FUNCTION locations_avant_insert()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_statut text;
    v_permis boolean;
BEGIN
    IF NEW.date_fin_prevue < NEW.date_debut THEN
        RAISE EXCEPTION 'Dates invalides : la fin (%) est avant le début (%)',
            NEW.date_fin_prevue, NEW.date_debut;
    END IF;
    IF NEW.date_debut < current_date THEN
        RAISE EXCEPTION 'Dates invalides : le début (%) est dans le passé', NEW.date_debut;
    END IF;

    SELECT permis_valide INTO v_permis FROM clients WHERE id = NEW.client_id;
    IF NOT COALESCE(v_permis, false) THEN
        RAISE EXCEPTION 'Client % : permis non valide, location refusée', NEW.client_id;
    END IF;

    -- FOR UPDATE : deux agents qui louent le même véhicule en même temps font la queue
    SELECT statut INTO v_statut FROM vehicules WHERE id = NEW.vehicule_id FOR UPDATE;
    IF v_statut IS DISTINCT FROM 'disponible' THEN
        RAISE EXCEPTION 'Véhicule % indisponible (état : %)', NEW.vehicule_id, v_statut;
    END IF;

    NEW.prix_total := calculer_prix(NEW.vehicule_id, NEW.date_debut, NEW.date_fin_prevue);
    NEW.statut := 'en_cours';
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS locations_avant_insert ON locations;
CREATE TRIGGER locations_avant_insert
BEFORE INSERT ON locations
FOR EACH ROW EXECUTE FUNCTION locations_avant_insert();

-- 4.2 Après une location : le véhicule passe à « loué » et on écrit dans le journal
CREATE OR REPLACE FUNCTION locations_apres_insert()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE vehicules SET statut = 'loue' WHERE id = NEW.vehicule_id;

    INSERT INTO journal_locations (location_id, action, ancien_statut, nouveau_statut, fait_par)
    VALUES (NEW.id, 'location', NULL, 'en_cours', session_user);

    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS locations_apres_insert ON locations;
CREATE TRIGGER locations_apres_insert
AFTER INSERT ON locations
FOR EACH ROW EXECUTE FUNCTION locations_apres_insert();

-- 4.3 Une location terminée ne se modifie plus
CREATE OR REPLACE FUNCTION locations_avant_update()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF OLD.statut = 'terminee' THEN
        RAISE EXCEPTION 'Location % déjà terminée : elle ne peut plus être modifiée', OLD.id;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS locations_avant_update ON locations;
CREATE TRIGGER locations_avant_update
BEFORE UPDATE ON locations
FOR EACH ROW EXECUTE FUNCTION locations_avant_update();

-- 4.4 Au retour : le véhicule redevient disponible (sauf s'il est en maintenance) + journal
CREATE OR REPLACE FUNCTION locations_apres_retour()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE vehicules
    SET statut = 'disponible'
    WHERE id = NEW.vehicule_id AND statut = 'loue';

    INSERT INTO journal_locations (location_id, action, ancien_statut, nouveau_statut, fait_par)
    VALUES (NEW.id, 'retour', 'en_cours', 'terminee', session_user);

    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS locations_apres_retour ON locations;
CREATE TRIGGER locations_apres_retour
AFTER UPDATE OF statut ON locations
FOR EACH ROW
WHEN (OLD.statut = 'en_cours' AND NEW.statut = 'terminee')
EXECUTE FUNCTION locations_apres_retour();


-- ##### sql/03_securite.sql #####

-- =====================================================================
-- PARTIE C · Vues, rôles et privilèges
-- À lancer APRÈS 01 (tables) et 02 (logique métier).
-- =====================================================================

-- ---------------------------------------------------------------------
-- 5. LES VUES (celles que l'API FastAPI interroge)
-- ---------------------------------------------------------------------
DROP VIEW IF EXISTS v_etat_flotte CASCADE;
DROP VIEW IF EXISTS v_locations_en_cours CASCADE;
DROP VIEW IF EXISTS v_clients_agent CASCADE;
DROP VIEW IF EXISTS v_stats_flotte CASCADE;
DROP VIEW IF EXISTS v_journal CASCADE;

-- Agent + contrôleur : l'état de la flotte (aucune donnée client)
CREATE VIEW v_etat_flotte AS
SELECT v.id,
       v.immatriculation,
       ma.nom      AS marque,
       mo.nom      AS modele,
       c.libelle   AS categorie,
       ag.nom      AS agence,
       v.prix_jour,
       v.statut,
       (SELECT max(l.date_fin_prevue)
        FROM locations l
        WHERE l.vehicule_id = v.id AND l.statut = 'en_cours') AS retour_prevu
FROM vehicules v
JOIN modeles    mo ON mo.id = v.modele_id
JOIN marques    ma ON ma.id = mo.marque_id
JOIN categories c  ON c.id  = mo.categorie_id
JOIN agences    ag ON ag.id = v.agence_id;

-- Agent : locations en cours (nom du client, jamais ses coordonnées)
CREATE VIEW v_locations_en_cours AS
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

-- Agent : recherche client. CACHE l'e-mail, la ville et la catégorie préférée.
CREATE VIEW v_clients_agent AS
SELECT id, nom, prenom, permis_valide
FROM clients;

-- Contrôleur : agrégats par catégorie, aucune donnée personnelle
CREATE VIEW v_stats_flotte AS
SELECT c.libelle                       AS categorie,
       count(DISTINCT v.id)            AS nb_vehicules,
       count(l.id)                     AS nb_locations,
       coalesce(sum(l.prix_total), 0)  AS chiffre_affaires
FROM categories c
LEFT JOIN modeles   mo ON mo.categorie_id = c.id
LEFT JOIN vehicules v  ON v.modele_id = mo.id
LEFT JOIN locations l  ON l.vehicule_id = v.id AND l.statut = 'terminee'
GROUP BY c.libelle;

-- Contrôleur : journal d'audit
CREATE VIEW v_journal AS
SELECT id, location_id, action, ancien_statut, nouveau_statut, fait_par, fait_le
FROM journal_locations;

-- ---------------------------------------------------------------------
-- 6. LES RÔLES
-- Les rôles existent pour tout le serveur : on teste avant de créer.
-- Mots de passe factices : les vrais se posent à la main
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
END
$$;

-- 1) On part de zéro : aucun droit direct sur les tables ni sur les vues
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM role_agent, role_controleur;

-- Sur Supabase, les rôles de l'API publique (anon, authenticated) reçoivent des droits
-- par défaut : on les retire aussi (ignoré sur un PostgreSQL ordinaire).
DO $$
BEGIN
  IF EXISTS (SELECT FROM pg_roles WHERE rolname = 'anon') THEN
    REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon;
  END IF;
  IF EXISTS (SELECT FROM pg_roles WHERE rolname = 'authenticated') THEN
    REVOKE ALL ON ALL TABLES IN SCHEMA public FROM authenticated;
  END IF;
END
$$;

-- 2) Les procédures sont exécutables par PUBLIC par défaut : on le retire,
--    sinon le contrôleur pourrait appeler louer()
REVOKE EXECUTE ON PROCEDURE louer(int, int, date, date),
                            retourner(int),
                            declarer_panne(int),
                            remettre_en_service(int)
  FROM PUBLIC;

-- 3) Droits donnés aux rôles-métiers, jamais à alice ou bob
GRANT USAGE ON SCHEMA public TO role_agent, role_controleur;

-- Agent : travail courant (lit ses vues, loue, retourne, déclare les pannes)
GRANT SELECT ON v_etat_flotte, v_locations_en_cours, v_clients_agent
  TO role_agent;
GRANT EXECUTE ON PROCEDURE louer(int, int, date, date),
                           retourner(int),
                           declarer_panne(int),
                           remettre_en_service(int)
  TO role_agent;

-- Contrôleur : lecture seule, aucun EXECUTE, aucune table
GRANT SELECT ON v_etat_flotte, v_stats_flotte, v_journal
  TO role_controleur;


-- ##### sql/04_index.sql #####

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

