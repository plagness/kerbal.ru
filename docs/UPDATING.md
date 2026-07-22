# Обновление и откат kerbal.ru

Русификатор выпускается версиями `vMAJOR.MINOR.PATCH`. Установщик по умолчанию берёт последний стабильный GitHub Release и хранит установленную версию рядом с KSP.

## Обычное обновление

Закрой KSP и повтори команду установки.

### Linux, macOS, Steam Deck

```bash
curl -fsSL https://raw.githubusercontent.com/plagness/kerbal.ru/main/install-ru.sh | bash
```

### Windows PowerShell

```powershell
irm https://raw.githubusercontent.com/plagness/kerbal.ru/main/install-ru.ps1 | iex
```

Если стояла v1, а последним релизом стала v2, установщик увидит разницу, сделает резервную копию и поставит v2. Повторный запуск на той же версии ничего не перезаписывает.

## Что хранится в каталоге KSP

| Путь | Назначение |
|---|---|
| `.kerbalru-version` | установленная версия, например `1.0.0` |
| `.kerbalru-files` | список файлов, которыми управляет kerbal.ru |
| `kerbal.ru-backups/<версия>-<дата>/` | копии файлов перед обновлением |
| `settings.cfg.bak-kerbalru` | исходный `settings.cfg` до первого переключения языка |

Установщик никогда не очищает `GameData` целиком. При обновлении он может удалить только путь, который одновременно был записан в старом `.kerbalru-files` и отсутствует в новом релизе. Перед этим существующий файл попадает в backup.

## Проверить обновление без установки

```bash
curl -fsSL https://raw.githubusercontent.com/plagness/kerbal.ru/main/install-ru.sh | bash -s -- --check
```

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/plagness/kerbal.ru/main/install-ru.ps1))) -Check
```

Команда выводит установленную и доступную версии и не меняет файлы.

## Установить конкретную версию

Это полезно для одинаковой сборки у нескольких игроков или временного отката.

```bash
curl -fsSL https://raw.githubusercontent.com/plagness/kerbal.ru/main/install-ru.sh | bash -s -- --version v1.0.0
```

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/plagness/kerbal.ru/main/install-ru.ps1))) -Version v1.0.0
```

Указанный тег должен существовать в [GitHub Releases](https://github.com/plagness/kerbal.ru/releases).

## Тестовый канал `main`

В `main` могут находиться переводы, ещё не вошедшие в релиз и не подтверждённые живым запуском. Канал нужен тестировщикам, не обычной игре.

```bash
curl -fsSL https://raw.githubusercontent.com/plagness/kerbal.ru/main/install-ru.sh | bash -s -- --channel main
```

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/plagness/kerbal.ru/main/install-ru.ps1))) -Channel main
```

Версия такого обновления выглядит как `main-401092d`. Чтобы вернуться на stable, снова выполни обычную команду без параметров.

## Восстановление из backup

1. Закрой KSP.
2. Найди нужную папку в `kerbal.ru-backups/`.
3. Скопируй её содержимое обратно в корень `Kerbal Space Program` с заменой.
4. Установи нужный релиз через `--version` или `-Version`, чтобы manifest и версия снова соответствовали файлам.

Backup содержит только файлы, затронутые обновлением, а не всю игру и не сохранения. Для полной страховки перед крупным обновлением модпака отдельно сохрани папку `saves`.

## После обновления модов через CKAN

CKAN может заменить каталоги модов и удалить добавленные внутрь них `ru.cfg`. Поэтому порядок такой:

1. обновить RO/RSS/RP-1 и зависимости через CKAN;
2. запустить KSP один раз, если обновлялся ModuleManager или состав модов;
3. повторно запустить установщик kerbal.ru с `--force` / `-Force`;
4. запустить KSP и при необходимости пересобрать аудит кэша.

Если новый релиз мода переименовал ключи или детали, старый перевод может стать неполным даже при актуальной версии kerbal.ru. Сообщи об этом через шаблон «Проблема перевода» и укажи версию мода.

## Когда обновлять номер релиза maintainer-у

Релизный PR должен:

1. изменить `VERSION`;
2. обновить цифры покрытия и заметки для игроков;
3. пройти GitHub Actions;
4. быть проверен на чистой установке и поверх предыдущего релиза;
5. получить тег `v<содержимое VERSION>`.

Тег запускает workflow создания GitHub Release. После публикации обычная команда установки автоматически начинает предлагать новую версию.
