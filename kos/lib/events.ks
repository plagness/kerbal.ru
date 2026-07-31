// lib/events.ks — событийная автоматика: не линия команд, а список
// «если условие — сделать один раз» и «пока условие — делать каждый тик».
// Зависит от: ничего.
// kerbal.ru · сборка «Оператор»
//
//   RUNONCEPATH("0:/lib/events.ks").
//   SET EV TO e_new().
//   e_once(EV, "смена SOI", { RETURN SHIP:BODY = MUN. }, { PRINT "у Муна!". }).
//   e_watch(EV, "мало заряда", { RETURN SHIP:ELECTRICITY < 20. }, { PANELS ON. }).
//   e_run(EV, { RETURN SHIP:STATUS = "LANDED". }).   // условие остановки
//
// Зачем: файл миссии перестаёт быть длинной цепочкой WAIT/IF и становится
// списком «что и когда» — читается как таблица, а не как программа.
// Один и тот же список триггеров переживает варп, смену фокуса и рестарт
// программы: условия проверяются заново, а не восстанавливаются из
// переменных-счётчиков, которые после сброса программы теряются.

// Новый список событий.
GLOBAL FUNCTION e_new { RETURN LIST(). }

// Сработать РОВНО ОДИН РАЗ, когда cond() впервые станет истинным.
GLOBAL FUNCTION e_once {
  PARAMETER events, name, cond, fn.
  events:ADD(LEXICON("name", name, "cond", cond, "fn", fn, "watch", FALSE, "fired", FALSE)).
}

// Срабатывать КАЖДЫЙ ТИК, пока cond() истинно (сторож: заряд, температура,
// связь). fired не выставляется — можно сработать снова на следующем тике.
GLOBAL FUNCTION e_watch {
  PARAMETER events, name, cond, fn.
  events:ADD(LEXICON("name", name, "cond", cond, "fn", fn, "watch", TRUE, "fired", FALSE)).
}

// Один проход по списку. Возвращает true, если что-то сработало
// (полезно для лога/HUD снаружи).
GLOBAL FUNCTION e_tick {
  PARAMETER events.
  LOCAL any IS FALSE.
  FOR ev IN events {
    IF (ev["watch"] OR NOT ev["fired"]) AND ev["cond"]() {
      IF NOT ev["watch"] {
        SET ev["fired"] TO TRUE.
        PRINT "=== событие: " + ev["name"].
      }
      ev["fn"]().
      SET any TO TRUE.
    }
  }
  RETURN any.
}

// Крутить список до стоп-условия. onTick — необязательный колбэк для
// телеметрии/HUD, зовётся каждый цикл вдобавок к самим событиям.
GLOBAL FUNCTION e_run {
  PARAMETER events.
  PARAMETER stopCond IS { RETURN FALSE. }.
  PARAMETER onTick IS { }.
  UNTIL stopCond() {
    e_tick(events).
    onTick().
    WAIT 0.
  }
}

// Все ли одноразовые события списка уже сработали (watch-события не считаются —
// у них нет «выполнено», они сторожат постоянно).
GLOBAL FUNCTION e_done {
  PARAMETER events.
  FOR ev IN events {
    IF NOT ev["watch"] AND NOT ev["fired"] { RETURN FALSE. }
  }
  RETURN TRUE.
}
