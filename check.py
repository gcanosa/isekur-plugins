#!/usr/bin/env python3
# The catalog's rules, checked on every push: each index.json entry has its <name>/<name>.lua, the file's own
# "-- version:" line says the entry's version, its "-- author:" and "-- contact:" lines say the entry's author and
# contact, its sha256 is the entry's, and every plugin folder is in the index.
# iSekur refuses an install whose sha256 doesn't match, and offers an update only for a newer version.
import hashlib, json, os, re, sys

root = os.path.dirname(os.path.abspath(__file__))
idx = json.load(open(os.path.join(root, "index.json"), encoding="utf-8"))
bad, seen = [], set()
for e in idx:
    n = e.get("name", "")
    if not re.fullmatch(r"[A-Za-z0-9_-]{1,32}", n): bad.append(f"bad name {n!r}"); continue
    seen.add(n)
    for k in ("version", "api", "description", "author", "contact", "sha256"):
        if k not in e: bad.append(f"{n}: no {k}")
    path = os.path.join(root, n, n + ".lua")
    if not os.path.isfile(path): bad.append(f"{n}: no {n}/{n}.lua"); continue
    data = open(path, "rb").read()
    head = data.decode("utf-8", "replace").splitlines()[:20]
    hdr = lambda k: next((l[len(k) + 4:].strip() for l in head if l.startswith(f"-- {k}:")), "")
    for k in ("version", "author", "contact"):
        if hdr(k) != e.get(k): bad.append(f"{n}: the file says {k} {hdr(k)!r}, index.json {e.get(k)!r}")
    if "official" in e and not isinstance(e["official"], bool): bad.append(f"{n}: official must be true or false")
    if hashlib.sha256(data).hexdigest() != e.get("sha256"): bad.append(f"{n}: sha256 isn't the file's ({hashlib.sha256(data).hexdigest()})")
for d in sorted(os.listdir(root)):
    if os.path.isfile(os.path.join(root, d, d + ".lua")) and d not in seen: bad.append(f"{d}/ isn't in index.json")
print("\n".join(bad) if bad else f"ok: {len(idx)} plugins")
sys.exit(1 if bad else 0)
