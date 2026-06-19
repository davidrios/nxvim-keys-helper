-- Runnable demo for nxvim-keys-helper.
--
--     NXVIM_CONFIG=examples cargo run -p nxvim -- examples/sample.txt
--
-- TRY IT: press <leader> (Space) and pause — the popup lists the keys below with
-- their descriptions, `f`/`g` shown as named groups. Type into a group (`f`) and it
-- refreshes; pause after `z`, `g`, or `<C-w>` for the built-in command grammar.

vim.g.mapleader = " "

-- Load the plugin straight from this repo (a local-dev spec: `dir` is never cloned).
-- A real config would instead use `{ "davidrios/nxvim-keys-helper", config = ... }`
-- and `:PluginSync`.
nx.plugins({
  {
    name = "nxvim-keys-helper",
    dir = vim.fn.expand("<sfile>:p:h:h"), -- the repo root (this file's grandparent dir)
    config = function()
      require("nxvim-keys-helper").setup({
        delay = 200,
        spec = {
          { "<leader>f", group = "file" },
          { "<leader>g", group = "git" },
        },
      })
    end,
  },
})

-- A small leader menu. `ff`/`fg` and `gs`/`gc` make `f` and `g` groups; the
-- single-key maps complete immediately, carrying their `desc`.
nx.keymap.set("n", "<leader>w", function()
  print("write")
end, { desc = "write" })
nx.keymap.set("n", "<leader>q", function()
  print("quit")
end, { desc = "quit" })
nx.keymap.set("n", "<leader>ff", function()
  print("find file")
end, { desc = "find file" })
nx.keymap.set("n", "<leader>fg", function()
  print("live grep")
end, { desc = "live grep" })
nx.keymap.set("n", "<leader>gs", function()
  print("git status")
end, { desc = "git status" })
nx.keymap.set("n", "<leader>gc", function()
  print("git commit")
end, { desc = "git commit" })
