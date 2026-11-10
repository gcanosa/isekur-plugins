-- version: 1.2
-- author: Gerardo Canosa
-- contact: gera.canosa@gmail.com
-- tts: reads messages aloud: with this machine's speech engine (terminal), the browser's voice (webchat), or both.
-- Only the networks and channels you enable (/plugin enable tts sekurnet/#chan) are read.
-- Engines, and the systems each one is for (/tts engines shows what this system has):
--   say        macOS (built in)                              -v voice (language: its voice)
--   spd-say    Linux, BSD: speech-dispatcher (its daemon runs)  -l language
--   espeak-ng  Linux, BSD, macOS (Homebrew)                  -v voice (language: -v es)
--   espeak     the older name of espeak-ng, the same systems -v voice
--   flite      Linux, BSD, macOS (Homebrew)                  -voice awb, kal, rms or slt
--   festival   Linux, BSD                                    no voice setting
-- auto: the first of these in the list above that is installed for this system.
-- Nothing runs through a shell: the host starts the engine itself (isekur.run), with the text on its stdin
-- (spd-say and flite take it as an argument instead, after -- and -t).

local function set(...) local t = {} for _, k in ipairs({...}) do t[k] = true end return t end
local BSD = set("freebsd", "openbsd", "netbsd", "dragonfly")
local NIX = set("linux", "freebsd", "openbsd", "netbsd", "dragonfly")
local ALL = set("linux", "freebsd", "openbsd", "netbsd", "dragonfly", "darwin")

local ENGINES = {
  {name = "say",       label = "macOS",                  os = set("darwin"), text = "stdin", voice = "-v"},
  {name = "spd-say",   label = "Linux, BSD",             os = NIX,           text = "arg"},
  {name = "espeak-ng", label = "Linux, BSD, macOS (brew)", os = ALL,         text = "stdin", voice = "-v"},
  {name = "espeak",    label = "Linux, BSD, macOS (brew)", os = ALL,         text = "stdin", voice = "-v"},
  {name = "flite",     label = "Linux, BSD, macOS (brew)", os = ALL,         text = "arg",   voice = "-voice"},
  {name = "festival",  label = "Linux, BSD",             os = NIX,           text = "stdin"},
}
local ENGINE_NAMES = "auto, say (macOS), spd-say (Linux, BSD), espeak-ng, espeak, flite, festival"

isekur.setting("where", "terminal", "g", "where the text is read: terminal (this machine's speech engine), web (the webchat's browser voice), both or off", {"terminal", "web", "both", "off"})
isekur.setting("engine", "auto", "g", "the terminal's engine: " .. ENGINE_NAMES .. " (/tts engines: which this system has)", {"auto", "say", "spd-say", "espeak-ng", "espeak", "flite", "festival"})
isekur.setting("language", "", "c", "language to speak, a code such as es, fr or de: everywhere, or per network or channel (say needs its voice installed); empty: the engine's own")
isekur.setting("voice", "", "g", "voice for say, espeak-ng, espeak (flite: awb, kal, rms, slt); empty: the language's voice, or the engine's own")
isekur.setting("only", "all", "c", "which messages: all, or only the highlights (your nick or highlight words)", {"all", "highlights"})

local PLAT = isekur.platform()
local MAX_QUEUE = 20  -- lines waiting to be said; the newest are dropped past it

-- the voice macOS's say uses for a language (installed with the system's voices)
local SAY_VOICE = {en = "Samantha", es = "Monica", fr = "Thomas", de = "Anna", it = "Alice", pt = "Luciana",
                   ru = "Milena", ja = "Kyoko", zh = "Ting-Ting", nl = "Xander", sv = "Alva"}

-- the engine's argv for text: its voice (or the language's), and the text on stdin or as the last argument
local function argv_for(e, text, voice, lang)
  local a = {e.name}
  local code = lang:match("^%a+") or ""  -- "es-MX" -> "es"; letters only, so it can't be read as an option
  if voice == "" and code ~= "" then
    if e.name == "say" then voice = SAY_VOICE[code] or ""
    elseif e.name == "espeak-ng" or e.name == "espeak" then voice = code end  -- espeak's voices are language codes
  end
  if e.voice and voice ~= "" then a[#a + 1] = e.voice; a[#a + 1] = voice end
  if e.name == "spd-say" and code ~= "" then a[#a + 1] = "-l"; a[#a + 1] = code end
  if e.name == "festival" then a[#a + 1] = "--tts" end  -- without it festival reads its stdin as Scheme, which can run programs
  if e.text == "stdin" then return a, text end
  if e.name == "spd-say" then a[#a + 1] = "--" end
  if e.name == "flite" then a[#a + 1] = "-t" end
  a[#a + 1] = text
  return a, nil
end

local function usable(e)
  return e.os[PLAT] and isekur.which(e.name) ~= nil
end

-- the engine the terminal uses here: the setting's, or the first usable one for auto
local function pick(srv, target)
  local want = isekur.opt("engine", srv, target)
  for _, e in ipairs(ENGINES) do
    if (want == "auto" or want == e.name) and usable(e) then return e end
  end
  return nil
end

-- what's still to say: isekur.run starts one engine at a time, so the rest wait here (the tick tries again)
local queue = {}
local function pump()
  while #queue > 0 do
    local item = queue[1]
    if not isekur.run(item.argv, item.stdin) then return end
    table.remove(queue, 1)
  end
end
isekur.on("tick", pump)

local function say_here(line, srv, target)
  local e = pick(srv, target)
  if not e then return end  -- /tts test says why
  if #queue >= MAX_QUEUE then return end
  local argv, stdin = argv_for(e, line, isekur.opt("voice", srv, target), isekur.opt("language", srv, target))
  queue[#queue + 1] = {argv = argv, stdin = stdin}
  pump()
end

-- IRC colors and control codes out, whitespace squeezed, a long line cut
local function clean(t)
  t = t:gsub("\3%d%d?,?%d?%d?", ""):gsub("%c", " "):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
  if #t > 300 then t = t:sub(1, 300) end
  return t
end

isekur.on("message", function(e)
  if e.self or e.notice then return end  -- your own lines and notices are not read
  local where = isekur.opt("where", e.srv, e.target)
  if where == "off" then return end
  if isekur.opt("only", e.srv, e.target) == "highlights" and not e.hilight then return end
  local text = clean(e.text)
  if text == "" then return end
  local line = e.nick .. " says " .. text
  if where == "terminal" or where == "both" then say_here(line, e.srv, e.target) end
  if where == "web" or where == "both" then isekur.speak_web(line, isekur.opt("language", e.srv, e.target)) end
end)

isekur.command("tts", "engines | test", function(args, srv, target)
  if args == "test" then
    local where = isekur.opt("where", srv, target)
    local line = "iSekur can read messages aloud"
    if where == "off" then print("tts is off here: set where to terminal, web or both") return end
    if where ~= "web" then
      local e = pick(srv, target)
      if e then
        say_here(line, srv, target)
        print("tts: saying it with " .. e.name)
      else
        print("no speech engine for " .. PLAT .. " is installed: /tts engines")
      end
    end
    if where ~= "terminal" then
      isekur.speak_web(line, isekur.opt("language", srv, target))
      print("tts: sent to the webchat")
    end
    return
  end
  local auto
  for _, e in ipairs(ENGINES) do if not auto and usable(e) then auto = e end end
  print("this system: " .. PLAT .. ". engine setting: " .. isekur.opt("engine", srv, target) ..
        (auto and ", auto takes " .. auto.name or ", no engine installed for it"))
  for _, e in ipairs(ENGINES) do
    local state = not e.os[PLAT] and "not for " .. PLAT or isekur.which(e.name) and "installed" or "not installed"
    print(string.format("  %-10s %-24s %s", e.name, e.label, state))
  end
  print("  web: the browser's voice, where it has one (Chrome, Edge, Safari, Firefox: most desktops)")
end)
