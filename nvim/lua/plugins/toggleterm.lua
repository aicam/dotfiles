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

      -- <C-t>: always open a brand-new terminal in a right-hand vertical split
      -- (creates a fresh one each press, even if terminals already exist).
      local Terminal = require("toggleterm.terminal").Terminal
      local function new_right_terminal()
        Terminal:new({ direction = "vertical" }):open()
      end
      vim.keymap.set("n", "<C-t>", new_right_terminal, { desc = "Terminal: new (right split)" })

      -- in terminal mode: <C-\> toggles, <Esc> exits, movement + new-terminal keys
      vim.api.nvim_create_autocmd("TermOpen", {
        pattern = "term://*toggleterm#*",
        callback = function()
          local opts = { buffer = 0 }
          vim.keymap.set("t", "<C-\\>", [[<Cmd>ToggleTerm<CR>]], opts)
          vim.keymap.set("t", "<Esc>", [[<C-\><C-n>]], opts)
          -- window movement: <C-l> left, <C-r> right (matches smart-splits)
          vim.keymap.set("t", "<C-l>", [[<C-\><C-n><C-w>h]], opts)
          vim.keymap.set("t", "<C-r>", [[<C-\><C-n><C-w>l]], opts)
          vim.keymap.set("t", "<C-h>", [[<C-\><C-n><C-w>h]], opts)
          vim.keymap.set("t", "<C-j>", [[<C-\><C-n><C-w>j]], opts)
          vim.keymap.set("t", "<C-k>", [[<C-\><C-n><C-w>k]], opts)
          -- open another terminal on the right from inside a terminal
          vim.keymap.set("t", "<C-t>", function() new_right_terminal() end, opts)
        end,
      })
    end,
  },
}
