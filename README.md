# TermList.nvim

TermList.nvim is a Neovim plugin that provides VSCode-like terminal management.

![image](./doc/termlist.png)

# Installation

```lua
  {
    'goropikari/termlist.nvim',
    dependencies = {
      'akinsho/toggleterm.nvim',
    },
    opts = {
      -- default values
      shell = "bash",
      keymaps = {
        toggle   = "<C-t>",
        select   = "<CR>",
        shutdown = "D",
        rename   = "r",
        add      = "<C-n>",
      },
    },
  },

```

# Usage

## Open / Close the terminal manager

```lua
:lua require("termlist").toggle()
```

## Default Keymaps (in terminal list window)

- `<CR>`: Select terminal
- `D`: Shutdown terminal
- `r`: Rename terminal
- `<C-n>`: Add new terminal
