"""
Minimal stand-in for the search service.

Serves queries from an in-memory index loaded from object storage on startup.
Index load is simulated here; in production it takes ~14 minutes per replica
against a 4 TB shard.
"""
import json
import os
import random
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

INDEX_LOAD_SECONDS = int(os.environ.get("INDEX_LOAD_SECONDS", "90"))
SHARD_ID = os.environ.get("SHARD_ID", "0")
POD_NAME = os.environ.get("POD_NAME", "local")

STATE = {"index_loaded": False, "docs": 0, "started": time.time()}
INGEST_BUFFER = []
BUFFER_LOCK = threading.Lock()


def load_index():
    """Pull this replica's shard from object storage into memory."""
    time.sleep(INDEX_LOAD_SECONDS)
    STATE["docs"] = 4_200_000
    STATE["index_loaded"] = True


def search(query):
    if not STATE["index_loaded"]:
        # Index still loading. Fall back to a cold scan of whatever is resident
        # so the request returns something rather than erroring.
        time.sleep(random.uniform(1.5, 4.0))
        return {"hits": [], "cold": True}
    time.sleep(random.uniform(0.02, 0.09))
    return {
        "hits": [{"doc": f"doc-{i}", "score": round(1.0 / (i + 1), 4)} for i in range(10)],
        "cold": False,
    }


def ingest(batch):
    """Write path. Merges new documents into the live index segment."""
    with BUFFER_LOCK:
        INGEST_BUFFER.extend(batch)
        if len(INGEST_BUFFER) > 500:
            # Segment merge: holds the lock and churns page cache.
            time.sleep(2.5)
            STATE["docs"] += len(INGEST_BUFFER)
            INGEST_BUFFER.clear()
    return {"accepted": len(batch)}


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _reply(self, code, body):
        payload = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self):
        if self.path.startswith("/healthz"):
            self._reply(200, {"status": "ok", "pod": POD_NAME, "shard": SHARD_ID})
        elif self.path.startswith("/search"):
            query = self.path.split("q=")[-1] if "q=" in self.path else ""
            self._reply(200, search(query))
        elif self.path.startswith("/metrics"):
            self._reply(200, {
                "index_loaded": STATE["index_loaded"],
                "docs": STATE["docs"],
                "uptime_seconds": int(time.time() - STATE["started"]),
                "ingest_buffer": len(INGEST_BUFFER),
            })
        else:
            self._reply(404, {"error": "not found"})

    def do_POST(self):
        if self.path.startswith("/ingest"):
            length = int(self.headers.get("Content-Length", 0))
            raw = self.rfile.read(length) or b"[]"
            self._reply(202, ingest(json.loads(raw)))
        else:
            self._reply(404, {"error": "not found"})

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    threading.Thread(target=load_index, daemon=True).start()
    ThreadingHTTPServer(("0.0.0.0", 8080), Handler).serve_forever()
