// lib/mission.ks — миссия одной строкой: говоришь целевую орбиту,
// остальное считается само.
// Зависит от: всех остальных модулей библиотеки.
// kerbal.ru · сборка «Оператор»
//
//   RUNONCEPATH("0:/lib/mission.ks").
//   SET s TO m_defaults().
//   SET s["ap"] TO 7867078.  SET s["pe"] TO 3331362.
//   SET s["inc"] TO 20.1.    SET s["lan"] TO 250.8.  SET s["aop"] TO 29.6.
//   m_orbit(s).
//
// Что скрипт решает сам:
//   · азимут пуска — из наклонения, с поправкой на вращение планеты;
//   · ждать ли окно под долготу узла — если lan задан;
//   · схему выведения:
//       aop не задан → один совмещённый прожиг из апоцентра подъёма;
//       aop задан    → круговая парковка, ожидание нужной точки витка,
//                      прожиг именно там (точка станет перицентром);
//   · нужен ли подъём перицентра и на сколько;
//   · какой апсиде соответствует ap, а какой pe.

RUNONCEPATH("0:/lib/util.ks").
RUNONCEPATH("0:/lib/ctrl.ks").
RUNONCEPATH("0:/lib/stage.ks").
RUNONCEPATH("0:/lib/orbit.ks").
RUNONCEPATH("0:/lib/ascent.ks").
RUNONCEPATH("0:/lib/deploy.ks").
RUNONCEPATH("0:/lib/sci.ks").
RUNONCEPATH("0:/lib/telem.ks").
RUNONCEPATH("0:/lib/hud.ks").

GLOBAL FUNCTION m_defaults {
  RETURN LEXICON(
    "name", "миссия",
    "ap", 100000,      // целевой апоцентр, м
    "pe", -1,          // целевой перицентр, м (-1 = круговая, равен ap)
    "inc", 0,          // наклонение, °
    "lan", -1,         // долгота восходящего узла, ° (-1 = не ждать окна)
    "aop", -1,         // аргумент перицентра, ° (-1 = не важен)
    "park", 80000,     // опорная орбита, м
    "log", "0:/mission.csv",
    "hud", TRUE
  ).
}

GLOBAL M_LAUNCH_LON IS 0.
GLOBAL M_LAUNCH_UT IS 0.

GLOBAL FUNCTION m_tick {
  sciTick().
  h_tick(A_CMD).
  t_line(ROUND(SHIP:ALTITUDE,0)
    + "," + ROUND(SHIP:VELOCITY:SURFACE:MAG,1)
    + "," + ROUND(SHIP:DYNAMICPRESSURE,4)
    + "," + ROUND(u_aoa(),1)
    + "," + ROUND(u_velAzimuth(),1)
    + "," + ROUND(SHIP:ORBIT:INCLINATION,2)
    + "," + ROUND(u_argLat(),1)
    + "," + ROUND(THROTTLE,2)
    + "," + ROUND(SHIP:APOAPSIS,0)
    + "," + ROUND(SHIP:PERIAPSIS,0)
    + "," + ROUND(SHIP:MONOPROPELLANT,1)
    + "," + sciZone()).
}

GLOBAL FUNCTION m_report {
  PARAMETER spec.
  PRINT "=== ИТОГ " + ROUND(SHIP:APOAPSIS/1000,1) + " / " + ROUND(SHIP:PERIAPSIS/1000,1)
        + " км · накл " + ROUND(SHIP:ORBIT:INCLINATION,2)
        + "° · узел " + ROUND(SHIP:ORBIT:LAN,2)
        + "° · арг.пер " + ROUND(SHIP:ORBIT:ARGUMENTOFPERIAPSIS,2) + "°".
  PRINT "    заказано " + ROUND(spec["ap"]/1000,1) + " / " + ROUND(spec["pe"]/1000,1)
        + " км · накл " + spec["inc"]
        + "° · узел " + spec["lan"] + "° · арг.пер " + spec["aop"] + "°".
}

GLOBAL FUNCTION m_orbit {
  PARAMETER spec.

  // ── нормализация: круговая орбита задаётся одним числом ──
  IF spec["pe"] < 0 { SET spec["pe"] TO spec["ap"]. }
  IF spec["pe"] > spec["ap"] {          // перепутали местами — молча меняем
    LOCAL tmp IS spec["ap"].
    SET spec["ap"] TO spec["pe"].
    SET spec["pe"] TO tmp.
  }

  SET IPU_SAVE TO CONFIG:IPU.
  SET CONFIG:IPU TO 800.

  t_init(spec["log"], "t,alt,spd,q,aoa,az,inc,arglat,thr,ap,pe,mono,zone").
  IF spec["hud"] { h_init(). }

  SET CFG TO a_defaults().
  SET CFG["park"] TO spec["park"].
  SET CFG["az"] TO u_launchAzimuth(spec["inc"]).
  SET CFG["onTick"] TO m_tick@.

  SET M_LAUNCH_LON TO SHIP:LONGITUDE.
  SET M_LAUNCH_UT TO TIME:SECONDS.

  PRINT "=== " + spec["name"] + " · цель " + ROUND(spec["ap"]/1000) + " x "
        + ROUND(spec["pe"]/1000) + " км · накл " + spec["inc"] + "°".
  PRINT "  азимут пуска " + ROUND(CFG["az"],2) + "°"
        + (CHOOSE " · узел " + spec["lan"] + "°" IF spec["lan"] >= 0 ELSE "")
        + (CHOOSE " · арг.пер " + spec["aop"] + "°" IF spec["aop"] >= 0 ELSE "").

  sciSweep("на столе", FALSE).
  IF spec["lan"] >= 0 { u_waitForLan(spec["lan"]). }
  IF spec["hud"] { h_say(spec["name"] + ": пуск"). }

  IF NOT a_run(CFG) {
    PRINT "подъём прерван".
    h_off(). c_release(). SET CONFIG:IPU TO IPU_SAVE.
    RETURN FALSE.
  }

  SAS ON.
  d_all().
  SET SCI_ALLOW_ANIM TO TRUE.
  SET SCI_LAST TO sciZone().
  sciSweep("вышли в космос", TRUE).

  IF spec["aop"] >= 0 {
    // Аргумент перицентра важен → нужна парковка, чтобы дождаться точки
    PRINT "=== скругление опорной".
    o_burn(o_nodeCircularize(), m_tick@).
    PRINT "  опорная " + ROUND(SHIP:APOAPSIS/1000,1) + " / " + ROUND(SHIP:PERIAPSIS/1000,1)
          + " км, наклонение " + ROUND(SHIP:ORBIT:INCLINATION,2) + "°".
    sciSweep("опорная орбита", TRUE).

    PRINT "=== жду точку витка " + spec["aop"] + "° от узла (сейчас "
          + ROUND(u_argLat(),1) + "°)".
    LOCAL burnUT IS u_utAtArgLat(spec["aop"]).
    PRINT "  прожиг через " + ROUND(burnUT - TIME:SECONDS,0) + " с".
    o_burn(o_nodeRaiseApoAt(spec["ap"], burnUT), m_tick@).
  } ELSE {
    // Аргумент перицентра не важен → один прожиг, парковка не нужна
    PRINT "=== разгон на переходную к " + ROUND(spec["ap"]/1000) + " км".
    o_burn(o_nodeRaiseOpposite(spec["ap"]), m_tick@).
  }
  PRINT "  переходная " + ROUND(SHIP:APOAPSIS/1000,1) + " / "
        + ROUND(SHIP:PERIAPSIS/1000,1) + " км".
  sciSweep("переходная орбита", TRUE).

  // Перицентр поднимаем, только если он реально ниже цели
  IF spec["pe"] - SHIP:PERIAPSIS > 2000 {
    PRINT "=== подъём перицентра до " + ROUND(spec["pe"]/1000) + " км".
    o_burn(o_nodeRaisePeri(spec["pe"]), m_tick@).
  }

  m_report(spec).
  sciSweep("целевая орбита", TRUE).

  LOCAL tries IS 0.
  UNTIL tries > 20 {
    WAIT 30.
    IF sciRetry() = 0 { BREAK. }
    SET tries TO tries + 1.
  }
  PRINT "передач " + SCI_SENT + " · пустых сброшено " + SCI_DUMPED
        + " · монотопливо " + ROUND(SHIP:MONOPROPELLANT,1).
  PRINT "калибровка узла: lon=" + ROUND(M_LAUNCH_LON,2) + " UT=" + ROUND(M_LAUNCH_UT,0)
        + " LAN=" + ROUND(SHIP:ORBIT:LAN,2).

  h_off().
  c_release().
  SET CONFIG:IPU TO IPU_SAVE.
  PRINT "лог: " + spec["log"].
  RETURN TRUE.
}
