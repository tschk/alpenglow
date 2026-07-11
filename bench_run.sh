#!/bin/bash
cd system/oil

# Use time command to measure the `oil update` process directly.
# First, create 10 slow taps that take 0.5 seconds each.
cat << 'PY_EOF' > test_server.py
import time
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import threading

class SlowHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        time.sleep(0.5)
        self.send_response(200)
        self.send_header('Content-type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps([]).encode('utf-8'))

    def log_message(self, format, *args):
        pass

def run():
    server = HTTPServer(('localhost', 8080), SlowHandler)
    server.serve_forever()

if __name__ == '__main__':
    t = threading.Thread(target=run)
    t.daemon = True
    t.start()
    while True:
        time.sleep(1)
PY_EOF

python3 test_server.py &
SERVER_PID=$!
sleep 1

cat << 'PY_EOF' > setup_taps.py
import json
import os

taps = {}
for i in range(1, 11):
    name = f"tap{i}"
    taps[name] = {"name": name, "url": f"http://localhost:8080/{name}"}

home = os.environ.get("HOME")
os.makedirs(f"{home}/.oil", exist_ok=True)
with open(f"{home}/.oil/taps.json", "w") as f:
    json.dump(taps, f)
PY_EOF
python3 setup_taps.py

echo "Compiling..."
cargo build --features wax

echo "Measuring original (should take ~5s due to 10 * 0.5s)..."
# Note: apk update will fail quickly, but then it proceeds to update taps.
time cargo run --features wax -- update || true

kill $SERVER_PID
