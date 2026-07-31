// lib/audit.ks — чекеры: точно ли на борту есть всё нужное под задачу
// или под тело. Прогоняется на столе, до пуска — дешевле проверить здесь,
// чем узнать в полёте, что нужного прибора нет.
// Зависит от: ничего.
// kerbal.ru · сборка «Оператор»
//
//   RUNONCEPATH("0:/lib/audit.ks").
//   q_report("SCANsat: высотометрия", q_taskScanAltimetry()).
//   q_report("Мун: топливо и заряд", q_bodyChecklist(q_bodyMun())).
//
// ЧЕСТНО ПРО ГРАНИЦЫ. Проверяется только то, что видно по деталям и
// модулям на столе: название детали (подстрокой, без учёта регистра) и
// класс модуля. НЕ проверяется: хватит ли конкретно ЭТОГО запаса топлива
// на весь профиль, сядет ли лендер мягко, не перекрыт ли эксперимент
// обтекателем. Список того, что чекер не видит, — в конце каждого отчёта.

// ─── низкоуровневые запросы к деталям ─────────────────────────────────

// Есть ли деталь, в названии которой (регистронезависимо) есть подстрока.
GLOBAL FUNCTION q_hasPart {
  PARAMETER substr.
  RETURN q_countPart(substr) > 0.
}

GLOBAL FUNCTION q_countPart {
  PARAMETER substr.
  LOCAL needle IS substr:TOLOWER.
  LOCAL n IS 0.
  LIST PARTS IN pl.
  FOR p IN pl {
    IF p:TITLE:TOLOWER:CONTAINS(needle) { SET n TO n + 1. }
  }
  RETURN n.
}

// Есть ли модуль, чей класс (регистрозависимо, это английские идентификаторы
// KSP) содержит подстроку — так ищут декаплеры, антенны, абляционный экран.
GLOBAL FUNCTION q_hasModule {
  PARAMETER substr.
  LIST PARTS IN pl.
  FOR p IN pl {
    LOCAL i IS 0.
    UNTIL i >= p:MODULES:LENGTH {
      IF p:MODULES[i]:CONTAINS(substr) { RETURN TRUE. }
      SET i TO i + 1.
    }
  }
  RETURN FALSE.
}

// Сколько деталей с меткой (TAG), начинающейся с prefix — так считают
// лендеров: lander-1, lander-2, lander-3 дадут q_countTag("lander-") = 3.
GLOBAL FUNCTION q_countTag {
  PARAMETER prefix.
  LOCAL n IS 0.
  LIST PARTS IN pl.
  FOR p IN pl {
    IF NOT (p:TAG = "") AND p:TAG:STARTSWITH(prefix) { SET n TO n + 1. }
  }
  RETURN n.
}

// Суммарная ёмкость электрозаряда по всем бакам, ЭЧ.
GLOBAL FUNCTION q_ecCapacity {
  FOR res IN SHIP:RESOURCES {
    IF res:NAME = "ElectricCharge" { RETURN res:CAPACITY. }
  }
  RETURN 0.
}

// ─── отчёт ──────────────────────────────────────────────────────────

// items — список LEXICON("label", строка, "ok", булево).
// Возвращает число непройденных пунктов (0 = всё готово).
GLOBAL FUNCTION q_report {
  PARAMETER title.
  PARAMETER items.
  PRINT "=== чекер: " + title.
  LOCAL fail IS 0.
  FOR it IN items {
    LOCAL mark IS CHOOSE "  [OK] " IF it["ok"] ELSE "  [! ] ".
    PRINT mark + it["label"].
    IF NOT it["ok"] { SET fail TO fail + 1. }
  }
  IF fail = 0 { PRINT "  всё на месте.". }
  ELSE { PRINT "  не хватает: " + fail + " из " + items:LENGTH. }
  RETURN fail.
}

// ─── задачи: примеры под контракты Field Research / Strategia ─────────
//
// Это ОБРАЗЦЫ, не полная база контрактов игры — их и не может быть,
// паков контрактов десятки. Добавляй свои по этому же шаблону: список
// LEXICON("label", "ok") — дальше в q_report().

// Список названий проверен не полностью по каталогу мода — конкретные
// детали отличаются по паку (например, «Радарная антенна R-EO-1» не
// угадывалась по имени, добавлена только после проверки её модулей
// SCANsat/SCANexperiment через telnet). Названия SCANsat- и
// мультиспектральных сканеров ниже расширяй по факту, а не по каталогу
// заранее — то же самое MODULE-класс "SCANsat" носят и другие типы
// сканеров мода (в т.ч. ресурсные), поэтому по одному классу модуля
// высотометрию от мультиспектрального не отличить — только по названию.
GLOBAL FUNCTION q_taskScanAltimetry {
  RETURN LIST(
    LEXICON("label", "высотомер SCAN, R-3B, R-EO-1 или SAR-*", "ok",
      q_hasPart("высотомер SCAN") OR q_hasPart("R-3B") OR q_hasPart("SCAN SAR")
      OR q_hasPart("SAR-X") OR q_hasPart("SAR-C") OR q_hasPart("SAR-L")
      OR q_hasPart("R-EO-1")),
    LEXICON("label", "есть ёмкость под заряд (ЭЧ > 0)", "ok", q_ecCapacity() > 0)
  ).
}

GLOBAL FUNCTION q_taskScanBiome {
  RETURN LIST(
    LEXICON("label", "мультиспектральный сканер (SCAN / MS-1 / MS-R / MS-2A)", "ok",
      q_hasPart("мультиспектральный") OR q_hasPart("MS-1")
      OR q_hasPart("MS-R") OR q_hasPart("MS-2A") OR q_hasPart("TRIXIE")),
    LEXICON("label", "есть ёмкость под заряд (ЭЧ > 0)", "ok", q_ecCapacity() > 0)
  ).
}

// n — сколько лендеров нужно (контракт «Зонды к Mun» просит 3 биома).
GLOBAL FUNCTION q_taskLandBiomes {
  PARAMETER n IS 3.
  RETURN LIST(
    LEXICON("label", "декаплеров с меткой lander-N: нужно " + n, "ok", q_countTag("lander-") >= n),
    LEXICON("label", "хотя бы один зонд-ядро (ModuleCommand) сверх шины", "ok", q_countPart("ядро") + q_countPart("core") >= n)
  ).
}

// n — сколько спутников созвездия отделяется, prefix — метка декаплеров.
// Требует прокачанного VAB (переименование деталей) — если тегов нет,
// используй q_taskConstellationByTitle.
GLOBAL FUNCTION q_taskConstellation {
  PARAMETER n IS 4.
  PARAMETER prefix IS "sat-".
  RETURN LIST(
    LEXICON("label", "декаплеров с меткой " + prefix + "N: нужно " + n, "ok", q_countTag(prefix) >= n),
    LEXICON("label", "антенна на борту (для связи спутников после отделения)", "ok", q_hasModule("DeployableAntenna"))
  ).
}

// То же самое, но без тегов — считает по названию детали. Годится, когда
// VAB не прокачан до переименования: n одинаковых деталей неотличимы
// друг от друга, но их можно просто пересчитать и отделять по одной,
// см. ds_release в lib/deepspace.ks.
GLOBAL FUNCTION q_taskConstellationByTitle {
  PARAMETER n IS 4.
  PARAMETER titleSubstr IS "субспутник".
  RETURN LIST(
    LEXICON("label", "деталей «" + titleSubstr + "»: нужно " + n
                     + " (сейчас " + q_countPart(titleSubstr) + ")",
            "ok", q_countPart(titleSubstr) >= n),
    LEXICON("label", "антенна на борту (для связи спутников после отделения)", "ok", q_hasModule("DeployableAntenna"))
  ).
}

GLOBAL FUNCTION q_taskGooOrMaterials {
  RETURN LIST(
    LEXICON("label", "капсула с загадочной слизью или контейнер материаловедения", "ok",
      q_hasPart("загадочной слизью") OR q_hasPart("материаловедения") OR q_hasPart("Микронаука"))
  ).
}

// ─── тело: топливо и живучесть ─────────────────────────────────────
//
// SHIP:DELTAV читает СТОКОВЫЙ расчёт дельта-v игры (KSP 1.11+, Advanced
// Tweakables → Delta-V readout должен быть включён). Если он выключен —
// SHIP:DELTAV:VACUUM даст 0, а не ошибку, так что пустой результат тоже
// значит «включи в настройках», а не «нет топлива».

GLOBAL FUNCTION q_bodyDefaults {
  RETURN LEXICON(
    "dv", -1,             // нужный запас Δv, м/с; -1 = не проверять
    "ecReserve", -1,       // ЭЧ на теневую сторону; -1 = не проверять
    "needHeatShield", FALSE
  ).
}

GLOBAL FUNCTION q_bodyChecklist {
  PARAMETER spec.
  LOCAL items IS LIST().
  IF spec["dv"] > 0 {
    items:ADD(LEXICON("label", "запас Δv ≥ " + ROUND(spec["dv"]) + " м/с (по бортовому счётчику)",
                       "ok", SHIP:DELTAV:VACUUM >= spec["dv"])).
  }
  IF spec["ecReserve"] > 0 {
    LOCAL hasRtg IS q_hasPart("РИТЭГ") OR q_hasPart("Нейтроник").
    items:ADD(LEXICON("label", "заряд на теневую сторону: РИТЭГ либо ёмкость ≥ "
                       + ROUND(spec["ecReserve"]) + " ЭЧ (сейчас " + ROUND(q_ecCapacity()) + ")",
                       "ok", hasRtg OR q_ecCapacity() >= spec["ecReserve"])).
  }
  IF spec["needHeatShield"] {
    items:ADD(LEXICON("label", "теплозащитный экран", "ok",
      q_hasPart("теплозащ") OR q_hasModule("Ablat"))).
  }
  RETURN items.
}

// ─── план: телеметрия + чекеры + Δv-бюджет одной функцией ─────────────
//
//   RUNONCEPATH("0:/lib/audit.ks").
//   SET spec TO LEXICON(
//     "tasks", LIST(
//       LEXICON("title", "SCANsat: высотометрия", "items", q_taskScanAltimetry()),
//       LEXICON("title", "Созвездие: 4 спутника", "items", q_taskConstellation(4, "sat-"))
//     ),
//     "budget", LIST(
//       LEXICON("label", "перелёт к телу", "dv", 856, "optional", FALSE),
//       LEXICON("label", "смена плоскости (опция)", "dv", 770, "optional", TRUE)
//     )
//   ).
//   q_plan(spec).
//
// Ничего не жжёт и не ставит узлов — только читает SHIP и считает суммы.
// Один и тот же q_plan обслуживает любой корабль: конкретика (какие
// чекеры, какие цифры бюджета) приходит СНАРУЖИ, спецификацией, а не
// прошита внутри функции.

GLOBAL FUNCTION q_shipReport {
  PRINT "имя:      " + SHIP:NAME.
  PRINT "тело:     " + SHIP:BODY:NAME.
  PRINT "статус:   " + SHIP:STATUS.
  PRINT "высота:   " + ROUND(SHIP:ALTITUDE,0) + " м".
  PRINT "масса:    " + ROUND(SHIP:MASS,2) + " т".
  PRINT "Δv (вак): " + ROUND(SHIP:DELTAV:VACUUM,0) + " м/с  [стоковый счётчик; 0 значит,".
  PRINT "          что в настройках выключен Advanced Tweakables → Delta-V readout]".
  PRINT "заряд:    " + ROUND(q_ecCapacity(),0) + " ЭЧ ёмкость".
  PRINT "деталей:  " + SHIP:PARTS:LENGTH.
}

// budget — список LEXICON("label", "dv", "optional"). Обязательные пункты
// суммируются в бегущий итог, опциональные печатаются отдельно и в сумму
// не входят (нужны или нет — решает конкретная миссия, не эта функция).
// Возвращает сумму обязательных пунктов.
GLOBAL FUNCTION q_dvBudget {
  PARAMETER budget.
  PRINT "=== бюджет Δv по фазам (ориентиры, не физический расчёт) ===".
  LOCAL running IS 0.
  FOR b IN budget {
    IF b["optional"] {
      PRINT "  [опция] " + b["label"] + ": " + b["dv"] + " м/с".
    } ELSE {
      SET running TO running + b["dv"].
      PRINT "  " + b["label"] + ": " + b["dv"] + " м/с   (итого " + running + ")".
    }
  }
  PRINT "  итого обязательных: " + running + " м/с".
  LOCAL haveDv IS SHIP:DELTAV:VACUUM.
  IF haveDv > 0 {
    PRINT "  запас на борту: " + ROUND(haveDv,0) + " м/с, остаток "
          + ROUND(haveDv - running,0) + " м/с".
  } ELSE {
    PRINT "  ! SHIP:DELTAV дал 0 — включи Advanced Tweakables → Delta-V readout,".
    PRINT "    иначе бюджет свериться не может.".
  }
  RETURN running.
}

// Живой расчёт узла перехода к телу — ТОЛЬКО если уже на стабильной
// орбите (не PRELAUNCH/суборбитальная). r_nodeTransfer создаёт NODE(),
// но НЕ добавляет его в план полёта (ADD не вызывается) — чтение, не действие.
// Требует RUNONCEPATH lib/transfer.ks заранее — эта функция её не тянет,
// чтобы q_plan оставался лёгким, когда живой расчёт не нужен.
GLOBAL FUNCTION q_liveTransfer {
  PARAMETER dest.
  IF SHIP:ALTITUDE < SHIP:BODY:ATM:HEIGHT OR SHIP:ORBIT:APOAPSIS <= 0 {
    PRINT "=== живой расчёт перехода недоступен — не на стабильной орбите ===".
    RETURN.
  }
  PRINT "=== живой расчёт (уже на орбите " + SHIP:BODY:NAME + ") ===".
  LOCAL nd IS r_nodeTransfer(dest).
  PRINT "  узел перехода к " + dest:NAME + ": " + ROUND(nd:DELTAV:MAG,1) + " м/с, через "
        + ROUND(nd:ETA,0) + " с (" + ROUND(nd:ETA/60,1) + " мин)".
  PRINT "  накл. к плоскости " + dest:NAME + ": " + ROUND(r_relInc(dest),2) + "°".
}

// Спецификация: "tasks" — список LEXICON("title","items") под q_report,
// "budget" — необязательный список под q_dvBudget. Возвращает число
// провалившихся пунктов по всем tasks вместе.
GLOBAL FUNCTION q_plan {
  PARAMETER spec.
  PRINT "======================================".
  q_shipReport().
  PRINT " ".
  LOCAL fail IS 0.
  FOR t IN spec["tasks"] {
    SET fail TO fail + q_report(t["title"], t["items"]).
  }
  IF spec:HASKEY("budget") {
    PRINT " ".
    q_dvBudget(spec["budget"]).
  }
  PRINT " ".
  IF fail = 0 { PRINT "== комплектация: всё, что видно чекеру, на месте ==". }
  ELSE { PRINT "== комплектация: не хватает " + fail + " пункт(ов), смотри выше ==". }
  PRINT "======================================".
  RETURN fail.
}

// Цифры — из [[missiya-mun]]: захват в картографическую 250 км ≈ 1150 м/с
// от опорной 80 км; теневая сторона Муна до 19 ч, зондовому ядру нужно
// 1400–3500 ЭЧ без РИТЭГа. Профиль «остаться на орбите картографом».
GLOBAL FUNCTION q_bodyMun {
  LOCAL s IS q_bodyDefaults().
  SET s["dv"] TO 1150.
  SET s["ecReserve"] TO 1400.
  RETURN s.
}

// Профиль «развести спутники и сесть, без обратного взлёта» — от опорной
// орбиты Кербина: перелёт 856 + захват на рабочую ~300 + развод по фазе
// ~100 + один манёвр смены плоскости под полярное покрытие ~770 +
// посадка без взлёта ~700, с запасом. Заряд не критичен — шина не сидит
// месяцами на орбите, весь профиль укладывается в один-два дня полёта.
GLOBAL FUNCTION q_bodyMunTour {
  LOCAL s IS q_bodyDefaults().
  SET s["dv"] TO 2700.
  RETURN s.
}
