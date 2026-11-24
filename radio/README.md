# The radio plugin's station list

`stations.tsv` is the list every iSekur with the radio plugin fetches (when it is older than the plugin's `refresh` setting,
24 hours by default; `/radio refresh` fetches it now). The plugin keeps the last good copy, so it works offline and a broken
or empty reply never replaces it. Point `stations` at your own list (an https address of a file in this format) with
`/plugin set radio stations <address>` (`off`: only the list built into the plugin).

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

## The directory (Browse and Search)

Besides this list, the plugin's Browse and Search tabs use the [Radio Browser](https://www.radio-browser.info) directory (about 50,000
stations, kept by its community): `directory` is its server (`https://de1.api.radio-browser.info`), and `off` turns Browse and Search off (`/plugin set radio directory off`; with no value it goes back to the default).
It is a third party: what you search for and the stations you play are known to it (playing one counts a listen, which is what makes its
votes and trends), nothing else is sent, and the requests say `iSekur-radio`. Its stations are not checked by `check.py`: one that doesn't
play is reported with the reason and the next one in the list is tried. `Add` keeps a station in Mine with its directory id, so it is found
again when its stream address changes.

## Where the audio goes

By default (`source` direct) the webchat's own browser connects to an https station, so with iSekur on a server the audio goes from the
station to you and not through the server; the station sees your address, not the server's. YouTube channels and plain http stations (a
page on https can't play them) go through the machine iSekur runs on, as does the terminal's speakers. If the browser can't play a station
(a format it lacks such as some HLS streams, a network that blocks it, no sound within 15 seconds) the plugin tries it through that machine
before moving on. `/plugin set radio source host` sends everything through the machine.
