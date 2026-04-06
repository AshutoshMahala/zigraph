# zgraph Neovim Support

Tree-sitter syntax highlighting and LSP integration for `.zgraph` files in Neovim.

## Prerequisites

- Neovim >= 0.9
- [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter)
- zgraph CLI binary on PATH (for LSP support)

## Setup

### 1. Filetype Detection

Copy `ftdetect/zgraph.vim` to your Neovim config:

```bash
cp ftdetect/zgraph.vim ~/.config/nvim/ftdetect/zgraph.vim
```

Or add this to your `init.lua`:

```lua
vim.filetype.add({
  extension = {
    zgraph = "zgraph",
  },
})
```

### 2. Tree-sitter Parser

Add the zgraph parser to your `nvim-treesitter` config:

```lua
local parser_config = require("nvim-treesitter.parsers").get_parser_configs()
parser_config.zgraph = {
  install_info = {
    url = "https://github.com/markussagen/zigraph",
    files = { "src/parser.c" },
    location = "tree-sitter-zgraph",
    branch = "main",
  },
  filetype = "zgraph",
}
```

Then install the parser:

```vim
:TSInstall zgraph
```

### 3. Highlight Queries

Copy the query files to your Neovim runtime:

```bash
mkdir -p ~/.config/nvim/queries/zgraph
cp queries/zgraph/highlights.scm ~/.config/nvim/queries/zgraph/highlights.scm
cp queries/zgraph/locals.scm ~/.config/nvim/queries/zgraph/locals.scm
```

### 4. LSP Configuration

Using `nvim-lspconfig` (add to your Lua config):

```lua
local lspconfig = require("lspconfig")
local configs = require("lspconfig.configs")

if not configs.zgraph then
  configs.zgraph = {
    default_config = {
      cmd = { "zgraph", "lsp" },
      filetypes = { "zgraph" },
      root_dir = lspconfig.util.find_git_ancestor,
      single_file_support = true,
    },
  }
end

lspconfig.zgraph.setup({})
```

Or using manual LSP start (without lspconfig):

```lua
vim.api.nvim_create_autocmd("FileType", {
  pattern = "zgraph",
  callback = function()
    vim.lsp.start({
      name = "zgraph",
      cmd = { "zgraph", "lsp" },
    })
  end,
})
```

### 5. Verify

Open a `.zgraph` file and check:

```vim
:echo &filetype                   " Should show: zgraph
:TSHighlightCapturesUnderCursor   " Should show highlight groups
:LspInfo                          " Should show zgraph LSP attached
```
