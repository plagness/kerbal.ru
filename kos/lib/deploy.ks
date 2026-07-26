// lib/deploy.ks — раскрытие панелей и антенн.
// Зависит от: ничего.
// kerbal.ru · сборка «Оператор»
//
// ТОЛЬКО в вакууме. В атмосфере на скорости панель или антенну срывает
// напором. Имена событий сверены в русской игре; английский вариант
// оставлен запасным.

GLOBAL FUNCTION d_vacuum { RETURN SHIP:ALTITUDE > SHIP:BODY:ATM:HEIGHT. }

GLOBAL FUNCTION d_all {
  IF NOT d_vacuum() { RETURN 0. }
  PANELS ON.
  LOCAL n IS 0.
  LIST PARTS IN pl.
  FOR p IN pl {
    LOCAL i IS 0.
    UNTIL i >= p:MODULES:LENGTH {
      IF p:MODULES[i] = "ModuleDeployableAntenna" {
        LOCAL m IS p:GETMODULEBYINDEX(i).
        IF m:HASEVENT("раскрыть антенну") { m:DOEVENT("раскрыть антенну"). SET n TO n + 1. }
        IF m:HASEVENT("extend antenna") { m:DOEVENT("extend antenna"). SET n TO n + 1. }
      }
      SET i TO i + 1.
    }
  }
  WAIT 4.
  PRINT "  раскрыто: панели " + PANELS + ", антенн " + n.
  RETURN n.
}
