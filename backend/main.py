import asyncio
import hmac
import os

import httpx
from fastapi import FastAPI, Header, HTTPException
from pydantic import BaseModel, Field

from .importer import ImportProblem, import_recipe

app = FastAPI(title="Recipe Vault Importer", version="1.0.0")
slots = asyncio.Semaphore(3)


class ImportRequest(BaseModel):
    content: str = Field(min_length=1, max_length=50000)


@app.get("/health")
async def health():
    return {"status": "ok", "modelEnabled": bool(os.getenv("OLLAMA_MODEL"))}


@app.post("/import")
async def import_endpoint(request: ImportRequest, authorization: str = Header(default="")):
    secret = os.getenv("IMPORT_API_TOKEN", "")
    if secret and not hmac.compare_digest(authorization, f"Bearer {secret}"):
        raise HTTPException(401, "Неверный ключ сервиса импорта.")
    if not request.content.strip():
        raise HTTPException(422, "Вставьте текст или ссылку.")
    async with slots:
        try:
            return await asyncio.wait_for(import_recipe(request.content), timeout=180)
        except ImportProblem as exc:
            raise HTTPException(422, str(exc)) from exc
        except (httpx.HTTPError, asyncio.TimeoutError) as exc:
            raise HTTPException(502, "Источник недоступен. Ссылку можно сохранить и заполнить рецепт вручную.") from exc
