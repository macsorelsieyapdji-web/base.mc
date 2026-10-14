"""API FastAPI de la gestion de location de véhicules (base PostgreSQL).

Toute la logique métier est dans la base (procédures, triggers, rôles, vues).
Ce fichier ne fait que relayer : chaque profil se connecte avec SON utilisateur SQL
(agent_alice ou controleur_bob), donc c'est PostgreSQL qui applique les droits,
pas Python. La clé SUPABASE_KEY n'est utilisée que pour la route de santé.

Lancer :  cd backend  puis  python main.py   (ou  uvicorn main:app --reload)
"""
import asyncio
import os
import sys
from datetime import date
from pathlib import Path
from urllib.parse import urlencode

import httpx
import psycopg
from dotenv import load_dotenv
from fastapi import FastAPI, Form, HTTPException, Request
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.templating import Jinja2Templates
from psycopg.rows import dict_row

# psycopg (mode asynchrone) ne fonctionne pas avec la boucle par défaut de Windows
if sys.platform == "win32":
    asyncio.set_event_loop_policy(asyncio.WindowsSelectorEventLoopPolicy())

load_dotenv()

app = FastAPI(title="Vehicle Rental API")
templates = Jinja2Templates(directory=str(Path(__file__).parent / "templates"))

STATUTS = {"disponible", "loue", "maintenance", "hors_service"}

# profil -> (variable du nom d'utilisateur, nom par défaut, variable du mot de passe)
PROFILS = {
    "agent": ("AGENT_USER", "agent_alice", "AGENT_PASSWORD"),
    "controleur": ("CONTROLEUR_USER", "controleur_bob", "CONTROLEUR_PASSWORD"),
}


# ---------------------------------------------------------------------------
# Routes de santé
# ---------------------------------------------------------------------------
@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/health/supabase")
async def supabase_health() -> dict[str, str]:
    supabase_url = os.getenv("SUPABASE_URL")
    supabase_key = os.getenv("SUPABASE_KEY")
    if not supabase_url or not supabase_key:
        raise HTTPException(
            status_code=503,
            detail="SUPABASE_URL and SUPABASE_KEY must be configured",
        )

    try:
        async with httpx.AsyncClient(timeout=10) as client:
            response = await client.get(
                f"{supabase_url.rstrip('/')}/auth/v1/health",
                headers={"apikey": supabase_key},
            )
            response.raise_for_status()
    except httpx.HTTPError as exc:
        raise HTTPException(
            status_code=503,
            detail="Supabase API is unreachable",
        ) from exc

    return {"status": "ok", "supabase_api": "reachable"}


@app.get("/health/db")
async def db_health() -> dict[str, str]:
    """Vérifie la connexion PostgreSQL avec l'utilisateur agent."""
    try:
        async with await connexion("agent") as conn:
            await conn.execute("SELECT 1")
    except psycopg.Error as exc:
        raise HTTPException(status_code=503, detail="Database is unreachable") from exc
    return {"status": "ok", "database": "reachable"}


# ---------------------------------------------------------------------------
# Accès à la base
# ---------------------------------------------------------------------------
async def connexion(profil: str) -> psycopg.AsyncConnection:
    """Ouvre une connexion PostgreSQL avec l'utilisateur SQL du profil.

    Local (Docker)  : DB_HOST=127.0.0.1  DB_PORT=5433  DB_SSLMODE=disable
    Direct Supabase : DB_HOST=db.<ref>.supabase.co      DB_USER_SUFFIX vide
    Pooler Supabase : DB_HOST=aws-0-<region>.pooler.supabase.com
                      DB_USER_SUFFIX=.<ref>  (l'utilisateur devient agent_alice.<ref>)
    """
    var_user, user_defaut, var_mdp = PROFILS[profil]
    host = os.getenv("DB_HOST")
    password = os.getenv(var_mdp)
    if not host or not password:
        raise HTTPException(
            status_code=503,
            detail=f"DB_HOST and {var_mdp} must be configured",
        )

    user = os.getenv(var_user, user_defaut) + os.getenv("DB_USER_SUFFIX", "")
    return await psycopg.AsyncConnection.connect(
        host=host,
        port=os.getenv("DB_PORT", "5432"),
        dbname=os.getenv("DB_NAME", "postgres"),
        user=user,
        password=password,
        sslmode=os.getenv("DB_SSLMODE", "require"),
        connect_timeout=10,
        prepare_threshold=None,  # compatible avec le pooler en mode transaction
        row_factory=dict_row,
    )


async def lire(conn: psycopg.AsyncConnection, sql: str, params=None) -> list[dict]:
    cur = await conn.execute(sql, params)
    return await cur.fetchall()


def message_erreur(exc: psycopg.Error) -> str:
    """Le texte du RAISE EXCEPTION écrit dans la base (ou un message générique)."""
    diag = getattr(exc, "diag", None)
    if diag is not None and diag.message_primary:
        return diag.message_primary
    return "Erreur de base de données"


def retour_accueil(msg: str, niveau: str) -> RedirectResponse:
    return RedirectResponse(f"/?{urlencode({'msg': msg, 'niveau': niveau})}", status_code=303)


async def appeler(sql: str, params: tuple, message_ok: str) -> RedirectResponse:
    """Exécute une procédure en tant qu'agent ; les refus de la base remontent à l'écran."""
    try:
        async with await connexion("agent") as conn:  # commit si OK, rollback sinon
            await conn.execute(sql, params)
    except psycopg.Error as exc:
        return retour_accueil(message_erreur(exc), "err")
    return retour_accueil(message_ok, "ok")


# ---------------------------------------------------------------------------
# Pages
# ---------------------------------------------------------------------------
@app.get("/", response_class=HTMLResponse)
async def agent(request: Request, statut: str = "", q: str = "", msg: str = "", niveau: str = "ok"):
    q = q.strip()
    try:
        async with await connexion("agent") as conn:
            if statut in STATUTS:
                flotte = await lire(conn, "SELECT * FROM v_etat_flotte WHERE statut = %s ORDER BY id", (statut,))
            else:
                flotte = await lire(conn, "SELECT * FROM v_etat_flotte ORDER BY id")
            locations = await lire(conn, "SELECT * FROM v_locations_en_cours ORDER BY date_fin_prevue, id")
            clients = []
            if q:
                clients = await lire(
                    conn,
                    "SELECT * FROM v_clients_agent WHERE nom ILIKE %s OR prenom ILIKE %s ORDER BY id LIMIT 15",
                    (f"%{q}%", f"%{q}%"),
                )
    except psycopg.Error as exc:
        raise HTTPException(status_code=503, detail="Database is unreachable") from exc

    return templates.TemplateResponse(
        request,
        "index.html",
        {
            "mode": "agent",
            "flotte": flotte,
            "locations": locations,
            "clients": clients,
            "statut": statut,
            "q": q,
            "msg": msg,
            "niveau": niveau if niveau in ("ok", "err") else "ok",
        },
    )


@app.get("/controle", response_class=HTMLResponse)
async def controle(request: Request):
    try:
        async with await connexion("controleur") as conn:
            stats = await lire(conn, "SELECT * FROM v_stats_flotte ORDER BY chiffre_affaires DESC")
            flotte = await lire(conn, "SELECT * FROM v_etat_flotte ORDER BY id")
            journal = await lire(conn, "SELECT * FROM v_journal ORDER BY id DESC LIMIT 30")
    except psycopg.Error as exc:
        raise HTTPException(status_code=503, detail="Database is unreachable") from exc

    return templates.TemplateResponse(
        request,
        "index.html",
        {"mode": "controle", "stats": stats, "flotte": flotte, "journal": journal, "msg": "", "niveau": "ok"},
    )


# ---------------------------------------------------------------------------
# Actions de l'agent (chacune appelle une procédure de la base)
# ---------------------------------------------------------------------------
@app.post("/louer")
async def louer(
    vehicule_id: int = Form(...),
    client_id: int = Form(...),
    debut: date = Form(...),
    fin: date = Form(...),
):
    return await appeler(
        "CALL louer(%s::int, %s::int, %s::date, %s::date)",
        (vehicule_id, client_id, debut, fin),
        "Location enregistrée.",
    )


@app.post("/retour/{location_id}")
async def retour(location_id: int):
    return await appeler("CALL retourner(%s::int)", (location_id,), "Retour enregistré.")


@app.post("/panne/{vehicule_id}")
async def panne(vehicule_id: int):
    return await appeler("CALL declarer_panne(%s::int)", (vehicule_id,), "Véhicule passé en maintenance.")


@app.post("/service/{vehicule_id}")
async def service(vehicule_id: int):
    return await appeler("CALL remettre_en_service(%s::int)", (vehicule_id,), "Véhicule remis en service.")


if __name__ == "__main__":
    import uvicorn

    uvicorn.run("main:app", host="127.0.0.1", port=8000, reload=True)
