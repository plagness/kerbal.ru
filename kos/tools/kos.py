#!/usr/bin/env python3
"""Минимальный telnet-клиент под kOS Terminal Server.

kOS требует RFC1073 (размер окна, NAWS) и RFC1091 (тип терминала) — без них
он отказывается работать. Обычный nc этого не умеет.

  python3 kos.py                      — подключиться, показать экран
  python3 kos.py 'PRINT 1+1.'         — выполнить команду и показать вывод
  python3 kos.py --watch 60           — просто смотреть экран 60 секунд
"""
import re
import socket
import sys
import time

HOST, PORT = "127.0.0.1", 5410
IAC, DONT, DO, WONT, WILL, SB, SE = 255, 254, 253, 252, 251, 250, 240
ECHO, SGA, TTYPE, NAWS = 1, 3, 24, 31
COLS, ROWS = 100, 44


# состояние согласованных опций: без него сервер зацикливает WILL/DO
_AGREED = set()


def negotiate(sock, data: bytes) -> bytes:
    """Отвечаем на телнет-переговоры, возвращаем чистый текст.

    Ключевой момент: на повторный WILL/DO по уже согласованной опции
    отвечать НЕЛЬЗЯ — иначе стороны уходят в бесконечный обмен и поток
    забивается служебными байтами (RFC 854, «avoid option negotiation loops»).
    """
    out, reply, i = bytearray(), bytearray(), 0
    while i < len(data):
        b = data[i]
        if b != IAC:
            out.append(b)
            i += 1
            continue
        if i + 1 >= len(data):
            break
        cmd = data[i + 1]
        if cmd == SB:
            end = data.find(bytes([IAC, SE]), i)
            if end < 0:
                break
            sub = data[i + 2:end]
            if sub and sub[0] == TTYPE and len(sub) > 1 and sub[1] == 1:   # SEND
                reply += bytes([IAC, SB, TTYPE, 0]) + b"XTERM" + bytes([IAC, SE])
            i = end + 2
            continue
        if i + 2 >= len(data):
            break
        opt = data[i + 2]
        key = (cmd, opt)
        if key not in _AGREED:
            _AGREED.add(key)
            if cmd == DO:
                if opt == TTYPE:
                    reply += bytes([IAC, WILL, TTYPE])
                elif opt == NAWS:
                    reply += bytes([IAC, WILL, NAWS])
                    reply += bytes([IAC, SB, NAWS, 0, COLS, 0, ROWS, IAC, SE])
                elif opt == SGA:
                    reply += bytes([IAC, WILL, SGA])
                else:
                    reply += bytes([IAC, WONT, opt])
            elif cmd == WILL:
                reply += bytes([IAC, DO, opt]) if opt in (ECHO, SGA) else bytes([IAC, DONT, opt])
        i += 3
    if reply:
        sock.sendall(bytes(reply))
    return bytes(out)


def clean(t: str) -> str:
    t = re.sub(r"\x1b\[[0-9;?]*[A-Za-z]", "", t)          # ANSI
    t = re.sub(r"[-]", "", t)                  # приватная зона kOS
    t = re.sub(r"[\x00-\x08\x0b\x0c\x0e-\x1f]", "", t)
    return t


def drain(sock, seconds=2.0) -> str:
    buf, t0 = b"", time.time()
    sock.settimeout(0.4)
    while time.time() - t0 < seconds:
        try:
            d = sock.recv(8192)
            if not d:
                break
            buf += negotiate(sock, d)
        except socket.timeout:
            continue
    return clean(buf.decode("utf-8", errors="replace"))


def main() -> int:
    args = sys.argv[1:]
    watch = 0.0
    if args and args[0] == "--watch":
        watch = float(args[1]); args = args[2:]

    s = socket.create_connection((HOST, PORT), timeout=6)
    banner = drain(s, 2.5)
    if "Choose a CPU" not in banner and "[1]" not in banner:
        print(banner[-1500:]); return 1

    s.sendall(b"1\r\n")                       # подключиться к первому процессору
    screen = drain(s, 2.5)
    print("=== экран терминала ===")
    print("\n".join(l.rstrip() for l in screen.splitlines() if l.strip())[-2500:])

    for cmd in args:
        print(f"\n=== отправляю: {cmd}")
        s.sendall(cmd.encode("utf-8") + b"\r\n")
        print("\n".join(l.rstrip() for l in drain(s, 3.5).splitlines() if l.strip())[-2500:])

    if watch:
        print(f"\n=== наблюдаю {watch:.0f} с ===")
        print("\n".join(l.rstrip() for l in drain(s, watch).splitlines() if l.strip())[-4000:])

    s.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
