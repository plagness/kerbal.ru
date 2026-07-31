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
RUNONCEPATH("0:/lib/transfer.ks").
RUNONCEPATH("0:/lib/events.ks").
RUNONCEPATH("0:/lib/land.ks").
RUNONCEPATH("0:/lib/deepspace.ks").
RUNONCEPATH("0:/lib/audit.ks").
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

// transfer: та же геометрия, что у rendezvous, но целью — небесное тело.
IF SHIP:BODY = KERBIN {
  PRINT "transfer: до Муна " + ROUND(MUN:POSITION:MAG/1000,0) + " км, плоскость "
        + ROUND(r_relInc(MUN),2) + "°, нужная фаза " + ROUND(r_phaseNeeded(MUN),1) + "°".
  PRINT "transfer: энкаунтера пока нет — " + (NOT x_hasEncounter()).
} ELSE {
  PRINT "transfer: не у Кербина — геометрия к Муну пропущена".
}

// orbit: захват в перицентре — та же формула, что o_nodeCircularize, но
// от ETA:PERIAPSIS, а не ETA:APOAPSIS (гипербола апоцентра не имеет).
SET nd2 TO o_nodeCircularizeAtPeri().
ADD nd2. WAIT 0.
PRINT "orbit:  узел захвата в перицентре ставится, Δv = " + ROUND(nd2:DELTAV:MAG,1) + " м/с".
REMOVE nd2. WAIT 0.

// events: одноразовое и сторожевое событие на чистой арифметике.
SET EV TO e_new().
SET EV_HIT TO FALSE.
e_once(EV, "тест-once", { RETURN TRUE. }, { SET EV_HIT TO TRUE. }).
e_tick(EV).
PRINT "events: once сработал " + EV_HIT + ", готово " + e_done(EV).

// land: интерполяция таблицы вертикальной скорости, без двигателя.
PRINT "land:   предел на 10000/2000/100/0 м = "
      + ROUND(l_vsLimit(10000),0) + "/" + ROUND(l_vsLimit(2000),0) + "/"
      + ROUND(l_vsLimit(100),0) + "/" + ROUND(l_vsLimit(0),0) + " м/с".

// deepspace: спецификация собирается и не падает.
SET ds TO ds_defaults().
PRINT "deepspace: по умолчанию — " + ds["body"]:NAME + ", парковка "
      + ROUND(ds["parkAlt"]/1000,1) + " км, карта " + ROUND(ds["mapAlt"]/1000,0) + " км".

// audit: чекеры реально смотрят детали на столе — печатают то, что есть,
// без остановки миссии (это просто отчёт, не ошибка компиляции).
PRINT "audit:  меток lander-*: " + q_countTag("lander-")
      + ", ёмкость ЭЧ " + ROUND(q_ecCapacity(),0).
q_report("пример: SCANsat высотометрия", q_taskScanAltimetry()).

PRINT "== проверка пройдена ==".
