#!/usr/bin/env python3
"""Create a consistent, private usage-only snapshot for Windows parity checks."""
from datetime import datetime, timezone
from pathlib import Path
import hashlib
import json
import os
import sqlite3

os.umask(0o077)
repo = Path(__file__).resolve().parents[2]
source = Path.home() / "Library/Application Support/dev.codexisland.CodexIsland/usage-history.sqlite3"
stamp = datetime.now(timezone.utc)
output = repo / "windows/artifacts" / ("mac-history-" + stamp.strftime("%Y%m%dT%H%M%SZ"))
output.mkdir()
snapshot = output / "mac-usage-history.sqlite3"
with sqlite3.connect(source.as_uri() + "?mode=ro", uri=True) as original:
    with sqlite3.connect(snapshot) as target:
        original.backup(target)
        target.execute("PRAGMA journal_mode=DELETE")
        assert target.execute("PRAGMA quick_check").fetchone() == ("ok",)
        providers = target.execute("SELECT source,provider,count(*),sum(input_tokens+output_tokens+cache_creation_tokens+cache_read_tokens) FROM usage_events GROUP BY source,provider").fetchall()
        historical = target.execute("SELECT provider,count(*),sum(tokens) FROM historical_daily_usage GROUP BY provider").fetchall()
price_cache = Path.home() / "Library/Caches/dev.codexisland.CodexIsland/model-prices.json"
payload = json.loads(price_cache.read_text())["payload"]
prices = output / "model-prices-payload.json"
prices.write_text(json.dumps(payload, separators=(",", ":")))
captured = datetime.now(timezone.utc)
hashes = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in (snapshot, prices)}
sources = {str(p.relative_to(repo)): hashlib.sha256(p.read_bytes()).hexdigest()
           for p in (repo / "Sources/Cost").glob("*.swift")}
manifest = {"capturedAt": captured.isoformat(), "nowUnix": captured.timestamp(), "timezone": "America/Chicago",
            "sha256": hashes, "sourceCodeSha256": sources, "eventTotals": providers, "historicalTotals": historical}
(output / "manifest.json").write_text(json.dumps(manifest, indent=2))
print(json.dumps({"snapshot": str(output), "eventTotals": providers, "historicalTotals": historical, "sha256": hashes}, indent=2))
