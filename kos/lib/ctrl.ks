// lib/ctrl.ks — политика РСУ и САС. Экономим монотопливо.
// Зависит от: ничего.
// kerbal.ru · сборка «Оператор»

GLOBAL C_MONO_RESERVE IS 4.      // ниже этого остатка РСУ не включаем
GLOBAL C_RCS_HOLD IS 3.          // сек помощи РСУ после события
GLOBAL C_RCS_UNTIL IS 0.

// РСУ жрёт монотопливо, которого на спутнике десятки единиц, а маховики
// работают на электричестве. Поэтому РСУ — точечно, а не «включил и забыл».
GLOBAL FUNCTION c_rcs {
  PARAMETER want.
  IF want AND SHIP:MONOPROPELLANT > C_MONO_RESERVE { RCS ON. } ELSE { RCS OFF. }
}

// Попросить помощь РСУ на несколько секунд (стейджинг, тревога, наведение)
GLOBAL FUNCTION c_rcsPulse {
  SET C_RCS_UNTIL TO TIME:SECONDS + C_RCS_HOLD.
  c_rcs(TRUE).
}

// Вызывать в цикле: сам погасит РСУ, когда окно истечёт
GLOBAL FUNCTION c_rcsTick {
  c_rcs(TIME:SECONDS < C_RCS_UNTIL).
}

// Развернуть корабль на Солнце и подержать так — перед долгим WARPTO без
// топлива на прожиг панели должны заряжаться, а не смотреть в темноту.
// Поймано вживую: разряд EC во время многочасового варпа между узлами.
GLOBAL FUNCTION c_faceSun {
  PARAMETER holdSec IS 5.
  SAS OFF.
  LOCK STEERING TO SUN:POSITION.
  WAIT holdSec.
  UNLOCK STEERING.
  SAS ON.
}

// Вернуть управление человеку
GLOBAL FUNCTION c_release {
  LOCK THROTTLE TO 0.
  UNLOCK STEERING.
  UNLOCK THROTTLE.
  RCS OFF.
  SAS ON.
}
