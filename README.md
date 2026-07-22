# kerbal.ru — русская локализация RO/RSS/RP-1 для Kerbal Space Program

Русский перевод для реалистичной сборки KSP1 на базе **Realism Overhaul + Real Solar System + RP-1** (Realistic Progression One).

Сайт: [kerbal.ru](https://kerbal.ru)

## Что это

Это **не** отдельный мод, а набор файлов локализации (`ru.cfg`) и вспомогательных ModuleManager-патчей, которые добавляют русский язык в 20 популярных модов из RO/RP-1 сборки. Устанавливается поверх уже собранной через CKAN сборки — просто копированием папки `GameData` из этого репозитория.

Технически: для модов, у которых уже была своя система локализации, добавлен только файл `ru.cfg`. Для модов без поддержки локализации добавлена пара файлов — `ru.cfg` (с оригинальным английским текстом под ключом + переводом) и `RuLocPatch.cfg` (ModuleManager-патч, который безопасно переключает поля `title`/`description`/`manufacturer`/`tags` деталей на эти ключи через оператор `%`, не трогая ни строки в оригинальных файлах модов).

## Переведено (20 модов)

**Полная локализация** (родная система локализации мода):
AJE, ContractConfigurator, EditorExtensionsRedux, ROCapsules, SXT, Trajectories, VenStockRevamp, KerbalChangelog, KerbalEngineerRedux, RealismOverhaul (ядро), SpaceTuxLibrary, BackgroundThrust

**Локализация через дополнительный патч** (у мода не было своей системы):
ROSolar, ROTanks, ROEngines, ROHeatshields, ProceduralFairings, ProceduralParts, RealChute, ModularLaunchPads

## Установка

1. Собери базовую сборку через CKAN: `RP-1-ExpressInstall` + `RP-1-ExpressInstall-Graphics-Low` + `RP-1` (плюс по желанию: KerbalAlarmClock, DockingPortAlignmentIndicator, KerbalEngineerRedux, Trajectories, TransferWindowPlannerFork, PreciseManeuver, EditorExtensionsRedux, BetterTimeWarpCont, BackgroundThrust, Astrogator, ASETProps).
2. Скачай этот репозиторий (Code → Download ZIP, либо `git clone`).
3. Скопируй содержимое папки `GameData` из архива в `GameData` своей установки KSP — файлы лягут в нужные подпапки автоматически.
4. В настройках KSP (или в `settings.cfg`, поле `LANGUAGE`) выбери русский язык — `ru`.

## Известные ограничения

- Это охватывает 20 модов из полного набора большой сборки — остальные (~50) пока остаются на английском. Список открыт для расширения.
- Контракты, уже сгенерированные ДО установки перевода (в существующем сохранении), останутся на английском — Contract Configurator запекает текст в момент создания контракта, а не при показе. Новые контракты будут на русском.
- Несколько деталей (в ProceduralFairings и ModularLaunchPads) не переведены — их исходные файлы содержат несбалансированную структуру, из-за которой нельзя было надёжно сверить перевод с оригиналом.

## Источники

Базовая сборка: [RP-1 Express Install](https://github.com/KSP-RO/RP-1-ExpressInstall), [RP-1](https://github.com/KSP-RO/RP-1), [Realism Overhaul](https://github.com/KSP-RO/RealismOverhaul).

## Лицензия

Переводы распространяются на условиях, совместимых с лицензиями оригинальных модов (в основном CC-BY-NC-SA). Это независимый проект, не аффилированный с авторами оригинальных модов.
