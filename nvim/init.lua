-- line numbers (absolute on the cursor line, relative elsewhere)
vim.opt.number = true
vim.opt.relativenumber = true

require("options")
require("config.lazy")
require("remap")
require("statusline")
