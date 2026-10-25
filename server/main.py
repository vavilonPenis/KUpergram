"""
KUpergram sync server
=====================
Небольшой бэкенд для синхронизации ВИЗУАЛЬНЫХ Stars и NFT-коллекций
между двумя пользователями приватного форка.

ВАЖНО: это косметическая система приватного приложения. Здесь нет и не может
быть настоящих Telegram Stars или блокчейн-NFT — только локальные карточки,
которые рисует клиент. Ничего из этого не является подтверждённым активом.

Запуск:
    pip install -r requirements.txt
    ADMIN_TOKEN=... python -m uvicorn main:app --host 0.0.0.0 --port 8099
"""
import json
import os
import re
import sqlite3
import time
import uuid
from contextlib import contextmanager
from typing import Optional

import httpx
from bs4 import BeautifulSoup
from fastapi import Depends, FastAPI, Header, HTTPException
from pydantic import BaseModel

DB_PATH = os.environ.get("KUPERGRAM_DB", "kupergram.db")
ADMIN_TOKEN = os.environ.get("ADMIN_TOKEN", "")          # админ-методы
# Пер-юзер токены: личность определяется сервером по токену, не из тела запроса.
USER_TOKENS = {t: uid for t, uid in (
    (os.environ.get("USER_TOKEN_ME", ""), "me"),
    (os.environ.get("USER_TOKEN_FRIEND", ""), "friend"),
) if t}

app = FastAPI(title="KUpergram Sync", version="0.1.0")


# --------------------------------------------------------------------------- db
@contextmanager
def db():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    try:
        yield conn
        conn.commit()
    finally:
        conn.close()


def init_db():
    with db() as conn:
        conn.executescript(
            """
            CREATE TABLE IF NOT EXISTS users (
                id   TEXT PRIMARY KEY,
                name TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS stars (
                user_id TEXT PRIMARY KEY,
                balance INTEGER NOT NULL DEFAULT 0
            );
            CREATE TABLE IF NOT EXISTS stars_history (
                id        TEXT PRIMARY KEY,
                user_id   TEXT NOT NULL,
                delta     INTEGER NOT NULL,
                balance   INTEGER NOT NULL,
                reason    TEXT,
                created_at INTEGER NOT NULL
            );
            CREATE TABLE IF NOT EXISTS nfts (
                id         TEXT PRIMARY KEY,
                slug       TEXT,
                name       TEXT,
                number     TEXT,
                model      TEXT,
                backdrop   TEXT,
                symbol     TEXT,
                image_url  TEXT,
                owner_id   TEXT,
                added_at   INTEGER NOT NULL
            );
            CREATE TABLE IF NOT EXISTS gifts_log (
                id         TEXT PRIMARY KEY,
                nft_id     TEXT NOT NULL,
                from_user  TEXT NOT NULL,
                to_user    TEXT NOT NULL,
                stars_cost INTEGER NOT NULL DEFAULT 0,
                message    TEXT,
                created_at INTEGER NOT NULL
            );
            CREATE TABLE IF NOT EXISTS processed_ops (
                key        TEXT PRIMARY KEY,
                result     TEXT NOT NULL,
                created_at INTEGER NOT NULL
            );
            """
        )
        # миграция: флаг «коллекционный» (апгрейд обычного подарка)
        cols = [r["name"] for r in conn.execute("PRAGMA table_info(nfts)")]
        if "is_collectible" not in cols:
            conn.execute("ALTER TABLE nfts ADD COLUMN is_collectible INTEGER NOT NULL DEFAULT 0")
        # два фиксированных пользователя форка; правь под себя
        for uid, name in (("me", "Me"), ("friend", "Friend")):
            conn.execute("INSERT OR IGNORE INTO users(id, name) VALUES(?,?)", (uid, name))
            conn.execute("INSERT OR IGNORE INTO stars(user_id, balance) VALUES(?,0)", (uid,))


init_db()


def require_admin(x_admin_token: str = Header(default="")):
    """Админ-методы: только по ADMIN_TOKEN."""
    if not ADMIN_TOKEN:
        raise HTTPException(500, "ADMIN_TOKEN не задан на сервере")
    if x_admin_token != ADMIN_TOKEN:
        raise HTTPException(401, "bad admin token")


def current_user(x_user_token: str = Header(default="")) -> str:
    """Личность пользователя определяется СЕРВЕРОМ по его токену."""
    uid = USER_TOKENS.get(x_user_token)
    if not uid:
        raise HTTPException(401, "bad user token")
    return uid


def now() -> int:
    return int(time.time())


def idem_get(conn, key: str):
    """Если операция с таким Idempotency-Key уже выполнялась — вернуть прежний
    результат (защита от двойного списания при повторном нажатии/ретрае)."""
    if not key:
        return None
    row = conn.execute("SELECT result FROM processed_ops WHERE key=?", (key,)).fetchone()
    return json.loads(row["result"]) if row else None


def idem_put(conn, key: str, result: dict):
    if not key:
        return
    conn.execute(
        "INSERT OR IGNORE INTO processed_ops(key, result, created_at) VALUES(?,?,?)",
        (key, json.dumps(result), now()))


def deduct_stars(conn, user_id: str, cost: int, reason: str) -> Optional[int]:
    """Списать визуальные звёзды у пользователя внутри текущей транзакции.
    Возвращает новый баланс либо None, если cost == 0."""
    if cost == 0:
        return None
    if cost < 0:
        raise HTTPException(400, "stars_cost не может быть отрицательным")
    bal = conn.execute("SELECT balance FROM stars WHERE user_id=?", (user_id,)).fetchone()
    if bal is None:
        raise HTTPException(404, "у пользователя нет счёта звёзд")
    if bal["balance"] < cost:
        raise HTTPException(400, "недостаточно звёзд")
    new_balance = bal["balance"] - cost
    conn.execute("UPDATE stars SET balance=? WHERE user_id=?", (new_balance, user_id))
    conn.execute(
        "INSERT INTO stars_history(id,user_id,delta,balance,reason,created_at)"
        " VALUES(?,?,?,?,?,?)",
        (uuid.uuid4().hex, user_id, -cost, new_balance, reason, now()))
    return new_balance


# ------------------------------------------------------------------------ models
class StarsAdjust(BaseModel):
    user_id: str
    delta: int
    reason: Optional[str] = None


class NFTIn(BaseModel):
    slug: Optional[str] = None
    name: Optional[str] = None
    number: Optional[str] = None
    model: Optional[str] = None
    backdrop: Optional[str] = None
    symbol: Optional[str] = None
    image_url: Optional[str] = None
    owner_id: str = "me"


class NFTPatch(BaseModel):
    name: Optional[str] = None
    number: Optional[str] = None
    model: Optional[str] = None
    backdrop: Optional[str] = None
    symbol: Optional[str] = None
    image_url: Optional[str] = None


class Transfer(BaseModel):
    to_user: str


class Gift(BaseModel):
    # from_user определяется сервером по токену — клиент его НЕ задаёт
    to_user: str
    stars_cost: int = 0       # сколько визуальных звёзд спишется у дарителя (0 = бесплатно)
    message: Optional[str] = None


class Purchase(BaseModel):
    # owner_id определяется сервером по токену — клиент его НЕ задаёт
    stars_cost: int = 0       # 0 = бесплатно
    collectible: bool = False
    slug: Optional[str] = None
    name: Optional[str] = None
    number: Optional[str] = None
    model: Optional[str] = None
    backdrop: Optional[str] = None
    symbol: Optional[str] = None
    image_url: Optional[str] = None


class Upgrade(BaseModel):
    stars_cost: int = 0
    model: Optional[str] = None
    backdrop: Optional[str] = None
    symbol: Optional[str] = None


# -------------------------------------------------------------------- slug resolve
async def resolve_slug(slug: str) -> dict:
    """Тянет публичную карточку подарка с t.me/nft/<slug> (OpenGraph + таблица
    характеристик). Если не найдено — возвращает пустые поля для ручного ввода."""
    url = f"https://t.me/nft/{slug}"
    out = {"slug": slug, "name": None, "number": None, "model": None,
           "backdrop": None, "symbol": None, "image_url": None, "source": url}
    try:
        async with httpx.AsyncClient(timeout=15, follow_redirects=True) as c:
            r = await c.get(url, headers={"User-Agent": "Mozilla/5.0"})
        if r.status_code != 200:
            return out
        soup = BeautifulSoup(r.text, "html.parser")

        def og(prop):
            tag = soup.find("meta", property=prop)
            return tag["content"].strip() if tag and tag.get("content") else None

        title = og("og:title")          # напр. "Artisan Brick #945"
        out["image_url"] = og("og:image")
        if title:
            out["name"] = title
            m = re.search(r"#\s*([\d,]+)", title)
            if m:
                out["number"] = m.group(1).replace(",", "")
        # характеристики Model / Backdrop / Symbol из описания
        desc = og("og:description") or ""
        for key in ("Model", "Backdrop", "Symbol"):
            m = re.search(rf"{key}\s*[:\-]\s*([^\n,]+?)(?:\s{{2,}}|$|,\s*(?:Model|Backdrop|Symbol))",
                          desc, re.IGNORECASE)
            if m:
                out[key.lower()] = m.group(1).strip()
    except Exception as e:  # noqa: BLE001  — сеть/парс, не критично
        out["error"] = str(e)
    return out


# ------------------------------------------------------------------------- routes
@app.get("/health")
def health():
    return {"ok": True, "ts": now()}


@app.get("/state")
def state(_uid: str = Depends(current_user)):
    """Полный снимок для синхронизации клиента."""
    with db() as conn:
        users = [dict(r) for r in conn.execute("SELECT * FROM users")]
        stars = {r["user_id"]: r["balance"]
                 for r in conn.execute("SELECT * FROM stars")}
        nfts = [dict(r) for r in conn.execute("SELECT * FROM nfts ORDER BY added_at DESC")]
        history = [dict(r) for r in conn.execute(
            "SELECT * FROM stars_history ORDER BY created_at DESC LIMIT 200")]
        gifts = [dict(r) for r in conn.execute(
            "SELECT * FROM gifts_log ORDER BY created_at DESC LIMIT 200")]
    return {"users": users, "stars": stars, "nfts": nfts,
            "history": history, "gifts": gifts}


@app.post("/stars/adjust", dependencies=[Depends(require_admin)])
def stars_adjust(body: StarsAdjust):
    with db() as conn:
        row = conn.execute("SELECT balance FROM stars WHERE user_id=?",
                           (body.user_id,)).fetchone()
        if row is None:
            raise HTTPException(404, "user not found")
        new_balance = row["balance"] + body.delta
        if new_balance < 0:
            raise HTTPException(400, "balance cannot go negative")
        conn.execute("UPDATE stars SET balance=? WHERE user_id=?",
                     (new_balance, body.user_id))
        conn.execute(
            "INSERT INTO stars_history(id,user_id,delta,balance,reason,created_at)"
            " VALUES(?,?,?,?,?,?)",
            (uuid.uuid4().hex, body.user_id, body.delta, new_balance,
             body.reason, now()))
    return {"user_id": body.user_id, "balance": new_balance}


@app.get("/nft/resolve", dependencies=[Depends(require_admin)])
async def nft_resolve(slug: str):
    return await resolve_slug(slug)


@app.post("/nft", dependencies=[Depends(require_admin)])
async def nft_add(body: NFTIn):
    data = body.model_dump()
    # если задан slug и не хватает полей — попробуем дорезолвить из публичного источника
    if body.slug and not body.name:
        resolved = await resolve_slug(body.slug)
        for k in ("name", "number", "model", "backdrop", "symbol", "image_url"):
            if not data.get(k) and resolved.get(k):
                data[k] = resolved[k]
    nid = uuid.uuid4().hex
    with db() as conn:
        conn.execute(
            "INSERT INTO nfts(id,slug,name,number,model,backdrop,symbol,image_url,owner_id,added_at)"
            " VALUES(?,?,?,?,?,?,?,?,?,?)",
            (nid, data["slug"], data["name"], data["number"], data["model"],
             data["backdrop"], data["symbol"], data["image_url"],
             data["owner_id"], now()))
    return {"id": nid, **data}


@app.patch("/nft/{nid}", dependencies=[Depends(require_admin)])
def nft_patch(nid: str, body: NFTPatch):
    fields = {k: v for k, v in body.model_dump().items() if v is not None}
    if not fields:
        raise HTTPException(400, "nothing to update")
    sets = ", ".join(f"{k}=?" for k in fields)
    with db() as conn:
        cur = conn.execute(f"UPDATE nfts SET {sets} WHERE id=?",
                           (*fields.values(), nid))
        if cur.rowcount == 0:
            raise HTTPException(404, "nft not found")
    return {"id": nid, **fields}


@app.post("/nft/{nid}/transfer", dependencies=[Depends(require_admin)])
def nft_transfer(nid: str, body: Transfer):
    with db() as conn:
        if conn.execute("SELECT 1 FROM users WHERE id=?", (body.to_user,)).fetchone() is None:
            raise HTTPException(404, "target user not found")
        cur = conn.execute("UPDATE nfts SET owner_id=? WHERE id=?", (body.to_user, nid))
        if cur.rowcount == 0:
            raise HTTPException(404, "nft not found")
    return {"id": nid, "owner_id": body.to_user}


@app.post("/nft/{nid}/gift")
def nft_gift(nid: str, body: Gift, from_user: str = Depends(current_user),
             idempotency_key: str = Header(default="")):
    """Визуально «подарить» карточку другому пользователю, как в оригинале.
    Даритель (from_user) определяется СЕРВЕРОМ по токену — нельзя дарить от чужого
    имени. Всё атомарно; Idempotency-Key защищает от двойного списания."""
    with db() as conn:
        cached = idem_get(conn, idempotency_key)
        if cached is not None:
            return cached

        nft = conn.execute("SELECT owner_id FROM nfts WHERE id=?", (nid,)).fetchone()
        if nft is None:
            raise HTTPException(404, "nft not found")
        if nft["owner_id"] != from_user:               # владелец проверяется на сервере
            raise HTTPException(403, "даритель не владеет этим подарком")
        if conn.execute("SELECT 1 FROM users WHERE id=?", (body.to_user,)).fetchone() is None:
            raise HTTPException(404, "получатель не найден")
        if from_user == body.to_user:
            raise HTTPException(400, "нельзя подарить самому себе")

        new_balance = deduct_stars(conn, from_user, body.stars_cost,
                                   f"gift {nid} → {body.to_user}")
        conn.execute("UPDATE nfts SET owner_id=? WHERE id=?", (body.to_user, nid))
        gid = uuid.uuid4().hex
        conn.execute(
            "INSERT INTO gifts_log(id,nft_id,from_user,to_user,stars_cost,message,created_at)"
            " VALUES(?,?,?,?,?,?,?)",
            (gid, nid, from_user, body.to_user, body.stars_cost,
             body.message, now()))
        result = {"gift_id": gid, "nft_id": nid, "owner_id": body.to_user,
                  "from_balance": new_balance}
        idem_put(conn, idempotency_key, result)
    return result


@app.post("/shop/purchase")
async def shop_purchase(body: Purchase, owner_id: str = Depends(current_user),
                        idempotency_key: str = Header(default="")):
    """Купить визуальный подарок за внутренние Stars (cost может быть 0 = бесплатно).
    Покупатель (owner_id) определяется СЕРВЕРОМ по токену."""
    with db() as conn:
        cached = idem_get(conn, idempotency_key)
        if cached is not None:
            return cached

    data = {"slug": body.slug, "name": body.name, "number": body.number,
            "model": body.model, "backdrop": body.backdrop, "symbol": body.symbol,
            "image_url": body.image_url}
    if body.slug and not body.name:
        resolved = await resolve_slug(body.slug)
        for k in ("name", "number", "model", "backdrop", "symbol", "image_url"):
            if not data.get(k) and resolved.get(k):
                data[k] = resolved[k]

    with db() as conn:
        new_balance = deduct_stars(conn, owner_id, body.stars_cost,
                                   f"purchase {body.slug or body.name}")
        nid = uuid.uuid4().hex
        conn.execute(
            "INSERT INTO nfts(id,slug,name,number,model,backdrop,symbol,image_url,"
            "owner_id,added_at,is_collectible) VALUES(?,?,?,?,?,?,?,?,?,?,?)",
            (nid, data["slug"], data["name"], data["number"], data["model"],
             data["backdrop"], data["symbol"], data["image_url"],
             owner_id, now(), 1 if body.collectible else 0))
        result = {"id": nid, "owner_id": owner_id, "balance": new_balance, **data}
        idem_put(conn, idempotency_key, result)
    return result


@app.post("/nft/{nid}/upgrade")
def nft_upgrade(nid: str, body: Upgrade, caller: str = Depends(current_user),
                idempotency_key: str = Header(default="")):
    """Апгрейд обычного подарка в коллекционный. Делать может только владелец
    (определяется по токену), звёзды списываются у него же."""
    with db() as conn:
        cached = idem_get(conn, idempotency_key)
        if cached is not None:
            return cached
        nft = conn.execute("SELECT owner_id, is_collectible FROM nfts WHERE id=?",
                           (nid,)).fetchone()
        if nft is None:
            raise HTTPException(404, "nft not found")
        if nft["owner_id"] != caller:
            raise HTTPException(403, "апгрейдить можно только свой подарок")
        if nft["is_collectible"]:
            raise HTTPException(400, "подарок уже коллекционный")

        new_balance = deduct_stars(conn, caller, body.stars_cost,
                                   f"upgrade {nid}")
        fields = {k: v for k, v in
                  {"model": body.model, "backdrop": body.backdrop,
                   "symbol": body.symbol}.items() if v is not None}
        fields["is_collectible"] = 1
        sets = ", ".join(f"{k}=?" for k in fields)
        conn.execute(f"UPDATE nfts SET {sets} WHERE id=?", (*fields.values(), nid))
        result = {"id": nid, "is_collectible": True, "balance": new_balance, **fields}
        idem_put(conn, idempotency_key, result)
    return result


@app.delete("/nft/{nid}", dependencies=[Depends(require_admin)])
def nft_delete(nid: str):
    with db() as conn:
        cur = conn.execute("DELETE FROM nfts WHERE id=?", (nid,))
        if cur.rowcount == 0:
            raise HTTPException(404, "nft not found")
    return {"deleted": nid}
