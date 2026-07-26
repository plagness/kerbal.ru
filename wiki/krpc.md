---
title: "kRPC: управление извне"
category: Автоматика
summary: Сервер внутри игры и клиент на Python снаружи — когда полноценный язык с numpy и графиками выигрывает у kOS, а когда проигрывает.
order: 50
related: [kos-prodvinutoe, avtomatika, sborka]
---

kRPC — это мост между KSP и внешним миром. Внутри игры работает сервер, снаружи — твоя программа на Python (или C#, C++, Java, Lua), которая читает телеметрию и отдаёт команды по TCP. Никакого своего языка: обычный Python со всеми библиотеками, обычный отладчик, обычный git.

> В «Операторе» kRPC — **опциональный мод**: в базовом наборе GameData его нет, ставится отдельно. Причина честная: он требует установленного Python вне игры, а это уже не «скачал сборку и играешь». Интерфейс мода не русифицирован — переводить нечего, это окно сервера с четырьмя полями.

## Зачем это нужно, если есть kOS

[[kos-prodvinutoe|kOS]] исполняется бортовым процессором и живёт по его правилам: лимит инструкций за тик, ограниченный локальный том, отсутствие связи = отсутствие архива. Это фича — она делает автоматизацию частью игры. kRPC этих ограничений не имеет вообще, потому что он вне игры.

Что открывается:

- **Настоящие библиотеки.** `numpy` для матриц и векторов, `scipy.optimize` для подбора параметров манёвра, `matplotlib` для графиков подъёма.
- **Телеметрия и разбор полётов.** Пишешь высоту, скорость, тягу и массу в CSV каждые 0.1 с, потом строишь график и видишь, где профиль разворота теряет 200 м/с.
- **Сложная логика.** Оптимизатор траектории, планировщик серии запусков, симулятор — то, что в kerboscript писать больно.
- **Серии миссий.** Один скрипт выводит десять одинаковых ретрансляторов подряд, включая переключение аппаратов и перемотку времени.

## Как включить

1. Поставить мод в `GameData` (актуальная версия — 0.6.0, есть в CKAN).
2. Запустить игру и загрузить сохранение — окно сервера появится само, кнопка есть и на панели инструментов.
3. Настройки открываются по **Edit**:
   - **Protocol** — для Python нужен `Protobuf over TCP`;
   - **Address** — `localhost`, если клиент на той же машине; чтобы управлять с другого компьютера в локальной сети, выбери IP-адрес машины;
   - **RPC port** — 50000, **Stream port** — 50001 (значения по умолчанию, менять не нужно).
   - В расширенных настройках есть **Auto-start server** (стартовать вместе с игрой) и **Auto-accept new clients** (не спрашивать разрешение на каждое подключение).
4. Кнопка **Start server** — лампочка становится зелёной.

Клиент ставится обычным образом: `pip install krpc`. Отдельная деталь на корабль не нужна: kRPC работает с активным аппаратом, каким бы он ни был.

## Первый скрипт

```python
import krpc

conn = krpc.connect(name="Привет")
vessel = conn.space_center.active_vessel
print(vessel.name)
print(vessel.flight().mean_altitude, "м")
print(vessel.orbit.apoapsis_altitude, "м")
```

Ключевая вещь kRPC — **потоки** (streams). Каждый вызов `vessel.flight().mean_altitude` — это запрос по сети; в цикле управления так делать нельзя. Поток регистрируется один раз, дальше сервер сам шлёт обновления, а чтение значения становится локальным:

```python
altitude = conn.add_stream(getattr, vessel.flight(), "mean_altitude")
apoapsis = conn.add_stream(getattr, vessel.orbit, "apoapsis_altitude")
print(altitude(), apoapsis())     # вызов как функции — свежее значение
```

## Автозапуск

Скелет вывода на орбиту — прямой аналог `ascent.ks` из [[kos-recepty]]:

```python
import time
import krpc

turn_start, turn_end, target = 250, 45000, 90000

conn = krpc.connect(name="Автозапуск")
vessel = conn.space_center.active_vessel

altitude = conn.add_stream(getattr, vessel.flight(), "mean_altitude")
apoapsis = conn.add_stream(getattr, vessel.orbit, "apoapsis_altitude")

vessel.control.sas = False
vessel.control.rcs = False
vessel.control.throttle = 1.0
vessel.control.activate_next_stage()

vessel.auto_pilot.engage()
vessel.auto_pilot.target_pitch_and_heading(90, 90)

turn_angle = 0
while apoapsis() < target * 0.9:
    if turn_start < altitude() < turn_end:
        frac = (altitude() - turn_start) / (turn_end - turn_start)
        new_angle = frac * 90
        if abs(new_angle - turn_angle) > 0.5:      # не дёргать автопилот каждый тик
            turn_angle = new_angle
            vessel.auto_pilot.target_pitch_and_heading(90 - turn_angle, 90)
    time.sleep(0.1)

vessel.control.throttle = 0.25
while apoapsis() < target:
    pass
vessel.control.throttle = 0.0
print("Апоцентр набран")
```

Дальше — узел циркуляризации: `vessel.control.add_node(ut + vessel.orbit.time_to_apoapsis, prograde=delta_v)`, длительность прожига по формуле Циолковского через `vessel.available_thrust`, `vessel.specific_impulse` и `vessel.mass`, наведение через `auto_pilot.reference_frame = node.reference_frame`. Перемотка времени доступна прямо из кода: `conn.space_center.warp_to(t)`. Есть и отдельный сервис для Kerbal Alarm Clock — будильники ставятся программно.

## Что выбрать

| Задача | kOS | kRPC |
|---|---|---|
| Скрипт живёт на борту, работает без тебя | ✅ | ❌ клиент должен быть запущен |
| Ограничения связи и памяти как часть игры | ✅ | ❌ их нет вообще |
| Загрузочный скрипт на спутнике | ✅ | ❌ |
| Матрицы, оптимизация, графики | ❌ | ✅ |
| Сбор телеметрии в CSV, разбор полёта | ❌ | ✅ |
| Отладчик, тесты, нормальный редактор | ❌ | ✅ |
| Серия из десяти запусков одним прогоном | тяжело | ✅ |
| Управление с другого компьютера | ❌ | ✅ |
| Ничего не ставить вне игры | ✅ | ❌ нужен Python |

Практический вывод для «Оператора»: **kOS остаётся основным инструментом**. Он часть игры — бортовой компьютер с реальными ограничениями, ради которых сборка и собрана. kRPC берут, когда задача перестаёт быть игровой и становится инженерной: посчитать оптимальный профиль подъёма, построить график расхода дельта-в, прогнать двадцать вариантов ракеты и сравнить цифры.

Ставить его «на всякий случай» смысла нет. Ставить, когда упёрся в потолок kerboscript, — да.
