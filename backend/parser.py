"""Conservative extraction: missing ingredients and quantities stay missing."""
import json
import re
from typing import Any
from urllib.parse import urlparse

from bs4 import BeautifulSoup

INGREDIENT_HEADER = re.compile(r"^(ингредиенты|состав|продукты|ingredients)\s*[:：]?\s*$", re.I)
STEP_HEADER = re.compile(r"^(приготовление|способ приготовления|инструкция|шаги|instructions|directions|method)\s*[:：]?\s*$", re.I)
QUANTITY = re.compile(r"\d[\d.,/\s]*\s*(?:кг|гр?\.?|мл|л|шт\.?|ст\.?\s*л\.?|ч\.?\s*л\.?|стакан\w*|зубчик\w*|tbsp|tsp|cups?|grams?|kg|ml)\b", re.I)


def empty_recipe(source_url: str = "", title: str = "Новый рецепт") -> dict:
    return {"title": title, "ingredients": [], "steps": [], "category": "Без категории",
            "servings": "", "time": "", "notes": "", "sourceUrl": source_url,
            "sourceText": "", "favorite": False, "draft": True}


def parse_text(text: str, source_url: str = "", title: str = "") -> dict:
    lines = [re.sub(r"^\s*[-•*]\s*", "", s).strip() for s in text.splitlines() if s.strip()]
    recipe = empty_recipe(source_url, title or (lines[0][:160] if lines else "Новый рецепт"))
    recipe["sourceText"] = text
    section = ""
    notes = []
    for i, line in enumerate(lines):
        if INGREDIENT_HEADER.fullmatch(line):
            section = "ingredients"
        elif STEP_HEADER.fullmatch(line):
            section = "steps"
        elif re.match(r"^(заметки|советы|примечания|notes)\s*:", line, re.I):
            section = "notes"
            notes.append(line.split(":", 1)[-1].strip())
        elif re.match(r"^(порци[ияй]|servings)\s*:", line, re.I):
            recipe["servings"] = line.split(":", 1)[-1].strip()
        elif re.match(r"^(время|time)\s*:", line, re.I):
            recipe["time"] = line.split(":", 1)[-1].strip()
        elif i == 0 and not title:
            continue
        elif section == "ingredients":
            recipe["ingredients"].append(line)
        elif section == "steps" or re.match(r"^\d+[.)]\s", line):
            recipe["steps"].append(re.sub(r"^\d+[.)]\s*", "", line))
        elif QUANTITY.search(line) and len(line) < 160:
            recipe["ingredients"].append(line)
        else:
            notes.append(line)
    recipe["notes"] = "\n".join(notes)
    recipe["draft"] = not (recipe["ingredients"] and recipe["steps"])
    return recipe


def find_recipes(value: Any) -> list[dict]:
    found = []
    if isinstance(value, list):
        for item in value:
            found.extend(find_recipes(item))
    elif isinstance(value, dict):
        types = value.get("@type", [])
        types = [types] if isinstance(types, str) else types
        if isinstance(types, list) and any(str(t).rsplit("/", 1)[-1] == "Recipe" for t in types):
            found.append(value)
        for child in value.values():
            if isinstance(child, (dict, list)):
                found.extend(find_recipes(child))
    return found


def plain(value: Any) -> str:
    return BeautifulSoup(str(value or ""), "html.parser").get_text(" ", strip=True)


def instructions(value: Any) -> list[str]:
    if isinstance(value, str):
        soup = BeautifulSoup(value, "html.parser")
        blocks = soup.find_all(["li", "p"])
        text = [s.get_text(" ", strip=True) for s in blocks] if blocks else value.splitlines()
        return [plain(s) for s in text if plain(s)]
    if isinstance(value, list):
        return [step for item in value for step in instructions(item)]
    if isinstance(value, dict):
        return instructions(value.get("itemListElement", value.get("text", "")))
    return []


def ingredient(value: Any) -> str:
    if isinstance(value, dict):
        return " ".join(plain(value.get(k)) for k in ("name", "value", "unitText", "unitCode") if value.get(k))
    return plain(value)


def readable_time(value: Any) -> str:
    text = plain(value)
    match = re.fullmatch(r"PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?", text)
    if not match:
        return text
    return " ".join(f"{amount} {unit}" for amount, unit in zip(match.groups(), ("ч", "мин", "сек")) if amount)


def parse_html(html: str, url: str) -> tuple[list[dict], str, str]:
    soup = BeautifulSoup(html, "html.parser")
    title = soup.title.get_text(strip=True) if soup.title else "Рецепт с сайта"
    recipes = []
    for script in soup.find_all("script", type="application/ld+json"):
        try:
            nodes = find_recipes(json.loads(script.string or script.get_text()))
        except (ValueError, TypeError):
            continue
        for node in nodes:
            recipe = empty_recipe(url, plain(node.get("name")) or title)
            raw = node.get("recipeIngredient", [])
            recipe["ingredients"] = [ingredient(x) for x in (raw if isinstance(raw, list) else [raw]) if ingredient(x)]
            recipe["steps"] = instructions(node.get("recipeInstructions", []))
            category = node.get("recipeCategory", "Без категории")
            recipe["category"] = plain(category[0] if isinstance(category, list) and category else category)
            servings = node.get("recipeYield", "")
            recipe["servings"] = ", ".join(map(str, servings)) if isinstance(servings, list) else plain(servings)
            recipe["time"] = readable_time(node.get("totalTime") or node.get("cookTime"))
            recipe["notes"] = plain(node.get("description"))
            recipe["draft"] = not (recipe["ingredients"] and recipe["steps"])
            recipes.append(recipe)
    host = (urlparse(url).hostname or "").lower()
    if not recipes and (host == "russianfood.com" or host.endswith(".russianfood.com")):
        heading = soup.select_one("h1.title")
        ingredients = [e.get_text(" ", strip=True) for e in soup.select('table.ingr tr[class^="ingr_tr_"] td')]
        ingredients = [s for s in ingredients if s and s != "*"]
        steps = [e.get_text(" ", strip=True) for e in soup.select(".step_images_n .step_n > p")]
        steps = [s for s in steps if s]
        if heading and (ingredients or steps):
            recipe = empty_recipe(url, heading.get_text(" ", strip=True))
            recipe["ingredients"] = ingredients
            recipe["steps"] = steps
            portion = soup.select_one("table.ingr .portion")
            recipe["servings"] = portion.get_text(" ", strip=True).strip("()") if portion else ""
            recipe["draft"] = not (ingredients and steps)
            recipes.append(recipe)
    for tag in soup(["script", "style", "nav", "footer", "header"]):
        tag.decompose()
    body = soup.find("article") or soup.find("main") or soup
    return recipes, body.get_text("\n", strip=True)[:50000], title
