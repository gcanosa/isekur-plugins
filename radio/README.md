# The radio plugin's station list

`stations.tsv` is the list every iSekur with the radio plugin fetches (when it is older than the plugin's `refresh` setting,
24 hours by default; `/radio refresh` fetches it now). The plugin keeps the last good copy, so it works offline and a broken
or empty reply never replaces it. Point `stations` at your own list (an https address of a file in this format) with
`/plugin set radio stations <address>`.

One station per line: `name`, a TAB, and the address. Lines starting with `#` are comments.

- a YouTube channel's live: `https://www.youtube.com/@name/live`. That address always means the channel's current stream, so a
  stream that restarts under a new video address keeps working. It needs yt-dlp on the machine iSekur runs on.
- a plain radio stream: any `http(s)` address of an MP3, AAC or Ogg stream (SomaFM, Radio Paradise, an Icecast or SHOUTcast
  station). Playing it directly from the webchat (`source` direct) needs `https`.

## Keeping it free of dead streams

`check.py` tests every station like the plugin plays it (yt-dlp for a YouTube live, ffmpeg for a plain stream) and counts the
checks that failed in a row in `health.json`. A station that fails 3 in a row moves to `removed.tsv`; a removed one that works
again comes back. If most stations fail at once the machine running the check is the problem (YouTube blocks many datacenter
addresses), so it changes nothing and exits 2. The `radio stations` workflow runs it every day; you can also run
`python3 radio/check.py` yourself (`--dry` shows what it would do, `--self-test` checks its rules).

To add a station, send a line for `stations.tsv`. To bring one back by hand, move its line from `removed.tsv`.
