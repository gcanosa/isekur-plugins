# iSekur plugins

The plugin catalog of [iSekur](https://github.com/gcanosa/iSekur), the terminal IRC client with a
built-in webchat. Nothing here is installed by default: in iSekur, `/plugin` opens the plugin
window (or the puzzle button in the webchat), and `/plugin install name` fetches one from here,
checks its sha256 against `index.json`, and turns it on.

| Plugin | Version | API | What it does |
|---|---|---|---|
| **autoaway** | 1.4 | 1 | Away when you're idle or nothing is attached, back when you return; on or off per network, away and back announced if you like. |
| **awaylog** | 1.4 | 1 | Your highlights and private messages while you were away or detached, summed up in each network's console when you come back, with a pointer in the tab you're on. |
| **lolcat** | 1.0 | 8 | The messages in the channels and queries where you turn it on, in color on your screens only: nothing is sent in color and the logs keep the plain text. `pattern`: `rainbow`, `theme` (your theme's nick colors), `pastel`, `fire`, `ice`, `forest`, `neon`, `sunset` or `random`; `lines`: everyone's, only yours or only the others'; a color per letter or per word (`by`), `spread` letters per step, and with `shift` the colors flow down the lines like lolcat. On a light theme the colors are darkened to read. `/lolcat` shows every pattern. |
| **keepnick** | 1.0 | 4 | Takes your nick back once it's free: when you see its holder leave, and by asking the server every 30 seconds (`every`). A `/nick` you type yourself stops it on that network until you reconnect. |
| **pasteguard** | 1.0 | 4 | A paste of 3 lines or more (`lines`) into a channel or a query goes to a pastebin (paste.rs by default, `service`) and only its link is said. If the upload fails nothing is sent: `/pasteguard send` or `/pasteguard retry`. |
| **autosort** | 1.1 | 6 | Keeps the tabs grouped by network, each network's status tab first, then its channels and queries by name. A tab you `/move` (or drag) stays where you put it and the others sort around it, until iSekur restarts. |
| **tts** | 1.2 | 7 | Reads messages aloud: with this machine's speech engine (`say` on macOS; `spd-say`, `espeak-ng`, `flite` or `festival` on Linux and BSD), in the webchat's browser voice, or both (`where`). `language` (everywhere, or per network or channel) picks the language. Only the networks and channels you enable. `/tts engines` shows which engines this system has; `/tts test` says a line. |
| **screensaver** | 1.1 | 5 | After `idle` minutes (10) without a key, click or mouse move, the terminal and the webchat show digital rain, floating particles or a quiet sky of drifting stars (`saver`: `matrix`, `particles`, `stars` or `random`) until you touch something. With `lock` on, waking asks for the lock password (the one `/lock` sets). Never while nobody is at a terminal or the webchat. `/screensaver [name]` starts one now. |
| **pmguard** | 1.1 | 9 | Private messages from people you haven't let through are held, not opened: you're told once and they get a notice (the `reply` setting, empty for none). `/pmguard allow nick`, or **Allow PMs** in the nicklist's right click, opens the query with what they said; **Remove from PM list** (`/pmguard deny nick`) holds them again. People you `/msg` yourself, services and notices go through; `channels on` lets in people who share a channel with you. |
| **preview** | 1.4 | 2 | Under links people post, in the webchat: a card with the page's title, description and picture, the picture itself for image links, and a player for audio and video links (mp3, ogg, m4a, mp4, webm...). In the terminal, the title and description as text. |
| **push** | 1.0 | 2 | Your highlights and private messages pushed to your phone, tablet or browser while you're away or nothing is attached: ntfy (no account: the ntfy app or ntfy.sh in a browser, `/plugin set push topic <name>`) or a Telegram bot. `/push test` checks it. |
| **proxy** | 1.0 | 3 | Connects the networks you pick through a SOCKS4/SOCKS5 or HTTP proxy, or an SSH jump host (`ssh -W`); the others stay direct. |
| **remind** | 1.0 | 1 | `/remind 10m check the build`, `/remind 1h30m ...`, `/remind 18:30 call home`: shown in that tab and the one you're on; saved, so one due while iSekur was off shows when it starts. `/remind` lists them, `/remind del 2`. |
| **seen** | 1.3 | 1 | `/seen nick`: when and where someone was last seen talking, joining, leaving, quitting or renaming; answers `!seen` where you turn it on. |

```
/plugin available
/plugin install seen
/plugin set seen@sekurnet reply on
/plugin update
```

All of these are official: made for iSekur by its author, Gerardo Canosa. Each one's About (in the
plugin windows) says who made a plugin and how to reach them.

Plugins are Lua 5.4, each in its own sandbox: no files, programs or sockets of their own (`isekur.http` fetches web pages for them, never from your LAN).
[WRITING.md](WRITING.md) is the guide for writing one (events, the `isekur` API, settings,
the catalog's rules). New plugins and fixes are welcome as pull requests; `python3 check.py`
must pass.

GPL-3.0-or-later, like iSekur.
