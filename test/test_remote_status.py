"""Exercise the Pascal bridge against a real local TCP listener."""

import json
import socket
import subprocess
import sys
import time
import unittest

HARNESS = sys.argv[1]


class RemoteStatusTest(unittest.TestCase):
    def test_listener_can_start_after_game(self):
        with socket.socket() as listener:
            listener.bind(("127.0.0.1", 0))
            listener.settimeout(8)
            process = subprocess.Popen(
                [HARNESS, str(listener.getsockname()[1])],
                stdin=subprocess.PIPE,
                text=True,
            )
            self.addCleanup(process.kill)
            process.stdin.write("start\n")
            process.stdin.flush()
            time.sleep(0.5)
            listener.listen()
            connection, _ = listener.accept()
            with connection:
                connection.settimeout(8)
                with connection.makefile("r", encoding="utf-8") as stream:
                    status = json.loads(stream.readline())
                    self.assertEqual(status["state"], "playing")
                    self.assertEqual(status["artist"], "Björk")
            process.stdin.write("exit\n")
            process.stdin.flush()
            self.assertEqual(process.wait(timeout=3), 0)
            process.stdin.close()

    def test_lifecycle_and_reconnect(self):
        with socket.socket() as listener:
            listener.bind(("127.0.0.1", 0))
            listener.listen()
            listener.settimeout(8)
            process = subprocess.Popen(
                [HARNESS, str(listener.getsockname()[1])],
                stdin=subprocess.PIPE,
                text=True,
            )
            self.addCleanup(process.kill)

            def command(value):
                process.stdin.write(value + "\n")
                process.stdin.flush()

            def receive(stream, expected):
                while True:
                    line = stream.readline()
                    self.assertTrue(line, "bridge disconnected unexpectedly")
                    status = json.loads(line)
                    if status["state"] == expected:
                        return status

            connection, _ = listener.accept()
            with connection:
                connection.settimeout(8)
                stream = connection.makefile("r", encoding="utf-8")
                self.assertEqual(receive(stream, "idle")["song_file"], "")
                command("start")
                playing = receive(stream, "playing")
                self.assertEqual(playing["artist"], "Björk")
                self.assertEqual(playing["title"], 'A "song"')
                self.assertEqual(playing["song_file"], "/songs/ä.txt")
                command("pause")
                self.assertEqual(receive(stream, "paused")["title"], 'A "song"')
                command("resume")
                receive(stream, "playing")
                stream.close()
                connection.shutdown(socket.SHUT_RDWR)

            connection, _ = listener.accept()
            with connection:
                connection.settimeout(8)
                with connection.makefile("r", encoding="utf-8") as stream:
                    self.assertEqual(receive(stream, "playing")["artist"], "Björk")
                    command("stop")
                    self.assertEqual(receive(stream, "idle")["title"], "")
            command("exit")
            self.assertEqual(process.wait(timeout=3), 0)
            process.stdin.close()


if __name__ == "__main__":
    unittest.main(argv=[sys.argv[0]])
