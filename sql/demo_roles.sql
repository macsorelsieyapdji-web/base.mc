BEGIN;
SET ROLE agent_alice;
CALL louer(1, 1, current_date, current_date + 2);    -- OK : véhicule 1 disponible, client 1 permis valide
RESET ROLE;
ROLLBACK;