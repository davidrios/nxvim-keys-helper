# nxvim-keys-helper

A live popup of the keys that can follow what you've just typed — a **which-key**
for [nxvim](https://github.com/davidrios/nxvim).

Press `<leader>` (or `g`, `z`, `<C-w>`, …) and pause: a bordered popup appears in
the bottom-right corner listing every key that can come next, each with its
description. Keep typing into a group and it refreshes to that group's keys;
complete a mapping, break the sequence, or wait out the timeout and it closes.

It is built natively on the `nx.*` API — **no blocking key reads, no key
interception**. It subscribes to nxvim's pending-key *oracle*
(`nx.on_key_pending`) and renders the continuations onto a non-focus floating
window, so it never interrupts the sequence you're in the middle of typing.

## Install

Declare it with the built-in `:Plugins` manager in your `init.lua`:

```lua
nx.plugins({
  {
    "davidrios/nxvim-keys-helper",
    config = function()
      require("nxvim-keys-helper").setup({})
    end,
  },
})
```

Then run `:PluginSync` to clone it. That's it — start typing a prefix and pause.

## Configuration

`setup()` takes an optional table; the defaults are:

```lua
require("nxvim-keys-helper").setup({
  delay = 200,          -- pause (ms) after the last key before the popup shows
  timeout = false,      -- vim.o.timeout: false keeps a paused prefix pending; true restores the mapping timeout
  relative = "bottom",  -- float anchor: "bottom" | "cursor" | "editor"
  border = "rounded",   -- "rounded" | "single" | "double" | "solid" | "none"
  group_marker = "+",   -- shown before a group name, e.g. "+file"
  highlights = {},      -- override the popup's highlight groups (see below)
  spec = {},            -- name your prefix groups (see below)
})
```

`setup()` is idempotent — calling it again re-applies config and highlights
without mounting a second popup.

### Naming groups

A prefix that only leads deeper (e.g. `<leader>f` when you have `<leader>ff` and
`<leader>fg`) shows as a **group**. nxvim's engine has no description to attach to
a bare prefix, so by default a group renders as `+more`. Give it a real name with
`spec` (or call `require("nxvim-keys-helper").add(...)` any time):

```lua
require("nxvim-keys-helper").setup({
  spec = {
    { "<leader>f", group = "file" }, -- positional prefix
    { prefix = "<leader>g", group = "git" }, -- or the named field
  },
})
```

`<leader>` / `<localleader>` are expanded the same way nxvim reports keys, so the
registry matches whatever leader you've set.

Leaf mappings need no registration — their description comes straight from the
`desc` you pass to `nx.keymap.set`:

```lua
nx.keymap.set("n", "<leader>w", "<cmd>write<cr>", { desc = "write" })
```

### Highlights

The popup uses four highlight groups (the which-key.nvim names, so a colorscheme
that already styles them just works):

| Group               | What it colors                       |
| ------------------- | ------------------------------------ |
| `WhichKey`          | the key itself                       |
| `WhichKeyGroup`     | a `+group` label                     |
| `WhichKeyDesc`      | a mapping's description / hint card  |
| `WhichKeySeparator` | the gap between the key and its desc |

The plugin only installs its built-in colors as a **fallback** — if your
colorscheme (or your `highlights` override) already defines a group, that wins.
Override any of them explicitly:

```lua
require("nxvim-keys-helper").setup({
  highlights = {
    WhichKey = { fg = "#89b4fa" },
    WhichKeyGroup = { fg = "#f9e2af", bold = true },
  },
})
```

## Built-in command grammar

The popup is fed by the same oracle nxvim uses for `showcmd`, so it covers the
built-in motions too, not just your maps:

- pause after `z` for the viewport commands (`zt`/`zz`/`zb`…),
- after `<C-w>` for the window commands,
- after `g` for the go-to motions, **merged** with any `g`-prefixed maps (the LSP
  `gd`/`gD`/`gr` defaults),
- mid-`f` or after a lone operator (`d`/`c`/`y`) for an "awaiting input" hint card
  (`Find character`, `Operator pending`, …).

## Trying it locally

This repo ships a runnable demo. From a checkout of this repo:

```sh
NXVIM_CONFIG=examples nxvim examples/sample.txt
```

The demo's `init.lua` loads the plugin straight from this checkout (`dir=`), so
no `:PluginSync` is needed — see `examples/init.lua`.

## Tests

This plugin carries a Lua test suite (`test/popup_spec.lua`) built on nxvim's
native `nx.test` framework. Run it headlessly:

```sh
nxvim --test-plugin .
```

The suite drives a real editor — feed a leader prefix, wait for the debounced
popup, and assert on the floating window's text via `t:float()`:

```lua
nx.test.it("shows the leader menu on pause", function(t)
  t:feed("<Space>")
  local float = t:wait_for(function() return t:float() end)
  nx.test.expect(float.text).to_contain("write")
end)
```

## License

MIT © David Rios
