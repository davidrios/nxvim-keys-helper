-- nxvim-keys-helper — a live popup of the keys that can follow what you've typed.
--
-- A which-key for nxvim, built natively on `nx.*`: no blocking key reads, no key
-- interception. It listens to the engine's pending-key ORACLE (`nx.on_key_pending`)
-- and draws the continuations as a non-focus floating window — so it never
-- interrupts the sequence you're in the middle of typing.
--
-- Install it through the `:Plugins` manager (in your init.lua):
--
--     nx.plugins({
--       { "davidrios/nxvim-keys-helper",
--         config = function() require("nxvim-keys-helper").setup({}) end },
--     })
--
-- TRY IT: press <leader> (or `g`, `z`, `<C-w>`) and pause. A bordered popup
-- appears in the bottom-right corner listing every key that can follow, with each
-- mapping's `desc`. Keep typing into a group and it refreshes to that group's keys;
-- complete a mapping, break the sequence, or wait the timeout and it closes.
--
-- ---------------------------------------------------------------------------
-- How it works (the three nx signals)
-- ---------------------------------------------------------------------------
--   * nx.on_key_pending(fn)   the engine's pending-prefix ORACLE. The server
--                 watches the mapped-prefix trie and pushes a context
--                 — { mode, keys, continuations = {{ key, desc, kind, available }}, label }
--                 — every time the withheld prefix changes (grows / descends /
--                 clears). It is fire-on-change, not per-keystroke (ADR 0002 rule
--                 4: no per-key Lua). The built-in command grammar arrives over the
--                 SAME event (source B): the OPEN states (`f` find-char, `r`
--                 replace, marks, operator-pending `d`/`c`/`y`) have no key list, so
--                 they carry a `label` ("Find character"); the FINITE built-in
--                 prefixes (`z` → zt/zz/zb…, `g` → gg/gt/…, `<C-w>` → window
--                 commands) carry enumerated `continuations`, and for `g` the engine
--                 MERGES the built-in motions with any maps sharing the `g` prefix
--                 (the LSP gd/gD/gr defaults) into one popup.
--   * nx.component{ surface = "float" }   the popup is a FLOAT-backed component:
--                 reactive state (the pending context) + a pure `render` + a
--                 lifecycle. An EMPTY render hides it, so the whole show/refresh/hide
--                 is declarative and the plugin never touches a float handle. The
--                 "float" surface takes NO focus and binds NO keys.
--   * nx.utils.debounce(fn, ms)   coalesce the oracle's bursts so a fast, deliberate
--                 sequence (`<Space>w` typed quickly) never flashes the popup — it
--                 only appears when you PAUSE.

local M = {}

-- The plugin's default highlight groups, mirroring the which-key.nvim names so a
-- colorscheme that already styles them just works. These are only applied as a
-- FALLBACK — if the active colorscheme (or the user, via opts.highlights) already
-- defines a group, that definition wins (see apply_highlights). The defaults read
-- well on a dark background with no theme loaded, so a bare setup() still looks
-- right.
local DEFAULT_HIGHLIGHTS = {
  WhichKey = { fg = "#7dcfff" }, -- the key itself (cyan)
  WhichKeyGroup = { fg = "#bb9af7", bold = true }, -- a +prefix group
  WhichKeyDesc = { fg = "#c0caf5" }, -- a mapping's description
  WhichKeySeparator = { fg = "#565f89" }, -- the gap between key and desc
}

-- Defaults merged with the user's opts in setup(). `delay` is the pause (ms) after
-- the LAST key before the popup appears — real which-key uses ~200ms so quick,
-- deliberate sequences stay invisible. `relative`/`border` are passed straight to
-- the float mount; "bottom" is the classic bottom-right which-key spot.
-- `timeout` is applied straight to `vim.o.timeout`. It defaults to FALSE — a
-- which-key wants a paused prefix to stay pending for as long as you look at the
-- popup, but vim's default `timeout = true` commits the prefix to the built-in
-- grammar after `timeoutlen` (which is what strands the LSP `g`-maps as
-- `available == false`, see lines_for). Disabling it keeps the sequence open. Pass
-- `timeout = true` to setup() to keep vim's mapping timeout instead.
M.config = {
  delay = 200,
  timeout = false,
  relative = "bottom",
  border = "rounded",
  group_marker = "+", -- prefix shown before a group's name (e.g. "+file")
  highlights = {}, -- user highlight overrides, keyed by group name
}

-- The group-name registry: a normalized prefix-notation → friendly name. The server
-- reports a prefix that only leads deeper as `kind = "group"` with `desc = nil` (it
-- has no own mapping to carry a description), so a group's NAME can only come from
-- here. Populated by M.add (and opts.spec in setup).
M._groups = {}

local mounted = nil -- the component handle, so a second setup() doesn't double-mount

-- ----- group registry -------------------------------------------------------

-- The notation a leader expands to, matching how the oracle reports it: a space
-- leader prints as "<Space>" (see key_to_notation), every other single-char leader
-- is itself. `which` is "mapleader" or "maplocalleader"; both default to "\" as in
-- vim. We normalize to NOTATION (not the raw char) because the live context path we
-- match against — ctx.keys .. continuation.key — is always notation.
local function leader_notation(which)
  local l = vim.g[which]
  if l == nil then
    l = "\\"
  end
  if l == " " then
    return "<Space>"
  end
  return l
end

-- Normalize a registered prefix (e.g. "<leader>f") into the notation the oracle
-- emits ("<Space>f"), expanding <leader>/<localleader> case-insensitively. This is
-- the key both M.add and the render-time lookup use, so they always agree.
local function normalize_prefix(s)
  s = s:gsub("<[lL][eE][aA][dD][eE][rR]>", function()
    return leader_notation("mapleader")
  end)
  s = s:gsub("<[lL][oO][cC][aA][lL][lL][eE][aA][dD][eE][rR]>", function()
    return leader_notation("maplocalleader")
  end)
  return s
end

-- add(spec) — name prefix groups so the popup shows "+file" instead of a bare
-- "+more". `spec` is a list of entries; each is either
--   { "<leader>f", group = "file" }            (positional prefix)
--   { prefix = "<leader>g", group = "git" }    (named field)
-- Only the group NAME is taken from here — leaf mappings carry their own `desc`
-- through nx.keymap.set. Call it any time (before or after setup); the next popup
-- reflects it. Safe to call repeatedly to extend/override.
function M.add(spec)
  if type(spec) ~= "table" then
    error("nxvim-keys-helper.add: expects a list of { prefix, group } entries", 2)
  end
  for _, entry in ipairs(spec) do
    local prefix = entry.prefix or entry[1]
    if type(prefix) ~= "string" then
      error("nxvim-keys-helper.add: each entry needs a prefix string", 2)
    end
    if entry.group ~= nil and type(entry.group) ~= "string" then
      error("nxvim-keys-helper.add: `group` must be a string", 2)
    end
    M._groups[normalize_prefix(prefix)] = entry.group
  end
end

-- ----- highlights -----------------------------------------------------------

-- Apply the highlight groups as a FALLBACK: an explicit user override (opts.highlights)
-- always wins; otherwise a default is installed only when the group isn't already
-- defined, so a colorscheme that styles WhichKey* keeps its colors.
local function apply_highlights(user)
  for name, spec in pairs(DEFAULT_HIGHLIGHTS) do
    if user[name] then
      nx.hl.define(0, name, user[name])
    elseif not nx.hl.exists(name) then
      nx.hl.define(0, name, spec)
    end
  end
  -- Any extra groups the user named that aren't in our defaults — honor them too.
  for name, spec in pairs(user) do
    if not DEFAULT_HIGHLIGHTS[name] then
      nx.hl.define(0, name, spec)
    end
  end
end

-- ----- rendering ------------------------------------------------------------

-- Lay the continuations out as an aligned `key   label` grid. Each row is a list of
-- `{ text, hl_group }` CHUNKS (the styled-float form), so the key, the separator,
-- and the description each get their own color. The key column is padded to the
-- widest DISPLAY width (not byte length) so wide/multibyte keys still line up.
--
-- A group continuation (`kind == "group"`) is shown as the configured marker plus
-- its registered name (M._groups), falling back to "more" — the server gives groups
-- no desc. A leaf shows its mapping's `desc`.
--
-- Source B (the open built-in states: `f` find-char, `r` replace, marks, …) has NO
-- discrete keys — its continuation set is open — so it arrives with empty
-- continuations and a `ctx.label`. We render that as a single hint card.
local function lines_for(ctx)
  -- Keep only continuations that can still fire. `available == false` is a mapped
  -- continuation (e.g. the LSP gd/gD/gr) the oracle still reports after the leader
  -- timeout committed its prefix to the built-in grammar — pressing it now does
  -- nothing, so we drop the dead row rather than show it.
  local conts = {}
  for _, c in ipairs(ctx.continuations) do
    if c.available ~= false then
      conts[#conts + 1] = c
    end
  end

  -- No keys to list (an open source-B state, or a context whose continuations were
  -- all unavailable): render the label as a single hint card.
  if #conts == 0 then
    return { { { string.format(" %s ", ctx.label or "…"), "WhichKeyDesc" } } }
  end

  local keyw = 1
  for _, c in ipairs(conts) do
    keyw = math.max(keyw, nx.str.displaywidth(c.key))
  end

  local rows = {}
  for _, c in ipairs(conts) do
    local pad = string.rep(" ", keyw - nx.str.displaywidth(c.key))
    local label, label_hl
    if c.kind == "group" then
      local name = M._groups[ctx.keys .. c.key]
      label = M.config.group_marker .. (name or (c.desc ~= "" and c.desc) or "more")
      label_hl = "WhichKeyGroup"
    else
      label = (c.desc and c.desc ~= "") and c.desc or ""
      label_hl = "WhichKeyDesc"
    end
    rows[#rows + 1] = {
      { " ", nil },
      { c.key, "WhichKey" },
      { pad .. "  ", "WhichKeySeparator" },
      { " ", nil },
      { label, label_hl },
      { " ", nil },
    }
  end
  return rows
end

-- ----- setup ----------------------------------------------------------------

-- setup(opts) — wire the popup. Idempotent: a second call re-applies config and
-- highlights but does not mount a second component.
--   opts.delay         pause (ms) after the last key before the popup shows (200)
--   opts.timeout       value for vim.o.timeout — false (the default) keeps a paused
--                      prefix pending; true restores vim's mapping timeout
--   opts.relative      float anchor: "bottom" | "cursor" | "editor" ("bottom")
--   opts.border        "rounded" | "single" | "double" | "solid" | "none"
--   opts.group_marker  string shown before a group name ("+")
--   opts.highlights    { GroupName = { fg=, bg=, bold= }, … } overrides
--   opts.spec          a group-name registry passed straight to M.add (see add)
function M.setup(opts)
  opts = opts or {}
  if type(opts) ~= "table" then
    error("nxvim-keys-helper.setup: opts must be a table", 2)
  end

  for _, k in ipairs({ "delay", "timeout", "relative", "border", "group_marker" }) do
    if opts[k] ~= nil then
      M.config[k] = opts[k]
    end
  end
  M.config.highlights = opts.highlights or {}
  apply_highlights(M.config.highlights)

  -- Keep the prefix pending while the popup is up: by default `timeout = false`
  -- disables vim's mapping timeout, so a paused leader sequence never commits to
  -- the built-in grammar out from under the popup. A user who passed
  -- `timeout = true` gets vim's normal behavior back.
  vim.o.timeout = M.config.timeout

  if opts.spec then
    M.add(opts.spec)
  end

  -- Already mounted (a re-run of setup): config/highlights are live above, nothing
  -- more to do — don't stack a second oracle listener / float component.
  if mounted then
    return M
  end

  mounted = nx.component({
    surface = "float",
    setup = function(ctx)
      -- The one piece of state: the current pending context (or nil when there is none).
      local state = ctx.reactive({ pending = nil })

      -- Debounce the SHOW so a quick sequence never flashes the popup. The HIDE is
      -- immediate (below), so it never lingers after you've answered.
      local show = nx.utils.debounce(function(c)
        state.pending = c
      end, M.config.delay)

      nx.on_key_pending(function(c)
        -- Cleared context (prefix completed, broke, or timed out): cancel the
        -- pending show and hide at once. A live source-B state has empty
        -- continuations but a non-empty `keys`, so gate on `keys` alone.
        if c.keys == "" then
          show:cancel()
          state.pending = nil
        else
          show(c)
        end
      end)

      return state
    end,

    -- Pure: the pending context in, the popup's rows out. `nil` → empty render → hidden.
    render = function(state)
      local c = state.pending
      if not c then
        return { lines = {} }
      end
      -- Title the popup `keys — label` so the prefix isn't cryptic: a bare `d` reads
      -- as "d — Delete". Source-A leader prefixes have no label, so they title with
      -- the keys alone.
      local title = " " .. c.keys
      if c.label and c.label ~= "" then
        title = title .. " — " .. c.label
      end
      return { lines = lines_for(c), title = title .. " " }
    end,
  }).mount({ relative = M.config.relative, border = M.config.border })

  return M
end

return M
