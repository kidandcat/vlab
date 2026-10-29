#!/usr/bin/env bash
# End-to-end check of vlab-server: cairn roundtrip across a restart,
# HTTP/1.1 keep-alive, a chunked body, and (when REQUIRE_FRONT=1) the wasm assets.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
BIN=${BIN:-$ROOT/.lake/build/bin/vlab-server}
DATA=$(mktemp -d)
PORT=${PORT:-18080}
STATIC=${STATIC:-$ROOT/web/dist}
PID=""

cleanup() {
  if [ -n "$PID" ]; then
    kill "$PID" 2>/dev/null || true
    wait "$PID" 2>/dev/null || true
  fi
  rm -rf "$DATA"
}
trap cleanup EXIT

start() {
  "$BIN" --data "$DATA/cairn" --host 127.0.0.1 --port "$PORT" --static "$STATIC" \
    >"$DATA/server.log" 2>&1 &
  PID=$!
  for _ in $(seq 1 80); do
    if curl -sf "http://127.0.0.1:$PORT/health" >/dev/null; then
      return 0
    fi
    if ! kill -0 "$PID" 2>/dev/null; then
      echo "server exited"
      cat "$DATA/server.log"
      exit 1
    fi
    sleep 0.1
  done
  echo "server did not answer"
  cat "$DATA/server.log"
  exit 1
}

stop() {
  kill "$PID" 2>/dev/null || true
  wait "$PID" 2>/dev/null || true
  PID=""
}

fail() {
  echo "e2e failed: $*"
  echo "----- server log -----"
  cat "$DATA/server.log" || true
  exit 1
}

start
HEALTH=$(curl -sf "http://127.0.0.1:$PORT/health") || fail "health"
python3 -c 'import json,sys; h=json.loads(sys.argv[1]); assert h["ok"] is True and h["boots"]==1 and h["http"]=="std" and h["toolchain"]=="4.35.0" and h.get("version"), h' "$HEALTH"

NOTE=$(curl -sf -X POST "http://127.0.0.1:$PORT/api/notes" \
  -H 'Content-Type: application/json' \
  --data '{"text":"hello \"cairn\""}') || fail "post"
ID=$(python3 -c 'import json,sys; n=json.loads(sys.argv[1]); assert n["text"]=="hello \"cairn\"" and n["version"]==1 and n["tookNs"]>=0; print(n["id"])' "$NOTE")

LIST=$(curl -sf "http://127.0.0.1:$PORT/api/notes") || fail "list"
python3 -c 'import json,sys; rows=json.loads(sys.argv[1])["notes"]; assert len(rows)==1 and rows[0]["id"]==sys.argv[2]' "$LIST" "$ID"

ONE=$(curl -sf "http://127.0.0.1:$PORT/api/notes/$ID") || fail "get"
python3 -c 'import json,sys; n=json.loads(sys.argv[1]); assert n["id"]==sys.argv[2]' "$ONE" "$ID"

CODE=$(curl -s -o /dev/null -w '%{http_code}' -X POST "http://127.0.0.1:$PORT/api/notes" --data '{"text":""}')
[ "$CODE" = "400" ] || fail "empty note status $CODE"

python3 - <<PY || fail "keepalive or chunked"
import json, socket, sys
host, port = "127.0.0.1", int("$PORT")
s = socket.create_connection((host, port), timeout=5)
req = (
    "GET /health HTTP/1.1\r\nHost: localhost\r\n\r\n"
    "GET /health HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n"
)
s.sendall(req.encode())
data = b""
s.settimeout(3)
while True:
    try:
        chunk = s.recv(4096)
    except socket.timeout:
        break
    if not chunk:
        break
    data += chunk
text = data.decode("utf-8", "replace")
if text.count("HTTP/1.1 200") != 2:
    sys.exit(f"keep-alive responses:\n{text}")
body = '{"text":"chunked"}'
chunked = (
    "POST /api/notes HTTP/1.1\r\nHost: localhost\r\nTransfer-Encoding: chunked\r\n"
    "Content-Type: application/json\r\nConnection: close\r\n\r\n"
    f"{len(body):x}\r\n{body}\r\n0\r\n\r\n"
)
s = socket.create_connection((host, port), timeout=5)
s.sendall(chunked.encode())
data = b""
s.settimeout(3)
while True:
    try:
        chunk = s.recv(4096)
    except socket.timeout:
        break
    if not chunk:
        break
    data += chunk
text = data.decode("utf-8", "replace")
if "HTTP/1.1 200" not in text or "chunked" not in text:
    sys.exit(f"chunked response:\n{text}")
head, _, raw = text.partition("\r\n\r\n")
json.loads(raw)
print("keepalive and chunked ok")
PY

if [ "${REQUIRE_FRONT:-0}" = "1" ]; then
  curl -sf "http://127.0.0.1:$PORT/uvl.wasm" -o "$DATA/app.wasm" || fail "wasm download"
  python3 -c 'import sys; d=open(sys.argv[1],"rb").read(4); assert d==b"\0asm", d' "$DATA/app.wasm"
  curl -sf "http://127.0.0.1:$PORT/" | grep -q 'id="app"' || fail "index"
  CODE=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/nope")
  [ "$CODE" = "404" ] || fail "missing route status $CODE"
fi

stop
start
HEALTH2=$(curl -sf "http://127.0.0.1:$PORT/health") || fail "health after restart"
python3 -c 'import json,sys; h=json.loads(sys.argv[1]); assert h["boots"]==2 and h["notes"]==2, h' "$HEALTH2"
AGAIN=$(curl -sf "http://127.0.0.1:$PORT/api/notes/$ID") || fail "note after restart"
python3 -c 'import json,sys; assert json.loads(sys.argv[1])["text"]=="hello \"cairn\""' "$AGAIN"
python3 - <<PY || fail "sandbox"
import json, urllib.request
base = "http://127.0.0.1:$PORT"
def call(method, path, body=None):
    data = body.encode() if body is not None else None
    req = urllib.request.Request(base + path, data=data, method=method)
    try:
        with urllib.request.urlopen(req, timeout=10) as res:
            return res.status, res.read().decode()
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()
st, created = call("POST", "/api/sandboxes", "fuel 1000\nmemory 131072\ncalls 4\nfs-read\n")
assert st == 200, created
a = json.loads(created)["id"]
st, created = call("POST", "/api/sandboxes", "fuel 50\nmemory 131072\ncalls 4\n")
assert st == 200, created
b = json.loads(created)["id"]
assert a != b
st, add = call("POST", f"/api/sandboxes/{a}/exec", "example add")
assert st == 200 and '"value":"42"' in add, add
st, oob = call("POST", f"/api/sandboxes/{a}/exec", "example oob")
assert st == 200 and "bounds" in oob, oob
st, loop = call("POST", f"/api/sandboxes/{b}/exec", "example loop")
assert st == 200 and "outOfFuel" in loop, loop
st, host = call("POST", f"/api/sandboxes/{b}/exec", "example host")
assert st == 200 and "deny fs_read" in host, host
st, audit_a = call("GET", f"/api/sandboxes/{a}/audit")
assert st == 200 and "trap bounds" in audit_a and "load?_inRange" in audit_a, audit_a
st, audit = call("GET", f"/api/sandboxes/{b}/audit")
assert st == 200 and "deny fs_read" in audit and "fsReadOk_grant" in audit, audit
assert "trap outOfFuel" in audit and "evalList_zero" in audit, audit
assert "perform_allow" not in audit and "perform_allow" not in audit_a
st, _ = call("DELETE", f"/api/sandboxes/{a}")
assert st == 200
st, again = call("POST", f"/api/sandboxes/{a}/exec", "example add")
assert st == 404, again
st, still = call("GET", f"/api/sandboxes/{b}/audit")
assert "deny fs_read" in still
print(f"sandbox ok a={a} b={b}")
PY
echo "e2e ok boots=2 notes=2 id=$ID"
echo "----- timings -----"
python3 - <<PY
import json, time, urllib.request
base = "http://127.0.0.1:$PORT"
def post(text):
    data = json.dumps({"text": text}).encode()
    req = urllib.request.Request(base + "/api/notes", data=data, headers={"Content-Type": "application/json"})
    t = time.perf_counter()
    with urllib.request.urlopen(req, timeout=10) as res:
        body = json.loads(res.read().decode())
    wall = (time.perf_counter() - t) * 1e6
    return body["tookNs"], wall
samples = [post(f"sample {i}") for i in range(5)]
print("post tookNs " + " ".join(str(a) for a, _ in samples))
print("post wallUs " + " ".join(str(int(b)) for _, b in samples))
t = time.perf_counter()
urllib.request.urlopen(base + "/health", timeout=10).read()
print(f"health wallUs {int((time.perf_counter()-t)*1e6)}")
PY
