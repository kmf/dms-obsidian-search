# Obsidian Vault Search for DMS

A [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell) launcher plugin that searches notes in your Obsidian vaults by filename, folder, and content.

## Features

- Search notes by title and folder path
- Content search (first 500 chars of each note, 3+ character queries)
- Auto-discovers vaults from Obsidian's config
- Manual vault path configuration
- Opens notes directly in Obsidian
- Context menu: copy path, open containing folder
- Always-active mode (skip trigger keyword)
- Supports native and Flatpak Obsidian installations

## Installation

Copy the plugin to your DMS plugins directory:

```bash
mkdir -p ~/.config/DankMaterialShell/plugins/obsidianSearch
cp ObsidianSearch.qml ObsidianSearchSettings.qml plugin.json \
  ~/.config/DankMaterialShell/plugins/obsidianSearch/
```

Restart DMS to discover the new plugin.

## Usage

Type `\note` in the DMS launcher followed by your search query. Title and folder matches appear first, content matches appear below.

## Settings

Configure via DMS plugin settings:

| Setting | Description | Default |
|---|---|---|
| Vault Path | Manual vault path, or empty for auto-detect | empty |
| Obsidian as Flatpak | Toggle for Flatpak installations | off |
| Always Active | Show results without trigger keyword | off |
| Search Trigger | Keyword to activate search | `note` |

## Requirements

- DankMaterialShell >= 1.4.0
- Quickshell
- Obsidian (native or Flatpak)

## License

MIT
