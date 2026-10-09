import codecs
import pytest

from backend.html_decoder import decode_html
from backend.parser import parse_html


PAGE = '''<html><head><meta http-equiv="Content-Type" content="text/html; charset=windows-1251">
<title>Рецепт на RussianFood.com</title></head><body><h1 class="title">Макароны с сыром</h1>
<table class="ingr"><tr><td class="ingr_title"><span class="portion">(на 3 порции)</span></td></tr>
<tr class="ingr_tr_0"><td>Макароны — 200 г</td></tr><tr class="ingr_tr_1"><td>Сыр — 100 г</td></tr></table>
<div class="step_images_n"><div class="step_n"><p>Отварите макароны.</p><div>Реклама</div></div>
<div class="step_n"><p>Добавьте сыр.</p></div></div></body></html>'''


@pytest.mark.parametrize('header', ['text/html; charset=windows-1251', 'text/html'])
def test_legacy_cyrillic_html_and_russianfood_recipe(header):
    decoded = decode_html(PAGE.encode('cp1251'), header)
    assert '\ufffd' not in decoded
    url = 'https://www.russianfood.com/recipes/recipe.php?rid=161091'
    recipes, _, _ = parse_html(decoded, url)
    recipe = recipes[0]
    assert recipe['title'] == 'Макароны с сыром'
    assert recipe['ingredients'] == ['Макароны — 200 г', 'Сыр — 100 г']
    assert recipe['steps'] == ['Отварите макароны.', 'Добавьте сыр.']
    assert recipe['sourceUrl'] == url and not recipe['draft']


def test_utf8_header_overrides_meta():
    assert 'Сыр 🧀' in decode_html('<meta charset="windows-1251"><p>Сыр 🧀</p>'.encode(), 'text/html; charset=utf-8')


def test_bom_overrides_header():
    assert decode_html(codecs.BOM_UTF8 + 'Сыр 🧀'.encode(), 'text/html; charset=windows-1251') == 'Сыр 🧀'
    assert decode_html('Сыр'.encode('utf-16')) == 'Сыр'


def test_cp1251_alias_and_yo():
    assert decode_html(bytes([0xcf, 0xf0, 0xe8, 0xe2, 0xe5, 0xf2, 0x20, 0xa8, 0xb8]), 'text/html; charset="cp1251"') == 'Привет Ёё'


def test_unmarked_utf8_and_comment_meta():
    assert decode_html('Рецепт 🥣'.encode()) == 'Рецепт 🥣'
    assert '<p>Сыр</p>' in decode_html('<!-- <meta charset="windows-1251"> --><p>Сыр</p>'.encode())


def test_invalid_unmarked_utf8_is_not_replaced():
    with pytest.raises(UnicodeDecodeError):
        decode_html(b'\xff\xff')
