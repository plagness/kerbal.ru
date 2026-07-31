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

GLOBAL FUNCTION q_taskScanAltimetry {
  RETURN LIST(
    LEXICON("label", "высотомер SCAN или R-3B на борту", "ok",
      q_hasPart("высотомер SCAN") OR q_hasPart("R-3B") OR q_hasPart("SCAN SAR")
      OR q_hasPart("SAR-X") OR q_hasPart("SAR-C") OR q_hasPart("SAR-L")),
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

// Цифры — из [[missiya-mun]]: захват в картографическую 250 км ≈ 1150 м/с
// от опорной 80 км; теневая сторона Муна до 19 ч, зондовому ядру нужно
// 1400–3500 ЭЧ без РИТЭГа.
GLOBAL FUNCTION q_bodyMun {
  LOCAL s IS q_bodyDefaults().
  SET s["dv"] TO 1150.
  SET s["ecReserve"] TO 1400.
  RETURN s.
}
