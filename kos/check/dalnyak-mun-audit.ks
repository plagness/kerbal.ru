// dalnyak-mun-audit.ks — чекер по задаче и по планете для «Дальняк-Мун»,
// под три контракта: SCANsat-высотометрия, SCANsat-биомы, «Зонды к Mun»
// (посадка в 3 биомах). Прогонять на столе ДО пуска.
//
//   RUNPATH("0:/check/dalnyak-mun-audit.ks").

RUNONCEPATH("0:/lib/audit.ks").

LOCAL fail IS 0.

SET fail TO fail + q_report("SCANsat: высотометрия низкого разрешения", q_taskScanAltimetry()).
SET fail TO fail + q_report("SCANsat: мультиспектральный (биомы)", q_taskScanBiome()).
SET fail TO fail + q_report("Зонды к Mun: 3 биома", q_taskLandBiomes(3)).
SET fail TO fail + q_report("Мун: топливо и заряд", q_bodyChecklist(q_bodyMun())).

PRINT "== чекер не видит: ==".
PRINT "  - хватит ли ТОПЛИВА КОНКРЕТНО КАЖДОМУ лендеру на деорбит + посадку;".
PRINT "  - мягкая ли будет посадка (опоры, тяговооружённость);".
PRINT "  - попадут ли лендеры именно в РАЗНЫЕ биомы — это зависит от того,".
PRINT "    когда их отделяют по орбите, автомат в deepspace.ks это не решает;".
PRINT "  - дотянется ли связь до Земли с обратной стороны Муна.".

IF fail = 0 {
  PRINT "== всё, что видно чекеру, — на месте ==".
} ELSE {
  PRINT "== не хватает " + fail + " пункт(ов) — смотри отчёты выше ==".
}
