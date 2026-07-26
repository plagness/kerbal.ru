// dalnyak.ks — первый контракт: спутник 4758 x 4592 км, наклонение 8,5°.
// Аргумент перицентра не задан, поэтому парковка не нужна —
// mission.ks сам выберет схему с одним совмещённым прожигом.
//   RUNPATH("0:/missions/dalnyak.ks").

RUNONCEPATH("0:/lib/mission.ks").

SET s TO m_defaults().
SET s["name"] TO "Дальняк-1".
SET s["ap"]  TO 4757918.
SET s["pe"]  TO 4591510.
SET s["inc"] TO 8.5.
SET s["lan"] TO 311.
SET s["log"] TO "0:/dalnyak.csv".

m_orbit(s).
