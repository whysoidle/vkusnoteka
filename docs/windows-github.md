# Собрать Windows-версию через GitHub

Этим способом можно пользоваться с Mac: компиляция выполняется на Windows-сервере GitHub, а готовые файлы скачиваются через браузер. Для установки уже готовой версии откройте [Releases](https://github.com/whysoidle/vkusnoteka/releases/latest).

## Через сайт

1. Отправьте нужные изменения в ветку `main` репозитория [whysoidle/vkusnoteka](https://github.com/whysoidle/vkusnoteka).
2. Откройте **Actions → Build Android, Windows and macOS**.
3. Нажмите **Run workflow**, выберите ветку `main` и `platform: windows`.
4. Дождитесь завершения задач `checks` и `windows`.
5. Внизу страницы запуска скачайте **Artifacts → Vkusnoteka-Windows-Setup**.

В артефакте будут EXE-установщик, portable ZIP и SHA-256. Артефакт сначала нужно распаковать. Portable-архив также распакуйте целиком, затем запустите `recipe_vault.exe`.

`platform: windows` собирает только Windows после общих проверок. `all` запускает сборки трёх платформ. Обычные push в `main` и pull request также запускают workflow; коммиты только с документацией в этом проекте можно отмечать `[skip ci]`.

## Через терминал VS Code

Если GitHub CLI уже установлен, выполните:

```bash
gh auth login --hostname github.com --git-protocol https --web --scopes workflow
```

Подтвердите вход в браузере. Затем из терминала:

```bash
gh workflow run build.yml --repo whysoidle/vkusnoteka --ref main -f platform=windows
gh run list --repo whysoidle/vkusnoteka --workflow build.yml
```

Номер запуска из списка можно использовать для скачивания:

```bash
gh run download НОМЕР_ЗАПУСКА --repo whysoidle/vkusnoteka --name Vkusnoteka-Windows-Setup --dir dist
```

Отдельное расширение VS Code для этих команд не требуется. Если CLI установлен в `~/.local/bin/gh`, используйте этот путь вместо `gh`.

## Что проверяет сборка

Сначала выполняются тесты Python, анализ Flutter и Flutter-тесты. Затем собирается Windows-приложение, добавляются библиотеки и движок ИИ, создаются установщик и portable-архив. Отдельно проверяются завершение процесса ИИ и разбор настоящей моделью.

Этот workflow создаёт **Artifacts**, но сам не публикует **Release**. Готовые установщики для пользователей находятся в [разделе выпусков](https://github.com/whysoidle/vkusnoteka/releases).

Для Windows-сборки секреты подписи Android не нужны. Они требуются только для выпуска APK с постоянной подписью.

## Проверенный выпуск 1.0.8

[Запуск 38038774625](https://github.com/whysoidle/vkusnoteka/actions/runs/38038774625) завершился успешно: 183 теста Flutter, 23 теста Python, нативный тест и настоящий разбор Qwen3 4B. Готовые файлы проверены по контрольным суммам. [Отчёт](validation.md)

При переносе проекта в другой репозиторий замените `whysoidle/vkusnoteka` в командах на свой `владелец/репозиторий`.
