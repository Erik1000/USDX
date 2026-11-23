# Local playback status bridge

This is the first part of the companion-service integration. It reports singing
screen playback; it does not yet accept commands or manage a request queue.

Start a TCP listener on `127.0.0.1`, then set `USDX_STATUS_PORT` to its port
before starting USDX. Without a valid port the bridge is disabled. USDX connects
to the listener and sends UTF-8 JSON objects, one per line:

```json
{"type":"status","state":"playing","artist":"Queen","title":"Example","song_file":"/songs/example/song.txt"}
```

The state is `idle`, `playing`, or `paused`. Song fields are empty while idle;
`song_file` is the game machine's local song text-file path, not a USDB ID.
Only singing mode is reported. The connection is local to the game machine,
and the receiving service should not expose song paths to browser clients.

Snapshots are sent on changes and at least every two seconds while connected.
On disconnection USDX retries and sends its latest snapshot after reconnecting.
This is a current-state feed, not a durable event log: rapid transitions can
be coalesced, and an unavailable listener misses intermediate states. The service
should mark the game offline when the connection closes or heartbeats stop.
The bridge performs network I/O on a worker thread.
