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
