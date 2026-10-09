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

## Первый выпуск Windows 1.0.5

[Запуск Actions](https://github.com/whysoidle/vkusnoteka/actions/runs/37977871653) собран из commit `4daf79cace47767829f98e4ceab52fac29a3c307`. На CI прошли 150 тестов Flutter и 23 теста Python, затем Windows-сервер собрал установщик и portable ZIP. Скачанные файлы проверены по SHA-256; проверены версия, бренд, x64, Visual C++ runtime и состав portable-пакета. Ручная проверка интерфейса Windows не выполнялась.

- `dist/Vkusnoteka-Windows-1.0.5-Setup.exe` — установщик, 18 505 296 байт.
- `dist/Vkusnoteka-Windows-1.0.5-Portable.zip` — portable-пакет, 23 155 181 байт.
- `dist/Vkusnoteka-Windows-1.0.5.sha256` — контрольные суммы.
