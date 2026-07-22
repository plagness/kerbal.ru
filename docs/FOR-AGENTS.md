# Для ИИ-агентов: настройка сборки и русификатора по просьбе пользователя

Если пользователь просит агента «настроить KSP / поставить реалистичную сборку / русифицировать» — этот файл описывает проверенный путь и грабли. Экономит часы.

## Контекст

- Целевая сборка: **RO / RSS / RP-1** (Realism Overhaul + Real Solar System + Realistic Progression One) на KSP **1.12.5**.
- Переводы на русский **уже готовы** в этом репозитории (`plagness/kerbal.ru`, 20 модов). Не переводи заново — используй готовое.
- Ставится всё через **CKAN**. Русификатор — поверх, копированием `GameData`.

## Быстрый путь (то, что нужно пользователю в 95% случаев)

1. Убедись, что стоит **лицензионная KSP 1.12.5** (Steam). Пиратку/репак не качай и не предлагай.
2. Поставь CKAN под ОС пользователя (см. ниже).
3. `ckan install --headless --no-recommends RP-1-ExpressInstall RP-1-ExpressInstall-Graphics-Low RP-1`
   (в GUI: отметить `RP-1-ExpressInstall`, Apply).
4. Русификатор: выполнить `install-ru.sh` (Linux/Mac/Deck) или `install-ru.ps1` (Windows) из этого репозитория, либо скопировать `GameData/` вручную и выставить `LANGUAGE = ru` в `settings.cfg`.
5. Проверить `KSP.log` на `[ERR`/`Exception`; попросить пользователя один раз запустить игру (первый запуск долгий — Module Manager собирает конфиги).

## CKAN по платформам

| ОС | Как поставить CKAN |
|----|--------------------|
| Windows | нужен .NET 4.8 (в Win10/11 есть). Скачать `ckan.exe`, запустить — GUI. |
| macOS | скачать `CKAN.dmg`, вытащить `CKAN.app`. На 10.15+ открывается как **консольный** UI (Mono, 32-бит GUI мёртв). |
| Linux | `mono-complete` + `ckan.exe` (`mono ckan.exe`), либо `.deb`/`.rpm` из релизов. |
| Steam Deck | SteamOS **read-only** → CKAN из контейнера **distrobox** (Debian + mono). См. ниже. |

## Steam Deck — рабочий рецепт (проверен)

Официальная wiki советует Lutris/Wine — он **хрупкий** (WinForms-диалоги CKAN под Wine глючат). Надёжнее distrobox:

```bash
distrobox create -n ckanbox -i debian:12 -Y
distrobox enter ckanbox -- sudo apt update
distrobox enter ckanbox -- sudo apt install -y mono-complete
# скачать ckan.exe (deb ставится, но объявляет неполные зависимости —
#   ставь mono-complete, иначе падает на System.ComponentModel.Composition)
distrobox enter ckanbox -- ckan instance add --headless "KSP" \
  "$HOME/.local/share/Steam/steamapps/common/Kerbal Space Program"
distrobox enter ckanbox -- ckan instance default KSP
distrobox enter ckanbox -- ckan update
distrobox enter ckanbox -- ckan install --headless --no-recommends \
  RP-1-ExpressInstall RP-1-ExpressInstall-Graphics-Low RP-1
```
Домашняя папка видна из контейнера напрямую — путь к игре тот же. Альтернатива без контейнера: собрать сборку на ПК и скопировать папку `Kerbal Space Program` на Deck целиком.

## Важные грабли (все реально пойманы)

- **RP-1 OR RONoCareer** — Express Install в headless НЕ доустанавливает сам `RP-1` (OR-зависимость). Ставь `RP-1` явно, иначе карьеры не будет. Лови в `ckan list` строку `Unsatisfied dependency`.
- **KSPBurst** тянет Windows-бинарник `bcl.exe` — на Linux/Deck JIT-ускорения не будет (`Win32Exception: Cannot find the specified file` в логе). Не критично, не чинится.
- **SCANsat** в RO с RSS жрёт 32+ ГБ RAM (чёрный список RP-1). На Deck — гарантированный краш. Не ставить.
- **Graphics-Low** выбирать осознанно: экономит память/VRAM (важно для Deck и слабого железа).
- Диск: полная сборка ~6–7 ГБ в `GameData`. Проверяй свободное место до установки.
- Не «оптимизируй» `settings.cfg` тени/свет вручную — при `QUALITY_PRESET = 0` они уже на минимуме; шкалы части значений не документированы, легко выставить невалидное.

## Что НЕ делать

- **Не извлекать ассеты игры** (текстуры/иконки/скриншоты KSP) и не публиковать их — они проприетарны (Squad/Private Division). Для сайтов/иконок брать открытые наборы (напр. Tabler Icons, MIT) или рисовать своё.
- **Не качать пиратку/репаки.** Только лицензия.
- **Не переводить заново** уже переведённые моды — брать из этого репозитория.
- **Не редактировать оригинальные .cfg модов** ради перевода — только добавлять файлы (см. `MAINTAINING.md` §2, техника `%`-патча).

## Проверка результата

- `KSP.log` (корень установки): `Config(Localization) <Mod>/Localization/ru/Localization` — перевод подхватился; `[ERR`/`Exception` — проблемы.
- Русский виден сразу в VAB (названия деталей читаются из локализации при каждой отрисовке); контракты — только новые (старые запечены в сейв).
- В `ckan list` не должно быть `Unsatisfied`/`Broken`/`Incompatible`.
