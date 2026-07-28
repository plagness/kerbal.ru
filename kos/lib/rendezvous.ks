// lib/rendezvous.ks — догнать аппарат на орбите и подойти вплотную.
// Зависит от: lib/ctrl.ks, lib/orbit.ks
// kerbal.ru · сборка «Оператор»
//
//   RUNONCEPATH("0:/lib/rendezvous.ks").
//   SET TARGET TO VESSEL("Станция-1").
//   r_go(TARGET, 100).            // подвести на 100 м и погасить скорость
//
// Что делает: подгоняет плоскость, ждёт фазовое окно, выполняет переход,
// гасит относительную скорость и подводит на заданную дистанцию.
// Чего НЕ делает: не причаливает по портам. Стыковка — отдельная задача
// с другой механикой (порты, оси, магниты), её ведёт игрок или MechJeb.
//
// ПРО ЗНАКИ. Плоскость подгоняется прожигом «поперёк», и знак этой
// компоненты в левой системе координат KSP интуиции не поддаётся —
// на этом уже терялись полёты. Поэтому знак не выводится, а ПРОВЕРЯЕТСЯ:
// узел строится дважды и остаётся тот, после которого расхождение
// плоскостей меньше. Проверка стоит доли секунды и не врёт.

RUNONCEPATH("0:/lib/ctrl.ks").
RUNONCEPATH("0:/lib/orbit.ks").

// ─── геометрия ────────────────────────────────────────────────────────

// Радиус-вектор объекта от центра тела. POSITION в kOS отсчитывается
// от корабля, поэтому центр тела вычитаем.
GLOBAL FUNCTION r_radius {
  PARAMETER obj.
  RETURN obj:POSITION - SHIP:BODY:POSITION.
}

GLOBAL FUNCTION r_selfRadius { RETURN -SHIP:BODY:POSITION. }

// Угол от вектора a до вектора b, отсчитанный ПО ХОДУ движения (0…360).
// hVec задаёт направление обхода — нормаль орбиты.
GLOBAL FUNCTION r_angleAlong {
  PARAMETER a, b, hVec.
  LOCAL ang IS VANG(a, b).
  IF VDOT(VCRS(a, b), hVec) < 0 { RETURN 360 - ang. }
  RETURN ang.
}

// Угол между плоскостями двух орбит. Считаем через наклонение и долготу
// узла, а не через векторы: формула не зависит от системы координат,
// и знаковых ловушек в ней нет.
GLOBAL FUNCTION r_planeAngle {
  PARAMETER o1, o2.
  LOCAL c IS COS(o1:INCLINATION) * COS(o2:INCLINATION)
           + SIN(o1:INCLINATION) * SIN(o2:INCLINATION)
             * COS(o1:LAN - o2:LAN).
  RETURN ARCCOS(MAX(-1, MIN(1, c))).
}

GLOBAL FUNCTION r_relInc {
  PARAMETER tgt.
  RETURN r_planeAngle(SHIP:ORBIT, tgt:ORBIT).
}

// ─── подгонка плоскости ───────────────────────────────────────────────

// Ближайший момент, когда мы проходим линию пересечения плоскостей.
GLOBAL FUNCTION r_utAtRelNode {
  PARAMETER tgt.
  LOCAL rs IS r_selfRadius().
  LOCAL h1 IS VCRS(rs, SHIP:VELOCITY:ORBIT).
  LOCAL h2 IS VCRS(r_radius(tgt), tgt:VELOCITY:ORBIT).
  LOCAL line IS VCRS(h1, h2).
  IF line:MAG < 0.0001 { RETURN TIME:SECONDS + 5. }   // плоскости уже совпали
  LOCAL a1 IS r_angleAlong(rs, line, h1).
  LOCAL a2 IS r_angleAlong(rs, -line, h1).
  RETURN TIME:SECONDS + MIN(a1, a2) / 360 * SHIP:ORBIT:PERIOD.
}

// Узел подгонки плоскости. Знак нормальной компоненты подбирается пробой.
GLOBAL FUNCTION r_nodeMatchPlanes {
  PARAMETER tgt.
  LOCAL ut IS r_utAtRelNode(tgt).
  LOCAL vNode IS VELOCITYAT(SHIP, ut):ORBIT:MAG.   // имя v занято конструктором V()
  LOCAL di IS r_relInc(tgt).
  LOCAL dvn IS 2 * vNode * SIN(di / 2).
  // Поворот вектора скорости съедает часть продольной составляющей —
  // возвращаем её, иначе после манёвра просядет апоцентр.
  LOCAL dvp IS vNode * (COS(di) - 1).

  LOCAL best IS 1.
  LOCAL bestAng IS 999.
  FOR sgn IN LIST(1, -1) {
    LOCAL probe IS NODE(ut, 0, sgn * dvn, dvp).
    ADD probe.
    WAIT 0.
    LOCAL ang IS r_planeAngle(probe:ORBIT, tgt:ORBIT).
    REMOVE probe.
    WAIT 0.
    IF ang < bestAng { SET bestAng TO ang. SET best TO sgn. }
  }
  PRINT "  плоскость: " + ROUND(di, 2) + "° → " + ROUND(bestAng, 2)
        + "°, " + ROUND(dvn, 1) + " м/с".
  RETURN NODE(ut, 0, best * dvn, dvp).
}

// ─── фазирование ──────────────────────────────────────────────────────

// Насколько цель впереди нас по орбите, ° (0…360, по ходу движения).
GLOBAL FUNCTION r_phase {
  PARAMETER tgt.
  LOCAL rs IS r_selfRadius().
  LOCAL h IS VCRS(rs, SHIP:VELOCITY:ORBIT).
  LOCAL rt IS VXCL(h, r_radius(tgt)).      // проекция цели на нашу плоскость
  IF rt:MAG < 1 { RETURN 0. }
  RETURN r_angleAlong(rs, rt, h).
}

// Какой должна быть фаза в момент старта перехода: за время перелёта
// (полвитка переходной орбиты) цель должна дойти до точки встречи.
GLOBAL FUNCTION r_phaseNeeded {
  PARAMETER tgt.
  LOCAL r1 IS SHIP:ORBIT:SEMIMAJORAXIS.
  LOCAL r2 IS tgt:ORBIT:SEMIMAJORAXIS.
  LOCAL at IS (r1 + r2) / 2.
  LOCAL tt IS CONSTANT:PI * SQRT(at ^ 3 / SHIP:BODY:MU).
  RETURN MOD(180 - 360 / tgt:ORBIT:PERIOD * tt + 720, 360).
}

// Когда фаза станет нужной. Возвращает -1, если окна не будет никогда
// (периоды совпали — мы уже летим строем).
GLOBAL FUNCTION r_utAtPhase {
  PARAMETER tgt, want.
  LOCAL ws IS 360 / SHIP:ORBIT:PERIOD.
  LOCAL wt IS 360 / tgt:ORBIT:PERIOD.
  LOCAL rel IS wt - ws.
  IF ABS(rel) < 0.000001 { RETURN -1. }
  LOCAL cur IS r_phase(tgt).
  LOCAL d IS MOD(want - cur + 720, 360).
  IF rel < 0 { SET d TO MOD(cur - want + 720, 360). }
  RETURN TIME:SECONDS + d / ABS(rel).
}

// Узел перехода к орбите цели.
GLOBAL FUNCTION r_nodeTransfer {
  PARAMETER tgt.
  LOCAL ut IS r_utAtPhase(tgt, r_phaseNeeded(tgt)).
  IF ut < 0 { RETURN NODE(TIME:SECONDS + 60, 0, 0, 0). }
  LOCAL rad IS (POSITIONAT(SHIP, ut) - POSITIONAT(SHIP:BODY, ut)):MAG.
  LOCAL at IS (rad + tgt:ORBIT:SEMIMAJORAXIS) / 2.
  LOCAL dv IS SQRT(SHIP:BODY:MU * (2 / rad - 1 / at))
            - VELOCITYAT(SHIP, ut):ORBIT:MAG.
  PRINT "  переход: старт через " + ROUND(ut - TIME:SECONDS, 0) + " с, "
        + ROUND(dv, 1) + " м/с".
  RETURN NODE(ut, 0, 0, dv).
}

// ─── ближнее наведение ────────────────────────────────────────────────

GLOBAL FUNCTION r_relVel {
  PARAMETER tgt.
  RETURN tgt:VELOCITY:ORBIT - SHIP:VELOCITY:ORBIT.
}

// Погасить относительную скорость до lim м/с.
GLOBAL FUNCTION r_kill {
  PARAMETER tgt.
  PARAMETER lim IS 0.5.
  IF r_relVel(tgt):MAG <= lim { RETURN. }
  PRINT "  гашу относительную скорость " + ROUND(r_relVel(tgt):MAG, 1) + " м/с".
  SAS OFF.
  c_rcsPulse().
  LOCK STEERING TO r_relVel(tgt).       // носом ПРОТИВ сближения: тяга тормозит
  WAIT UNTIL VANG(SHIP:FACING:VECTOR, r_relVel(tgt)) < 5 OR r_relVel(tgt):MAG < lim.
  LOCK THROTTLE TO 0.15.
  UNTIL r_relVel(tgt):MAG <= lim {
    IF VANG(SHIP:FACING:VECTOR, r_relVel(tgt)) > 20 { LOCK THROTTLE TO 0. }
    ELSE { LOCK THROTTLE TO MIN(0.3, MAX(0.05, r_relVel(tgt):MAG / 40)). }
    WAIT 0.
  }
  LOCK THROTTLE TO 0.
  UNLOCK STEERING.
  RCS OFF.
  SAS ON.
}

// Подойти на standoff метров: разгон в сторону цели, торможение у точки.
GLOBAL FUNCTION r_approach {
  PARAMETER tgt.
  PARAMETER standoff IS 100.
  LOCAL dist IS tgt:POSITION:MAG.
  IF dist <= standoff * 1.5 { RETURN. }
  PRINT "  подхожу с " + ROUND(dist, 0) + " м до " + standoff + " м".
  SAS OFF.
  c_rcs(TRUE).
  UNTIL tgt:POSITION:MAG <= standoff * 1.2 {
    LOCAL d IS tgt:POSITION:MAG.
    // Скорость сближения держим пропорционально дистанции: чем ближе,
    // тем медленнее. Иначе тормозить придётся резче, чем позволяет РСУ.
    LOCAL want IS MIN(20, MAX(1, (d - standoff) / 20)).
    LOCAL closing IS -VDOT(r_relVel(tgt), tgt:POSITION:NORMALIZED).
    IF closing < want * 0.8 {
      LOCK STEERING TO tgt:POSITION.               // разгон в сторону цели
      LOCK THROTTLE TO 0.1.
    } ELSE IF closing > want * 1.5 {
      LOCK STEERING TO r_relVel(tgt).              // тормозим, пока не проскочили
      LOCK THROTTLE TO 0.1.
    } ELSE {
      LOCK THROTTLE TO 0.                          // держим скорость, дрейфуем
    }
    WAIT 0.
  }
  LOCK THROTTLE TO 0.
  UNLOCK STEERING.
  r_kill(tgt, 0.3).
  PRINT "  на месте: " + ROUND(tgt:POSITION:MAG, 0) + " м, отн. скорость "
        + ROUND(r_relVel(tgt):MAG, 2) + " м/с".
}

// ─── весь цикл ────────────────────────────────────────────────────────

GLOBAL FUNCTION r_go {
  PARAMETER tgt.
  PARAMETER standoff IS 100.

  PRINT "=== рандеву с " + tgt:NAME.
  PRINT "  сейчас: " + ROUND(tgt:POSITION:MAG / 1000, 1) + " км, плоскость "
        + ROUND(r_relInc(tgt), 2) + "°, фаза " + ROUND(r_phase(tgt), 1) + "°".

  IF r_relInc(tgt) > 0.2 { o_burn(r_nodeMatchPlanes(tgt)). }

  LOCAL ut IS r_utAtPhase(tgt, r_phaseNeeded(tgt)).
  IF ut < 0 {
    PRINT "  ! периоды совпали — фазовое окно не наступит.".
    PRINT "    Смени высоту на 5–10 км и повтори.".
    RETURN FALSE.
  }
  o_burn(r_nodeTransfer(tgt)).

  // К точке встречи подходим по инерции, следя за дистанцией.
  PRINT "  жду сближения…".
  LOCAL closest IS tgt:POSITION:MAG.
  UNTIL FALSE {
    LOCAL d IS tgt:POSITION:MAG.
    IF d < closest { SET closest TO d. }
    IF d < 5000 { BREAK. }
    IF d > closest * 1.5 AND closest < 50000 { BREAK. }   // разошлись
    IF d > 10000 { WARPTO(TIME:SECONDS + 30). }
    WAIT 1.
  }

  r_kill(tgt, 2).
  r_approach(tgt, standoff).
  c_release().
  PRINT "=== рандеву завершено: " + ROUND(tgt:POSITION:MAG, 0) + " м".
  RETURN TRUE.
}
