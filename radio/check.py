#!/usr/bin/env python3
# Keeps the radio plugin's station list free of dead streams. For every station in stations.tsv (and removed.tsv) it asks
# the stream for a few seconds of audio the way the plugin does (yt-dlp for a YouTube channel's live, ffmpeg for a plain
# stream), and keeps a count of failed checks in a row in health.json. A station that fails FAILS_TO_PURGE times in a row
# moves to removed.tsv; a removed one that works again comes back. Run it from anywhere (a cron job, the repository's
# radio-stations workflow): python3 radio/check.py [--dry] ; --self-test checks the rules without the network.
# Needs yt-dlp and ffmpeg. If most stations fail at once the machine running this is probably blocked (YouTube blocks many
# datacenter addresses): nothing is changed and it exits 2, so a bad run never empties the list.
import concurrent.futures, datetime, json, os, shutil, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
FAILS_TO_PURGE = 3
RETRY_AFTER = 8  # seconds before a failed check is tried once more: a hiccup isn't a dead station
BLOCKED_ABOVE = 0.5  # more than this fraction failing: the checker is the problem, not the stations


def read_tsv(path):
    head, rows = [], []
    if os.path.exists(path):
        for line in open(path, encoding="utf-8").read().splitlines():
            if line.startswith("#"):
                if not rows:
                    head.append(line)  # the comments before the first station stay as they are
            elif "\t" in line:
                name, url = line.split("\t", 1)
                rows.append((name.strip(), url.strip()))
    return head, rows


def write_tsv(path, head, rows):
    with open(path, "w", encoding="utf-8") as f:
        f.write("".join(h + "\n" for h in head) + "".join(f"{n}\t{u}\n" for n, u in rows))


def is_youtube(url):
    try:
        return "youtu" in url.split("/")[2]
    except IndexError:
        return False


def check(url):
    """True when the stream gives audio (a failure is tried once more after RETRY_AFTER seconds)."""
    if check_once(url):
        return True
    time.sleep(RETRY_AFTER)
    return check_once(url)


def check_once(url):
    try:
        if is_youtube(url):
            r = subprocess.run(["yt-dlp", "--no-warnings", "--no-playlist", "-f", "234/233/bestaudio", "-g", "--", url],
                               capture_output=True, text=True, timeout=120)
            return r.returncode == 0 and r.stdout.strip().startswith("http")
        r = subprocess.run(["ffmpeg", "-nostdin", "-loglevel", "error", "-protocol_whitelist", "http,https,tcp,tls,crypto",
                            "-t", "4", "-i", url, "-vn", "-f", "null", "-"], capture_output=True, timeout=45)
        return r.returncode == 0
    except (subprocess.TimeoutExpired, OSError, IndexError):
        return False


def missing_tools(urls):
    """The programs the checks need and this machine lacks: a missing one would make every station that needs it look dead."""
    need = {"ffmpeg"} if any(not is_youtube(u) for u in urls) else set()
    if any(is_youtube(u) for u in urls):
        need.add("yt-dlp")
    return sorted(t for t in need if not shutil.which(t))


def apply(active, removed, health, results, today):
    """The rules. results: url -> bool. Returns (active, removed, health, moved_out, moved_back); the inputs aren't changed."""
    health = {u: dict(h) for u, h in health.items()}
    out, back, keep_a, keep_r = [], [], [], []
    for name, url in active:
        h = health.setdefault(url, {"fails": 0})
        if results.get(url, True):
            h["fails"], h["last_ok"] = 0, today
        else:
            h["fails"] += 1
            h["last_fail"] = today
        if h["fails"] >= FAILS_TO_PURGE:
            out.append((name, url))
            keep_r.append((name, url))
        else:
            keep_a.append((name, url))
    for name, url in removed:
        h = health.setdefault(url, {"fails": FAILS_TO_PURGE})
        if results.get(url, False):
            h["fails"], h["last_ok"] = 0, today
            back.append((name, url)), keep_a.append((name, url))
        else:
            h["fails"] = h.get("fails", FAILS_TO_PURGE) + 1
            keep_r.append((name, url))
    return keep_a, keep_r, health, out, back


def self_test():
    a = [("A", "https://a/x"), ("B", "https://b/x"), ("C", "https://c/x")]
    r, h = [("Old", "https://old/x")], {}
    for day in range(1, 3):  # two failures of B: still active
        a2, _, h, out, _ = apply(a, r, h, {"https://a/x": True, "https://b/x": False, "https://c/x": True, "https://old/x": False}, f"d{day}")
        assert [n for n, _ in a2] == ["A", "B", "C"] and not out
    a2, r2, h, out, _ = apply(a, r, h, {"https://a/x": True, "https://b/x": False, "https://c/x": True, "https://old/x": False}, "d3")
    assert [n for n, _ in a2] == ["A", "C"] and out == [("B", "https://b/x")] and ("B", "https://b/x") in r2  # the third in a row purges it
    a3, r3, h, _, _ = apply(a2, r2, h, {"https://a/x": True, "https://c/x": True, "https://b/x": True, "https://old/x": True}, "d4")
    assert ("B", "https://b/x") in a3 and ("Old", "https://old/x") in a3 and not r3 and h["https://b/x"]["fails"] == 0  # working again: back
    a4, _, h2, _, _ = apply(a3, r3, h, {"https://a/x": False, "https://c/x": True, "https://b/x": True, "https://old/x": True}, "d5")
    assert ("A", "https://a/x") in a4 and h2["https://a/x"]["fails"] == 1  # one failure doesn't purge
    assert missing_tools(["https://a/x"]) in ([], ["ffmpeg"]) and missing_tools(["https://www.youtube.com/@x/live"]) in ([], ["yt-dlp"], ["ffmpeg", "yt-dlp"])
    print("ok: the rules hold")


def main():
    if "--self-test" in sys.argv:
        return self_test()
    dry = "--dry" in sys.argv
    sp, rp, hp = (os.path.join(HERE, f) for f in ("stations.tsv", "removed.tsv", "health.json"))
    ahead, active = read_tsv(sp)
    rhead, removed = read_tsv(rp)
    health = json.load(open(hp)) if os.path.exists(hp) else {}
    urls = [u for _, u in active + removed]
    lacking = missing_tools(urls)
    if lacking:
        print("not installed here: " + ", ".join(lacking) + ", so nothing is checked or changed")
        return 2
    with concurrent.futures.ThreadPoolExecutor(6) as ex:
        results = dict(zip(urls, ex.map(check, urls)))
    for n, u in active + removed:
        print(("ok    " if results[u] else "FAIL  ") + n)
    bad = sum(not results[u] for _, u in active)
    if active and bad / len(active) > BLOCKED_ABOVE:
        print(f"{bad} of {len(active)} stations failed: this machine looks blocked, so nothing is changed")
        return 2
    today = datetime.date.today().isoformat()
    active2, removed2, health2, out, back = apply(active, removed, health, results, today)
    for n, _ in out:
        print(f"purged: {n}")
    for n, _ in back:
        print(f"back:   {n}")
    if dry:
        return print("(dry run: nothing written)")
    write_tsv(sp, ahead, active2)
    write_tsv(rp, rhead, removed2)
    json.dump(health2, open(hp, "w"), indent=1, sort_keys=True)
    open(hp, "a").write("\n")


if __name__ == "__main__":
    sys.exit(main() or 0)
