// survey2.ks — контракт Astronomical Survey Society, второй спутник.
// Апоцентр 7 867 078 м · перицентр 3 331 362 м · наклонение 20,1°
// Долгота узла 250,8° · АРГУМЕНТ ПЕРИЦЕНТРА 29,6°
//   RUNPATH("0:/missions/survey2.ks").
// kerbal.ru · сборка «Оператор»
//
// Отличие от прошлой миссии: контракт задаёт ещё и аргумент перицентра —
// где именно на витке должна оказаться низшая точка. Поэтому профиль
// другой: выходим на КРУГОВУЮ опорную, ждём нужную точку витка и только
// там разгоняемся. Точка прожига становится перицентром.

RUNONCEPATH("0:/lib/util.ks").
RUNONCEPATH("0:/lib/ctrl.ks").
RUNONCEPATH("0:/lib/stage.ks").
RUNONCEPATH("0:/lib/orbit.ks").
RUNONCEPATH("0:/lib/ascent.ks").
RUNONCEPATH("0:/lib/deploy.ks").
RUNONCEPATH("0:/lib/sci.ks").
RUNONCEPATH("0:/lib/telem.ks").
RUNONCEPATH("0:/lib/hud.ks").

// ─── цель ───────────────────────────────────────────────────────────
SET TGT_AP  TO 7867078.
SET TGT_PE  TO 3331362.
SET TGT_INC TO 20.1.
SET TGT_LAN TO 250.8.
SET TGT_AOP TO 29.6.
SET PARK    TO 80000.

// ─── подготовка ─────────────────────────────────────────────────────
SET IPU_SAVE TO CONFIG:IPU.
SET CONFIG:IPU TO 800.

t_init("0:/survey2.csv", "t,alt,vspd,spd,q,aoa,az,inc,arglat,thr,ap,pe,mono,zone").
h_init().

FUNCTION missionTick {
  sciTick().
  h_tick(A_CMD).
  t_line(ROUND(SHIP:ALTITUDE,0)
    + "," + ROUND(SHIP:VERTICALSPEED,1)
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

SET CFG TO a_defaults().
SET CFG["park"] TO PARK.
SET CFG["az"] TO u_launchAzimuth(TGT_INC).
SET CFG["onTick"] TO missionTick@.

SET LAUNCH_LON TO SHIP:LONGITUDE.
SET LAUNCH_UT TO TIME:SECONDS.

PRINT "=== Спутник-2 · цель " + ROUND(TGT_AP/1000) + " x " + ROUND(TGT_PE/1000)
      + " км · накл " + TGT_INC + "° · узел " + TGT_LAN + "° · арг.пер " + TGT_AOP + "°".
PRINT "  азимут пуска " + ROUND(CFG["az"],2) + "°".
sciSweep("на столе", FALSE).
u_waitForLan(TGT_LAN).
h_say("Спутник-2: пуск").

IF a_run(CFG) {
  SAS ON.
  d_all().
  SET SCI_ALLOW_ANIM TO TRUE.
  SET SCI_LAST TO sciZone().
  sciSweep("вышли в космос", TRUE).

  // 1. Круговая опорная — без неё негде ждать нужную точку витка
  PRINT "=== скругление опорной".
  o_burn(o_nodeCircularize(), missionTick@).
  PRINT "  опорная " + ROUND(SHIP:APOAPSIS/1000,1) + " / " + ROUND(SHIP:PERIAPSIS/1000,1)
        + " км, наклонение " + ROUND(SHIP:ORBIT:INCLINATION,2) + "°".
  sciSweep("опорная орбита", TRUE).

  // 2. Разгон в точке, которая станет перицентром
  PRINT "=== жду точку витка " + TGT_AOP + "° от узла (сейчас " + ROUND(u_argLat(),1) + "°)".
  SET burnUT TO u_utAtArgLat(TGT_AOP).
  PRINT "  прожиг через " + ROUND(burnUT - TIME:SECONDS,0) + " с".
  o_burn(o_nodeRaiseApoAt(TGT_AP, burnUT), missionTick@).
  PRINT "  переходная " + ROUND(SHIP:APOAPSIS/1000,1) + " / " + ROUND(SHIP:PERIAPSIS/1000,1) + " км".
  sciSweep("переходная орбита", TRUE).

  // 3. Подъём перицентра в апоцентре
  PRINT "=== подъём перицентра до " + ROUND(TGT_PE/1000) + " км".
  o_burn(o_nodeRaisePeri(TGT_PE), missionTick@).

  PRINT "=== ИТОГ " + ROUND(SHIP:APOAPSIS/1000,1) + " / " + ROUND(SHIP:PERIAPSIS/1000,1)
        + " км · накл " + ROUND(SHIP:ORBIT:INCLINATION,2)
        + "° · узел " + ROUND(SHIP:ORBIT:LAN,2)
        + "° · арг.пер " + ROUND(SHIP:ORBIT:ARGUMENTOFPERIAPSIS,2) + "°".
  sciSweep("целевая орбита", TRUE).
  SET tries TO 0.
  UNTIL tries > 20 {
    WAIT 30.
    IF sciRetry() = 0 { BREAK. }
    SET tries TO tries + 1.
  }
  PRINT "передач " + SCI_SENT + " · монотопливо " + ROUND(SHIP:MONOPROPELLANT,1).
  PRINT "калибровка узла: lon=" + ROUND(LAUNCH_LON,2) + " UT=" + ROUND(LAUNCH_UT,0)
        + " LAN=" + ROUND(SHIP:ORBIT:LAN,2).
}

h_off().
c_release().
SET CONFIG:IPU TO IPU_SAVE.
PRINT "лог: 0:/survey2.csv".
