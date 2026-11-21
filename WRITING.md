# Writing iSekur plugins

A plugin is one Lua 5.4 file, `<name>.lua` (letters, digits, `_`, `-`), in the `plugins` folder next
to your config (`~/.config/isekur/plugins/`). It runs once when it loads: there it declares its
settings, commands and event handlers. `/plugin enable <name>` loads it, `/plugin reload <name>`
loads it again after you edit it.

Put its version in a `-- version:` line near the top, and who made it in `-- author:` and
`-- contact:` lines (an email address or an https:// page). iSekur reads the version to tell an update in
the catalog (a newer version) from a file you edited yourself (same version, other contents); the plugin
windows' About shows the author and contact.

```lua
-- version: 1.0
-- author: Your Name
-- contact: you@example.org
-- hello.lua: /hello [nick], and a wave back at anyone who says "hi isekur"
isekur.setting("greeting", "Hello", "c", "what /hello says first")  -- per channel, network or global

isekur.command("hello", "[nick]", function(args, srv, target)
  if not srv then return "Use /hello in a channel" end  -- a returned string is shown as an error
  local who = args ~= "" and args or "everyone"
  isekur.say(srv, target, isekur.opt("greeting", srv, target) .. ", " .. who .. "!")
end)

isekur.on("message", function(e)
  if not e.self and e.text:lower():find("hi isekur", 1, true) then
    isekur.say(e.srv, e.target, "\x01ACTION waves at " .. e.nick .. "\x01")
  end
end)
```

## The sandbox

Only Lua's base library (without `load`, `loadfile`, `dofile`), `string`, `table`, `math` and `utf8`.
No `io`, `os`, `package`, `require` or `debug`. A call that runs too long (about 10 million Lua
instructions) is stopped with an error, and a plugin gets 32 MB of memory. Errors show in the main
window as `[name] error: ...`; after 5 in a row the plugin is unloaded until `/plugin reload`.
`print(...)` writes to the main window. Everything a plugin prints carries a badge with its name
(and `/plugin`'s own messages a `plugin` one), in the theme's `plugin` colors, so a line always
says where it came from.

## Settings

Options live in the config, one section per scope, and are looked up channel → network → global →
the default the plugin declared:

```ini
[plugin.hello]                  ; enabled = on: everywhere
greeting = Hi
[plugin.hello@sekurnet]         ; this network
greeting = Hey
[plugin.hello@sekurnet/#isekur] ; this channel (lowercase)
greeting = Welcome
```

`/plugin set hello@sekurnet/#isekur greeting Welcome` writes that last one.
`enabled` works the same way: a plugin is loaded when any of its sections has `enabled = on`, and its
events only come from the networks and channels where `enabled` resolves to on.

- `isekur.setting(key, default, scope, help, choices)`: declare an option. `help` is a short line the plugin
  windows show next to it: what it is and its unit ("minutes without typing; 0: never"). `scope` is `"g"` (global only), `"n"`
  (up to the network) or `"c"` (up to the channel, the default). The default's type is what
  `opt` returns: a boolean (`on`/`true`/`yes`/`1` are true), a number or a string. `choices`, a list of
  strings (`{"random", "matrix", "stars"}`), are the only values it takes: `/plugin set` refuses others, the
  terminal's plugin window steps through them with Space or Enter and the webchat's shows a list.
- `isekur.opt(key, srv, target)`: the option's value there; `srv`/`target` may be nil. `enabled` is
  always a boolean: whether the plugin is on there.
- `isekur.set(key, value, srv)`: writes one of the plugin's own settings, saved to the config like `/plugin set`:
  for that network (scope `"n"` or `"c"`, `srv` given) or everywhere. `nil` or `""` clears it. Never `enabled`, and an
  unknown `srv` is an error. For a list the user should see and edit in the plugin window (pmguard's `allowed`).

## Events

`isekur.on(event, function(e) ... end)`. `e.srv` (the network's name) and `e.target` (channel or
query nick) are set when the event has them.

| event | fields |
|---|---|
| `message` | `nick`, `text`, `self`, `hilight`, `notice`, `action`, `id` (for `isekur.embed`), `opened` (a private message that opens a new query tab). Return `true` to hide the line (and close the tab it opened). Your own lines only arrive when the server has echo-message |
| `join` | `nick`, `host`, `self` |
| `part` | `nick`, `reason`, `self`, `kick`, `by` (who kicked) |
| `quit` | `nick`, `host`, `reason` (no target: it's the whole network) |
| `nick` | `nick` (the old one), `new`, `self` (no target) |
| `away` | `away`: the server says you're away (306) or back (305) |
| `command` | `name`, `args`: you typed a /command (not one a plugin runs). Return `true` to take it over |
| `raw` | `cmd` (a numeric: `"303"`, `"433"`...), `args`: its parameters as on the wire, the last one always after a `:` (`"yournick :a b"`). Return `true` to hide it, and what iSekur does with it: only for replies to what your plugin sent |
| `paste` | `text`: lines pasted into a channel or a query (plain chat, no /commands), joined with `\n`. Return `true` to take them: nothing is sent. With a `paste` handler on in a tab, iSekur doesn't ask "Send N lines?" there |
| `show` | `nick`, `text`, `self`, `action`, `notice`: a message about to be shown in a tab (yours too, and history). Return a string to show that instead, in the terminal and the webchat only: the network got the original and the log keeps it. It runs again over the scrollback when a plugin is enabled, disabled, reloaded or has a setting changed, so a change shows on what is already there (`e.text` is always the original) |
| `nickmenu` | `nick`: you right-clicked a nick in the nicklist, or a query tab. Return `{{"Label", "/command ..."}, ...}` (up to 8) to add them to its menu, after a separator. Commands only, one line each, and not ones `isekur.exec` refuses or `/plugin`. A command ending in a space goes to the input line instead |
| `tick` | every second, no fields: check `isekur.opt("enabled", srv)` for the networks you act on |
| `connect` | iSekur is about to connect to the network (no target): the moment for `isekur.proxy` |
| `lock` | iSekur was just locked (Alt+S, `/lock`, `lock_idle`, a plugin's `isekur.lock()`), no fields. API 11 |
| `window` | a click, Enter or Esc in your `isekur.window`, and only your plugin gets it: `action` is `"pick"` (Enter or a double click on a row: `index`), `"button"` (`button`, its label, and `index`, the row the cursor is on), `"slider"` (the slider moved: `value`) or `"close"` (Esc, the ×: the window is already gone). No `srv`. API 12 |
| `attach`, `detach` | a terminal or a browser came back / nobody is attached any more |

## Calls

| call | what it does |
|---|---|
| `isekur.command(name, usage, fn)` | adds `/name`; `fn(args, srv, target)` gets the rest of the line, the tab's network (nil in the main window) and the tab's name. iSekur's own commands can't be replaced |
| `isekur.say(srv, target, text)` | says text (each line of it) in a channel or to a nick |
| `isekur.send(srv, line)` | a raw IRC line (one line) |
| `isekur.print(srv, target, text, note)` | shows text in that tab only (else the network's tab, else the main window); `note` true puts the INFO badge first |
| `isekur.exec(srv, target, "/cmd ...")` | runs a command as if typed in that tab (not `/plugin`, `/exec`, `/sh`, `/shell`, `/attach`, `/alias` or `/perform`; no `/set` of a security setting such as `exec_web`, `dcc_dir`, `web.*`, `perform` or `aliases.*`; `/dcc send` only a file in `dcc_dir`) |
| `isekur.http(url, fn, body)` | fetches an `https://` or `http://` URL in the background (with `body`, a POST of it as `text/plain`) (redirects followed, the first 512 KB of the body, a 15s timeout); `fn(r)` gets `r.status` (0 when it failed), `r.type` (the content type, lowercase, no `; charset`), `r.body`, `r.url` (after redirects) and `r.error`. Hosts on loopback, private or link-local addresses are refused. At most 4 at once per plugin: it returns `false, why` past that, or for a URL that isn't http(s) |
| `isekur.embed(srv, target, id, t)` | shows `t` under the message with that `id` (its `message` event's `e.id`) in the webchat. `t.type` is `"link"` (with `url`, `title`, and `desc`, `site`, `image` if you have them), `"image"`, `"audio"` or `"video"` (with `url`). The terminal shows `"link"` ones too, as text (site, title, description), unless `term` is `false`. Only http(s) URLs are shown, and everything as plain text. `false` when the line is gone |
| `isekur.proxy(srv, url)` | in a `connect` handler: this connection goes through `url`, `socks5://`, `socks4://`, `http://` (`[user:pass@]host[:port]`) or `ssh://[user@]host[:port]` (ssh -W, keys or an agent). `nil` or `""`: direct. A bad URL is an error |
| `isekur.store_get(key)`, `isekur.store_set(key, value)` | the plugin's own saved strings (`<name>.data`); `nil` removes a key. Written within 5 seconds, and when it's unloaded or iSekur exits |
| `isekur.store_keys()` | every key in the store |
| `isekur.active()` | the tab you're on: its network (nil for the main window) and its name |
| `isekur.date(t, fmt)` | `t` (default now) as local time with strftime's `fmt` (default: your timestamp format) |
| `isekur.is_chan(srv, name)` | a channel name by that network's own prefixes |
| `isekur.servers()` | names of the connected networks |
| `isekur.channels(srv)` | the channels joined there |
| `isekur.me(srv)` | your nick there, nil when not connected |
| `isekur.nick(srv)` | the nick the config asks for there (the one you'd have if it were free) |
| `isekur.rank(srv, chan, nick)` | the nick's prefix there (`"@"`, `"+"`, `""`), nil if it's not in the channel |
| `isekur.away(srv)`, `isekur.attached()` | booleans |
| `isekur.idle()`, `isekur.detached_for()`, `isekur.time()` | seconds since you typed, seconds nobody's been attached (0 while attached), the Unix time |
| `isekur.inactive()` | seconds since the last key, click or mouse move in the terminal or the webchat (`idle()` counts only lines you send) |
| `isekur.screen(fn, fps)` | a screensaver: the terminal and the webchat show only your frames, on black, `fps` a second (1-30, default 15), until a key, click or mouse move on either side. `fn(e)` draws one frame with `isekur.put`, from scratch each time; `e.w`, `e.h` (in cells), `e.ui` (`"term"` or `"web"`: each at its own size, so keep their states apart) and `e.t` (ms since it started). `true` if it started: never while no terminal or webchat is attached (it ends when the last one goes). An error in `fn` ends it. `isekur.screen(false)` ends yours, `isekur.screen()` says whether one is up |
| `isekur.put(x, y, text, color)` | in a frame: `text` from cell `x`, `y` (0-based, clipped), `color` `0xRRGGBB` (default white). `x` and `y` may be fractions: the webchat draws there, between cells, so slow motion is smooth; the terminal draws in the cell. The webchat gets only the cells that changed, so colors in a few steps instead of a smooth fade cost it less |
| `isekur.lock()` | locks the terminal and the webchat like `/lock`, when a lock password is set; `false` when there's none. Under a screensaver the password box shows once it ends |
| `isekur.platform()` | the system's name in lowercase: `darwin`, `linux`, `freebsd`, `openbsd`, `netbsd`, `dragonfly` |
| `isekur.which(name)` | the program's full path on PATH, `nil` when it isn't there. A name with a `/` is `nil` |
| `isekur.run(argv, text)` | starts a speech engine: `argv[1]` must be `say`, `spd-say`, `espeak-ng`, `espeak`, `flite` or `festival` (only as `{"festival", "--tts"}`: without it festival reads its stdin as Scheme), no other program and never a shell. `text` goes to its stdin, its output is dropped. `true` if started; `false` while the last one still runs (one at a time per plugin: queue and try again on `tick`). An error for any other program |
| `isekur.speak_web(text, lang)` | the webchat says `text` aloud in its browser (speechSynthesis): nothing in the terminal. `lang` (optional, a code such as `es`) makes the browser pick a voice for it. Nothing happens with no webchat open |
| `isekur.sort_tabs()` | puts the tabs in order: each network's tabs together in the network's place, its status tab first, then the channels and queries by name (A to Z, case ignored). The console and shell tabs stay where they are. `true` if the order changed. Call it on `tick` to keep the order. A tab the user `/move`d (or dragged) keeps its place in its network's group until iSekur restarts; the others sort around it |
| `isekur.radio(url, {name, host, direct, volume})` | plays a stream, audio only: an `http(s)` address, or a YouTube channel's live (`https://www.youtube.com/@name/live`: always its current one; a video's own address changes when it restarts). ffmpeg turns it into one MP3 that iSekur relays to every webchat's `<audio>` (it plays on a phone with the screen locked) and, with `host`, to a player on this machine (mpv, ffplay or vlc). A YouTube live goes through yt-dlp first: the address it finds works only from this machine's own IP, which is why the audio comes through iSekur and not straight from the browser. `direct`: nothing runs on this machine, the webchat's browsers connect to the stream themselves (an `https` one that isn't YouTube). `volume`: where it starts, in percent (see `isekur.radio_volume`). One radio at a time, a new one replaces yours. `true`, or `nil` and why: no ffmpeg, no yt-dlp, no player, or an address it won't fetch (anything but `http(s)`, nothing on this machine or a private network, no `user:pass@`). A stream that drops starts again (three times), then the console says why. `isekur.radio(false)` stops yours and clears its mute. `isekur.radio()` says what's on: `state` (`"off"`, `"resolving"` while it finds and opens the stream, `"playing"`), `name`, `host`, `direct`, `web` (a webchat is attached), `muted`, `volume`, `err` (why the last one stopped). While it plays, the status bar shows `R: ON` (`MUTE` when muted) in the terminal and the webchat. Going away with its plugin (disabled, removed, reloaded) stops it. API 12 |
| `isekur.radio_volume(percent)` | the volume of your radio, 0 to 150 (100: the stream as it comes; above it a limiter keeps it from clipping), changed while it plays, and kept for the next one. ffmpeg applies it, so it works for the webchat on a phone (where a page can't set its own volume) and for the player on this machine; a `direct` stream's volume is the browser's (it can't go above 100, and iOS ignores it: its buttons). Returns the volume. Only with no radio on, or yours. API 12 |
| `isekur.radio_mute(on)` | mutes or unmutes your radio: the webchat's sound and the player on this machine. A new station keeps the mute, `isekur.radio(false)` clears it. Returns whether it is muted. API 12 |
| `isekur.window{title, display, items, sel, mark, star, buttons, icons, reels, slider}` | opens or updates your window, in the terminal and the webchat at once (one at a time: a new one replaces another plugin's). `display`: up to 4 lines in a panel at the top (the first one in the title color); `items`: the list (up to 300 rows; with 6 or more a filter box, `/` in the terminal); `sel`: the row the cursor starts on (it moves when this number changes, not when you call it again with the same one); `mark`: the row drawn with a ▶ (what plays), `star`: the one drawn with a ★ (1-based, 0 none); `buttons`: up to 6 labels, the first is the default one (the terminal presses them by their first letter), `icons`: a short symbol before each one's label; `reels`: a cassette in the panel, its reels turning when `true`, still when `false` (nothing if left out); `slider = {value, max, step, icon}`: a bar under the list (the terminal: ←/→ or +/-, a click or the wheel on it; the webchat: a range input), 0 to `max` in `step`s, with `icon` (a few characters) before it, sent back as the `window` event `"slider"`. The user's clicks come back as the `window` event. Call it again to update it (nothing is sent when it didn't change, so it's fine every tick); `isekur.window(false)` closes it, `isekur.window()` says whether it's open. Going away with its plugin closes it. API 12 |
| `isekur.view{term, web, width, lines, theme, events}` | the focus view (the zen plugin's): on the terminal (`term`) and/or the webchat (`web`), both by default, only the chat shows, in a column `width` characters wide (80) in the middle, the lines before the last `lines` (5) dimmed, joins, parts and quits hidden unless `events`. `theme` (a theme's name) draws it in that theme; nil keeps the configured one. Nothing is saved: `isekur.view(false)` ends yours, and so do Esc on an empty input line and your plugin going (disabled, removed, reloaded). `true`, or nil and why (a theme that won't load). `isekur.view()` says whether one is up |
| `isekur.theme()` | the loaded theme's colors, `0xRRGGBB`: `name`, `fg` and `bg` (its text and background; nil where the terminal's own is used), `hilight`, `timestamp`, `nicks` (its nick colors, a list) and `self` (your own nick's color, one none of `nicks` is: nil when the theme has one nick color or `/set own_nick_color` is off). API 13 added `self` |
| `isekur.nick_color(srv, nick)` | the color the chat gives that nick, `0xRRGGBB`: yours is `theme().self` (the theme's own color for you when `own_nick_color` is off), anyone else's comes from a hash of the nick (one of `nicks`, the same one in the nick column, the terminal and the webchat). nil when the theme has no nick colors. API 13 |
| `isekur.nicklist_colors(on)` | the user list shows each nick in its chat color (`nick_color`), in the channels where your plugin is on (it follows `enabled` per network and channel), in the terminal and the webchat; the rank letter keeps its own color. Display only. One plugin at a time, and it ends with the plugin (disabled, removed, reloaded). Call it again whenever your setting changes (a `tick` handler is the place). `isekur.nicklist_colors()` says whether yours is on. API 13 |
| `isekur.fold(on)` | runs of joins, parts, quits and nick changes show as one row, `› 3 joined, 2 left` in the terminal and `⇄ 3 joined, 2 left ▸` in the webchat, that a click opens and a click folds again; every run folds again when you leave the tab. In the channels where your plugin is on (it follows `enabled` per network and channel), in the terminal and the webchat. Display only: the logs and the scrollback keep every line; kicks, your own joins and parts and messages end a run, and a lone event stays a line. It reads three of your plugin's settings, so declare them with `isekur.setting`: `names` (a boolean: the nicks in the row), `nicks` (a boolean, default on: nick changes are counted; off leaves them as plain lines) and `quiet` (`"hide"`, the default, or `"fold"`: in a `/quiet` tab nothing shows, or only the summary rows). One plugin at a time, and it ends with the plugin. `isekur.fold()` says whether yours is on. API 14 |
| `isekur.name`, `isekur.api` | the plugin's name, the API version (2: `http`, `embed` and `e.id` came with it; 3: `proxy` and the `connect` event; 4: the `raw` and `paste` events, `e.opened`, `isekur.nick` and `http`'s `body`; 5: `screen`, `put`, `inactive` and `lock`; 6: `sort_tabs`; 7: `platform`, `which`, `run` and `speak_web`; 8: the `show` event and `theme`; 9: the `nickmenu` event; 10: `set`; 11: the `lock` event, and later `view`: check `if isekur.view` before using it; 12: `radio`, `radio_mute`, `radio_volume`, `window` and the `window` event; 13: `nick_color`, `nicklist_colors` and `theme().self`; 14: `fold`) |

## The catalog

`/plugin available` and `/plugin install` read this repository from GitHub: `index.json` and
`<name>/<name>.lua`. To add a plugin, put it in `<name>/<name>.lua` and an entry in `index.json`:

```json
{"name": "hello", "version": "1.0", "api": 1, "author": "Your Name", "contact": "you@example.org",
 "description": "Says hello", "sha256": "<shasum -a 256 hello/hello.lua>"}
```

`author` and `contact` must be the file's own lines. `"official": true` marks a plugin made for iSekur by its
author (the About says "Official iSekur plugin"); the catalog's maintainer sets it, not a pull request.

The sha256 must match the file byte for byte: iSekur refuses the install otherwise. `version` must
be the file's own `-- version:` line; raise both with every change, or nobody is offered the
update. `python3 check.py` checks every entry (the repository's CI runs it, and compiles each plugin
with `luac -p`). iSekur keeps the index it fetched in `.catalog.json` in the user's plugins folder and
fetches it again after 12 hours (`/plugin refresh` sooner), so a new version can take that long to
show up. `api` is the `isekur.api` the plugin needs; older iSekurs hide it.

To try a catalog before it's published: `ISEKUR_PLUGIN_URL=file:///path/to/isekur-plugins/ isekur`.
