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

// Включить сканирование на всех сканерах SCANsat разом. У модуля SCANsat
// РОВНО одно событие вида «запустить сканирование: <тип>» — radar,
// multispectral, resource и т.д. Названия проверены на живом корабле
// через telnet, а не угаданы: R-EO-1 (высотомер) → radar, MS-1
// (мультиспектральный) → multispectral. У SCANsat нет своего «раскрыть»:
// сами детали не складываются, включать нечего кроме сканирования.
// Не путать с SCANexperiment на той же детали — это НАУЧНЫЙ бонус-отчёт,
// другой модуль с другим интерфейсом (несовместим с sciSweep, см.
// SCI_INCOMPATIBLE в lib/sci.ks), сюда отношения не имеет.
GLOBAL FUNCTION d_scan {
  LOCAL n IS 0.
  LIST PARTS IN pl.
  FOR p IN pl {
    LOCAL i IS 0.
    UNTIL i >= p:MODULES:LENGTH {
      IF p:MODULES[i] = "SCANsat" {
        LOCAL m IS p:GETMODULEBYINDEX(i).
        LOCAL el IS m:ALLEVENTNAMES.       // LIST...IN работает только для встроенных
        FOR ev IN el {                     // коллекций (PARTS, ENGINES…), не для суффиксов
          IF ev:STARTSWITH("запустить сканирование") { m:DOEVENT(ev). SET n TO n + 1. }
        }
      }
      SET i TO i + 1.
    }
  }
  PRINT "  сканеров включено: " + n.
  RETURN n.
}
