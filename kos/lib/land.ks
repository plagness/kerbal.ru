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

  // Деорбит обычно жжётся у апоцентра — до реального касания земли ещё
  // почти виток пустого падения. Раньше l_descend просто сидела в цикле
  // WAIT 0 всё это время (до ~часа реального времени на вытянутой
  // орбите — поймано вживую). Домотать варпом можно смело: тяга ещё не
  // нужна высоко, l_vsLimit(10000+) всё равно даёт потолок 150 м/с.
  IF ALT:RADAR > 15000 AND ETA:PERIAPSIS > 30 {
    PRINT "  варп через пустое падение до перицентра…".
    WARPTO(TIME:SECONDS + ETA:PERIAPSIS - 20).
    WAIT UNTIL ALT:RADAR <= 15000 OR SHIP:STATUS = "LANDED" OR SHIP:STATUS = "SPLASHED".
  }

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
  // Если перицентр уже НИЖЕ цели — мы уже падаем на поверхность (уже был
  // отдельный прожиг, снёсший перицентр под 0). l_nodeDeorbit жжёт В
  // АПОЦЕНТРЕ — на таком заходе к моменту, когда WARPTO дотащит до
  // апоцентра, аппарат уже врежется. Поймано вживую: второй «деорбитный»
  // узел на уже падающей траектории привёл к столкновению до прожига.
  // В этом случае деорбит не нужен вообще — сразу тормозим.
  IF SHIP:PERIAPSIS > targetAlt {
    o_burn(l_nodeDeorbit(targetAlt)).
  } ELSE {
    PRINT "  перицентр уже " + ROUND(SHIP:PERIAPSIS/1000,1) + " км — уже падаем, деорбит не нужен, торможу сразу.".
  }
  l_descend(onTick).
}

// ─── посадка на нужной стороне тела ────────────────────────────────
//
// Мун приливно заперт: сторона, обращённая к Кербину, — фиксированное
// полушарие, не блуждает во времени. Точное место посадки этот приём
// НЕ даёт (это отдельная нерешённая задача, см. kos/README.md) — только
// гарантирует полушарие: деорбит стартует, пока корабль над нужной
// стороной, а спуск сносит недалеко относительно размера тела.

// Косинус угла между «вверх с корабля» и направлением на refBody —
// >0 значит над ближней стороной. Вынесено отдельно от l_facingBody,
// чтобы поиск мог печатать тренд и не гадать вслепую, сколько ещё ждать.
GLOBAL FUNCTION l_facingCos {
  PARAMETER refBody.
  LOCAL zenith IS -SHIP:BODY:POSITION.                     // центр тела → корабль
  LOCAL toRef IS refBody:POSITION - SHIP:BODY:POSITION.     // центр тела → refBody
  RETURN VDOT(zenith:NORMALIZED, toRef:NORMALIZED).
}

// TRUE, если корабль сейчас над полушарием, обращённым к refBody.
GLOBAL FUNCTION l_facingBody {
  PARAMETER refBody.
  RETURN l_facingCos(refBody) > 0.
}

// СТАРАЯ ВЕРСИЯ (для памяти, не звать напрямую в l_go): проверяла «смотрим
// ли на refBody СЕЙЧАС», где бы корабль ни был в этот момент орбиты — а
// потом l_go жгла деорбит и падала до ПЕРИЦЕНТРА, который на вытянутой
// орбите может быть совсем в другой точке. Поймано вживую: проверка
// прошла у апоцентра, а перицентр (реальная точка посадки) оказался над
// обратной стороной Муны — сторона зафиксирована приливным захватом,
// но НАШ перицентр зафиксирован в инерциальном пространстве, а Муна
// вращается под ним (период 38.6 ч) — со временем перицентр «проезжает»
// по разным долготам. Проверять нужно СТОРОНУ ИМЕННО У ПЕРИЦЕНТРА, не
// где попало на орбите.
GLOBAL FUNCTION l_waitFacing {
  PARAMETER refBody.
  PARAMETER maxOrbits IS 3.
  IF l_facingBody(refBody) { RETURN TRUE. }
  PRINT "  жду виток над стороной, обращённой к " + refBody:NAME + "…".
  LOCAL deadline IS TIME:SECONDS + SHIP:ORBIT:PERIOD * maxOrbits.
  WARPTO(TIME:SECONDS + SHIP:ORBIT:PERIOD * 0.4).   // грубый скачок вперёд, не точный расчёт
  WAIT UNTIL l_facingBody(refBody) OR TIME:SECONDS > deadline.
  RETURN l_facingBody(refBody).
}

// Правильная версия: проверяет сторону РЯДОМ С ПЕРИЦЕНТРОМ, вживую, без
// предсказаний через POSITIONAT (эта библиотека уже обжигалась на нём —
// см. rendezvous.ks). Домотать почти до перицентра, посмотреть на месте,
// не подходит — домотать почти виток вперёд к следующему перицентру,
// повторить. До maxTries витков (по умолчанию покрывает больше, чем
// один оборот Муны вокруг своей оси, — гарантированно застанет нужную
// сторону хотя бы раз, если орбита вообще её пересекает).
GLOBAL FUNCTION l_waitFacingAtPeri {
  PARAMETER refBody.
  // Дрейф прилегания к стороне идёт с периодом порядка периода вращения
  // тела / периода нашей орбиты (для Муны ~43 витка на полный цикл) —
  // 30 витков одно время казалось «с запасом», но старт вблизи начала
  // «дальней» половины цикла исчерпал лимит вхолостую. 50 витков —
  // с запасом покрывает полный цикл при любой стартовой фазе.
  PARAMETER maxTries IS 50.
  LOCAL n IS 0.
  UNTIL n >= maxTries {
    IF ETA:PERIAPSIS > 60 { WARPTO(TIME:SECONDS + ETA:PERIAPSIS - 60). }
    WAIT UNTIL ETA:PERIAPSIS <= 60.
    LOCAL c IS l_facingCos(refBody).
    IF c > 0 {
      PRINT "  перицентр витка " + (n+1) + " — над нужной стороной (cos=" + ROUND(c,2) + "), сажусь на этом заходе.".
      RETURN TRUE.
    }
    SET n TO n + 1.
    PRINT "  перицентр витка " + n + " — не над " + refBody:NAME + " (cos=" + ROUND(c,2) + "), жду следующий (" + n + "/" + maxTries + ")…".
    WARPTO(TIME:SECONDS + SHIP:ORBIT:PERIOD * 0.5).   // уйти от этого перицентра, не застрять на нём же
  }
  PRINT "  ! не нашли подходящий перицентр за " + maxTries + " витков.".
  RETURN FALSE.
}

// Дождаться перицентра над конкретной точкой (не просто полушарием) —
// напр. waypoint от SCANsat/контракта. Как l_waitFacingAtPeri, но
// сравнивает GEOPOSITION у самого перицентра с целью через
// u_greatCircleDist, а не грубый dot-product по полушарию.
// Измерить дистанцию до цели у ближайшего перицентра, не сдвигая скрипт
// дальше (для планирования шага снаружи).
GLOBAL FUNCTION l_distAtNextPeri {
  PARAMETER targetLat, targetLng.
  IF ETA:PERIAPSIS > 60 { WARPTO(TIME:SECONDS + ETA:PERIAPSIS - 60). }
  WAIT UNTIL ETA:PERIAPSIS <= 60.
  RETURN u_greatCircleDist(SHIP:GEOPOSITION:LAT, SHIP:GEOPOSITION:LNG,
                            targetLat, targetLng, SHIP:BODY:RADIUS) / 1000.
}

// Найти перицентр над целью. Долгота цели относительно перицентра
// дрейфует медленно (тело вращается под почти неподвижным в инерциале
// перицентром) — на грубом переборе по 0.5 витка это могло бы занять
// сотни витков. Сначала КРУПНЫМИ прыжками (coarseOrbits витков за раз)
// ищем окрестность минимума, ловим момент, когда дистанция начинает
// расти обратно (проскочили) — откатываемся на один крупный шаг назад и
// добираем ТОЧНО по одному витку, как раньше.
GLOBAL FUNCTION l_waitOverSite {
  PARAMETER targetLat, targetLng.
  PARAMETER tolKm IS 150.
  PARAMETER coarseOrbits IS 12.
  PARAMETER maxCoarse IS 40.
  PARAMETER maxFine IS 15.

  LOCAL orbP IS SHIP:ORBIT:PERIOD.
  LOCAL d IS l_distAtNextPeri(targetLat, targetLng).
  PRINT "  старт: " + ROUND(d,0) + " км от цели.".
  IF d <= tolKm { RETURN TRUE. }

  // ─── грубый проход ───
  LOCAL n IS 0.
  LOCAL prevD IS d.
  UNTIL n >= maxCoarse {
    WARPTO(TIME:SECONDS + orbP * coarseOrbits - orbP * 0.5).   // подвести к концу прыжка минус запас на точный подход к перицентру
    LOCAL nd IS l_distAtNextPeri(targetLat, targetLng).
    SET n TO n + 1.
    PRINT "  грубый шаг " + n + " (+" + coarseOrbits + " вит.): " + ROUND(nd,0) + " км от цели.".
    IF nd <= tolKm {
      PRINT "  попали в допуск на грубом шаге, сажусь.".
      RETURN TRUE.
    }
    IF nd > prevD {
      PRINT "  проскочили минимум (было " + ROUND(prevD,0) + ", стало " + ROUND(nd,0) + ") — ухожу в точный поиск с прошлого шага.".
      SET n TO n - 1.
      BREAK.
    }
    SET prevD TO nd.
  }

  // ─── точный проход по одному витку от найденной окрестности ───
  LOCAL m IS 0.
  LOCAL bestDist IS prevD.
  UNTIL m >= maxFine {
    LOCAL fd IS l_distAtNextPeri(targetLat, targetLng).
    IF fd < bestDist { SET bestDist TO fd. }
    IF fd <= tolKm {
      PRINT "  точный виток " + (m+1) + " — " + ROUND(fd,0) + " км от цели, сажусь на этом заходе.".
      RETURN TRUE.
    }
    SET m TO m + 1.
    PRINT "  точный виток " + m + " — " + ROUND(fd,0) + " км от цели (допуск " + tolKm + "), " + m + "/" + maxFine + "…".
    WARPTO(TIME:SECONDS + orbP * 0.5).
  }
  PRINT "  ! не подошли ближе " + ROUND(bestDist,0) + " км.".
  RETURN FALSE.
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
