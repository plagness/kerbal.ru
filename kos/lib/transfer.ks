// lib/transfer.ks — перелёт к другому телу той же сферы влияния (Мун, Минмус)
// и заход на круговую орбиту вокруг него.
// Зависит от: lib/ctrl.ks, lib/orbit.ks, lib/rendezvous.ks
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
GLOBAL FUNCTION x_aimPeri {
  PARAMETER wantAlt.
  PARAMETER tol IS 15000.
  PARAMETER tries IS 6.

  IF NOT x_hasEncounter() {
    PRINT "  ! энкаунтера нет — подгонять пока нечего".
    RETURN FALSE.
  }
  LOCAL n IS 0.
  UNTIL ABS(x_encounterPeri() - wantAlt) <= tol OR n >= tries {
    LOCAL ut IS TIME:SECONDS + 30.
    LOCAL nd IS x_nodeAimPeri(wantAlt, ut).
    o_burn(nd).
    SET n TO n + 1.
    IF x_hasEncounter() {
      PRINT "  прицел: перицентр " + ROUND(x_encounterPeri()/1000,1)
            + " км (цель " + ROUND(wantAlt/1000,1) + " км)".
    }
  }
  RETURN x_hasEncounter() AND ABS(x_encounterPeri() - wantAlt) <= tol.
}

// ─── перелёт целиком ──────────────────────────────────────────────────

// Перелёт к телу dest внутри той же сферы влияния и заход на круговую
// орбиту высотой wantAlt. Наклонение НЕ подгоняется здесь — закладывай
// его на пуске у родительского тела ([[rendezvous]], тот же принцип).
// Имя параметра НЕ body — это встроенная функция kOS, CLOBBERBUILTINS
// ловит попытку её перекрыть уже при компиляции, до пуска.
GLOBAL FUNCTION x_go {
  PARAMETER dest.
  PARAMETER wantAlt.

  PRINT "=== перелёт к " + dest:NAME + ", цель " + ROUND(wantAlt/1000,1) + " км".

  IF r_relInc(dest) > 0.5 { o_burn(r_nodeMatchPlanes(dest)). }

  LOCAL nd IS r_nodeTransfer(dest).
  o_burn(nd).
  PRINT "  переходная: апоцентр " + ROUND(SHIP:APOAPSIS/1000,0) + " км".

  x_aimPeri(wantAlt).

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
