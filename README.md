# kerbal.ru — русский хаб KSP-моддинга

**Не одна сборка, а две вещи сразу:**

1. **Библиотека переводов модов** (`translations/`) — русификация модов Kerbal Space Program 1.12.5,
   по **одной папке на мод**. Нужен перевод конкретного мода — берёшь его папку и кладёшь себе в `GameData`.
2. **Каталог готовых русских сборок + удобный установщик** (`builds/` + `install.sh`) — выбираешь сборку,
   и она ставится «в пару кликов»: официальный CKAN тянет моды, поверх ложатся наши переводы, включается русский.

Мы **не храним и не распространяем чужие моды** — только свои дескрипторы сборок и переводы; сами моды всегда
ставит официальный **CKAN**.

---

## Быстрый старт (пользователю)

```bash
# выбрать сборку интерактивно (меню)
curl -fsSL https://kerbal.ru/install.sh | bash

# или сразу конкретную
curl -fsSL https://kerbal.ru/install.sh | bash -s -- --build operator

curl -fsSL https://kerbal.ru/install.sh | bash -s -- --list        # каталог сборок
```

Установщик — **менеджер сборок**: при повторном запуске он находит уже стоящую сборку и предлагает
**обновить / сменить / только переводы**. Состояние пишется в `<KSP>/.kerbalru-build.json`.

Флаги: `--build <id>` · `--update` · `--ru-only` · `--list` · `--yes`.

---

## Структура репозитория

```
translations/            библиотека переводов — ПО ПАПКЕ НА МОД
  <mod>/
    translation.json     метаданные: mod, folder (папка в GameData), method (keyed/ui-dict), status
    Localization/*.cfg    перевод через #LOC-ключи (ru.cfg) и/или MM-патчи title (RuLocPatch.cfg)
    KerbalRuUiTranslations/<Mod>.txt   словарь ui-translator (Англ⇥Рус) для хардкод-модов
engine/
  Plugins/KerbalRuUiTranslator.dll     движок перевода интерфейса (Harmony) — общий
builds/                  каталог сборок; имя папки = id сборки
  <id>/
    build.json           что ставить (mods.core/recommended/optional) + ckan-опции
    README.md            описание сборки
    config/              опц. конфиг сборки (зеркалит GameData/), напр. мягкий пресет KCT
  _catalog.json          индекс для сайта/меню (генерируется)
install.sh               менеджер сборок (Linux/macOS/Steam Deck)
tools/                   валидаторы, генератор каталога, статистика переводов
docs/  data/  assets/  index.html  vendor/
```

### Как перевод попадает в игру
`install.sh` (`--build`/`--update`/`--ru-only`) кладёт под **реально установленные моды**:
движок → `GameData/kerbalru-ui-translator/Plugins/`; ui-словари → `.../KerbalRuUiTranslations/`;
Localization-патчи → `GameData/zzz-kerbalru-translations/<mod>/` (префикс `zzz-` гарантирует применение
после Realism Overhaul, чтобы наши `:FINAL`-переводы `title` выигрывали). Всё безопасно: перевод
отсутствующего мода = no-op.

---

## Продвинутым: взять перевод одного мода
Скопируй папку `translations/<mod>/` к себе в `GameData/` (Localization-файлы работают из любого места; для
хардкод-модов нужен ещё `engine/Plugins/KerbalRuUiTranslator.dll`) и выставь `LANGUAGE = ru` в `settings.cfg`.

## Авторам сборок
Добавь `builds/<id>/build.json` (образец — `builds/operator/build.json`) + `README.md`. Моды — по CKAN-id;
`ckan.compatVersions` — для модов с отставшим тегом версии; `config/` — для конфигов сборки.

## Переводчикам
Добавь/дополни `translations/<mod>/`. Политика — **умный перевод**: по максимуму на русский, латиницей только
настоящие бренды/модели/единицы/технические токены; сохраняй токены (`\n`, `<<1>>`, `<color>`).

---

Домен **kerbal.ru** (GitHub Pages). Ассеты игры (текстуры/иконки KSP) не извлекаем и не публикуем.
