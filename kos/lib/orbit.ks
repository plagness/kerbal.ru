// lib/orbit.ks — орбитальная механика и узлы манёвра.
// Зависит от: lib/ctrl.ks, lib/stage.ks
// kerbal.ru · сборка «Оператор»
//
// Заголовок объявлял зависимость годами, а RUNONCEPATH не было ни одного —
// работало только пока каждый вызывающий файл (mission.ks) сам грузил
// ctrl/stage РАНЬШЕ orbit.ks. deepspace.ks грузит orbit.ks через
// transfer.ks/rendezvous.ks, ctrl/stage в этой цепочке никто не тянет —
// o_burn падал на s_tick() с «Undefined Variable Name» посреди прожига.
// Поймано в реальном полёте через telnet.

RUNONCEPATH("0:/lib/ctrl.ks").
RUNONCEPATH("0:/lib/stage.ks").

GLOBAL FUNCTION o_mu { RETURN SHIP:BODY:MU. }
GLOBAL FUNCTION o_br { RETURN SHIP:BODY:RADIUS. }

// Круговая скорость на радиусе rad. Имя rad, а не r: R() занята встроенной.
GLOBAL FUNCTION o_vCirc { PARAMETER rad. RETURN SQRT(o_mu() / rad). }
// Скорость на радиусе rad для орбиты с большой полуосью sma
GLOBAL FUNCTION o_vAt { PARAMETER rad, sma. RETURN SQRT(o_mu() * (2/rad - 1/sma)). }

// Узел: скруглить орбиту в апоцентре
GLOBAL FUNCTION o_nodeCircularize {
  LOCAL rad IS SHIP:APOAPSIS + o_br().
  LOCAL dv IS o_vCirc(rad) - o_vAt(rad, SHIP:ORBIT:SEMIMAJORAXIS).
  RETURN NODE(TIME:SECONDS + ETA:APOAPSIS, 0, 0, dv).
}

// Узел: поднять ПРОТИВОПОЛОЖНУЮ апсиду до targetAlt, жжём в апоцентре.
// Точка прожига становится перицентром новой орбиты — так один прожиг
// заменяет связку «скруглить + разогнаться» и не требует ETA:PERIAPSIS,
// который на круговой орбите шумит.
GLOBAL FUNCTION o_nodeRaiseOpposite {
  PARAMETER targetAlt.
  LOCAL r1 IS SHIP:APOAPSIS + o_br().
  LOCAL at IS (r1 + targetAlt + o_br()) / 2.
  LOCAL dv IS o_vAt(r1, at) - o_vAt(r1, SHIP:ORBIT:SEMIMAJORAXIS).
  RETURN NODE(TIME:SECONDS + ETA:APOAPSIS, 0, 0, dv).
}

// Узел: поднять перицентр до targetAlt, жжём в апоцентре
GLOBAL FUNCTION o_nodeRaisePeri {
  PARAMETER targetAlt.
  LOCAL r2 IS SHIP:APOAPSIS + o_br().
  LOCAL af IS (r2 + targetAlt + o_br()) / 2.
  LOCAL dv IS o_vAt(r2, af) - o_vAt(r2, SHIP:ORBIT:SEMIMAJORAXIS).
  RETURN NODE(TIME:SECONDS + ETA:APOAPSIS, 0, 0, dv).
}

// Узел: скруглить орбиту В ПЕРИЦЕНТРЕ. Для захвата на гиперболическом
// подлёте (после ETA:APOAPSIS не существует — апоцентра у гиперболы нет),
// поэтому здесь жжём в ETA:PERIAPSIS, а не в апоцентре, как o_nodeCircularize.
GLOBAL FUNCTION o_nodeCircularizeAtPeri {
  LOCAL rad IS SHIP:PERIAPSIS + o_br().
  LOCAL dv IS o_vCirc(rad) - o_vAt(rad, SHIP:ORBIT:SEMIMAJORAXIS).
  RETURN NODE(TIME:SECONDS + ETA:PERIAPSIS, 0, 0, dv).
}

// Исполнить узел: навестись, перемотать, прожечь, снять.
// onTick — необязательная функция, зовётся в цикле прожига (лог, HUD).
GLOBAL FUNCTION o_burn {
  PARAMETER nd.
  PARAMETER onTick IS { }.
  // Узел должен быть в плане полёта: без ADD обращение к nd:DELTAV
  // падает с «Must attach node first». Фабрики выше возвращают узел
  // неприкреплённым, поэтому вешаем его здесь — один владелец, одно место.
  IF NOT HASNODE OR NEXTNODE <> nd { ADD nd. }
  WAIT 0.
  LOCAL dv0 IS nd:DELTAV.
  LOCAL acc IS MAX(0.05, SHIP:AVAILABLETHRUST / SHIP:MASS).
  LOCAL bt IS dv0:MAG / acc.
  PRINT "  прожиг " + ROUND(dv0:MAG,1) + " м/с, ~" + ROUND(bt,0) + " с".

  SAS OFF.                     // САС и kOS не должны рулить одновременно
  c_rcsPulse().
  LOCK STEERING TO nd:DELTAV.
  WAIT 5.
  WAIT UNTIL VANG(SHIP:FACING:VECTOR, nd:DELTAV) < 2 OR nd:ETA < bt.
  c_rcs(FALSE).

  IF nd:ETA > bt/2 + 30 { WARPTO(TIME:SECONDS + nd:ETA - bt/2 - 15). }
  WAIT UNTIL nd:ETA <= bt/2.

  LOCK THROTTLE TO MIN(1, MAX(0.05, nd:DELTAV:MAG / (acc * 3))).
  UNTIL VDOT(dv0, nd:DELTAV) < 0 OR nd:DELTAV:MAG < 0.15 {
    IF s_tick() { c_rcsPulse(). }
    onTick().
    WAIT 0.
  }
  LOCK THROTTLE TO 0.
  UNLOCK STEERING.
  RCS OFF.
  IF HASNODE { REMOVE nd. }
  SAS ON.                      // между этапами держим аппарат, а не бросаем
  WAIT 0.5.
}

// Узел: поднять апоцентр до targetAlt, прожиг В ЗАДАННЫЙ МОМЕНТ.
// Точка прожига становится перицентром — так задаётся аргумент перицентра.
// Радиус в момент ut берём текущий: на околокруговой парковке он не меняется.
GLOBAL FUNCTION o_nodeRaiseApoAt {
  PARAMETER targetAlt, ut.
  LOCAL rad IS SHIP:ALTITUDE + o_br().
  LOCAL at IS (rad + targetAlt + o_br()) / 2.
  LOCAL dv IS o_vAt(rad, at) - o_vAt(rad, SHIP:ORBIT:SEMIMAJORAXIS).
  RETURN NODE(ut, 0, 0, dv).
}
