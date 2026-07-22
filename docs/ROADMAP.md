# Roadmap

Состояние проекта и планы. Отмечай `[x]` по мере выполнения.
Полная раскладка «что переведено / что нет» — в [COVERAGE.md](COVERAGE.md).

## Сделано (v1)

- [x] Переведено 20 модов сборки RO/RSS/RP-1 (~3500 строк).
  - 12 «полных» (родная локализация мода): AJE, ContractConfigurator, EditorExtensionsRedux, ROCapsules, SXT, Trajectories, VenStockRevamp, KerbalChangelog, KerbalEngineerRedux, RealismOverhaul, SpaceTuxLibrary, BackgroundThrust.
  - 8 через доп-патч (у мода не было локализации): ROSolar, ROTanks, ROEngines, ROHeatshields, ProceduralFairings, ProceduralParts, RealChute, ModularLaunchPads.
- [x] Все переводы сверены с апстримом (имена деталей, побайтовый en-us, длина ≤ английской).
- [x] Установщики `install-ru.sh` / `install-ru.ps1` (Win/Mac/Linux/Deck).
- [x] Сайт kerbal.ru (GitHub Pages) с инструкциями под 4 платформы.

## Ближайшее (v1.x)

- [ ] Доперевести пропущенные детали в ProceduralFairings (`KzInterstageAdapter2`, `KzResizableFairingBaseRing`) и ModularLaunchPads (`AM_MLP_AtlasLaunchStand`, `AM_MLP_AtlasLaunchStandAlt`, `AM_MLP_LargeLaunchStand`) — их исходные `.cfg` имеют несбалансированные скобки, нужна ручная сверка.
- [ ] PR в апстрим-репозитории «полных» модов (у них уже есть система локализации → перевод примут проще всего). Начать с ContractConfigurator и KerbalEngineerRedux — их текст игрок видит постоянно.
- [ ] Русская обёртка для стоковых `#autoLOC`, которые RP-1 переопределяет (см. `RP-1/Localization/LocPatches.cfg`) — там английские строки программ/стратегий.

## Расширение охвата (v2)

- [ ] Перевести оставшиеся ~50 модов сборки. Приоритет по видимости для игрока:
  1. RealFuels, Kerbalism/-Config (ресурсы, ЖО — уже частично на русском из апстрима, проверить полноту).
  2. RealAntennas (связь), TestFlight (надёжность), SolverEngines.
  3. Остальные RO-парты и служебные библиотеки.
- [ ] Свести все переводы в единый глоссарий терминов (апогей/перигей, тяга, ступень, окислитель…) для согласованности между модами.

## Инфраструктура (v2+)

- [ ] Оформить как CKAN-устанавливаемый мод (netkan), чтобы ставился/обновлялся через CKAN вместе со сборкой.
- [ ] Автосборка релизов (GitHub Actions): zip + версия при пуше в main.
- [ ] Поток контрибуций: как сообщество может присылать переводы (шаблон, проверка длины строк, CI-валидатор скобок/ключей).

## Идеи

- [ ] Один клик из Gaming Mode на Steam Deck (non-Steam shortcut, запускающий install-ru).
- [ ] Переключатель «локализация деталей вкл/выкл» на случай, если игрок хочет английские названия партов, но русский UI.
