# Parc de location de véhicules · Projet SQL avancé (Ycode B2)

**Groupe :** SIEYAPDJI MAC SOREL, ABOUBAKAR DEWA, HOSSAM HASSAM, OUKSILI LYES, RAYEN BEN SOUISSI

Une base PostgreSQL pour gérer la location de véhicules motorisés ou non (voitures, utilitaires, scooters, trottinettes, vélos) dans plusieurs grandes villes, avec une appli FastAPI et une page HTML.
Règle métier à faire respecter : un véhicule indisponible ne se loue pas, et un client sans permis valide non plus.

Tables : `agences`, `categories`, `marques`, `modeles`, `vehicules`, `clients` (avec leur catégorie préférée), `locations` (12 000 lignes), `journal_locations`.

## Lancer le projet

1. **Base (locale, Docker)**
   ```
   docker run --name pg-test -e POSTGRES_PASSWORD=pw -p 5433:5432 -d postgres:16
   ```
   Exécuter `projet.sql` (TablePlus : Run All, connexion 127.0.0.1 port 5433, utilisateur `postgres`, mot de passe `pw`).
   Il contient tout (tables, données, fonctions, triggers, vues, rôles, index) et s'exécute sans erreur sur une base vide.
   Les mêmes scripts existent séparément dans `sql/` (`01` à `04`).
2. **Mots de passe des utilisateurs** (valeurs de test, à poser à la main) :
   ```
   ALTER ROLE agent_alice PASSWORD 'alice_pwd';
   ALTER ROLE controleur_bob PASSWORD 'bob_pwd';
   ```
3. **Appli** : copier `.env.example` en `.env`, puis
   ```
   pip install -r requirements.txt
   cd backend
   python main.py
   ```
   Ouvrir http://127.0.0.1:8000 (page Agent) et http://127.0.0.1:8000/controle (page Contrôle).

## Fonctions et procédures

- **Ce qu'elles font :** `calculer_prix` calcule le prix (-10 % dès 7 jours, -20 % dès 30 jours) ; `louer`, `retourner`, `declarer_panne` et `remettre_en_service` modifient la base en refusant les cas invalides, avec un message clair.
- **Pourquoi elles sont là :** la logique est écrite une seule fois dans la base. Elles sont en `SECURITY DEFINER` : l'agent n'a aucun droit sur les tables et passe uniquement par elles.
- **La preuve :** `CALL louer(999999, 1, current_date, current_date + 1);` renvoie `Véhicule 999999 inconnu` ; `SELECT calculer_prix(1, current_date, current_date + 6);` renvoie 7 jours moins 10 %.

## Triggers

- **Ce qu'ils font :** avant une location, ils vérifient les dates, le permis et la disponibilité, puis calculent le prix. Après, ils passent le véhicule à « loué » et écrivent dans `journal_locations`. Une location terminée ne se modifie plus. Au retour, le véhicule redevient disponible.
- **Pourquoi dans la base plutôt que dans l'application :** l'appli, un script ou un autre programme peuvent tous écrire dans la table. Un oubli côté application suffirait à louer deux fois le même véhicule ; `FOR UPDATE` fait aussi attendre deux agents qui visent le même véhicule en même temps.
- **La preuve :** louer un véhicule déjà loué renvoie `Véhicule 50 indisponible (état : loue)` ; `UPDATE locations SET date_fin_prevue = ... WHERE id = <location terminée>;` renvoie `Location ... déjà terminée : elle ne peut plus être modifiée`.

## Rôles

- **Ce qu'ils font :** `role_agent` (travail courant : lit ses vues, loue, retourne, déclare les pannes) et `role_controleur` (contrôle en lecture seule). Les utilisateurs `agent_alice` et `controleur_bob` héritent de leur rôle ; aucun droit n'est donné aux personnes.
- **Pourquoi ils sont là :** principe du moindre privilège. Chaque profil n'a que le strict nécessaire, et l'appli se connecte avec l'utilisateur SQL du profil : c'est PostgreSQL qui applique les droits, pas Python.
- **La preuve :** `SET ROLE agent_alice;` puis `SELECT * FROM v_etat_flotte;` est autorisé et `SELECT * FROM clients;` renvoie `permission denied`. `SET ROLE controleur_bob;` puis `CALL louer(...)` renvoie `permission denied for procedure louer`. Faire `RESET ROLE;` après chaque test.

## Vues

- **Ce qu'elles font :** `v_etat_flotte`, `v_locations_en_cours` et `v_clients_agent` pour l'agent ; `v_stats_flotte` et `v_journal` pour le contrôleur. Elles cachent les jointures et masquent les données personnelles (e-mail, ville, préférences).
- **Pourquoi elles sont là :** le rôle a le droit sur sa vue, pas sur les tables : il ne peut pas lire plus que ce qu'on lui montre.
- **La preuve :** `agent_alice` lit `v_clients_agent` (id, nom, prénom, permis) mais pas la colonne `email`, et `SELECT * FROM clients;` lui renvoie `permission denied`.

## Index

Deux index, mesurés avec `EXPLAIN ANALYZE` (deuxième exécution, après `ANALYZE`). Script de mesure : `tests/mesures_index.sql`. Les temps dépendent de la machine : ce qui compte, c'est l'ordre de grandeur entre avant et après.

| Requête | Index | Avant | Après |
|---|---|---|---|
| `SELECT * FROM v_etat_flotte` (une sous-requête par véhicule) | `locations (vehicule_id)` | Seq Scan, 624,3 ms | Bitmap Index Scan, 30,4 ms |
| `SELECT * FROM locations WHERE statut = 'en_cours' ORDER BY date_fin_prevue` | `locations (date_fin_prevue) WHERE statut = 'en_cours'` | Seq Scan + tri, 4,0 ms | Bitmap Index Scan + tri, 0,07 ms |

- **Pourquoi :** la première requête relit la table `locations` pour chacun des 300 véhicules (`loops=300`, 12 021 lignes lues à chaque fois) ; avec l'index, PostgreSQL ne lit que les environ 40 locations de chaque véhicule. La seconde ne cible qu'une vingtaine de locations sur 12 000, d'où un index partiel très petit.
- **Contre-exemple :** un index sur `statut` seul ne servirait à rien : 12 000 locations sur 12 021 (99,8 %) sont `terminee`, PostgreSQL lirait quand même toute la table.
- **La preuve :** les plans et les temps du tableau ci-dessus. Gain d'environ 20 fois pour la première requête et 57 fois pour la seconde.

## Données

12 000 locations terminées, environ 20 en cours, 300 véhicules, 2 000 clients, générés avec `generate_series`.