// lib/transfer.ks — перелёт к другому телу той же сферы влияния (Мун, Минмус)
// и заход на круговую орбиту вокруг него.
// Зависит от: lib/util.ks, lib/ctrl.ks, lib/orbit.ks, lib/rendezvous.ks
// kerbal.ru · сборка «Оператор»
//
//   RUNONCEPATH("0:/lib/transfer.ks").
//   x_go(MUN, 250000).      // выйти на круговую полярную 250 км у Муна
//
// Геометрия перелёта и фазового окна — та же, что при рандеву с аппаратом
// ([[rendezvous]]): у CelestialBody в kOS те же суффиксы ORBIT/POSITION/
// VELOCITY, что у Vessel, поэтому r_nodeMatchPlanes(MUN) и r_nodeTransfer(MUN)
// работают без изменений. Новое здесь — то, чего у обычного рандеву нет:
// подгонка прицельного перицентра ДО входа в чужую сферу влияния и захват
// на гиперболическом подлёте, где апоцентра ещё не существует.

RUNONCEPATH("0:/lib/util.ks").
RUNONCEPATH("0:/lib/ctrl.ks").
RUNONCEPATH("0:/lib/orbit.ks").
RUNONCEPATH("0:/lib/rendezvous.ks").

// ─── подгонка прицельного перицентра ─────────────────────────────────
//
// После прожига перехода NEXTPATCH — это уже орбита ВНУТРИ чужой сферы
// влияния (если она вообще предсказана). Её перицентр — это и есть точка
// прицеливания. Двигаем её узлом «поперёк» в момент перехода: пробуем
// оба знака и оставляем тот, что приближает перицентр к цели — тот же
// приём проверки знака, что и в r_nodeMatchPlanes, потому что «какая
// сторона ближе» тоже не выводится интуицией в левой системе координат.

GLOBAL FUNCTION x_hasEncounter {
  RETURN SHIP:ORBIT:HASNEXTPATCH AND SHIP:ORBIT:NEXTPATCH:BODY <> SHIP:BODY.
}

GLOBAL FUNCTION x_encounterPeri {
  IF NOT x_hasEncounter() { RETURN -1. }
  RETURN SHIP:ORBIT:NEXTPATCH:PERIAPSIS.
}

// Подправить прицельный перицентр у тела-цели небольшим боковым прожигом
// в известный момент ut (обычно — момент узла перехода). tol — допуск, м.
GLOBAL FUNCTION x_nodeAimPeri {
  PARAMETER wantAlt.
  PARAMETER ut.
  PARAMETER step IS 15.       // м/с, шаг пробы

  LOCAL best IS 1.
  LOCAL bestErr IS 9e9.
  FOR sgn IN LIST(1, -1) {
    LOCAL probe IS NODE(ut, 0, sgn * step, 0).
    ADD probe.
    WAIT 0.
    IF x_hasEncounter() {
      LOCAL err IS ABS(x_encounterPeri() - wantAlt).
      IF err < bestErr { SET bestErr TO err. SET best TO sgn. }
    }
    REMOVE probe.
    WAIT 0.
  }
  RETURN NODE(ut, 0, best * step, 0).
}

// Прогнать подгонку прицела до попадания в допуск или до предела попыток.
// Каждая проба — реальный узел на плане полёта, поэтому дорого по времени
// выполнения; вызывать сразу после узла перехода, пока запас есть.
//
// АВАРИЯ (2026-07-31): фиксированный шаг пробы (15 м/с) на живом перелёте
// сдвигал перицентр всего на 0,6–0,8 км за попытку, а нужно было пройти
// 299 км (перицентр -199 км при цели 100 км — минус означает «ПОД
// поверхностью», Мун радиусом 200 км). За 6 попыток дошли до ~-195 км, всё
// ещё смертельно, и x_go пошёл дальше — WARPTO домотал прямо до
// столкновения. Фикс — адаптивный шаг: меряем чувствительность на первой
// пробе (км сдвига на 1 м/с) и дальше считаем шаг напрямую под остаток
// ошибки, а не тычемся тем же микрошагом снова и снова.
GLOBAL FUNCTION x_aimPeri {
  PARAMETER wantAlt.
  PARAMETER tol IS 15000.
  PARAMETER tries IS 10.

  IF NOT x_hasEncounter() {
    PRINT "  ! энкаунтера нет — подгонять пока нечего".
    RETURN FALSE.
  }
  LOCAL n IS 0.
  LOCAL step IS 15.        // м/с, стартовый шаг пробы — дальше подстраивается
  UNTIL ABS(x_encounterPeri() - wantAlt) <= tol OR n >= tries {
    LOCAL before IS x_encounterPeri().
    LOCAL ut IS TIME:SECONDS + 30.
    LOCAL nd IS x_nodeAimPeri(wantAlt, ut, step).
    o_burn(nd).
    SET n TO n + 1.
    IF NOT x_hasEncounter() { BREAK. }   // прожиг мог сорвать энкаунтер вовсе
    LOCAL after IS x_encounterPeri().
    PRINT "  прицел: перицентр " + ROUND(after/1000,1)
          + " км (цель " + ROUND(wantAlt/1000,1) + " км), шаг " + ROUND(step,1) + " м/с".
    LOCAL moved IS after - before.
    LOCAL err IS wantAlt - after.
    IF ABS(moved) > 200 {
      // видна реальная чувствительность — считаем следующий шаг напрямую,
      // а не гадаем: сколько км сдвинул 1 м/с, столько и просим на остаток.
      LOCAL sensitivity IS moved / step.       // м перицентра на 1 м/с прожига
      SET step TO u_clamp(err / sensitivity, -2000, 2000).
    } ELSE {
      SET step TO step * 5.    // движения почти не видно — шаг был слишком мал
    }
  }
  RETURN x_hasEncounter() AND ABS(x_encounterPeri() - wantAlt) <= tol.
}

// ─── перелёт целиком ──────────────────────────────────────────────────

// Проверить узел ПЕРЕД прожигом: просит больше 90% того, что реально на
// борту (SHIP:DELTAV:VACUUM), — не жжём, а печатаем и отказываем. Родилось
// из реальной аварии: опорная орбита была полярной (85°), а Мун лежит
// у экватора Кербина — подгонка плоскости попросила 3682,8 м/с при
// ~2300 на борту. Без этой проверки o_burn жжёт что дают, до последней
// капли, и разбирается уже постфактум. 90%, а не 100% — запас на то,
// что после подгонки плоскости ещё нужен сам переход и захват.
GLOBAL FUNCTION x_checkBudget {
  PARAMETER nd.
  PARAMETER label.
  // У неприкреплённого узла нельзя спросить :DELTAV — «Must attach node
  // first» (тот же приём, что в o_burn: ADD, потом WAIT 0, потом читаем).
  // Если проверка проходит, узел остаётся в плане — o_burn его подхватит,
  // не добавляя повторно (NEXTNODE уже будет равен nd).
  IF NOT HASNODE OR NEXTNODE <> nd { ADD nd. }
  WAIT 0.
  LOCAL need IS nd:DELTAV:MAG.
  LOCAL have IS SHIP:DELTAV:VACUUM.
  IF need < 1 {
    PRINT "  ! " + label + " не даёт рабочего узла (Δv ~0) — смотри диагностику выше, прожиг не даю.".
    IF HASNODE { REMOVE nd. }
    RETURN FALSE.
  }
  IF have > 0 AND need > have * 0.9 {
    PRINT "  ! " + label + " просит " + ROUND(need,0) + " м/с, на борту " + ROUND(have,0)
          + " м/с — это не мелкий недолёт, а перепутанные плоскости.".
    PRINT "  ! проверь наклонение опорной орбиты против ORBIT:INCLINATION цели, прожиг не даю.".
    IF HASNODE { REMOVE nd. }
    RETURN FALSE.
  }
  RETURN TRUE.
}

// Перелёт к телу dest внутри той же сферы влияния и заход на круговую
// орбиту высотой wantAlt. Наклонение НЕ подгоняется здесь — закладывай
// его на пуске у родительского тела так, чтобы плоскость совпадала с
// dest:ORBIT:INCLINATION (для Муна это обычно 0° — экватор родителя,
// НЕ полярная!), см. [[rendezvous]]. Имя параметра НЕ body — это
// встроенная функция kOS, CLOBBERBUILTINS ловит попытку её перекрыть
// уже при компиляции, до пуска.
GLOBAL FUNCTION x_go {
  PARAMETER dest.
  PARAMETER wantAlt.

  PRINT "=== перелёт к " + dest:NAME + ", цель " + ROUND(wantAlt/1000,1) + " км".

  IF r_relInc(dest) > 0.5 {
    LOCAL matchNd IS r_nodeMatchPlanes(dest).
    IF NOT x_checkBudget(matchNd, "смена плоскости") { RETURN FALSE. }
    o_burn(matchNd).
  }

  LOCAL nd IS r_nodeTransfer(dest).
  IF NOT x_checkBudget(nd, "переход") { RETURN FALSE. }
  o_burn(nd).
  PRINT "  переходная: апоцентр " + ROUND(SHIP:APOAPSIS/1000,0) + " км".

  x_aimPeri(wantAlt).

  // ЖЁСТКАЯ ГРАНИЦА БЕЗОПАСНОСТИ (2026-07-31, после столкновения с Муной).
  // x_aimPeri раньше не проверялся вообще — WARPTO домотал прямо до
  // столкновения, потому что подгонка не сошлась, а x_go не глядя летел
  // дальше. Здесь — последний рубеж перед варпом: если энкаунтера нет
  // или прицел остался в опасной зоне (меньше половины заказанной
  // высоты — курс либо в поверхность, либо близко к ней), лёт
  // ОСТАНАВЛИВАЕТСЯ ДО входа в сферу влияния, а не после столкновения.
  IF NOT x_hasEncounter() OR x_encounterPeri() < wantAlt * 0.5 {
    PRINT "  ! перицентр не в безопасной зоне (" + ROUND(x_encounterPeri()/1000,1)
          + " км при заказанных " + ROUND(wantAlt/1000,1) + " км) — курс мог вести".
    PRINT "  ! в поверхность или мимо. Лечу ДО сферы влияния — не варплю вслепую.".
    RETURN FALSE.
  }

  PRINT "  жду вход в сферу влияния " + dest:NAME + "…".
  LOCAL deadline IS TIME:SECONDS + dest:ORBIT:PERIOD.   // с запасом на весь виток тела
  WARPTO(TIME:SECONDS + ETA:APOAPSIS - 60).
  WAIT UNTIL SHIP:BODY = dest OR TIME:SECONDS > deadline.
  IF SHIP:BODY <> dest {
    PRINT "  ! в сферу влияния не вошли — перелёт не удался".
    RETURN FALSE.
  }

  PRINT "  вошли в СВП " + dest:NAME + ": пери " + ROUND(SHIP:PERIAPSIS/1000,1) + " км".
  o_burn(o_nodeCircularizeAtPeri()).
  PRINT "=== на орбите " + dest:NAME + ": " + ROUND(SHIP:APOAPSIS/1000,1)
        + " / " + ROUND(SHIP:PERIAPSIS/1000,1) + " км, накл "
        + ROUND(SHIP:ORBIT:INCLINATION,1) + "°".
  RETURN TRUE.
}
