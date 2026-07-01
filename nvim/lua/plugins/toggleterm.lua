-- Toggle a terminal from any buffer with <C-\>; run code, then hide it again.
return {
  {
    "akinsho/toggleterm.nvim",
    version = "*",
    -- load at startup so the <C-\> open_mapping always exists
    lazy = false,
    config = function()
      require("toggleterm").setup({
        open_mapping = [[<c-\>]], -- Ctrl-\ toggles the terminal from any tab
        direction = "float",      -- "float" | "horizontal" | "vertical"
        float_opts = { border = "curved" },
        start_in_insert = true,
        -- vertical (right-side) terminals get ~40% of the window width
        size = function(term)
          if term.direction == "vertical" then
            return math.floor(vim.o.columns * 0.4)
          end
          return 15
        end,
      })

      -- Right-side terminals behave like IDE tabs: each one is a full-height
      -- vertical split, and only one is visible at a time. Opening or switching
      -- hides the others instead of stacking them.
      local termmod = require("toggleterm.terminal")
      local Terminal = termmod.Terminal

      -- Show `term` full-height on the right, hiding every other open terminal.
      local function focus_only(term)
        for _, t in ipairs(termmod.get_all(true)) do
          if t.id ~= term.id and t:is_open() then
            t:close()
          end
        end
        if term:is_open() then
          local win = vim.fn.bufwinid(term.bufnr)
          if win ~= -1 then vim.api.nvim_set_current_win(win) end
        else
          term:open()
        end
      end

      -- <C-t>: open a brand-new full-height terminal (hides the current one).
      local function new_right_terminal()
        focus_only(Terminal:new({ direction = "vertical" }))
      end
      vim.keymap.set("n", "<C-t>", new_right_terminal, { desc = "Terminal: new (right split)" })

      -- ]t / [t: switch to the next / previous terminal, keeping it full-height.
      local function cycle_terminal(step)
        local all = termmod.get_all(true)
        if #all == 0 then
          return new_right_terminal()
        end
        local idx = 1
        for i, t in ipairs(all) do
          if t:is_open() then idx = i break end
        end
        focus_only(all[((idx - 1 + step) % #all) + 1])
      end
      vim.keymap.set("n", "]t", function() cycle_terminal(1) end, { desc = "Terminal: next" })
      vim.keymap.set("n", "[t", function() cycle_terminal(-1) end, { desc = "Terminal: previous" })

      -- <C-S-=>/<C-S-+>: expand the terminal to (nearly) full screen.
      -- <C-S-->        : snap it back to the default right-hand ~40% column.
      -- (Ctrl+= / Ctrl+- without Shift are Ghostty's font zoom, so we use Shift.
      --  width only; the terminal is already full height.)
      local function term_resize(width)
        if vim.bo.filetype == "toggleterm" then
          vim.cmd("vertical resize " .. width)
        end
      end
      local function term_fullscreen() term_resize(vim.o.columns) end
      local function term_dock_right() term_resize(math.floor(vim.o.columns * 0.4)) end

      -- in terminal mode: <C-\> toggles, <Esc> exits, movement + new-terminal keys
      vim.api.nvim_create_autocmd("TermOpen", {
        pattern = "term://*toggleterm#*",
        callback = function()
          local opts = { buffer = 0 }
          vim.keymap.set("t", "<C-\\>", [[<Cmd>ToggleTerm<CR>]], opts)
          vim.keymap.set("t", "<Esc>", [[<C-\><C-n>]], opts)
          -- window movement, leftward only (the terminal is the rightmost
          -- window). <C-i> is deliberately NOT mapped here: in a terminal it
          -- shares a keycode with <Tab>, so mapping it would steal <Tab> from
          -- the shell's completion. <C-i> still moves right in the editor.
          vim.keymap.set("t", "<C-l>", [[<C-\><C-n><C-w>h]], opts)
          vim.keymap.set("t", "<C-h>", [[<C-\><C-n><C-w>h]], opts)
          vim.keymap.set("t", "<C-j>", [[<C-\><C-n><C-w>j]], opts)
          vim.keymap.set("t", "<C-k>", [[<C-\><C-n><C-w>k]], opts)
          -- open another terminal on the right from inside a terminal
          vim.keymap.set("t", "<C-t>", function() new_right_terminal() end, opts)
          -- resize: <C-S-=>/<C-S-+> full screen, <C-S--> back to the right column
          -- (Shift avoids Ghostty's Ctrl+= / Ctrl+- font zoom). Extra symbol
          -- variants cover how terminals report the shifted keys.
          for _, m in ipairs({ "t", "n" }) do
            vim.keymap.set(m, "<C-S-=>", term_fullscreen, opts)
            vim.keymap.set(m, "<C-S-+>", term_fullscreen, opts)
            vim.keymap.set(m, "<C-S-->", term_dock_right, opts)
            vim.keymap.set(m, "<C-S-_>", term_dock_right, opts)
          end
        end,
      })
    end,
  },
}
