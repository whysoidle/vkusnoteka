# Windows-сборка через GitHub

Репозиторий проекта: [whysoidle/vkusnoteka](https://github.com/whysoidle/vkusnoteka), приватный. Текущая папка проекта связана с ним через Git remote `origin`; изменения видны в Source Control VS Code.

## Повторная сборка

1. Загрузите нужные изменения в `main`.
2. Откройте **Actions → Build Android, Windows and macOS → Run workflow**.
3. Выберите `main` и `platform: windows`.
4. После прохождения общих проверок задача `windows` соберёт приложение через Flutter и упакует его через Inno Setup.
5. Скачайте **Artifacts → Vkusnoteka-Windows-Setup**. Внутри находятся установщик с номером версии, portable ZIP и SHA-256.

Ручной запуск `platform: windows` пропускает Android/macOS. Значение `all` собирает три платформы. Автоматические запуски при push в `main` и pull request сохраняют проверки и сборки всех платформ.

## Доступ из VS Code

Плагины Codex не поддерживаются в IDE-расширении. Для загрузки исходников и управления Actions используется GitHub CLI; отдельное расширение VS Code для этого не требуется.

На этом Mac CLI установлен в `~/.local/bin/gh` и настроен для HTTPS. При необходимости повторного входа выполните в терминале:

```bash
~/.local/bin/gh auth login --hostname github.com --git-protocol https --web --scopes workflow
```

Вход подтверждается на сайте GitHub. Секреты Android нужны только для подписи Android APK; сборка Windows использует встроенный токен GitHub Actions с `contents: read`.

Пример запуска из терминала:

```bash
~/.local/bin/gh workflow run build.yml --repo whysoidle/vkusnoteka --ref main -f platform=windows
```

Сборка x64 предназначена для Windows. Установщик не подписан коммерческим сертификатом. Идентификатор приложения и каталог данных сохраняются при обновлении: техническое поле `ProductName` остаётся прежним, а отображаемое имя — «Вкуснотека».

Источники: [вход GitHub CLI](https://cli.github.com/manual/gh_auth_login), [ручной запуск Actions](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow), [плагины Codex и поддерживаемые интерфейсы](https://learn.chatgpt.com/docs/plugins).

## Выпуск Windows 1.0.7

[Успешный запуск Actions](https://github.com/whysoidle/vkusnoteka/actions/runs/38034865606), commit `b121821caf715bde1c63ea0a3a3cb02021496e36`. Прошли 168 тестов Flutter, 23 теста Python, анализатор, нативный тест процесса и проверка настоящей модели ИИ. Установщик `dist/Vkusnoteka-Windows-1.0.7-Setup.exe` и portable ZIP скачаны и проверены по SHA-256. Android и macOS собраны на Mac с тем же номером 1.0.7/build 17.

В Windows исправлена прокрутка пустых полей страниц, приглушена иконка импорта, добавлены жесты и глобальные `Ctrl+N`/`Ctrl+F`. Локальный ИИ из 1.0.6 сохранён; модель повторно скачивать после обновления не нужно. [Описание выпуска](release-1.0.7.md), [полный отчёт](validation.md).

## Выпуск Windows 1.0.6 с локальным ИИ

[Успешный запуск Actions](https://github.com/whysoidle/vkusnoteka/actions/runs/37987056030), commit `7a20dd15536a7a393a223e31ac18ffdbd7d9f6f8`. Прошли 158 тестов Flutter, 23 теста Python, анализатор, нативный тест процесса и разбор настоящей Qwen3 4B на Windows CPU. В артефакте `Vkusnoteka-Windows-AI-Validation` сохранены проверенные запросы и ответы модели.

- `dist/Vkusnoteka-Windows-1.0.6-Setup.exe` — установщик, 28 845 872 байта.
- `dist/Vkusnoteka-Windows-1.0.6-Portable.zip` — portable-пакет, 44 207 312 байт.
- `dist/Vkusnoteka-Windows-1.0.6.sha256` — проверенные контрольные суммы.

После установки откройте **Настройки → Локальный ИИ → Скачать модель**. Движок уже включён в приложение; Ollama и Python устанавливать не нужно. Qwen3 4B Q4_K_M загружается отдельно и занимает около 2,50 ГБ. Рекомендуется от 8 ГБ оперативной памяти и 3,5 ГБ свободного места; для ИИ нужны Windows 10 версии 1903 или новее либо Windows 11, x64. Проверены русские пути с пробелами, отмена и освобождение процесса. Ручная проверка интерфейса на Windows не выполнялась. [Правила разбора](release-1.0.6.md), [отчёт о проверках](validation.md).

## Первый выпуск Windows 1.0.5

[Запуск Actions](https://github.com/whysoidle/vkusnoteka/actions/runs/37977871653) собран из commit `4daf79cace47767829f98e4ceab52fac29a3c307`. На CI прошли 150 тестов Flutter и 23 теста Python, затем Windows-сервер собрал установщик и portable ZIP. Скачанные файлы проверены по SHA-256; проверены версия, бренд, x64, Visual C++ runtime и состав portable-пакета. Ручная проверка интерфейса Windows не выполнялась.

- `dist/Vkusnoteka-Windows-1.0.5-Setup.exe` — установщик, 18 505 296 байт.
- `dist/Vkusnoteka-Windows-1.0.5-Portable.zip` — portable-пакет, 23 155 181 байт.
- `dist/Vkusnoteka-Windows-1.0.5.sha256` — контрольные суммы.
