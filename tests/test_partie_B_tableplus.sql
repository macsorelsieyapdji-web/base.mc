-- Version TablePlus : à exécuter LIGNE PAR LIGNE (curseur sur la ligne, puis Ctrl+Entrée / Cmd+Entrée).
-- Ne pas utiliser « Run All » : les lignes ERREUR s'arrêteraient net.
-- À faire après avoir chargé 01_tables_donnees.sql puis 02_logique_metier.sql.
-- Véhicules 1 à 100 : disponibles. Client 10 : permis non valide. Clients 1 et 2 : valides.
-- La première location créée ici a le numéro 12021 (la base en contient 12020).

-- 1. Les fonctions
SELECT prix_jour, calculer_prix(1, current_date, current_date + 2) AS prix_3j, calculer_prix(1, current_date, current_date + 6) AS prix_7j, calculer_prix(1, current_date, current_date + 29) AS prix_30j FROM vehicules WHERE id = 1;
-- attendu : prix_3j = 3 x prix_jour ; prix_7j = 7 x prix_jour x 0.9 ; prix_30j = 30 x prix_jour x 0.8

-- 2. Une location qui marche
CALL louer(1, 1, current_date, current_date + 2);
SELECT id, statut, prix_total FROM locations WHERE id = 12021;
-- attendu : 12021 | en_cours | 3 x prix_jour
SELECT id, statut FROM vehicules WHERE id = 1;
-- attendu : loue
SELECT action, nouveau_statut, fait_par FROM journal_locations;
-- attendu : 1 ligne : location | en_cours

-- 3. Les refus (chacune doit afficher une erreur, c'est normal)
CALL louer(1, 2, current_date, current_date + 1);
-- ERREUR attendue : Véhicule 1 indisponible (état : loue)
CALL louer(2, 10, current_date, current_date + 1);
-- ERREUR attendue : Client 10 : permis non valide, location refusée
CALL louer(2, 2, current_date + 5, current_date + 2);
-- ERREUR attendue : Dates invalides : la fin (...) est avant le début (...)
CALL louer(2, 2, current_date - 1, current_date + 2);
-- ERREUR attendue : Dates invalides : le début (...) est dans le passé
CALL louer(121, 2, current_date, current_date + 1);
-- ERREUR attendue : Véhicule 121 indisponible (état : maintenance)
CALL louer(999999, 1, current_date, current_date + 1);
-- ERREUR attendue : Véhicule 999999 inconnu
CALL louer(2, 999999, current_date, current_date + 1);
-- ERREUR attendue : Client 999999 inconnu
SELECT count(*) FROM locations;
-- attendu : 12021 (les refus n'ont rien écrit)

-- 4. Le retour
CALL retourner(12021);
SELECT statut, date_retour FROM locations WHERE id = 12021;
-- attendu : terminee | date du jour
SELECT statut FROM vehicules WHERE id = 1;
-- attendu : disponible
SELECT action FROM journal_locations ORDER BY id;
-- attendu : location, retour
CALL retourner(12021);
-- ERREUR attendue : Location 12021 déjà terminée
CALL retourner(999999);
-- ERREUR attendue : Location 999999 inconnue

-- 5. Le trigger protège aussi contre une modification directe
UPDATE locations SET date_fin_prevue = current_date + 10 WHERE id = 12021;
-- ERREUR attendue : Location 12021 déjà terminée : elle ne peut plus être modifiée

-- 6. Panne et remise en service
CALL declarer_panne(2);
SELECT statut FROM vehicules WHERE id = 2;
-- attendu : maintenance
CALL declarer_panne(2);
-- ERREUR attendue : Véhicule 2 : impossible de déclarer une panne (état : maintenance)
CALL declarer_panne(126);
-- ERREUR attendue : ... (état : hors_service)
CALL remettre_en_service(2);
SELECT statut FROM vehicules WHERE id = 2;
-- attendu : disponible
CALL remettre_en_service(2);
-- ERREUR attendue : Véhicule 2 n'est pas en maintenance (état : disponible)

-- 7. Panne pendant une location : le véhicule reste « loué » à la remise en service
CALL declarer_panne(101);
SELECT statut FROM vehicules WHERE id = 101;
-- attendu : maintenance
CALL remettre_en_service(101);
SELECT statut FROM vehicules WHERE id = 101;
-- attendu : loue
