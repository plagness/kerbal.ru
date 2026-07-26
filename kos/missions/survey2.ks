// survey2.ks — контракт Astronomical Survey Society, второй спутник.
// Вся механика в 0:/lib/mission.ks — здесь только цифры из контракта.
//   RUNPATH("0:/missions/survey2.ks").

RUNONCEPATH("0:/lib/mission.ks").

SET s TO m_defaults().
SET s["name"] TO "Спутник-2".
SET s["ap"]  TO 7867078.
SET s["pe"]  TO 3331362.
SET s["inc"] TO 20.1.
SET s["lan"] TO 250.8.
SET s["aop"] TO 29.6.
SET s["log"] TO "0:/survey2.csv".

m_orbit(s).
