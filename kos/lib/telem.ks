// lib/telem.ks — телеметрия в CSV с ограничением частоты.
// Зависит от: ничего.
// kerbal.ru · сборка «Оператор»
//
// Запись на каждом тике — тысячи операций ввода-вывода за полёт; они
// отъедают у цикла управления больше, чем сам расчёт. Пишем по таймеру.

GLOBAL T_PATH IS "0:/telemetry.csv".
GLOBAL T_EVERY IS 0.5.
GLOBAL T_NEXT IS 0.
GLOBAL T_T0 IS 0.

GLOBAL FUNCTION t_init {
  PARAMETER fpath, header.       // имя path занято встроенной функцией PATH()
  SET T_PATH TO fpath.
  SET T_T0 TO TIME:SECONDS.
  SET T_NEXT TO 0.
  IF EXISTS(T_PATH) { DELETEPATH(T_PATH). }
  LOG header TO T_PATH.
}

GLOBAL FUNCTION t_elapsed { RETURN TIME:SECONDS - T_T0. }

// Вернёт FALSE, если писать ещё рано
GLOBAL FUNCTION t_due {
  IF TIME:SECONDS < T_NEXT { RETURN FALSE. }
  SET T_NEXT TO TIME:SECONDS + T_EVERY.
  RETURN TRUE.
}

GLOBAL FUNCTION t_line {
  PARAMETER text.
  IF NOT t_due() { RETURN. }
  LOG ROUND(t_elapsed(),1) + "," + text TO T_PATH.
}
