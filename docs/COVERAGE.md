# Покрытие переводом — что на русском, а что нет

Полная раскладка по установленной сборке RO/RSS/RP-1 (84 папки мода в `GameData`).
Данные сняты с реальной сборки: мод считается русифицированным, если в его папке есть блок локализации `ru`/`ru-ru` (в любом файле, не только `ru.cfg`).

**Итого:** русский есть у **40 из 84** — 20 сделали мы + 20 идут с русским от авторов. Остальные 44 на английском, но большинство из них — служебные библиотеки без пользовательского текста.

---

## 1. Переведено нами (kerbal.ru) — 20

### Полная локализация (родная система мода, добавлен `ru.cfg`) — 12
AJE · BackgroundThrust · ContractConfigurator · EditorExtensionsRedux · KerbalChangelog · KerbalEngineerRedux · ROCapsules · RealismOverhaul · SXT · SpaceTuxLibrary · Trajectories · VenStockRevamp

### Через доп-патч (у мода не было локализации) — 8
ModularLaunchPads · ProceduralFairings · ProceduralParts · ROEngines · ROHeatshields · ROSolar · ROTanks · RealChute

> Примечание: несколько отдельных деталей в ProceduralFairings и ModularLaunchPads оставлены на английском (несбалансированные скобки в исходниках, см. [ROADMAP](ROADMAP.md)).

## 2. Уже на русском от авторов мода (не мы) — 20

Эти моды поставляются с русской локализацией из коробки — переводить не нужно:

Astrogator · B9PartSwitch · B9 Procedural Wings · CommunityResourcePack · ConformalDecals · Ferram Aerospace Research (FAR) · KSPCommunityFixes · Kerbalism · Kerbalism-Config · Kopernicus · MechJeb2 · Docking Port Alignment Indicator *(папка NavyFish)* · PreciseManeuver · RP-1 · RSSDateTimeFormatter · ReStock · ReStock+ · RealFuels · Real Solar System · **стоковая KSP** *(папка Squad)*

## 3. Ещё на английском — 44

### 3a. Служебные — перевод не требуется (нет пользовательского текста)

Библиотеки, плагины, эффекты, текстуры, конфиги без видимых игроку строк:

ClickThroughBlocker · Harmony · KSPBurst · TexturesUnlimited · ToolbarControl · CustomBarnKit · DepthMask · KSPTextureLoader · ModularFlightIntegrator · PatchManager · Shabby · SmokeScreen · SolverEngines · StagedAnimation · TextureReplacer · Waterfall · RealHeat · RealPlume · RSS-Textures · ROLib · ROUtils · RP-1-ExpressInstall · RP-1-ExpressInstall-Graphics · Firespitter · Resurfaced · KerbalRenamer · Output *(артефакт сборки KerbalEngineer)*

### 3b. Реальные кандидаты для перевода (есть детали/UI) — план на будущее

Моды с пользовательским текстом, которые имеет смысл перевести дальше:

- **RealAntennas** — антенны и UI связи (тема связи).
- **TestFlight** — надёжность, сообщения об отказах.
- **Skopos** — симуляция наземных станций связи (RP-1).
- **ASET** — пропсы IVA, названия агентств.
- **CommunityCategoryKit** — названия категорий деталей в VAB.
- **KSPWheel** — шасси/колёса (детали).
- **BahaSP** *(BDAnimationModules)* — анимированные детали.
- **RCSBuildAid** — оверлей RCS в редакторе.
- **AtmosphereAutopilot** — UI автопилота в атмосфере.
- **KerbalJointReinforcement** — настройки прочности стыков.
- **BetterTimeWarpContinued** — UI ускорения времени.
- **RetractableLiftingSurface** — деталь.
- **FShangarExtender** — UI расширения ангара.
- **KSCSwitcher** — названия стартовых площадок.
- **EngineGroupController** — UI групп двигателей.
- **Kerbal Alarm Clock / Transfer Window Planner** *(папка TriggerTech)* — UI будильников/окон.
- **RasterPropMonitor** *(папка JSI)* — тексты приборных панелей IVA.

Приоритеты и порядок — в [ROADMAP.md](ROADMAP.md).

---

*Раскладка построена скриптом по факту наличия блока `ru` в cfg-файлах модов. Деление §3a/§3b — по назначению мода (наилучшая оценка), не по формальному признаку.*
