// missions/dalnyak.ks — миссия «Дальняк-1»: спутник на 4758 × 4592 км,
// наклонение 8,5°, контракт Astronomical Survey Society.
// Запуск:  RUNPATH("0:/missions/dalnyak.ks").
// kerbal.ru · сборка «Оператор»
//
// Сам файл миссии не содержит механики — только цифры цели и порядок
// шагов. Вся механика в 0:/lib/. Хочешь другую миссию — копируешь этот
// файл и меняешь параметры.

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
SET TGT_AP TO 4757918.
SET TGT_PE TO 4591510.
SET TGT_INC TO 8.5.
SET TGT_LAN TO 311.       // долгота восходящего узла из контракта
SET PARK TO 80000.

// ─── подготовка ─────────────────────────────────────────────────────
SET IPU_SAVE TO CONFIG:IPU.
SET CONFIG:IPU TO 800.          // рулевой закон тяжёлый, 200 не хватает

t_init("0:/dalnyak.csv", "t,alt,vspd,spd,q,aoa,vpitch,az,inc,thr,ap,pe,mono,zone").
h_init().

FUNCTION missionTick {
  sciTick().
  h_tick(A_CMD).
  t_line(
      ROUND(SHIP:ALTITUDE,0)
    + "," + ROUND(SHIP:VERTICALSPEED,1)
    + "," + ROUND(SHIP:VELOCITY:SURFACE:MAG,1)
    + "," + ROUND(SHIP:DYNAMICPRESSURE,4)
    + "," + ROUND(u_aoa(),1)
    + "," + ROUND(u_vPitch(),1)
    + "," + ROUND(u_velAzimuth(),1)
    + "," + ROUND(SHIP:ORBIT:INCLINATION,2)
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

// ─── полёт ──────────────────────────────────────────────────────────
PRINT "=== Дальняк-1 · цель " + ROUND(TGT_AP/1000) + " x " + ROUND(TGT_PE/1000)
      + " км, наклонение " + TGT_INC + "°".
PRINT "  азимут пуска " + ROUND(CFG["az"],2) + "° (с поправкой на вращение)".
sciSweep("на столе", FALSE).
u_waitForLan(TGT_LAN).        // ждём окно: узел задаётся временем старта
h_say("Дальняк-1: пуск").

IF a_run(CFG) {
  SAS ON.                       // на коасте и между прожигами аппарат держим
  d_all().                      // панели и антенны — только теперь
  SET SCI_ALLOW_ANIM TO TRUE.   // в вакууме можно и выдвижные приборы
  SET SCI_LAST TO sciZone().
  sciSweep("вышли в космос", TRUE).
  h_say("орбита: панели раскрыты").

  PRINT "=== разгон на переходную к " + ROUND(TGT_AP/1000) + " км".
  o_burn(o_nodeRaiseOpposite(TGT_AP), missionTick@).
  PRINT "  переходная " + ROUND(SHIP:APOAPSIS/1000,1) + " / " + ROUND(SHIP:PERIAPSIS/1000,1) + " км".
  sciSweep("переходная орбита", TRUE).

  PRINT "=== подъём перицентра до " + ROUND(TGT_PE/1000) + " км".
  o_burn(o_nodeRaisePeri(TGT_PE), missionTick@).

  PRINT "=== орбита " + ROUND(SHIP:APOAPSIS/1000,1) + " / " + ROUND(SHIP:PERIAPSIS/1000,1)
        + " км, наклонение " + ROUND(SHIP:ORBIT:INCLINATION,2) + "°".
  sciSweep("целевая орбита", TRUE).

  SET tries TO 0.
  UNTIL tries > 20 {
    WAIT 30.
    IF sciRetry() = 0 { BREAK. }
    SET tries TO tries + 1.
  }
  PRINT "передач всего: " + SCI_SENT.
  PRINT "монотоплива осталось: " + ROUND(SHIP:MONOPROPELLANT,1) + " ед".
  PRINT "калибровка узла: lon=" + ROUND(LAUNCH_LON,2)
        + " UT=" + ROUND(LAUNCH_UT,0) + " LAN=" + ROUND(SHIP:ORBIT:LAN,2).
  h_say("миссия выполнена", 8).
}

h_off().
c_release().
SET CONFIG:IPU TO IPU_SAVE.
PRINT "лог: 0:/dalnyak.csv".
