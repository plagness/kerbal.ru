// dalnyak-mun-plan.ks — параметры конкретного корабля, вся логика в
// lib/audit.ks (q_plan). Двигателей не трогает, узлов не ставит.
//
//   RUNPATH("0:/check/dalnyak-mun-plan.ks").

RUNONCEPATH("0:/lib/audit.ks").

SET spec TO LEXICON(
  "tasks", LIST(
    LEXICON("title", "SCANsat: высотометрия низкого разрешения", "items", q_taskScanAltimetry()),
    LEXICON("title", "SCANsat: мультиспектральный (биомы)", "items", q_taskScanBiome()),
    LEXICON("title", "Созвездие: 4 спутника", "items", q_taskConstellation(4, "sat-"))
  ),
  "budget", LIST(
    LEXICON("label", "перелёт Кербин → Мун", "dv", 856, "optional", FALSE),
    LEXICON("label", "захват на рабочую орбиту", "dv", 320, "optional", FALSE),
    LEXICON("label", "развод 4 спутников (фаза)", "dv", 100, "optional", FALSE),
    LEXICON("label", "смена плоскости 90° под полюса", "dv", 770, "optional", TRUE),
    LEXICON("label", "посадка без обратного взлёта", "dv", 650, "optional", FALSE)
  )
).

q_plan(spec).

RUNONCEPATH("0:/lib/transfer.ks").
q_liveTransfer(MUN).
