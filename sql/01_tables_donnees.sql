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
