// dalnyak-mun-lander.ks — посадка одного из лендеров, выпущенных
// «Дальняк-Мун» ([[missions/dalnyak-mun.ks]]). Запускать ПОСЛЕ переключения
// фокуса на отделившийся лендер — он уже на низкой круговой орбите Муна.
//
//   RUNPATH("0:/missions/dalnyak-mun-lander.ks").

RUNONCEPATH("0:/lib/land.ks").
RUNONCEPATH("0:/lib/deploy.ks").
RUNONCEPATH("0:/lib/sci.ks").

PRINT "=== посадка: биом на подлёте «" + SHIP:GEOPOSITION:BIOME + "»".

SET s TO l_defaults().
SET s["sci"] TO TRUE.

l_run(s).
d_all().

PRINT "  снята наука в биоме «" + SHIP:GEOPOSITION:BIOME + "»".
