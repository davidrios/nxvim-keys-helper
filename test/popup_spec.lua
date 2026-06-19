-- Tests for nxvim-keys-helper, run with `nxvim --test-plugin`.
--
--     nxvim --test-plugin ~/work/nxvim-plugins/nxvim-keys-helper
--
-- They drive a real editor through the `nx.test` framework: feed a leader prefix,
-- wait for the debounced popup, and assert on the floating window's text via
-- `t:float()`. `delay = 0` makes the popup appear on the next tick so a test never
-- waits on a wall-clock timer.

nx.test.describe("nxvim-keys-helper", function()
  nx.test.before_each(function()
    -- Space leader, set BEFORE the maps so <leader> expands to <Space>.
    vim.g.mapleader = " "
    require("nxvim-keys-helper").setup({
      delay = 0,
      spec = {
        { "<leader>f", group = "file" },
        { "<leader>g", group = "git" },
      },
    })
    nx.keymap.set("n", "<leader>w", function() end, { desc = "write" })
    nx.keymap.set("n", "<leader>q", function() end, { desc = "quit" })
    nx.keymap.set("n", "<leader>ff", function() end, { desc = "find file" })
    nx.keymap.set("n", "<leader>fg", function() end, { desc = "live grep" })
    nx.keymap.set("n", "<leader>gs", function() end, { desc = "git status" })
    nx.keymap.set("n", "<leader>gc", function() end, { desc = "git commit" })
  end)

  -- Pressing <leader> and pausing pops the menu of continuations.
  nx.test.it("shows the leader menu on pause", function(t)
    t:feed("<Space>")
    local float = t:wait_for(function()
      return t:float()
    end)
    nx.test.expect(float.text).to_contain("write")
    nx.test.expect(float.text).to_contain("quit")
  end)

  -- A prefix that only leads deeper renders with its registered group name.
  nx.test.it("names groups from the spec", function(t)
    t:feed("<Space>")
    local float = t:wait_for(function()
      return t:float()
    end)
    nx.test.expect(float.text).to_contain("+file")
    nx.test.expect(float.text).to_contain("+git")
  end)

  -- Descending into a group refreshes the popup to that group's keys.
  nx.test.it("refreshes when descending into a group", function(t)
    t:feed("<Space>f")
    local float = t:wait_for(function()
      local f = t:float()
      return f and f.text:find("find file") and f
    end)
    nx.test.expect(float.text).to_contain("find file")
    nx.test.expect(float.text).to_contain("live grep")
    -- The top-level leaves are gone now that we're inside `f`.
    nx.test.expect(float.text).never.to_contain("quit")
  end)

  -- Breaking the sequence (<Esc>) closes the popup.
  nx.test.it("closes when the sequence is aborted", function(t)
    t:feed("<Space>")
    t:wait_for(function()
      return t:float()
    end)
    t:feed("<Esc>")
    local closed = t:wait_for(function()
      return t:float() == nil
    end)
    nx.test.expect(closed).to_be_truthy()
  end)

  -- The built-in command grammar feeds the same popup: pausing after `z` lists the
  -- viewport commands (their continuation keys), no user maps involved.
  nx.test.it("shows the built-in z viewport grammar", function(t)
    t:feed("z")
    local float = t:wait_for(function()
      return t:float()
    end)
    -- `zt` (scroll cursor to top) — its continuation key `t` is listed.
    nx.test.expect(float.text).to_contain("t")
  end)
end)
