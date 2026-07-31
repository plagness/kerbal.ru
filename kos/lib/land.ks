// lib/land.ks — посадка двигателем на тело без атмосферы (Мун, Минмус).
// Зависит от: lib/util.ks, lib/ctrl.ks, lib/orbit.ks
// kerbal.ru · сборка «Оператор»
//
//   RUNONCEPATH("0:/lib/land.ks").
//   o_burn(o_nodeRaisePeri(0)).    // деорбит: опустить перицентр к поверхности
//   l_descend().                   // дальше держит вертикальную скорость сам
//
// Порог «высота → не быстрее» — таблица из [[vozvrat]], проверенная руками
// на живых посадках, здесь только переложена в код построчной интерполяцией.
// НЕ придумывает новую физику: между узлами таблицы — прямая линия.
// Только для тел БЕЗ атмосферы: с воздухом сопротивление меняет картину,
// там работает связка «парашют → l_descend», а не один l_descend.

RUNONCEPATH("0:/lib/util.ks").
RUNONCEPATH("0:/lib/ctrl.ks").
RUNONCEPATH("0:/lib/orbit.ks").

// Предел вертикальной скорости на заданной радарной высоте, м/с (положительное
// число = скорость снижения). Узлы таблицы: 10 км→150, 5 км→100, 2 км→60,
// 500 м→25, 100 м→10, касание→5.
GLOBAL FUNCTION l_vsLimit {
  PARAMETER radarAlt.       // не alt — ALT занят встроенным
  IF radarAlt > 10000 { RETURN 150. }
  IF radarAlt > 5000  { RETURN 100 + (radarAlt - 5000) / 5000 * 50. }
  IF radarAlt > 2000  { RETURN  60 + (radarAlt - 2000) / 3000 * 40. }
  IF radarAlt >  500  { RETURN  25 + (radarAlt -  500) / 1500 * 35. }
  IF radarAlt >  100  { RETURN  10 + (radarAlt -  100) /  400 * 15. }
  RETURN 5 + radarAlt / 100 * 5.
}

// Опустить перицентр к поверхности — деорбит. targetAlt по умолчанию 0 —
// o_nodeRaisePeri сам добавляет радиус тела, формула симметрична: с тем же
// успехом опускает перицентр, с каким поднимает, разница только в знаке dv.
GLOBAL FUNCTION l_nodeDeorbit {
  PARAMETER targetAlt IS 0.
  RETURN o_nodeRaisePeri(targetAlt).
}

// Спуск от «перицентр у поверхности» до касания. Держит нос против
// вектора скорости относительно поверхности, у земли — строго вверх,
// тягу — по разнице текущей и предельной вертикальной скорости.
GLOBAL FUNCTION l_descend {
  PARAMETER onTick IS { }.
  PARAMETER vertAt IS 150.       // ниже этой высоты нос строго вверх, не по потоку

  PRINT "=== посадка: жду касания поверхности".
  SAS OFF.
  c_rcs(TRUE).
  // Оба LOCK — динамические выражения, kOS сам пересчитывает их каждый
  // тик: перезапирать в цикле не нужно, см. o_burn для того же приёма.
  LOCK STEERING TO CHOOSE UP IF ALT:RADAR < vertAt ELSE SHIP:SRFRETROGRADE.
  LOCK THROTTLE TO u_clamp((-SHIP:VERTICALSPEED - l_vsLimit(ALT:RADAR) * 0.9) / 20, 0, 1).

  UNTIL SHIP:STATUS = "LANDED" OR SHIP:STATUS = "SPLASHED" {
    onTick().
    WAIT 0.
  }

  LOCK THROTTLE TO 0.
  UNLOCK STEERING.
  RCS OFF.
  SAS ON.
  PRINT "=== посадка завершена: " + SHIP:STATUS + ", биом «" + SHIP:GEOPOSITION:BIOME + "»".
}

// Деорбит и посадка одной командой.
GLOBAL FUNCTION l_go {
  PARAMETER targetAlt IS 0.
  PARAMETER onTick IS { }.
  o_burn(l_nodeDeorbit(targetAlt)).
  l_descend(onTick).
}

// ─── посадка на нужной стороне тела ────────────────────────────────
//
// Мун приливно заперт: сторона, обращённая к Кербину, — фиксированное
// полушарие, не блуждает во времени. Точное место посадки этот приём
// НЕ даёт (это отдельная нерешённая задача, см. kos/README.md) — только
// гарантирует полушарие: деорбит стартует, пока корабль над нужной
// стороной, а спуск сносит недалеко относительно размера тела.

// TRUE, если корабль сейчас над полушарием, обращённым к refBody.
GLOBAL FUNCTION l_facingBody {
  PARAMETER refBody.
  LOCAL zenith IS -SHIP:BODY:POSITION.                     // центр тела → корабль
  LOCAL toRef IS refBody:POSITION - SHIP:BODY:POSITION.     // центр тела → refBody
  RETURN VDOT(zenith:NORMALIZED, toRef:NORMALIZED) > 0.
}

// Дождаться витка, на котором корабль окажется над нужным полушарием.
GLOBAL FUNCTION l_waitFacing {
  PARAMETER refBody.
  PARAMETER maxOrbits IS 3.
  IF l_facingBody(refBody) { RETURN TRUE. }
  PRINT "  жду виток над стороной, обращённой к " + refBody:NAME + "…".
  LOCAL deadline IS TIME:SECONDS + SHIP:ORBIT:PERIOD * maxOrbits.
  WAIT UNTIL l_facingBody(refBody) OR TIME:SECONDS > deadline.
  RETURN l_facingBody(refBody).
}

// ─── одной спецификацией, как ds_run() в lib/deepspace.ks ─────────────
//
//   RUNONCEPATH("0:/lib/land.ks"). RUNONCEPATH("0:/lib/sci.ks").
//   SET s TO l_defaults().
//   SET s["sci"] TO TRUE.     // снять науку после касания
//   l_run(s).

GLOBAL FUNCTION l_defaults {
  RETURN LEXICON(
    "targetAlt", 0,     // высота прицельного перицентра деорбита, м
    "vertAt", 150,      // ниже этой высоты нос строго вверх
    "sci", TRUE         // снять науку сразу после посадки — требует RUNONCEPATH lib/sci.ks заранее
  ).
}

GLOBAL FUNCTION l_run {
  PARAMETER spec.
  o_burn(l_nodeDeorbit(spec["targetAlt"])).
  l_descend({ }, spec["vertAt"]).
  IF spec["sci"] { sciSweep("на поверхности", FALSE). }
}
