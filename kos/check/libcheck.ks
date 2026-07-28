// libcheck.ks — прогон всей библиотеки на стартовом столе.
// Двигатели не трогает: только загружает модули и вызывает чистые функции.
// Ловит опечатки, конфликты имён со встроенными и битые суффиксы —
// то есть всё, что иначе вылезет уже в полёте.
//
//   RUNPATH("0:/check/libcheck.ks").

RUNONCEPATH("0:/lib/util.ks").
RUNONCEPATH("0:/lib/ctrl.ks").
RUNONCEPATH("0:/lib/stage.ks").
RUNONCEPATH("0:/lib/orbit.ks").
RUNONCEPATH("0:/lib/ascent.ks").
RUNONCEPATH("0:/lib/deploy.ks").
RUNONCEPATH("0:/lib/sci.ks").
RUNONCEPATH("0:/lib/telem.ks").
RUNONCEPATH("0:/lib/hud.ks").
RUNONCEPATH("0:/lib/rendezvous.ks").
PRINT "== модули загружены ==".

PRINT "util:   азимут под 8.5° = " + ROUND(u_launchAzimuth(8.5),2)
      + "°, угол атаки " + ROUND(u_aoa(),1) + "°".
PRINT "util:   узел при старте сейчас = " + ROUND(u_lanIfLaunchNow(),1) + "°".
PRINT "ascent: тангаж 1/10/30/60 км = "
      + ROUND(a_pitchSchedule(1000),0) + "/" + ROUND(a_pitchSchedule(10000),0)
      + "/" + ROUND(a_pitchSchedule(30000),0) + "/" + ROUND(a_pitchSchedule(60000),0).

SET CFG TO a_defaults().
SET CFG["az"] TO u_launchAzimuth(8.5).
PRINT "ascent: тяга = " + ROUND(a_throttle(CFG),2) + ", рулевой вектор получен".
SET d TO a_steer(CFG).

PRINT "stage:  живых двигателей " + s_liveEngines() + ", нужен стейдж " + s_need().
PRINT "orbit:  круговая на 80 км = " + ROUND(o_vCirc(SHIP:BODY:RADIUS+80000),0) + " м/с".

SET nd TO o_nodeRaiseOpposite(4757918).
ADD nd. WAIT 0.
PRINT "orbit:  узел ставится, Δv = " + ROUND(nd:DELTAV:MAG,1) + " м/с".
REMOVE nd. WAIT 0.

PRINT "ctrl:   монотопливо " + ROUND(SHIP:MONOPROPELLANT,1)
      + ", РСУ разрешён " + (SHIP:MONOPROPELLANT > C_MONO_RESERVE).
PRINT "sci:    приборов " + sciModules():LENGTH + ", зона «" + sciZone() + "»".
PRINT "deploy: вакуум " + d_vacuum().

t_init("0:/check.csv", "t,test").
t_line("ok").
PRINT "telem:  файл создан " + EXISTS("0:/check.csv").

h_init().
h_tick(SHIP:FACING:VECTOR).
WAIT 2.
h_off().
PRINT "hud:    стрелки рисуются".

// Рандеву проверяем только в чистой арифметике: цель не нужна, орбита своя.
PRINT "rendez: угол своей плоскости с собой = " + ROUND(r_planeAngle(SHIP:ORBIT, SHIP:ORBIT),3) + "°".
PRINT "rendez: угол по ходу 90° = "
      + ROUND(r_angleAlong(SHIP:UP:VECTOR, SHIP:NORTH:VECTOR,
                           VCRS(SHIP:UP:VECTOR, SHIP:NORTH:VECTOR)),1) + "°".
IF HASTARGET {
  PRINT "rendez: до цели " + ROUND(TARGET:POSITION:MAG/1000,1) + " км, плоскость "
        + ROUND(r_relInc(TARGET),2) + "°, фаза " + ROUND(r_phase(TARGET),1)
        + "°, нужная фаза " + ROUND(r_phaseNeeded(TARGET),1) + "°".
} ELSE {
  PRINT "rendez: цель не выбрана — проверены только формулы".
}
PRINT "== проверка пройдена ==".
