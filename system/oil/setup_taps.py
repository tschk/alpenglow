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
