import json
import os
import socket
import threading
import time

import requests

LOGFILE = os.getenv("LOGFILE", "/app/llama-server.log")

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

buffer = [{
    "message": 'Collecting Logs for {HOSTNAME} just started'.format(HOSTNAME = HOSTNAME),
    "hostname": HOSTNAME,
    "service": SERVICE
}]


def sender():
    while True:
        time.sleep(SEND_INTERVAL)

        if not buffer:
            continue

        payload = buffer.copy()
        buffer.clear()

        try:
            print("Try sending Logs to New Relic...")
            requests.post(
                ENDPOINT,
                headers={
                    "Api-Key": LICENSE_KEY,
                    "Content-Type": "application/json"
                },
                json=payload,
                timeout=10,
            )
        except Exception as e:
            print(f"New Relic upload failed: {e}")


def follow(filename):
    print('Following Logfile at {filename}'.format(filename = filename))
    with open(filename, "r") as f:
        f.seek(0, 0)

        while True:
            line = f.readline()

            if not line:
                time.sleep(0.2)
                continue

            buffer.append({
                "message": line.rstrip(),
                "hostname": HOSTNAME,
                "service": SERVICE
            })


if __name__ == "__main__":

    if not LICENSE_KEY:
        print("NEW_RELIC_LICENSE_KEY not set")
        exit(0)

    print('Log Collector started on {HOSTNAME}...'.format(HOSTNAME = HOSTNAME))

    threading.Thread(target=sender, daemon=True).start()

    follow(LOGFILE)