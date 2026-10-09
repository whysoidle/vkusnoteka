# Вкуснотека

Выбран вариант №4 из `docs/design/icon-concepts-v1`: стеклянная книга с зелёной закладкой.

- `vkusnoteka-desktop.png`: мастер для macOS, Windows и старых версий Android; прозрачный фон вокруг зелёной плитки.
- `vkusnoteka-foreground.png`: прозрачный передний слой адаптивной иконки Android.

Подготовлено встроенным image_gen (навык imagegen). Системные размеры PNG создаются через macOS sips; Windows ICO содержит PNG нескольких размеров. Эти операции меняют только размер и контейнер изображения.

Промпты редактирования выбранного изображения:

## 1

```text
Use case: background-extraction.
Asset type: production desktop application icon PNG with real alpha transparency.
Edit target: the provided selected glass cookbook icon.
Primary request: remove ONLY the warm off-white exterior background and exterior cast shadow outside the green rounded-square tile. Replace that exterior with actual alpha transparency, NOT a checkerboard drawing. Preserve the entire green tile including its rounded silhouette, and preserve the glass cookbook, green bookmark, reflections, colors, placement and size exactly. Keep the square canvas and approximately original 8% transparent inset on every side. Do not redesign, crop, zoom, recolor, sharpen, or add anything. No text.
```

## 2

```text
Use case: background-extraction.
Asset type: production Android adaptive icon FOREGROUND layer with actual alpha transparency.
Edit target: the provided selected glass cookbook icon.
Primary request: isolate ONLY the complete translucent ivory open cookbook and its green bookmark, replacing the entire green square tile, exterior off-white background and exterior tile shadow with real alpha transparency. Keep the complete cookbook centered at its original scale and position, with its original silhouette, ivory glass appearance, green bookmark, internal reflections and illumination. Preserve a cohesive bright ivory glass book, not just thin outlines. The green tile must disappear completely; no rectangle, circle or icon frame behind the book. No checkerboard drawing, no text, no added decoration. Square canvas.
```

