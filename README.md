# dbt.nvim

A Neovim plugin for seamless dbt (data build tool) project navigation and dependency visualization.

## Features

- **Smart Go-to-Definition**: Navigate to dbt models, seeds, and sources with `gd`
- **Dependency Panel**: Visual representation of upstream and downstream dependencies
- **Column Information**: View table schemas directly in Neovim
- **YAML Integration**: Intelligent dbt node detection in schema files
- **Multi-window Support**: Independent panels for each buffer

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "yusufshalaby/dbt.nvim",
  -- only loads if opened in an existing dbt_project
  cond = function()
      local cwd = vim.uv.cwd()
      local path = cwd .. "/dbt_project.yml"
      local stat = vim.uv.fs_stat(path)
      return stat ~= nil
  end,
  config = function()
    require("dbt").setup()
  end,
}
```

Using [packer.nvim](https://github.com/wbthomason/packer.nvim):

```lua
use {
  "yusufshalaby/dbt.nvim",
  config = function()
    require("dbt").setup()
  end,
}
```

## Requirements

- Neovim 0.9+ with Treesitter support
- A dbt project with compiled artifacts:
  - `target/manifest.json` (required)
  - `target/catalog.json` (optional, for column information)
  - `dbt_project.yml` (required)

Run `dbt compile` or `dbt run` in your dbt project to generate these files.

## Usage

### Commands

- `:DBTUI` - Toggle the dependency panel

### Keymaps

- `gd` (normal mode) - Go to definition:
  - Jump to the dbt model or seed file.

### Dependency Panel

The panel shows contextual information about the current dbt node:

**Title Section**
- Node type (Model/Seed/Source/Snapshot) and name
- Click to navigate to YAML documentation (patch path)

**Parents Section** (collapsible)
- Upstream dependencies
- Shows all parent models, seeds, snapshots, and sources
- Press `<CR>` on any item to navigate to its source file

**Children Section** (collapsible)
- Downstream dependencies
- Shows all dependent models and snapshots
- Press `<CR>` on any item to navigate to its source file

**Columns Section** (collapsible)
- Table schema with column names and types
- Sorted by column index
- Requires `target/catalog.json`

### Navigation

The dependency panel automatically updates when:
- You open a SQL or CSV file
- You save a YAML file
- Your cursor moves to a different dbt node in a YAML file

Press `<CR>` (Enter) on any highlighted item to navigate or toggle sections.

## How It Works

dbt.nvim reads your dbt project's compiled artifacts to understand the lineage graph:

1. Parses `target/manifest.json` for node relationships
2. Extracts column information from `target/catalog.json`
3. Uses Treesitter to detect dbt nodes in YAML schema files
4. Maintains separate UI instances for each window

The plugin intelligently detects which dbt node you're working on by:
- Matching file paths for SQL/CSV files
- Parsing YAML structure for schema definitions
- Tracking cursor position across YAML nodes

## Supported Node Types

- **Models** - SQL transformations
- **Seeds** - CSV data files
- **Sources** - External data sources
- **Snapshots** - Type-2 slowly changing dimensions

## Configuration

Currently, the plugin works with default settings. Call `setup()` to initialize:

```lua
require("dbt").setup()
```

## Tips

- Keep your dbt artifacts up to date by running `dbt compile` after making changes
- Use `target/catalog.json` by running `dbt docs generate` to enable column information
- The panel updates automatically as you navigate your project
- Multiple panels can be open simultaneously for different files

## Contributing

Contributions are welcome! Please feel free to submit issues or pull requests.

## License

MIT
