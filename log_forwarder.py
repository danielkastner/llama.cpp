#!/usr/bin/env python3

import os
import signal
import socket
import sys
import threading
import time
import urllib.request
import json

LICENSE_KEY = os.getenv("NEW_RELIC_LICENSE_KEY")
ENDPOINT = os.getenv(
    "NEW_RELIC_LOG_ENDPOINT",
    "https://log-api.eu.newrelic.com/log/v1"
)

CONTAINER_ID = os.getenv("CONTAINER_ID", "unknown")
CONTAINER_NAME = 'vastai-{CONTAINER_ID}'.format(CONTAINER_ID = CONTAINER_ID)

HOSTNAME = os.getenv("NEW_RELIC_HOSTNAME", CONTAINER_NAME)
SERVICE = os.getenv("NEW_RELIC_SERVICE", "llama-server")

SEND_INTERVAL = int(os.getenv("NEW_RELIC_INTERVAL", "5"))

buffer = []
mode = sys.argv[1] if len(sys.argv) > 1 else "appending"
if mode == "initial":
    buffer.append({
        "message": 'Collecting Logs for {HOSTNAME} just started'.format(HOSTNAME = HOSTNAME),
        "hostname": HOSTNAME,
        "service": SERVICE
    })

lock = threading.Lock()
shutdown = threading.Event()

def flush():
    with lock:
        if not buffer:
            return

        payload = json.dumps(buffer.copy()).encode("utf-8")
        buffer.clear()

    try:
        req = urllib.request.Request(
            ENDPOINT,
            data=payload,
            headers={
                "Content-Type": "application/json",
                "Api-Key": LICENSE_KEY
            },
            method="POST"
        )

        with urllib.request.urlopen(req, timeout=10) as response:
            if response.status >= 300:
                print(
                    f"New Relic upload failed: {response.status_code} {response.text}",
                    file=sys.stderr,
                )

    except Exception as e:
        print(f"New Relic upload failed: {e}", file=sys.stderr)


def sender():
    while not shutdown.wait(SEND_INTERVAL):
        flush()


def signal_handler(signum, frame):
    print("Stopping log forwarder...", file=sys.stderr)

    shutdown.set()

    # Letzten Puffer senden
    flush()

    sys.exit(0)


def reader():
    for line in sys.stdin:
        line = line.rstrip("\r\n")

        if not line:
            continue

        with lock:
            buffer.append({
                "message": line,
                "hostname": HOSTNAME,
                "service": SERVICE,
                "timestamp": int(time.time() * 1000),
            })

        # Zeile weiterhin ausgeben
        print(line, flush=True)

    # stdin wurde geschlossen (Anwendung beendet)
    shutdown.set()
    flush()


if __name__ == "__main__":

    if not LICENSE_KEY:
        print("NEW_RELIC_LICENSE_KEY not set", file=sys.stderr)
        sys.exit(0)

    signal.signal(signal.SIGTERM, signal_handler)
    signal.signal(signal.SIGINT, signal_handler)

    threading.Thread(target=sender, daemon=True).start()

    reader()