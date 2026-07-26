// lib/ascent.ks — подъём с поверхности на опорную орбиту.
// Зависит от: lib/util.ks, lib/ctrl.ks, lib/stage.ks
// kerbal.ru · сборка «Оператор»
//
// Настройки передаются лексиконом, чтобы модуль не знал ничего о миссии:
//   park     целевой апоцентр опорной, м
//   az       азимут пуска, °
//   vVert    до этой скорости идём строго вверх, м/с
//   hDense   ниже этой высоты воздух опасен, м
//   aoaLo    допуск угла атаки в плотном воздухе, °
//   aoaHi    допуск выше hDense, °
//   hTwr     ниже этой высоты держим потолок перегрузки, м
//   twrMax   потолок перегрузки
//   qMax     потолок скоростного напора, атм
//   aoaAlarm угол атаки, выше которого включается восстановление, °
//   onTick   функция, зовётся каждый проход (лог, HUD)

GLOBAL FUNCTION a_defaults {
  RETURN LEXICON(
    "park", 80000, "az", 90, "vVert", 60,
    "hDense", 25000, "aoaLo", 5, "aoaHi", 20,
    "hTwr", 22000, "twrMax", 2.3, "qMax", 0.32, "aoaAlarm", 14,
    "onTick", { }
  ).
}

// Расписание тангажа по высоте. Следование чисто за потоком уводит
// слишком круто: аппарат приходит к апоцентру почти без горизонтальной
// скорости, и скругление стоит впятеро дороже нормального.
GLOBAL FUNCTION a_pitchSchedule {
  PARAMETER hgt.                 // имя alt занято встроенной переменной ALT
  // Расписание уплощено по итогам полёта: к апоцентру аппарат подошёл
  // со скоростью 1284 м/с вместо расчётных 2100, и совмещённый прожиг
  // стоил 1752 м/с вместо 936. Значит подъём всё ещё слишком крутой.
  IF hgt < 1000  { RETURN 90 - 6  * (hgt/1000). }
  IF hgt < 5000  { RETURN 84 - 18 * ((hgt-1000)/4000). }
  IF hgt < 10000 { RETURN 66 - 18 * ((hgt-5000)/5000). }
  IF hgt < 20000 { RETURN 48 - 16 * ((hgt-10000)/10000). }
  IF hgt < 30000 { RETURN 32 - 12 * ((hgt-20000)/10000). }
  IF hgt < 45000 { RETURN 20 - 11 * ((hgt-30000)/15000). }
  IF hgt < 60000 { RETURN 9  - 6  * ((hgt-45000)/15000). }
  RETURN 3.
}

GLOBAL A_CMD IS V(0,0,0).        // куда целимся — для HUD и лога

// Куда рулить: расписание, зажатое допуском по углу атаки
GLOBAL FUNCTION a_steer {
  PARAMETER cfg.
  LOCAL vel IS SHIP:VELOCITY:SURFACE.      // имя v занято конструктором V()
  IF vel:MAG < 40 { SET A_CMD TO HEADING(cfg["az"], 90):VECTOR. RETURN HEADING(cfg["az"], 90). }
  LOCAL want IS HEADING(cfg["az"], a_pitchSchedule(SHIP:ALTITUDE)):VECTOR.
  LOCAL lim IS cfg["aoaHi"].
  IF SHIP:ALTITUDE < cfg["hDense"] { SET lim TO cfg["aoaLo"]. }
  SET A_CMD TO u_limitTo(vel, want, lim).
  RETURN LOOKDIRUP(A_CMD, SHIP:UP:VECTOR).
}

// Тяга: потолок перегрузки в плотном воздухе + потолок напора
GLOBAL FUNCTION a_throttle {
  PARAMETER cfg.
  LOCAL thr IS 1.
  IF SHIP:ALTITUDE < cfg["hTwr"] AND SHIP:AVAILABLETHRUST > 0.1 {
    LOCAL twr IS SHIP:AVAILABLETHRUST / (SHIP:MASS * CONSTANT:g0).
    IF twr > cfg["twrMax"] { SET thr TO cfg["twrMax"] / twr. }
  }
  IF SHIP:DYNAMICPRESSURE > cfg["qMax"] { SET thr TO MIN(thr, 0.7). }
  RETURN thr.
}

// Весь подъём. Возвращает TRUE при успехе.
GLOBAL FUNCTION a_run {
  PARAMETER cfg.
  LOCAL onTick IS cfg["onTick"].
  LOCAL aborted IS FALSE.

  WHEN SHIP:VERTICALSPEED < -10 AND SHIP:ALTITUDE < 60000 AND SHIP:ALTITUDE > 3000 THEN {
    LOCK THROTTLE TO 0.
    SET aborted TO TRUE.
    PRINT "!!! АВАРИЯ: падаем на подъёме".
  }

  SAS OFF.
  c_rcs(TRUE).
  LOCAL thr IS 1.
  LOCK THROTTLE TO thr.
  LOCK STEERING TO HEADING(cfg["az"], 90).
  STAGE.

  PRINT "  вертикаль до " + cfg["vVert"] + " м/с".
  UNTIL SHIP:VELOCITY:SURFACE:MAG > cfg["vVert"] OR aborted {
    IF s_tick() { c_rcsPulse(). }
    onTick().
    WAIT 0.
  }

  PRINT "  разворот по расписанию, азимут " + ROUND(cfg["az"],1) + "°".
  LOCAL recover IS FALSE.
  LOCK STEERING TO a_steer(cfg).

  UNTIL SHIP:APOAPSIS > cfg["park"] OR aborted {
    IF s_tick() { c_rcsPulse(). }
    SET thr TO a_throttle(cfg).

    IF u_aoa() > cfg["aoaAlarm"] AND SHIP:ALTITUDE < cfg["hDense"] {
      IF NOT recover { SET recover TO TRUE. PRINT "  ! угол атаки " + ROUND(u_aoa(),0) + "° — на поток". }
      LOCK STEERING TO LOOKDIRUP(SHIP:VELOCITY:SURFACE, SHIP:UP:VECTOR).
      // тягу не роняем в ноль: вместе с ней пропадёт подвес двигателя
      SET thr TO MAX(0.45, thr * 0.6).
      c_rcsPulse().
    } ELSE {
      IF recover AND u_aoa() < 4 {
        SET recover TO FALSE.
        PRINT "  выровнялась".
        LOCK STEERING TO a_steer(cfg).
      }
      c_rcs(SHIP:ALTITUDE < cfg["hDense"]).
    }
    onTick().
    WAIT 0.
  }
  PRINT "  апоцентр " + ROUND(SHIP:APOAPSIS/1000,1) + " км".

  // В верхних слоях воздух ещё грызёт апоцентр — подтягиваем импульсами
  UNTIL SHIP:ALTITUDE > SHIP:BODY:ATM:HEIGHT OR aborted {
    IF SHIP:APOAPSIS < cfg["park"] - 1500 { SET thr TO 0.35. } ELSE { SET thr TO 0. }
    onTick().
    WAIT 0.
  }
  LOCK THROTTLE TO 0.
  RCS OFF.
  RETURN NOT aborted.
}
