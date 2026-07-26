// lib/stage.ks — автостейджер.
// Зависит от: ничего.
// kerbal.ru · сборка «Оператор»

GLOBAL FUNCTION s_liveEngines {
  LIST ENGINES IN el.
  LOCAL n IS 0.
  FOR e IN el { IF e:IGNITION AND NOT e:FLAMEOUT { SET n TO n + 1. } }
  RETURN n.
}

// Ступень нужна, когда НЕ ОСТАЛОСЬ живых двигателей.
// Проверка «зажжённый выгорел» пропускает ступени-переходники,
// где двигателя нет вообще — на них скрипт зависает навсегда.
GLOBAL FUNCTION s_need {
  IF STAGE:NUMBER = 0 { RETURN FALSE. }
  IF NOT STAGE:READY { RETURN FALSE. }
  RETURN s_liveEngines() = 0.
}

// Отработать ступень, если надо. Возвращает TRUE, если стейджила.
GLOBAL FUNCTION s_tick {
  IF NOT s_need() { RETURN FALSE. }
  STAGE.
  WAIT 0.7.
  RETURN TRUE.
}
