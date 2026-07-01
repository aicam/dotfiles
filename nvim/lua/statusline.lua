-- Always-visible global statusline.
-- Left side shows the git repository (owner/repo, derived from the remote URL)
-- and the current branch; right side shows filetype and cursor position.

vim.opt.laststatus = 3 -- one global statusline shared by all windows

local repo_cache = {}   -- git root -> "owner/repo" | false
local branch_cache = {} -- git root -> branch name  | false

-- Git root of the current buffer (or cwd for unnamed/special buffers).
local function git_root()
  local name = vim.api.nvim_buf_get_name(0)
  local dir = (name ~= "" and vim.fs.dirname(name)) or vim.fn.getcwd()
  return vim.fs.root(dir, ".git")
end

-- Reduce a remote URL to "owner/repo" (works for ssh and https forms).
local function parse_repo(url)
  if not url or url == "" then return nil end
  url = vim.trim(url):gsub("%.git$", "")
  return url:match("[:/]([^/]+/[^/]+)$")
end

-- Pick a remote (the current branch's upstream, else origin, else the first)
-- and turn its URL into "owner/repo".
local function remote_repo(root)
  local remote
  local up = vim.fn.systemlist({ "git", "-C", root, "rev-parse", "--abbrev-ref", "@{upstream}" })[1]
  if vim.v.shell_error == 0 and up and up:find("/") then
    remote = up:match("^([^/]+)/")
  end
  if not remote then
    local remotes = vim.fn.systemlist({ "git", "-C", root, "remote" })
    remote = vim.tbl_contains(remotes, "origin") and "origin" or remotes[1]
  end
  if not remote or remote == "" then return nil end
  return parse_repo(vim.fn.systemlist({ "git", "-C", root, "remote", "get-url", remote })[1])
end

local function repo_name(root)
  if repo_cache[root] == nil then
    repo_cache[root] = remote_repo(root) or false
  end
  return repo_cache[root] or nil
end

local function branch_name(root)
  local b = vim.b.gitsigns_head -- kept fresh by gitsigns for file buffers
  if b and b ~= "" then return b end
  if branch_cache[root] == nil then
    local out = vim.fn.systemlist({ "git", "-C", root, "branch", "--show-current" })[1]
    branch_cache[root] = (vim.v.shell_error == 0 and out and out ~= "") and out or false
  end
  return branch_cache[root] or nil
end

-- "owner/repo · branch" for the current buffer's repo (either part may be absent).
function _G.statusline_git()
  local root = git_root()
  if not root then return "" end
  local repo, branch = repo_name(root), branch_name(root)
  if repo and branch then return repo .. " · " .. branch end
  return repo or branch or ""
end

-- A clean buffer label (special buffers get friendly names, not "filesystem [1]").
function _G.statusline_file()
  local ft = vim.bo.filetype
  if ft == "neo-tree" then return "explorer" end
  if ft == "toggleterm" then return "terminal " .. (vim.b.toggle_number or "") end
  if ft == "TelescopePrompt" then return "telescope" end
  local name = vim.fn.expand("%:.")
  return name ~= "" and name or "[No Name]"
end

vim.opt.statusline = table.concat({
  "  %{v:lua.statusline_git()}", -- repo · branch
  "   %{v:lua.statusline_file()}",
  "%( %m%)",                     -- [+] when modified
  "%=",                          -- right-align what follows
  "%y ",                         -- filetype
  " %l:%c ",                     -- line:column
})

-- Remote/branch can change outside nvim; drop the caches on the usual triggers.
vim.api.nvim_create_autocmd({ "DirChanged", "FocusGained" }, {
  callback = function()
    repo_cache, branch_cache = {}, {}
  end,
})

-- Terminal/tab title: emit "repo · branch" so multiplexer tabs (WezTerm, tmux,
-- Ghostty, ...) show it instead of user@host. Falls back to the cwd name when
-- there's no git repo.
function _G.statusline_title()
  local git = _G.statusline_git()
  if git ~= "" then return git end
  local cwd = vim.fn.fnamemodify(vim.fn.getcwd(), ":t")
  return cwd ~= "" and cwd or "nvim"
end

vim.opt.title = true
vim.opt.titlestring = "%{v:lua.statusline_title()}"
