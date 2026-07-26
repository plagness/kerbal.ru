// lib/util.ks — мелкие помощники, ни от чего не зависит.
// Все имена с префиксом u_, чтобы не сталкиваться с другими модулями.
// kerbal.ru · сборка «Оператор»

GLOBAL FUNCTION u_clamp {
  PARAMETER x, lo, hi.
  RETURN MAX(lo, MIN(hi, x)).
}

// Тангаж произвольного вектора над горизонтом, °
GLOBAL FUNCTION u_pitchOf {
  PARAMETER vec.
  IF vec:MAG < 0.001 { RETURN 0. }
  RETURN 90 - VANG(SHIP:UP:VECTOR, vec).
}

// Тангаж вектора скорости; на околонулевой скорости считаем «вверх»
GLOBAL FUNCTION u_vPitch {
  IF SHIP:VELOCITY:SURFACE:MAG < 15 { RETURN 90. }
  RETURN u_pitchOf(SHIP:VELOCITY:SURFACE).
}

// Угол атаки: между носом и набегающим потоком
GLOBAL FUNCTION u_aoa {
  IF SHIP:VELOCITY:SURFACE:MAG < 15 { RETURN 0. }
  RETURN VANG(SHIP:FACING:VECTOR, SHIP:VELOCITY:SURFACE).
}

// Компасный азимут вектора скорости, 0=север, 90=восток
GLOBAL FUNCTION u_velAzimuth {
  LOCAL h IS VXCL(SHIP:UP:VECTOR, SHIP:VELOCITY:SURFACE).
  IF h:MAG < 1 { RETURN 0. }
  LOCAL n IS VXCL(SHIP:UP:VECTOR, SHIP:NORTH:VECTOR).
  LOCAL a IS VANG(n, h).
  IF VDOT(VCRS(n, h), SHIP:UP:VECTOR) < 0 { RETURN 360 - a. }
  RETURN a.
}

// Азимут пуска под заданное наклонение С ПОПРАВКОЙ на вращение планеты:
// часть восточной скорости планета даёт бесплатно, и наивная формула
// sin(A)=cos(i)/cos(lat) её не учитывает.
// Эмпирическая поправка: расчётный азимут 80,80° дал наклонение 8,02°
// вместо 8,50°. Чувствительность около 1° наклонения на 1° азимута,
// поэтому вычитаем недобор. Измерено на своём пуске, не выведено.
GLOBAL U_AZ_BIAS IS -0.45.

GLOBAL FUNCTION u_launchAzimuth {
  PARAMETER inc.                      // желаемое наклонение, °
  PARAMETER vOrb IS 2279.             // скорость на целевой опорной, м/с
  LOCAL lat IS SHIP:LATITUDE.
  LOCAL c IS COS(inc) / COS(lat).
  IF ABS(c) > 1 { RETURN 90. }        // такое наклонение с этой широты недостижимо
  LOCAL b IS ARCSIN(c).
  LOCAL vRot IS 2 * CONSTANT:PI * SHIP:BODY:RADIUS / SHIP:BODY:ROTATIONPERIOD * COS(lat).
  RETURN ARCTAN2(vOrb * SIN(b) - vRot, vOrb * COS(b)) + U_AZ_BIAS.
}

// Повернуть вектор from в сторону to, но не дальше lim градусов.
// Это ядро защиты от заваливания: команда рулю никогда не уходит
// от набегающего потока дальше допустимого угла атаки.
GLOBAL FUNCTION u_limitTo {
  PARAMETER from, to, lim.
  IF from:MAG < 0.001 { RETURN to. }
  IF VANG(from, to) <= lim { RETURN to. }
  LOCAL ax IS VCRS(from, to).
  IF ax:MAG < 0.0001 { RETURN from. }
  LOCAL r1 IS ANGLEAXIS(lim, ax) * from.
  LOCAL r2 IS ANGLEAXIS(-lim, ax) * from.
  IF VANG(r1, to) < VANG(r2, to) { RETURN r1. }
  RETURN r2.
}

// ─── окно пуска под долготу восходящего узла ─────────────────────────
// Модель выведена из телеметрии собственного пуска, а не из теории:
//   пуск при долготе КЦК -74,56° в UT 31288 дал LAN 179,93°
//   LAN = долгота_старта + поворот_планеты(UT) + C,  где C = 91,80°
// Для другой планеты или другого сейва C надо перемерить: запусти,
// запиши три числа из финального сообщения и пересчитай.
GLOBAL U_LAN_C IS 91.80.

GLOBAL FUNCTION u_bodyRot {
  PARAMETER ut IS TIME:SECONDS.
  RETURN MOD(360 * ut / SHIP:BODY:ROTATIONPERIOD, 360).
}

// Какой узел получится, если стартовать прямо сейчас
GLOBAL FUNCTION u_lanIfLaunchNow {
  RETURN MOD(SHIP:LONGITUDE + u_bodyRot() + U_LAN_C + 720, 360).
}

// Сколько секунд ждать до нужного узла
GLOBAL FUNCTION u_lanWait {
  PARAMETER targetLan.
  LOCAL diff IS MOD(targetLan - u_lanIfLaunchNow() + 720, 360).
  RETURN diff / 360 * SHIP:BODY:ROTATIONPERIOD.
}

// Дождаться окна. tol — допуск в градусах, при попадании не ждём вовсе.
GLOBAL FUNCTION u_waitForLan {
  PARAMETER targetLan.
  PARAMETER tol IS 2.
  LOCAL off IS MOD(targetLan - u_lanIfLaunchNow() + 720, 360).
  IF off > 180 { SET off TO 360 - off. }
  IF off <= tol {
    PRINT "  окно узла уже открыто: " + ROUND(u_lanIfLaunchNow(),1) + "°".
    RETURN.
  }
  LOCAL wait IS u_lanWait(targetLan).
  // Целевой момент считаем ОДИН раз и ждём его по абсолютному времени.
  // Проверять остаток нельзя: величина модульная, сразу после пропуска
  // окна она скачком становится «почти период», и условие вида
  // «остаток мал ИЛИ велик» срабатывает мгновенно — ожидания не будет.
  LOCAL tgtUT IS TIME:SECONDS + wait.
  PRINT "  жду окно узла " + ROUND(targetLan,1) + "°: " + ROUND(wait/60,1)
        + " мин (сейчас дало бы " + ROUND(u_lanIfLaunchNow(),1) + "°)".
  IF wait > 60 { WARPTO(tgtUT - 20). }
  WAIT UNTIL TIME:SECONDS >= tgtUT.
  PRINT "  окно открыто: узел даст " + ROUND(u_lanIfLaunchNow(),1) + "°".
}
