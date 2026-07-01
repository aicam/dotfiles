-- mason-tool-installer: auto-installs non-LSP Mason tools (debug adapters); LSP servers are in lsp.lua.
return {
  {
    "WhoIsSethDaniel/mason-tool-installer.nvim",
    dependencies = { "williamboman/mason.nvim" },
    config = function()
      -- Initialize Mason before the tool-installer touches the registry.
      -- mason.setup() is what registers the package registry sources; without it
      -- get_package() errors with "Cannot find package ...". lsp.lua also calls
      -- setup() (on BufReadPre), but that never fires for `nvim <dir>` (netrw),
      -- so the tool-installer, which runs at startup, would crash. setup() is
      -- idempotent, so calling it here too is safe.
      require("mason").setup()

      require("mason-tool-installer").setup({
        ensure_installed = {
          -- Java
          "java-debug-adapter",
          "java-test",
          -- Python
          "debugpy",
          -- TypeScript / JavaScript
          "js-debug-adapter",
        },
      })
    end,
  },
}
