// _template.ks — заготовка новой миссии. Скопируй, переименуй, правь цифры.
// Механики здесь нет: она вся в 0:/lib/. Этот файл — только цель и порядок.
//
//   RUNPATH("0:/missions/моя-миссия.ks").

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
SET TGT_AP  TO 100000.      // целевой апоцентр, м
SET TGT_PE  TO 100000.      // целевой перицентр, м
SET TGT_INC TO 0.           // наклонение, °
SET TGT_LAN TO -1.          // долгота узла, ° (-1 = не ждать окна)
SET PARK    TO 80000.       // опорная орбита, м

// ─── подготовка ─────────────────────────────────────────────────────
SET IPU_SAVE TO CONFIG:IPU.
SET CONFIG:IPU TO 800.

t_init("0:/mission.csv", "t,alt,spd,q,aoa,inc,thr,ap,pe").
h_init().

FUNCTION missionTick {
  sciTick().
  h_tick(A_CMD).
  t_line(ROUND(SHIP:ALTITUDE,0)
    + "," + ROUND(SHIP:VELOCITY:SURFACE:MAG,1)
    + "," + ROUND(SHIP:DYNAMICPRESSURE,4)
    + "," + ROUND(u_aoa(),1)
    + "," + ROUND(SHIP:ORBIT:INCLINATION,2)
    + "," + ROUND(THROTTLE,2)
    + "," + ROUND(SHIP:APOAPSIS,0)
    + "," + ROUND(SHIP:PERIAPSIS,0)).
}

SET CFG TO a_defaults().
SET CFG["park"] TO PARK.
SET CFG["az"] TO u_launchAzimuth(TGT_INC).
SET CFG["onTick"] TO missionTick@.

// ─── полёт ──────────────────────────────────────────────────────────
sciSweep("на столе", FALSE).
IF TGT_LAN >= 0 { u_waitForLan(TGT_LAN). }

IF a_run(CFG) {
  SAS ON.
  d_all().
  SET SCI_ALLOW_ANIM TO TRUE.
  SET SCI_LAST TO sciZone().
  sciSweep("вышли в космос", TRUE).

  o_burn(o_nodeRaiseOpposite(TGT_AP), missionTick@).
  IF ABS(TGT_PE - TGT_AP) > 1000 OR TGT_PE > PARK {
    o_burn(o_nodeRaisePeri(TGT_PE), missionTick@).
  }

  PRINT "=== орбита " + ROUND(SHIP:APOAPSIS/1000,1) + " / " + ROUND(SHIP:PERIAPSIS/1000,1)
        + " км, наклонение " + ROUND(SHIP:ORBIT:INCLINATION,2) + "°".
  sciSweep("целевая орбита", TRUE).
}

h_off().
c_release().
SET CONFIG:IPU TO IPU_SAVE.
