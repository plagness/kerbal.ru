---
title: kOS по telnet: пульт снаружи игры
category: Автоматика
summary: Как открыть терминал kOS наружу, почему обычный telnet-клиент не работает, готовый клиент на Python и что это даёт связке «человек + ИИ-агент».
order: 45
related: [kos-otladka, agenty, kos-interfeys]
---

У kOS есть встроенный **telnet-сервер**. Включаешь — и бортовой терминал становится доступен снаружи игры: из другого окна, из скрипта, из ассистента с доступом к терминалу.

Это меняет весь рабочий цикл. Не «правка → альт-таб → перепечатать команду → прочитать скриншот», а прямой канал: отправил команду, получил ответ текстом.

## Как включить

Панель kOS → **TELNET**. Порт по умолчанию **5410**, адрес **127.0.0.1** (только этот компьютер). Внизу окна появится:

```
Telnet server listening on 127.0.0.1 port 5410. (no clients connected).
```

Менять адрес на сетевой имеет смысл только если знаешь, зачем: это открытый порт, дающий полное управление кораблём.

## Почему `nc` и `telnet` не работают

Первое, что видишь при попытке подключиться обычным `nc`:

```
{YOUR TELNET CLIENT WONT IMPLEMENT RFC1073 (Terminal dimensions). kOS CANNOT WORK WITH IT.}DIE
{YOUR TELNET CLIENT WONT IMPLEMENT RFC1091 (Terminal type). kOS CANNOT WORK WITH IT.}DIE
```

kOS требует от клиента двух telnet-опций:

- **RFC 1091 — тип терминала.** На запрос `IAC SB TTYPE SEND` надо ответить именем, например `XTERM`.
- **RFC 1073 — размер окна (NAWS).** Надо сообщить ширину и высоту.

`nc` — «голая труба», он не умеет ни того, ни другого.

### Вторая ловушка: цикл переговоров

Даже реализовав обе опции, легко получить поток мусора вместо экрана. Сервер шлёт `IAC WILL ECHO`, клиент отвечает `IAC DO ECHO`, сервер отвечает снова — и так до бесконечности. Экран забивается служебными байтами, а нажатия тонут: меню отвечает «Garbled selection. Try again.»

Правило из RFC 854: **на повторное согласование уже согласованной опции отвечать нельзя.** Нужно помнить состояние.

## Рабочий клиент

Полсотни строк на Python, без зависимостей. Реализует ровно необходимое.

```python
import re, socket, time

HOST, PORT = "127.0.0.1", 5410
IAC, DONT, DO, WONT, WILL, SB, SE = 255, 254, 253, 252, 251, 250, 240
ECHO, SGA, TTYPE, NAWS = 1, 3, 24, 31
COLS, ROWS = 100, 44

_AGREED = set()          # без этого сервер зациклит переговоры

def negotiate(sock, data):
    out, reply, i = bytearray(), bytearray(), 0
    while i < len(data):
        if data[i] != IAC:
            out.append(data[i]); i += 1; continue
        cmd = data[i+1]
        if cmd == SB:                                   # подпереговоры
            end = data.find(bytes([IAC, SE]), i)
            sub = data[i+2:end]
            if sub and sub[0] == TTYPE and sub[1] == 1:  # просят тип
                reply += bytes([IAC, SB, TTYPE, 0]) + b"XTERM" + bytes([IAC, SE])
            i = end + 2; continue
        opt = data[i+2]
        if (cmd, opt) not in _AGREED:                   # отвечаем ОДИН раз
            _AGREED.add((cmd, opt))
            if cmd == DO and opt == TTYPE:
                reply += bytes([IAC, WILL, TTYPE])
            elif cmd == DO and opt == NAWS:
                reply += bytes([IAC, WILL, NAWS])
                reply += bytes([IAC, SB, NAWS, 0, COLS, 0, ROWS, IAC, SE])
            elif cmd == DO:
                reply += bytes([IAC, WILL if opt == SGA else WONT, opt])
            elif cmd == WILL:
                reply += bytes([IAC, DO if opt in (ECHO, SGA) else DONT, opt])
        i += 3
    if reply: sock.sendall(bytes(reply))
    return bytes(out)

def clean(t):
    t = re.sub(r"\x1b\[[0-9;?]*[A-Za-z]", "", t)        # ANSI-коды
    return re.sub(r"[\x00-\x08\x0b\x0c\x0e-\x1f-]", "", t)

def drain(sock, seconds=2.0):
    buf, t0 = b"", time.time()
    sock.settimeout(0.4)
    while time.time() - t0 < seconds:
        try:
            d = sock.recv(8192)
            if not d: break
            buf += negotiate(sock, d)
        except socket.timeout:
            continue
    return clean(buf.decode("utf-8", errors="replace"))

s = socket.create_connection((HOST, PORT), timeout=6)
drain(s, 3)                    # дать переговорам завершиться
s.sendall(b"1\n")              # выбрать первый процессор из меню
print(drain(s, 2))
s.sendall(b'PRINT SHIP:NAME.\n')
print(drain(s, 3))
```

После подключения сервер показывает меню процессоров:

```
              Pick Open Telnets  Vessel Name (CPU tagname)
               [1]  yes    0     Дальняк-1 (CX-4181())
```

Цифра и `\n` — и ты в терминале корабля.

## Что это даёт

| Без telnet | С telnet |
|---|---|
| ошибку видно только на экране | текст ошибки с номером строки приходит сразу |
| телеметрию пересказываешь словами | `PRINT SHIP:APOAPSIS.` и точное число |
| проверка скрипта = запуск ракеты | синтаксис проверяется на площадке за секунду |
| правка → альт-таб → перепечатать | правка файла и повторный `RUNPATH` из скрипта |

Отдельно это ценно для работы с ИИ-агентом ([[agenty]]): агент правит `.ks` в папке игры **и тут же сам его прогоняет**, читая вывод. Цикл «правка → прогон → разбор» сокращается с минут до секунд, и человеку не нужно быть посредником.

Приём, который экономит больше всего: **проверочный файл**. Берём боевой скрипт, отрезаем исполняемую часть, оставляем объявления и функции — и запускаем на площадке. Разбор пройдёт весь файл целиком, но двигатели не тронет. Все опечатки и конфликты имён вылезут до пуска.

## Правила, купленные опытом

**Не печатай в терминал, пока работает программа.** Ввод во время исполнения kOS воспринимает как прерывание — программа завершится с «Program aborted». Мы так уронили скрипт посреди выведения. Во время полёта — только слушать.

**Виджеты через telnet не работают.** Это ограничение самого kOS: GUI живёт в окне игры и требует мыши. Снаружи доступен только текстовый терминал — см. [[kos-interfeys]].

**Порт даёт полное управление кораблём.** На `127.0.0.1` это безопасно. Открывать наружу без нужды не стоит.

**Кириллица в терминале работает**, но kOS иногда шлёт символы из приватной зоны Юникода — их нужно вычищать при разборе вывода, иначе они склеивают строки.
