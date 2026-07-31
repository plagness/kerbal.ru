// dalnyak-mun-plan.ks — «максимум по сборке, максимум по расчётам, потом
// старт»: полная телеметрия корабля + чекеры + бюджет Δv по фазам одной
// командой. Двигателей не трогает, узлов манёвра НЕ ставит (ADD не
// вызывается нигде) — читает и считает, ничего не делает физически.
//
//   RUNPATH("0:/check/dalnyak-mun-plan.ks").

RUNONCEPATH("0:/lib/audit.ks").
RUNONCEPATH("0:/lib/transfer.ks").

// ─── телеметрия корабля ────────────────────────────────────────────

PRINT "======================================".
PRINT "  ДАЛЬНЯК-МУН — ПЛАН, БЕЗ ДЕЙСТВИЙ".
PRINT "======================================".
PRINT "имя:      " + SHIP:NAME.
PRINT "тело:     " + SHIP:BODY:NAME.
PRINT "статус:   " + SHIP:STATUS.
PRINT "высота:   " + ROUND(SHIP:ALTITUDE,0) + " м".
PRINT "масса:    " + ROUND(SHIP:MASS,2) + " т".
PRINT "Δv (вак): " + ROUND(SHIP:DELTAV:VACUUM,0) + " м/с  ["
      + "стоковый счётчик; 0 значит, что в настройках выключен".
PRINT "          Advanced Tweakables → Delta-V readout]".

LOCAL ecCap IS q_ecCapacity().
PRINT "заряд:    " + ROUND(ecCap,0) + " ЭЧ ёмкость".
PRINT "деталей:  " + SHIP:PARTS:LENGTH.

// ─── чекеры: комплектация ──────────────────────────────────────────

PRINT " ".
LOCAL fail IS 0.
SET fail TO fail + q_report("SCANsat: высотометрия низкого разрешения", q_taskScanAltimetry()).
SET fail TO fail + q_report("SCANsat: мультиспектральный (биомы)", q_taskScanBiome()).
SET fail TO fail + q_report("Созвездие: 4 спутника", q_taskConstellation(4, "sat-")).

// ─── бюджет Δv по фазам — статические ориентиры из missiya-mun/rendezvous ──

PRINT " ".
PRINT "=== бюджет Δv по фазам (ориентиры, не физический расчёт) ===".
LOCAL bTransfer IS 856.     // НОО 80 км → переходная к Муну
LOCAL bCapture  IS 320.     // захват на рабочую орбиту ~100 км
LOCAL bDeploy   IS 100.     // развод 4 спутников по фазе, без смены плоскости
LOCAL bPlane    IS 770.     // ОПЦИОНАЛЬНО: один манёвр смены плоскости под полюса, 90°
LOCAL bLand     IS 650.     // деорбит + посадка, без обратного взлёта

LOCAL running IS 0.
SET running TO running + bTransfer.
PRINT "  перелёт Кербин → Мун:        " + bTransfer + " м/с   (итого " + running + ")".
SET running TO running + bCapture.
PRINT "  захват на рабочую орбиту:    " + bCapture + " м/с   (итого " + running + ")".
SET running TO running + bDeploy.
PRINT "  развод 4 спутников (фаза):   " + bDeploy + " м/с   (итого " + running + ")".
PRINT "  [опция] смена плоскости 90°: " + bPlane + " м/с   (если нужно полярное покрытие)".
SET running TO running + bLand.
PRINT "  посадка без взлёта:          " + bLand + " м/с   (итого " + running + ")".
PRINT "  итого без опции:             " + running + " м/с".
PRINT "  итого с плоскостным манёвром: " + (running + bPlane) + " м/с".

LOCAL haveDv IS SHIP:DELTAV:VACUUM.
IF haveDv > 0 {
  PRINT "  запас на борту:               " + ROUND(haveDv,0) + " м/с".
  PRINT "  остаток без опции:            " + ROUND(haveDv - running,0) + " м/с".
  PRINT "  остаток с плоскостным манёвром: " + ROUND(haveDv - running - bPlane,0) + " м/с".
} ELSE {
  PRINT "  ! SHIP:DELTAV дал 0 — включи Advanced Tweakables → Delta-V readout,".
  PRINT "    иначе сверить бюджет не с чем.".
}

// ─── живой расчёт узла перехода — ТОЛЬКО если уже на орбите Кербина ──
// r_nodeTransfer создаёт объект NODE(), но НЕ добавляет его в план полёта
// (ADD не вызывается) — это чтение чисел, не действие.

PRINT " ".
IF SHIP:BODY = KERBIN AND SHIP:ALTITUDE > SHIP:BODY:ATM:HEIGHT AND SHIP:ORBIT:APOAPSIS > 0 {
  PRINT "=== живой расчёт (уже на орбите Кербина) ===".
  LOCAL nd IS r_nodeTransfer(MUN).
  PRINT "  узел перехода к Муну: " + ROUND(nd:DELTAV:MAG,1) + " м/с, через "
        + ROUND(nd:ETA,0) + " с (" + ROUND(nd:ETA/60,1) + " мин)".
  PRINT "  накл. к плоскости Муна: " + ROUND(r_relInc(MUN),2) + "°".
} ELSE {
  PRINT "=== живой расчёт перехода недоступен — корабль ещё не на орбите Кербина ===".
  PRINT "  (нормально на стартовом столе — досчитается после подъёма)".
}

PRINT " ".
IF fail = 0 { PRINT "== комплектация: всё, что видно чекеру, на месте ==". }
ELSE { PRINT "== комплектация: не хватает " + fail + " пункт(ов), смотри выше ==". }
PRINT "======================================".
