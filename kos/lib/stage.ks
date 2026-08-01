// lib/stage.ks — автостейджер.
// Зависит от: ничего.
// kerbal.ru · сборка «Оператор»

GLOBAL FUNCTION s_liveEngines {
  LIST ENGINES IN el.
  LOCAL n IS 0.
  FOR e IN el { IF e:IGNITION AND NOT e:FLAMEOUT { SET n TO n + 1. } }
  RETURN n.
}

// Есть ли в ТЕКУЩЕЙ (ещё не отделённой) ступени обтекатель/грузовой отсек.
// Если да и мы ещё в атмосфере — сбрасывать его сейчас нельзя: набегающий
// поток сорвёт или повредит то, что под ним (антенны, приборы науки).
GLOBAL FUNCTION s_hasFairingNow {
  LIST PARTS IN pl.
  FOR p IN pl {
    IF p:STAGE = STAGE:NUMBER - 1 {
      LOCAL i IS 0.
      UNTIL i >= p:MODULES:LENGTH {
        IF p:MODULES[i] = "ModuleProceduralFairing" OR p:MODULES[i] = "ModuleFairing" { RETURN TRUE. }
        SET i TO i + 1.
      }
    }
  }
  RETURN FALSE.
}

// Ступень нужна, когда НЕ ОСТАЛОСЬ живых двигателей.
// Проверка «зажжённый выгорел» пропускает ступени-переходники,
// где двигателя нет вообще — на них скрипт зависает навсегда.
// ИСКЛЮЧЕНИЕ: если следующая ступень — обтекатель, а мы ещё в атмосфере,
// НЕ стейджим (иначе автостейджер слепо срывает обтекатель сразу вслед
// за отделением ускорителя, в разгар набегающего потока). Ждём, пока
// корабль сам выйдет из атмосферы — тогда придётся стейджить вручную/из
// вахтенного скрипта, s_tick тут намеренно замирает.
GLOBAL FUNCTION s_need {
  IF STAGE:NUMBER = 0 { RETURN FALSE. }
  IF NOT STAGE:READY { RETURN FALSE. }
  IF s_liveEngines() > 0 { RETURN FALSE. }
  IF s_hasFairingNow() AND SHIP:ALTITUDE < SHIP:BODY:ATM:HEIGHT { RETURN FALSE. }
  RETURN TRUE.
}

// Отработать ступень, если надо. Возвращает TRUE, если стейджила.
GLOBAL FUNCTION s_tick {
  IF NOT s_need() { RETURN FALSE. }
  STAGE.
  WAIT 0.7.
  RETURN TRUE.
}
