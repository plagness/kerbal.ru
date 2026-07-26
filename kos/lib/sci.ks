// sci.ks — наука: сбор по пути, передача только когда это безопасно.
// kerbal.ru · сборка «Оператор»
//
// ПОЧЕМУ ТАК (разбор после второй попытки):
//   Антенны сломались не от эксперимента, а от ПЕРЕДАЧИ. В KSP складная
//   антенна РАСКРЫВАЕТСЯ САМА, когда через неё передают науку. Мы передавали
//   на подъёме — HG-5 и Zebulon раскрылись в набегающий поток и были сорваны.
//   Правило: в атмосфере данные только СОБИРАЕМ и держим в приборах,
//   передаём уже в вакууме, когда антенны раскрыты штатно.
//
// ОТБОР: атмосфера — только пассивные многоразовые без выдвижных штанг;
//        вакуум    — всё, что есть на борту.

GLOBAL SCI_PASSIVE IS "ModuleScienceExperiment".
GLOBAL SCI_ANIM IS LIST("DMModuleScienceAnimateGeneric", "DMBasicScienceModule").
GLOBAL SCI_ALLOW_ANIM IS FALSE.
GLOBAL SCI_LAST IS "".
GLOBAL SCI_SENT IS 0.

FUNCTION sciVacuum { RETURN SHIP:ALTITUDE > SHIP:BODY:ATM:HEIGHT. }

FUNCTION sciZone {
  LOCAL a IS SHIP:ALTITUDE.
  IF SHIP:STATUS = "PRELAUNCH" OR SHIP:STATUS = "LANDED" { RETURN "старт". }
  IF a < 18000 { RETURN "атмосфера низко". }
  IF a < SHIP:BODY:ATM:HEIGHT { RETURN "атмосфера высоко". }
  IF a < 250000 { RETURN "космос низко". }
  RETURN "космос высоко".
}

// Перебор ПО ИНДЕКСУ: в детали бывает несколько научных модулей —
// у мачты CA-AMA их два, поиск по имени вернул бы только первый.
FUNCTION sciModules {
  LOCAL out IS LIST().
  LIST PARTS IN pl.
  FOR p IN pl {
    LOCAL i IS 0.
    UNTIL i >= p:MODULES:LENGTH {
      LOCAL mn IS p:MODULES[i].
      LOCAL ok IS (mn = SCI_PASSIVE).
      IF SCI_ALLOW_ANIM AND sciVacuum() AND SCI_ANIM:CONTAINS(mn) { SET ok TO TRUE. }
      IF ok { out:ADD(p:GETMODULEBYINDEX(i)). }
      SET i TO i + 1.
    }
  }
  RETURN out.
}

FUNCTION sciSweep {
  PARAMETER label IS sciZone().
  PARAMETER mayTransmit IS FALSE.
  LOCAL ran IS 0.
  FOR m IN sciModules() {
    IF NOT m:HASDATA AND NOT m:INOPERABLE AND m:RERUNNABLE {
      m:DEPLOY().
      SET ran TO ran + 1.
      WAIT 0.4.
    }
  }
  IF NOT mayTransmit {
    LOCAL held IS 0.
    FOR m IN sciModules() { IF m:HASDATA { SET held TO held + 1. } }
    PRINT "  наука [" + label + "]: снято " + ran + ", в приборах " + held + ", передача позже".
    RETURN.
  }
  WAIT 1.
  LOCAL sent IS 0.
  FOR m IN sciModules() {
    IF m:HASDATA { m:TRANSMIT(). SET sent TO sent + 1. WAIT 0.6. }
  }
  SET SCI_SENT TO SCI_SENT + sent.
  PRINT "  наука [" + label + "]: снято " + ran + ", передано " + sent.
}

// Смена зоны — собираем. Передаём только в вакууме.
FUNCTION sciTick {
  LOCAL z IS sciZone().
  IF z <> SCI_LAST AND z <> "старт" {
    SET SCI_LAST TO z.
    sciSweep(z, sciVacuum()).
  }
}

FUNCTION sciRetry {
  IF NOT sciVacuum() { RETURN 0. }
  LOCAL n IS 0.
  FOR m IN sciModules() {
    IF m:HASDATA { m:TRANSMIT(). SET n TO n + 1. WAIT 0.6. }
  }
  IF n > 0 { PRINT "  добор: передано " + n. }
  RETURN n.
}
