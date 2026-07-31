// lib/deepspace.ks — дальний вылет одной спецификацией: тело, орбиты,
// лендеры, наука. Остальное считает и делает сама автоматика.
// Зависит от: lib/rendezvous.ks, lib/transfer.ks, lib/deploy.ks, lib/sci.ks
// kerbal.ru · сборка «Оператор»
//
//   RUNONCEPATH("0:/lib/deepspace.ks").
//   SET s TO ds_defaults().
//   SET s["body"]    TO MUN.
//   SET s["parkAlt"] TO 18000.     // низкая орбита — отсюда выпускаем спутники
//   SET s["mapAlt"]  TO 250000.    // картографическая полярная (0 = не подниматься)
//   SET s["landers"] TO LIST("sat-1", "sat-2", "sat-3", "sat-4").  // метки декаплеров
//   SET s["selfLand"] TO TRUE.     // сама шина садится ПОСЛЕ развода спутников
//   SET s["sci"]     TO TRUE.      // снимать/передавать науку на каждом рубеже
//   ds_run(s).
//
// Тот же принцип, что у m_orbit() в lib/mission.ks: файл миссии содержит
// только параметры цели, порядок шагов и решения по ходу («сколько отделяемых
// нагрузок», «нужна ли подгонка плоскости», «садится ли шина сама в конце») —
// здесь, одним местом. «landers» — общее имя для всего, что отделяется по
// метке декаплера: это могут быть посадочные зонды, а могут быть спутники
// созвездия, которые остаются на орбите. Наклонение к телу этим модулем
// НЕ задаётся — закладывай его на пуске у родителя, см. [[rendezvous]].

RUNONCEPATH("0:/lib/rendezvous.ks").
RUNONCEPATH("0:/lib/transfer.ks").
RUNONCEPATH("0:/lib/deploy.ks").
RUNONCEPATH("0:/lib/sci.ks").
RUNONCEPATH("0:/lib/land.ks").

GLOBAL FUNCTION ds_defaults {
  RETURN LEXICON(
    "name", "дальний вылет",
    "body", MUN,
    "parkAlt", 18000,     // низкая орбита захвата, м — старт для отделяемых нагрузок
    "mapAlt", 250000,     // картографическая полярная, м; 0 = не подниматься
    "landers", LIST(),    // метки декаплеров, пусто = отделяемых нагрузок нет
    "selfLand", FALSE,    // TRUE — шина сама садится после развода нагрузок
    "sci", TRUE,          // снимать/передавать науку на рубежах
    "log", "0:/deepspace.csv"
  ).
}

// Выпустить лендер по метке декаплера. Ищет ЛЮБОЙ модуль с событием
// «decouple»/«расстыковать» на детали с этой меткой — не завязываемся
// на конкретный тип декаплера.
GLOBAL FUNCTION ds_release {
  PARAMETER tag.
  LOCAL found IS FALSE.
  LIST PARTS IN pl.
  FOR p IN pl {
    IF p:TAG = tag {
      SET found TO TRUE.
      LOCAL i IS 0.
      UNTIL i >= p:MODULES:LENGTH {
        LOCAL m IS p:GETMODULEBYINDEX(i).
        IF m:HASEVENT("decouple") { m:DOEVENT("decouple"). }
        IF m:HASEVENT("расстыковать") { m:DOEVENT("расстыковать"). }
        SET i TO i + 1.
      }
    }
  }
  IF found { PRINT "  выпущен: " + tag. } ELSE { PRINT "  ! метка не найдена: " + tag. }
  RETURN found.
}

GLOBAL FUNCTION ds_run {
  PARAMETER spec.

  PRINT "=== " + spec["name"] + ": перелёт к " + spec["body"]:NAME.
  IF NOT x_go(spec["body"], spec["parkAlt"]) {
    PRINT "! перелёт не удался — смотри лог выше".
    RETURN FALSE.
  }
  IF spec["sci"] { sciSweep("захват " + spec["body"]:NAME, TRUE). }

  IF spec["landers"]:LENGTH > 0 {
    PRINT "=== развод отделяемых нагрузок на орбите " + ROUND(spec["parkAlt"]/1000,1) + " км".
    PRINT "  разносим по доле витка — так у них разная фаза/трек, а не всё в одной точке.".
    LOCAL per IS SHIP:ORBIT:PERIOD.
    LOCAL step IS per / spec["landers"]:LENGTH.
    FOR tag IN spec["landers"] {
      PRINT "  над «" + SHIP:GEOPOSITION:BIOME + "» — выпускаю " + tag.
      ds_release(tag).
      WAIT step.
    }
  }

  IF spec["selfLand"] {
    PRINT "=== шина садится сама".
    l_go(0).
    d_all().
    IF spec["sci"] { sciSweep("на поверхности " + spec["body"]:NAME, TRUE). }
    PRINT "=== " + spec["name"] + ": на поверхности, биом «" + SHIP:GEOPOSITION:BIOME + "»".
    RETURN TRUE.
  }

  IF spec["mapAlt"] > 0 AND spec["mapAlt"] <> spec["parkAlt"] {
    PRINT "=== подъём в картографическую орбиту " + ROUND(spec["mapAlt"]/1000,0) + " км".
    o_burn(o_nodeRaiseOpposite(spec["mapAlt"])).
    o_burn(o_nodeCircularize()).
  }
  d_all().
  IF spec["sci"] { sciSweep("целевая орбита", TRUE). }

  PRINT "=== " + spec["name"] + ": на месте " + ROUND(SHIP:APOAPSIS/1000,1)
        + " / " + ROUND(SHIP:PERIAPSIS/1000,1) + " км, накл "
        + ROUND(SHIP:ORBIT:INCLINATION,1) + "°".
  PRINT "  сканеры SCANsat kOS не включает — имена их событий не сверены,".
  PRINT "  переключи с приборной панели вручную.".
  IF spec["landers"]:LENGTH > 0 {
    PRINT "  посадка отделённой нагрузки — после переключения фокуса на неё:".
    PRINT "    SET s TO l_defaults(). l_run(s).   (lib/land.ks)".
  }
  RETURN TRUE.
}
