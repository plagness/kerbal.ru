// lib/hud.ks — визуальная отладка: стрелки в полётном виде и HUD.
// Зависит от: lib/util.ks (для угла атаки)
// kerbal.ru · сборка «Оператор»

RUNONCEPATH("0:/lib/util.ks").
//
// Две стрелки от центра масс: куда летим (зелёная) и куда целится
// рулевой закон (оранжевая). Расхождение между ними — это и есть угол
// атаки, и его видно глазами, а не по логу постфактум.

GLOBAL H_ON IS FALSE.
GLOBAL H_VEL IS 0.
GLOBAL H_CMD IS 0.

GLOBAL FUNCTION h_init {
  SET H_VEL TO VECDRAW(V(0,0,0), V(0,0,0), RGB(0.4,1,0.4), "поток", 1.0, TRUE, 0.25, TRUE, TRUE).
  SET H_CMD TO VECDRAW(V(0,0,0), V(0,0,0), RGB(1,0.6,0.1), "команда", 1.0, TRUE, 0.25, TRUE, TRUE).
  SET H_ON TO TRUE.
}

// cmdVec — вектор, куда целится рулевой закон (например A_CMD из ascent)
GLOBAL FUNCTION h_tick {
  PARAMETER cmdVec IS V(0,0,0).
  IF NOT H_ON { RETURN. }
  SET H_VEL:VEC TO SHIP:VELOCITY:SURFACE:NORMALIZED * 25.
  IF cmdVec:MAG > 0.001 { SET H_CMD:VEC TO cmdVec:NORMALIZED * 25. }
}

GLOBAL FUNCTION h_say {
  PARAMETER text.
  PARAMETER secs IS 5.
  HUDTEXT(text, secs, 2, 22, GREEN, FALSE).
}

GLOBAL FUNCTION h_off {
  SET H_ON TO FALSE.
  CLEARVECDRAWS().
}
