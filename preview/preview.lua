-- version: 1.4
-- author: Gerardo Canosa
-- contact: gera.canosa@gmail.com
-- preview: in the webchat, a small preview under links people post. A card with the page's title, description and
-- picture, the picture itself for image links, and a player for audio and video links (mp3, ogg, opus, wav, m4a,
-- flac, mp4, webm...). The terminal shows the cards as text (site, title, description), without pictures or players.
-- iSekur fetches the pages (https only, never your LAN); pictures and media load in your browser from their own
-- site, a player's only once you press play.
isekur.setting("links", true, "c", "a card with the page's title, description and picture")
isekur.setting("images", true, "c", "pictures: image links and the cards' pictures (your browser loads them from their site)")
isekur.setting("media", true, "c", "a player for audio and video links (nothing loads until you press play)")
isekur.setting("max", 3, "c", "previews per message at most")
isekur.setting("terminal", true, "c", "show the link cards in the terminal too, as text")
isekur.setting("size", "small", "c", "how big pictures and players are: small, medium or large")
isekur.setting("ignore", "", "g", "domains never previewed, separated by spaces (their sub-domains too)")

local AUDIO = {mp3 = 1, ogg = 1, oga = 1, opus = 1, wav = 1, m4a = 1, aac = 1, flac = 1}
local VIDEO = {mp4 = 1, webm = 1, m4v = 1, ogv = 1, mov = 1}
local IMAGE = {png = 1, jpg = 1, jpeg = 1, gif = 1, webp = 1, avif = 1, bmp = 1, svg = 1}

local function host_of(url) return (url:match("^%a+://([^/?#]+)") or ""):gsub("^.*@", ""):gsub(":%d+$", ""):lower() end

local function ignored(url)
  local h = host_of(url)
  for word in isekur.opt("ignore"):lower():gmatch("%S+") do
    local d = word:gsub("^%*?%.", "")
    if h == d or h:sub(-#d - 1) == "." .. d then return true end
  end
  return false
end

-- the links in a line, without mIRC formatting or the punctuation around them. All as https: "www.x.org" is
-- https://www.x.org, and http:// ones are fetched (and shown) over https, which nearly every site has. The second
-- list says which were http://: those are tried as posted when https fails (a site on a port without TLS)
local function urls(text)
  text = text:gsub("\3%d%d?,%d%d?", ""):gsub("\3%d%d?", ""):gsub("[\2\3\15\22\29\30\31]", "")
  local out, seen, plain = {}, {}, {}
  for word in text:gmatch("[^%s<>\"]+") do
    local u, was = word:gsub("^[%(%['`]+", ""), false
    if u:lower():match("^www%.[%w%-]+%.%a") then u = "https://" .. u
    elseif u:lower():match("^http://") then u = "https://" .. u:sub(8) was = true
    elseif not u:lower():match("^https://") then u = nil end
    if u then
      u = u:gsub("[%.,;:!%?'%*]+$", "")
      if u:sub(-1) == ")" and not u:find("(", 1, true) then u = u:sub(1, -2) end  -- "(see https://x/y)"
      if u:sub(-1) == "]" and not u:find("[", 1, true) then u = u:sub(1, -2) end
      if #u > 12 and not seen[u] then seen[u] = true, table.insert(out, u) plain[u] = was or nil end
    end
  end
  return out, plain
end

local function ext(url) return (url:match("^[^?#]*%.(%w+)$") or url:match("^[^?#]*%.(%w+)[?#]") or ""):lower() end

local ENT = {amp = "&", lt = "<", gt = ">", quot = '"', apos = "'", nbsp = " ", ndash = "–", mdash = "—", hellip = "…",
             lsquo = "‘", rsquo = "’", ldquo = "“", rdquo = "”", middot = "·", copy = "©", reg = "®", trade = "™"}
local function decode(s)
  s = s:gsub("&#[xX](%x+);", function(h) local n = tonumber(h, 16) return n and n < 0x110000 and utf8.char(n) or "" end)
  s = s:gsub("&#(%d+);", function(d) local n = tonumber(d) return n and n < 0x110000 and utf8.char(n) or "" end)
  return (s:gsub("&(%a+);", function(n) return ENT[n] or ENT[n:lower()] end))
end

local function clean(s, max)  -- one line of text, cut at max characters
  if not s then return nil end
  s = decode(s):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
  if s == "" then return nil end
  if utf8.len(s) and utf8.len(s) > max then s = s:sub(1, utf8.offset(s, max) - 1):gsub("%s*%S*$", "") .. "…" end
  return s
end

local function attr(tag, name)
  return tag:match("[%s/]" .. name .. "%s*=%s*\"([^\"]*)\"") or tag:match("[%s/]" .. name .. "%s*=%s*'([^']*)'")
      or tag:match("[%s/]" .. name .. "%s*=%s*([^%s>\"']+)")
end

-- relative picture URLs from the page's own; https only, like everything else here
local function absolute(u, page)
  if not u then return nil end
  u = decode(u)
  if u:match("^//") then u = "https:" .. u
  elseif u:match("^/") then u = page:match("^(https?://[^/?#]+)") .. u
  elseif not u:match("^%a+://") then u = page:match("^([^?#]*/)") .. u end
  return u:match("^https://") and u or nil
end

-- the page's head: Open Graph and Twitter tags, else <title> and the description
local function card(html, url)
  local head = html:sub(1, (html:lower():find("</head>", 1, true) or #html))
  local m = {}
  for tag in head:gmatch("<[Mm][Ee][Tt][Aa]%s[^>]*>") do
    local k = (attr(tag, "property") or attr(tag, "name") or ""):lower()
    local v = attr(tag, "content")
    if k ~= "" and v and not m[k] then m[k] = v end
  end
  local title = m["og:title"] or m["twitter:title"] or head:match("<[Tt][Ii][Tt][Ll][Ee][^>]*>(.-)</[Tt][Ii][Tt][Ll][Ee]>")
  title = clean(title, 160)
  if not title then return nil end
  local desc = clean(m["og:description"] or m["twitter:description"] or m["description"], 240)
  return {type = "link", url = url, title = title, desc = desc ~= title and desc or nil,
          site = clean(m["og:site_name"], 60) or host_of(url):gsub("^www%.", ""),
          image = absolute(m["og:image:secure_url"] or m["og:image"] or m["twitter:image"] or m["twitter:image:src"], url)}
end

-- a JSON string field: enough for an oEmbed answer
local function jstr(json, key)
  local at = select(2, json:find('"' .. key .. '"%s*:%s*"'))
  if not at then return nil end
  local out, i = {}, at + 1
  while i <= #json do
    local ch = json:sub(i, i)
    if ch == '"' then return table.concat(out) end
    if ch == "\\" then
      local n = json:sub(i + 1, i + 1)
      if n == "u" then
        local cp = tonumber(json:sub(i + 2, i + 5), 16) or 63
        i = i + 4
        if cp >= 0xd800 and cp < 0xdc00 and json:sub(i + 2, i + 3) == "\\u" then  -- a surrogate pair
          local lo = tonumber(json:sub(i + 4, i + 7), 16) or 0
          cp, i = 0x10000 + (cp - 0xd800) * 0x400 + (lo - 0xdc00), i + 6
        end
        table.insert(out, utf8.char(cp))
      else table.insert(out, ({n = "\n", t = " ", r = "", b = "", f = ""})[n] or n) end
      i = i + 2
    else table.insert(out, ch) i = i + 1 end
  end
end

-- YouTube's page has its tags 800 KB in: its oEmbed answer has the same in a few hundred bytes
local function oembed(url)
  local h = host_of(url)
  if h:match("youtube%.com$") or h == "youtu.be" then
    return "https://www.youtube.com/oembed?format=json&url=" .. url:gsub("[^%w%-%._~]", function(c)
      return string.format("%%%02X", c:byte()) end)
  end
end

local function put(srv, target, id, em)  -- every preview carries the size it's shown at
  local size = isekur.opt("size", srv, target):lower()
  em.size = (size == "medium" or size == "large") and size or "small"
  if not isekur.opt("terminal", srv, target) then em.term = false end
  return isekur.embed(srv, target, id, em)
end

isekur.on("message", function(e)
  if e.notice or not e.id then return end
  local srv, target, n = e.srv, e.target, 0
  local list, plain = urls(e.text)
  for _, u in ipairs(list) do
    if n >= isekur.opt("max", srv, target) then break end
    if not ignored(u) then
      local x = ext(u)
      local kind = AUDIO[x] and "audio" or VIDEO[x] and "video" or IMAGE[x] and "image"
      if kind then
        local em = isekur.opt(kind == "image" and "images" or "media", srv, target) and {type = kind, url = u}
        if em then put(srv, target, e.id, em) n = n + 1 end
      elseif isekur.opt("links", srv, target) and u:match("^https://") and oembed(u) then
        n = n + 1
        isekur.http(oembed(u), function(r)
          local title = r.status == 200 and clean(jstr(r.body, "title"), 160)
          if not title then return end
          local img = isekur.opt("images", srv, target) and jstr(r.body, "thumbnail_url")
          put(srv, target, e.id, {type = "link", url = u, title = title, desc = clean(jstr(r.body, "author_name"), 80),
                                           site = clean(jstr(r.body, "provider_name"), 60), image = img and absolute(img, u)})
        end)
      elseif isekur.opt("links", srv, target) and u:match("^https://") then
        n = n + 1
        local function got(r)  -- what the link turns out to be decides: a page's card, or a picture or player
          if r.error and plain[u] then plain[u] = nil return isekur.http("http://" .. u:sub(9), got) end  -- no TLS there
          if r.error or r.status ~= 200 then return end
          local at = r.url:match("^https://") and r.url or u  -- after an http:// fetch: where it led (a short link's page)
          local t, em = r.type, nil
          if t == "text/html" or t == "application/xhtml+xml" or t == "" then
            em = card(r.body, at)
            if em and not isekur.opt("images", srv, target) then em.image = nil end
          elseif t:match("^image/") then em = isekur.opt("images", srv, target) and {type = "image", url = at}
          elseif t:match("^audio/") or t:match("^video/") then
            em = isekur.opt("media", srv, target) and {type = t:match("^(%a+)/"), url = at}
          end
          if em then put(srv, target, e.id, em) end
        end
        isekur.http(u, got)
      end
    end
  end
end)
