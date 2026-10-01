#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Loopback WebSocket fixture. Only synthetic Service Auth credentials are accepted."""

import base64
import hashlib
import socketserver
import struct


def read_exact(stream, size):
    data = bytearray()
    while len(data) < size:
        chunk = stream.read(size - len(data))
        if not chunk:
            raise EOFError
        data.extend(chunk)
    return bytes(data)


def frame(opcode, payload, final=True):
    header = bytes([(0x80 if final else 0) | opcode])
    size = len(payload)
    if size < 126:
        header += bytes([size])
    elif size < 65536:
        header += b"\x7e" + struct.pack("!H", size)
    else:
        header += b"\x7f" + struct.pack("!Q", size)
    return header + payload


class Handler(socketserver.StreamRequestHandler):
    def handle(self):
        self.connection.settimeout(10)
        try:
            self.serve()
        except (EOFError, OSError):
            pass

    def serve(self):
        request = self.rfile.readline(4096).decode("ascii").split()
        if len(request) != 3:
            return
        path = request[1]
        headers = {}
        for _ in range(64):
            line = self.rfile.readline(4096)
            if line == b"\r\n":
                break
            name, value = line.decode("ascii").split(":", 1)
            headers[name.lower()] = value.strip()
        else:
            return
        authorized = headers.get("cf-access-client-id") == "fixture-client"
        authorized &= headers.get("cf-access-client-secret") == "fixture-secret"
        if not authorized or path == "/deny":
            self.connection.sendall(b"HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\n\r\n")
            return
        if path == "/redirect":
            location = f"http://127.0.0.1:{self.server.server_address[1]}/leaked"
            self.connection.sendall(
                f"HTTP/1.1 302 Found\r\nLocation: {location}\r\nContent-Length: 0\r\n\r\n".encode()
            )
            return
        if path == "/leaked":
            # Following the redirect must make the test fail, even on the same host.
            self.connection.sendall(b"HTTP/1.1 500 Redirect Followed\r\nContent-Length: 0\r\n\r\n")
            return
        key = headers["sec-websocket-key"]
        accept = base64.b64encode(hashlib.sha1((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()).digest())
        self.connection.sendall(
            b"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
            + b"Sec-WebSocket-Accept: " + accept + b"\r\n\r\n"
        )
        if path == "/text":
            self.connection.sendall(frame(1, b"unexpected text"))
            return
        if path == "/close":
            self.connection.sendall(frame(8, struct.pack("!H", 1000)))
            return
        if path == "/push":
            payload = bytes(range(256)) * 4096
            self.connection.sendall(frame(2, payload[:100003], final=False))
            self.connection.sendall(frame(0, payload[100003:]))
        while True:
            first, second = read_exact(self.rfile, 2)
            opcode = first & 0x0F
            size = second & 0x7F
            if size == 126:
                size = struct.unpack("!H", read_exact(self.rfile, 2))[0]
            elif size == 127:
                size = struct.unpack("!Q", read_exact(self.rfile, 8))[0]
            if size > 4 * 1024 * 1024 or not second & 0x80:
                return
            mask = read_exact(self.rfile, 4)
            payload = read_exact(self.rfile, size)
            payload = bytes(value ^ mask[index % 4] for index, value in enumerate(payload))
            if opcode == 8:
                return
            if opcode == 9:
                self.connection.sendall(frame(10, payload))
            elif opcode == 2:
                # Frame boundaries deliberately differ from the TCP client's write boundaries.
                midpoint = len(payload) // 2
                self.connection.sendall(frame(2, payload[:midpoint]))
                self.connection.sendall(frame(2, payload[midpoint:]))
            elif opcode != 10:
                return


class Server(socketserver.ThreadingTCPServer):
    daemon_threads = True
    allow_reuse_address = True


if __name__ == "__main__":
    with Server(("127.0.0.1", 0), Handler) as server:
        print(server.server_address[1], flush=True)
        server.serve_forever()
