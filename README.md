# Obsidian Vault Search for DMS

A [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell) launcher plugin that searches your Obsidian vaults using the [Obsidian CLI](https://obsidian.md/help/cli).

danksearch / `dsearch` is no longer used or required.

## Features

- Full-text search through Obsidian itself (filenames, folders, note content)
- Obsidian search operators (`file:`, tags, properties, `"exact phrase"`)
- Empty query lists recently opened files
- Auto-discovers vaults with `obsidian vaults`
- Optional extra vault path
- Opens `.md` / `.canvas` / `.base` / `.pdf` in Obsidian; other files open in their default app
- Context menu: copy path, open containing folder
- Always-active mode (skip the trigger keyword)
- Native and Flatpak Obsidian — the CLI finds the running instance
- Shows **Obsidian isn't running** when the app is closed; select it to launch Obsidian

## Requirements

- DankMaterialShell >= 1.5.0
- Quickshell
- Obsidian **running** (1.12 installer or newer, native or Flatpak)
- [Obsidian CLI](https://obsidian.md/help/cli) enabled and registered

The CLI is a small binary that talks to the live Obsidian app. It is **not** `/usr/bin/obsidian` (the Electron app). That binary hangs when launched without a TTY.

### Enable the Obsidian CLI

1. Use a current Obsidian installer (1.12.7+).
2. In Obsidian: **Settings → General → Command line interface** — turn it on.
3. Follow the prompt to register the CLI on your `PATH`.
4. On Linux the binary is copied to `~/.local/bin/obsidian`. Make sure `~/.local/bin` is on your `PATH`, or set **Obsidian CLI Path** in the plugin settings.

Confirm it works:

```bash
obsidian version
obsidian help
```

## Installation

```bash
mkdir -p ~/.config/DankMaterialShell/plugins/obsidianSearch
cp ObsidianSearch.qml ObsidianSearchSettings.qml StartupCheck.qml plugin.json \
  ~/.config/DankMaterialShell/plugins/obsidianSearch/
```

Restart DMS to discover the plugin, or reload if it is already known:

```bash
dms ipc plugins reload obsidianSearch
```

Enable it in DMS **Settings → Plugins**.

## Usage

Type `\note` (or your configured trigger) in the DMS launcher, then your query. With no query, recently opened files are shown.

Queries are passed through to Obsidian search:

| Query | Meaning |
|---|---|
| `meeting notes` | Words anywhere in the note |
| `"exact phrase"` | Exact phrase |
| `file:invoice` | Match in the filename |
| `tag:#work` | Notes with that tag |
| `[status:active]` | Notes with that property |

Select a result to open it. Right-click for **Copy path** and **Open folder**.

Obsidian must be running. The CLI only talks to a live app instance. If the app is closed, the launcher shows **Obsidian isn't running** — select that row to start it.

## Settings

Configure via DMS plugin settings:

| Setting | Description | Default |
|---|---|---|
| Enable Plugin | Turn launcher results on or off | on |
| Vault Path | Optional extra vault path. Leave empty to use vaults reported by the CLI. | empty |
| Obsidian CLI Path | Path to the CLI binary (typically `~/.local/bin/obsidian`). Leave empty to auto-detect. Do not point this at `/usr/bin/obsidian`. | empty |
| Always Active | When ON, notes appear in any launcher search. When OFF, notes only appear when you type the trigger keyword (syncs with DMS Plugin Visibility). | off |
| Search Trigger | Keyword to activate search | `note` |

## Troubleshooting

**Launcher says “Obsidian isn't running”**

The CLI cannot search unless the Obsidian app is open. Select that result to launch Obsidian, wait a couple of seconds, and search again.

**No results, or the plugin will not enable**

- Obsidian is not running — start it and try again.
- CLI not installed — `obsidian version` should print a version, not hang. See [Obsidian CLI](https://obsidian.md/help/cli).
- Wrong binary — `/usr/bin/obsidian` is the app, not the CLI. Set **Obsidian CLI Path** to `~/.local/bin/obsidian`.
- After registering the CLI, reload the plugin: `dms ipc plugins reload obsidianSearch`.

## License

MIT
