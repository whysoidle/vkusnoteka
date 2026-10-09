import json
from unittest.mock import AsyncMock

import httpx
import pytest
from fastapi.testclient import TestClient

from backend import importer
from backend.main import app
from backend.parser import parse_html, parse_text


@pytest.fixture(autouse=True)
def no_model(monkeypatch):
    monkeypatch.delenv("OLLAMA_MODEL", raising=False)
    monkeypatch.delenv("IMPORT_API_TOKEN", raising=False)


def test_russian_text_preserves_amounts_and_missing_values():
    recipe = parse_text("Сырники\nИнгредиенты:\nТворог — 400 г\nСоль по вкусу\nПриготовление:\n1. Смешайте.\n2. Обжарьте.\nВремя: 20 минут\nПорции: 2")
    assert recipe["ingredients"] == ["Творог — 400 г", "Соль по вкусу"]
    assert recipe["steps"] == ["Смешайте.", "Обжарьте."]
    assert recipe["time"] == "20 минут"
    assert not recipe["draft"]


def test_non_recipe_stays_draft():
    recipe = parse_text("Заметка\nКакой красивый пейзаж")
    assert recipe["draft"]
    assert recipe["ingredients"] == [] and recipe["steps"] == []
    assert recipe["servings"] == ""


def test_graph_multiple_recipes_and_section_steps():
    data = {"@graph": [{"@type": "Recipe", "name": "Суп", "recipeIngredient": ["Вода — 1 л"],
      "recipeInstructions": [{"@type": "HowToSection", "itemListElement": [{"@type": "HowToStep", "text": "<b>Вскипятите</b> воду."}]}]},
      {"@type": ["CreativeWork", "Recipe"], "name": "Чай", "recipeIngredient": ["Чай"], "recipeInstructions": "Заварите."}]}
    html = f'<title>Кухня</title><script type="application/ld+json">{json.dumps(data)}</script>'
    recipes, _, _ = parse_html(html, "https://example.com/recipe")
    assert len(recipes) == 2
    assert recipes[0]["steps"] == ["Вскипятите воду."]
    assert recipes[1]["sourceUrl"] == "https://example.com/recipe"


def test_invalid_jsonld_does_not_crash():
    recipes, text, title = parse_html('<title>Страница</title><script type="application/ld+json">bad</script><main>Текст</main>', "https://example.com")
    assert recipes == [] and text == "Текст" and title == "Страница"


@pytest.mark.parametrize("url", ["https://youtu.be/abcdefghijk?t=30", "https://www.youtube.com/watch?v=abcdefghijk", "https://youtube.com/shorts/abcdefghijk"])
def test_youtube_links(url):
    assert importer.youtube_id(url) == "abcdefghijk"


def test_fake_youtube_domain_is_not_video():
    assert importer.youtube_id("https://youtube.com.evil.test/watch?v=abcdefghijk") is None


async def test_unavailable_youtube_keeps_exact_link(monkeypatch):
    monkeypatch.setattr(importer, "fetch_page", AsyncMock(side_effect=importer.ImportProblem("unavailable")))
    monkeypatch.setattr(importer, "transcript", lambda _: (_ for _ in ()).throw(RuntimeError("no captions")))
    url = "https://youtu.be/abcdefghijk?t=15"
    result = await importer.import_recipe(url)
    assert result["recipes"][0]["sourceUrl"] == url
    assert result["recipes"][0]["draft"]
    assert result["warnings"]


async def test_youtube_description_is_used_without_transcript(monkeypatch):
    details = {"videoDetails": {"title": "Сырники", "shortDescription": "Ингредиенты:\nТворог — 400 г\nПриготовление:\nОбжарьте."}}
    html = "var ytInitialPlayerResponse = " + json.dumps(details) + ";"
    monkeypatch.setattr(importer, "fetch_page", AsyncMock(return_value=(html, "")))
    result = await importer.import_recipe("https://youtu.be/abcdefghijk")
    assert not result["recipes"][0]["draft"]
    assert result["recipes"][0]["title"] == "Сырники"


async def test_rejects_local_network(monkeypatch):
    monkeypatch.setattr(importer.socket, "getaddrinfo", lambda *args: [(2, 1, 6, "", ("127.0.0.1", 80))])
    with pytest.raises(importer.ImportProblem):
        await importer.validate_public_url("http://localhost/test")


async def test_model_failure_falls_back_without_losing_source(monkeypatch):
    monkeypatch.setattr(importer, "parse_with_model", AsyncMock(side_effect=httpx.ConnectError("offline")))
    recipe, warnings = await importer.extract_text("Суп\nИнгредиенты:\nВода — 1 л\nПриготовление:\nВскипятите.", "https://example.com", "Суп")
    assert not recipe["draft"] and recipe["sourceUrl"] == "https://example.com"
    assert warnings


def test_api_auth_and_validation(monkeypatch):
    monkeypatch.setenv("IMPORT_API_TOKEN", "secret")
    with TestClient(app) as client:
        assert client.post("/import", json={"content": "Суп"}).status_code == 401
        response = client.post("/import", json={"content": "Суп\nИнгредиенты:\nВода\nПриготовление:\nВскипятите."}, headers={"Authorization": "Bearer secret"})
        assert response.status_code == 200
        assert response.json()["recipes"][0]["steps"] == ["Вскипятите."]
        assert client.post("/import", json={"content": " "}, headers={"Authorization": "Bearer secret"}).status_code == 422


@pytest.mark.parametrize("failed", [False, True])
def test_transcript_always_closes_http_session(monkeypatch, failed):
    from types import SimpleNamespace
    sessions = []

    class Session(importer.TranscriptSession):
        def __init__(self):
            super().__init__()
            self.closed = False
            sessions.append(self)

        def close(self):
            self.closed = True
            super().close()

    class Api:
        def __init__(self, http_client):
            assert http_client is sessions[0]

        def list(self, _):
            if failed:
                raise RuntimeError("unavailable")
            return SimpleNamespace(find_transcript=lambda _: SimpleNamespace(fetch=lambda: [SimpleNamespace(text="Мука — 200 г")]))

    monkeypatch.setattr(importer, "TranscriptSession", Session)
    monkeypatch.setattr(importer, "YouTubeTranscriptApi", Api)
    if failed:
        with pytest.raises(RuntimeError):
            importer.transcript("abcdefghijk")
    else:
        assert importer.transcript("abcdefghijk") == "Мука — 200 г"
    assert sessions[0].closed


def test_transcript_worker_has_a_network_timeout(monkeypatch):
    captured = {}

    def request(self, *args, **kwargs):
        captured.update(kwargs)

    monkeypatch.setattr(importer.requests.Session, "request", request)
    with importer.TranscriptSession() as session:
        session.get("https://example.com")
    assert captured["timeout"] == (10, 20)
