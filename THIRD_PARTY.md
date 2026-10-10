# Сторонние компоненты

Код Вкуснотеки распространяется под [GPLv3](LICENSE). Сторонние компоненты сохраняют собственные лицензии, авторские уведомления и условия распространения. Этот список помогает найти их; он не заменяет полные тексты лицензий и уведомления внутри конкретных пакетов.

| Компонент | Лицензия и источник |
| --- | --- |
| Flutter | [BSD-3-Clause](https://github.com/flutter/flutter/blob/master/LICENSE) |
| Google LiteRT-LM 0.18.0, Android и macOS | [Apache-2.0](https://github.com/google-ai-edge/LiteRT-LM/blob/v0.18.0/LICENSE); [копия лицензии](app/macos/RecipeMacNative/Sources/RecipeMacNative/Resources/LiteRT-LM-LICENSE.txt) и [уведомление](app/macos/RecipeMacNative/Sources/RecipeMacNative/Resources/NOTICE.txt) в проекте |
| llama.cpp b11429, Windows | [MIT](https://github.com/ggml-org/llama.cpp/blob/b11429/LICENSE); текст включён в `LocalAI/LICENSE-llama.cpp.txt` Windows-сборки |
| LLVM OpenMP, Windows | Apache-2.0 WITH LLVM-exception; полный текст включён в `LocalAI/LICENSE-LLVM-OpenMP` Windows-сборки |
| Qwen3 1.7B, модель Android и macOS | [Карточка конвертации LiteRT](https://huggingface.co/litert-community/Qwen3-1.7B/blob/73fbc3fe8271c162a603ee66f6e7ed25b6211195/README.md) ссылается на [Apache-2.0 исходной модели](https://huggingface.co/Qwen/Qwen3-1.7B/blob/main/LICENSE) |
| Qwen3 4B GGUF, модель Windows | [Apache-2.0](https://huggingface.co/Qwen/Qwen3-4B-GGUF/blob/bc640142c66e1fdd12af0bd68f40445458f3869b/LICENSE); текст включён в `LocalAI/LICENSE-Qwen3.txt` Windows-сборки |
| Данные Tesseract OCR | [Apache-2.0](app/assets/tessdata/LICENSE) |
| pdfrx и Dart-обвязка PDFium | [MIT](https://github.com/espresso3389/pdfrx/blob/master/LICENSE); нативный [PDFium](https://pdfium.googlesource.com/pdfium/+/refs/heads/main/LICENSE) и его зависимости имеют отдельные уведомления |
| Microsoft Visual C++ Runtime, Windows | Распространяется по условиям Microsoft. Это системная зависимость с собственной лицензией, а не часть кода Вкуснотеки под GPLv3 |

Остальные Dart-зависимости и их точные версии перечислены в [pubspec.lock](app/pubspec.lock), Python-зависимости — в [requirements.lock](backend/requirements.lock). Тексты их лицензий находятся в исходных пакетах. Flutter собирает уведомления Dart-пакетов в ресурсы приложения. У нативных библиотек могут быть дополнительные зависимости и уведомления.

При подготовке собственной сборки сохраняйте лицензии и уведомления всех включённых компонентов. Скачиваемые модели распространяются отдельно от установщиков. Лицензия приложения не предоставляет права на чужие рецепты, фотографии или видео.
