---
title: "kOS: продвинутое"
category: Автоматика
summary: Функции, списки, библиотека из нескольких файлов, триггеры и их подводные камни, узлы манёвра из кода и защита от «улетел в космос».
order: 40
related: [kos-recepty, krpc, avtomatika]
---

Когда скриптов становится больше трёх, начинается копипаста: одна и та же формула вис-вива в четырёх файлах, один и тот же цикл исполнения узла в каждом. Эта статья — про то, как из набора скриптов сделать бортовое ПО. Всё проверено на kOS 1.6.0.1; если [[kos-recepty|рецепты]] ещё не работали у тебя вживую — начни с них.

## Функции

```kos
FUNCTION circVel {
  PARAMETER r.
  RETURN SQRT(SHIP:BODY:MU / r).
}

FUNCTION burnTime {
  PARAMETER dv, minAcc IS 0.01.
  LOCAL acc IS SHIP:AVAILABLETHRUST / SHIP:MASS.
  IF acc < minAcc { RETURN -1. }      // двигателя нет — сигнал вызывающему
  RETURN dv / acc.
}

PRINT burnTime(120).
```

- `PARAMETER` идёт **первой** строкой тела функции, аргументы через запятую.
- `PARAMETER dv, minAcc IS 0.01.` — параметр со значением по умолчанию. Все такие параметры обязаны стоять в конце списка: `PARAMETER x, y IS 0.` можно, `PARAMETER x IS 0, y.` — нет.
- `LOCAL имя IS значение.` объявляет переменную в текущей области. Без `LOCAL` переменная станет глобальной, и две функции незаметно перезапишут друг другу счётчик.
- `RETURN` без значения просто выходит из функции.

Директива `@LAZYGLOBAL OFF.` в первой строке файла запрещает автосоздание глобальных переменных: опечатка в имени превращается из молчаливого бага в ошибку компиляции. В библиотеках ставь её всегда.

## Списки, циклы и словари

```kos
LOCAL heights IS LIST(80000, 500000, 2863334).
FOR h IN heights {
  PRINT ROUND(h / 1000) + " км -> " + ROUND(circVel(SHIP:BODY:RADIUS + h), 1) + " м/с".
}

LOCAL log IS LIST().
log:ADD(SHIP:APOAPSIS).
PRINT "записей: " + log:LENGTH.

LOCAL cfg IS LEXICON().
SET cfg["ap"] TO 500000.
SET cfg["inc"] TO 63.4.
IF cfg:HASKEY("inc") { PRINT cfg["inc"]. }
```

`LIST` — упорядоченный массив (`:ADD`, `:LENGTH`, `:EMPTY`, индексация `log[0]`), `LEXICON` — словарь ключ→значение. Словарём удобно передавать «настройки миссии» одним аргументом вместо восьми.

## Библиотека из нескольких файлов

Идея простая: файлы `lib_*.ks` содержат **только функции** и ничего не выполняют, рабочие скрипты их подключают.

```kos
// 0:/lib_orbit.ks
@LAZYGLOBAL OFF.

FUNCTION circVel {
  PARAMETER r.
  RETURN SQRT(SHIP:BODY:MU / r).
}

FUNCTION nodeCircAp {                 // узел циркуляризации в апоцентре
  LOCAL r IS SHIP:BODY:RADIUS + SHIP:APOAPSIS.
  LOCAL vNow IS SQRT(SHIP:BODY:MU * (2 / r - 1 / SHIP:ORBIT:SEMIMAJORAXIS)).
  RETURN NODE(TIME:SECONDS + ETA:APOAPSIS, 0, 0, circVel(r) - vNow).
}
```

```kos
// 0:/sat.ks — рабочий скрипт
PARAMETER targetAp, targetInc IS 0.

RUNONCEPATH("0:/lib_orbit.ks").       // подключить, но не перезапускать
PRINT "Цель: " + ROUND(targetAp / 1000) + " км, i = " + targetInc.
ADD nodeCircAp().
```

Запуск с аргументами: `RUNPATH("0:/sat.ks", 500000, 63.4).` — они попадут в `PARAMETER` первой строки. `RUNONCEPATH` отличается от `RUNPATH` тем, что второй раз тот же файл не выполнит: библиотеку можно подключать из десяти мест без дублирования.

Архив доступен только при связи с КЦ, поэтому боевой комплект кладут на локальный том:

```kos
COPYPATH("0:/lib_orbit.ks", "1:/").
COPYPATH("0:/sat.ks", "1:/").
```

Место на локальном томе ограничено (по конфигам деталей): KR-2042 b — 5 000 байт, CX-4181 — 10 000, КомпоМакс Радиальный — 60 000, KAL9000 — 255 000. Библиотека на дальний зонд ставится вместе с процессором соответствующего размера.

**Загрузочный скрипт.** Файлы из папки `Ships/Script/boot/` показываются в редакторе в меню процессора как выбор загрузочного файла. При появлении аппарата в игре kOS сам скопирует выбранный файл на локальный том и запустит его — идеально для «спутник вышел из тени, развернул панели, доложился». Имя текущего файла читается как `CORE:BOOTFILENAME`.

## Триггеры: WHEN и ON

```kos
WHEN MAXTHRUST < 0.1 THEN { STAGE. PRESERVE. }   // отделять по потере тяги
ON AG1 { PRINT "Группа 1 переключена". PRESERVE. }
```

`WHEN` проверяет условие каждый физический тик, `ON` срабатывает на **изменение** значения выражения (нажали группу действий — сработал, отпустили — сработал ещё раз). Без `PRESERVE.` триггер отрабатывает один раз и снимается.

Четыре грабли, на которые наступают все:

1. **Тело триггера обязано уложиться в один тик.** Все триггеры вместе не могут потратить больше, чем `CONFIG:IPU` инструкций, иначе получишь `Ran more than N instructions in trigger bodies`. Поднять лимит можно (`SET CONFIG:IPU TO 500.`), но правильный ответ — вынести логику в основной цикл.
2. **`WAIT` внутри триггера разрешён, но вреден**: он блокирует всё, кроме более приоритетных триггеров. Вместо паузы ставь флаг, а разбирайся в главном цикле.
3. **Триггер живёт ровно столько, сколько программа, которая его создала.** Скрипт закончился — автоступень исчезла. Если нужна фоновая логика, главный цикл должен крутиться.
4. **Условие тоже стоит инструкций.** `WHEN <тяжёлая функция> THEN` считается каждый тик и съедает бюджет впустую.

Правильный шаблон — триггер только ставит флаг:

```kos
GLOBAL needStage IS FALSE.
WHEN MAXTHRUST < 0.1 THEN { SET needStage TO TRUE. PRESERVE. }

UNTIL SHIP:APOAPSIS > 90000 {
  IF needStage {
    WAIT 0.5.                      // пауза здесь безопасна
    STAGE.
    SET needStage TO FALSE.
  }
  WAIT 0.
}
```

## Узлы манёвра из кода

```kos
FUNCTION execNode {
  IF NOT HASNODE { PRINT "Узла нет.". RETURN. }
  LOCAL nd IS NEXTNODE.
  LOCAL dv0 IS nd:DELTAV.
  LOCAL t IS burnTime(dv0:MAG).
  IF t < 0 { PRINT "Нет тяги — узел не исполнить.". RETURN. }

  LOCK STEERING TO nd:DELTAV.
  WAIT UNTIL nd:ETA <= t / 2 + 20.
  WAIT UNTIL nd:ETA <= t / 2.

  LOCK THROTTLE TO 1.
  UNTIL VDOT(dv0, nd:DELTAV) < 0 {
    IF nd:DELTAV:MAG < 5 { LOCK THROTTLE TO 0.1. }
    WAIT 0.
  }
  LOCK THROTTLE TO 0.
  UNLOCK STEERING.
  REMOVE nd.
}
```

`HASNODE` — есть ли хоть один узел, `NEXTNODE` — ближайший, `ALLNODES` — список всех. Снести планы целиком: `FOR n IN ALLNODES { REMOVE n. }`. Создаётся узел через `NODE(время_UT, радиальный, нормальный, прогрейд)` и вешается командой `ADD`.

## Чтение состояния корабля

```kos
FUNCTION resAmount {
  PARAMETER resName.
  FOR r IN SHIP:RESOURCES {
    IF r:NAME = resName { RETURN r:AMOUNT. }
  }
  RETURN 0.
}

PRINT "Заряд: " + ROUND(resAmount("ElectricCharge")) + " ЭЧ".
```

Работа с конкретными деталями идёт через **метки**: в редакторе правый клик по детали → поле метки kOS, вписываешь, например, `relay`. Дальше:

```kos
FOR p IN SHIP:PARTSTAGGED("relay") {
  PRINT p:TITLE.
  LOCAL m IS p:GETMODULE("ModuleDeployableAntenna").
  PRINT m:ALLEVENTS.                       // узнать точные имена событий
  IF m:HASEVENT("extend antenna") { m:DOEVENT("extend antenna"). }
}
```

Имена событий и полей не угадывай — распечатай `:ALLEVENTS` один раз на стартовом столе и подставь то, что вывелось. `PARTSDUBBED` ищет и по метке, и по имени, и по названию детали; `PARTSNAMED` — только по внутреннему имени из конфига.

## Меню в терминале

```kos
CLEARSCREEN.
PRINT "1 - взлёт   2 - циркуляризация   3 - выход".
UNTIL FALSE {
  IF TERMINAL:INPUT:HASCHAR {
    LOCAL c IS TERMINAL:INPUT:GETCHAR().
    IF c = "1" { RUNPATH("1:/ascent.ks", 90000). }
    IF c = "2" { RUNPATH("1:/circ.ks"). }
    IF c = "3" { BREAK. }
  }
  WAIT 0.
}
```

Этого хватает, чтобы на аппарате лежал один «пульт», а не десять файлов, которые надо помнить по именам.

## Защита от «улетел в космос»

Скрипт без выхода по времени однажды повиснет в `UNTIL` с включённой тягой. Правило: **у каждого цикла два условия выхода — целевое и аварийное**.

```kos
LOCAL deadline IS TIME:SECONDS + 600.
UNTIL SHIP:APOAPSIS > targetAp {
  IF TIME:SECONDS > deadline OR SHIP:AVAILABLETHRUST < 0.1 {
    LOCK THROTTLE TO 0.
    PRINT "Аварийный выход: время вышло или нет тяги.".
    BREAK.
  }
  WAIT 0.
}
LOCK THROTTLE TO 0.
UNLOCK STEERING.
```

Остальной чек-лист:

- Перед действием, которому нужен архив, проверяй `SHIP:HASKSCCONNECTION` — за Муном его не будет ([[svyaz-osnovy]]).
- В меню процессора есть **Аварийное подавление**: мгновенно отбирает управление у скрипта, не выключая его. Вешай его на группу действий заранее.
- Финальный блок с `LOCK THROTTLE TO 0.` и `UNLOCK STEERING.` — в каждом скрипте, даже если «он и так дойдёт до конца».
- Быстрое сохранение перед каждым первым прогоном. Каждым.

Дальше — либо MechJeb и рутина в [[avtomatika]], либо шаг наружу: полноценный язык вместо kerboscript в статье [[krpc]].
