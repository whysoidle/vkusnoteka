# Сборка из исходников

Для обычной установки скачайте приложение из [Releases](https://github.com/whysoidle/vkusnoteka/releases/latest). Эта страница нужна, если вы хотите изменить код или собрать свою версию.

## Подготовка

В проекте используется **Flutter 3.47.6**. Зависимости закреплены в `app/pubspec.lock`.

```bash
git clone https://github.com/whysoidle/vkusnoteka.git
cd vkusnoteka/app
flutter pub get
flutter run
```

Если репозиторий закрыт, сначала войдите в GitHub с доступом к нему. Команды ниже выполняются из корня проекта, если не указано другое.

## Android

Нужны Android SDK и JDK 21. Сборку можно выполнять на macOS, Windows или Linux.

Для собственных обновляемых APK один раз создайте ключ подписи:

```bash
python3 scripts/init-signing.py
```

Затем соберите приложение:

```bash
cd app
flutter build apk --release
```

Результат: `app/build/app/outputs/flutter-apk/app-release.apk` относительно корня проекта.

Храните `.local-signing/recipe-vault.p12` и `app/android/key.properties`: они исключены из Git. Для обновления уже установленного APK нужен тот же ключ. Если ключа нет, проект собирает тестовый APK с отладочной подписью; такая подпись на другой машине может отличаться.

## macOS

Нужен Mac, полный Xcode 26+ с принятой лицензией и установленными начальными компонентами.

```bash
./scripts/build-macos.sh
```

Если Flutter не добавлен в PATH:

```bash
FLUTTER_BIN=/путь/к/flutter/bin/flutter ./scripts/build-macos.sh
```

Сценарий создаёт универсальное приложение для Apple Silicon и Intel, DMG, ZIP и SHA-256 в `dist`. Плагины подключены через Swift Package Manager, CocoaPods для этой сборки не нужен. Личная сборка использует ad-hoc-подпись; нотариализация Apple в сценарий не входит.

## Windows

Нужен Windows-компьютер с Visual Studio, компонентом **Desktop development with C++**, Windows SDK, Flutter и Inno Setup 6.

Из PowerShell в корне проекта:

```powershell
./scripts/build-windows.ps1
```

В `dist` появятся установщик, portable ZIP и контрольные суммы. Сценарий сам добавляет Visual C++ runtime и движок локального ИИ; веса модели скачиваются пользователем отдельно.

С Mac можно запустить сборку на Windows-сервере: [инструкция GitHub Actions](windows-github.md).

## Проверки

Flutter, из папки `app`:

```bash
flutter analyze
flutter test --enable-vmservice
```

Python-сервис, из корня проекта и в своём виртуальном окружении:

```bash
python -m pip install -r backend/requirements.lock
python -m pip install --no-deps -e ./backend
python -m pip install pytest pytest-asyncio
python -m pytest backend/tests -q
```

Для 1.0.8 прошли 183 теста Flutter и 23 теста Python. [Полный отчёт](validation.md)

## Дополнительный сервис импорта

Приложение работает и без него. Сервис пригодится, если вы хотите использовать собственный сервер разбора или Ollama вместо встроенной модели. Нужен Python 3.11+.

Создайте виртуальное окружение и активируйте его:

```bash
python -m venv .venv
```

macOS/Linux:

```bash
source .venv/bin/activate
```

Windows PowerShell:

```powershell
.venv\Scripts\Activate.ps1
```

Установите зависимости и запустите сервис из корня проекта:

```bash
python -m pip install -r backend/requirements.lock
python -m pip install --no-deps -e ./backend
uvicorn backend.main:app --host 0.0.0.0 --port 8000
```

Или используйте Docker. Сначала скопируйте `backend/.env.example` в `backend/.env` и настройте нужные значения:

```bash
docker build -f backend/Dockerfile -t recipe-vault-importer .
docker run --rm -p 8000:8000 --env-file backend/.env recipe-vault-importer
```

Обычный запуск uvicorn читает переменные окружения; `.env` в приведённом Docker-примере передаётся явно. `OLLAMA_MODEL` задаёт имя уже установленной модели Ollama, `OLLAMA_URL` — её адрес, по умолчанию `http://127.0.0.1:11434`. Без Ollama остаётся обычный разбор текста.

В приложении отключите локальный ИИ и укажите адрес в **Настройки → Импорт сайтов и YouTube → Адрес сервиса**:

| Откуда подключаетесь | Пример адреса |
| --- | --- |
| Тот же компьютер | `http://127.0.0.1:8000` |
| Телефон в одной сети с компьютером | `http://<IP-компьютера>:8000` |
| Эмулятор Android | `http://10.0.2.2:8000` |

`localhost` на телефоне означает сам телефон. Для сервиса вне домашней сети используйте HTTPS и `IMPORT_API_TOKEN`; тот же ключ укажите в приложении.

Проверка доступности: `GET /health`. Импорт: `POST /import` с JSON `{"content":"текст или ссылка"}`. Интерактивное описание API доступно по `/docs` на вашем сервисе. Каталог и пароль Яндекс Диска сервису не передаются; отправленный текст или ссылка обрабатываются им.

## Архив исходников

```bash
python3 scripts/package-source.py
```

Получится `dist/Vkusnoteka-Source.zip` с кодом и документацией. Ключи подписи, локальные пароли, SDK и кеши в архив не включаются.
