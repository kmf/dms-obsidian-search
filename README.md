# Obsidian Vault Search for DMS

A [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell) launcher plugin that searches files in your Obsidian vaults by filename, folder, and full content, backed by the [danksearch](https://github.com/AvengeMedia/danksearch) (`dsearch`) full-text index.

## Features

- Full-text search across every file in your vault (not just notes)
- Filename and folder matching with relevance ranking from dsearch
- Auto-discovers vaults from Obsidian's config
- Manual vault path configuration
- Opens `.md` / `.canvas` / `.base` / `.pdf` directly in Obsidian; other file types open in their default app
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

Type `\note` in the DMS launcher followed by your search query. With no query, recently-modified files are shown.

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
- [danksearch](https://github.com/AvengeMedia/danksearch) running locally (`dsearch serve`) with the vault path within an indexed root

## License

MIT
