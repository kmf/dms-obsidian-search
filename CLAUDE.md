# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A DMS (DankMaterialShell) launcher plugin that searches Obsidian vault files via the Obsidian CLI (`obsidian search` / `obsidian recents` / `obsidian vaults`). Written in QML for the Quickshell framework. No build step — QML files are interpreted at runtime by DMS.

## Deploy and test

```bash
# Copy plugin to DMS plugins directory and reload
cp ObsidianSearch.qml ObsidianSearchSettings.qml StartupCheck.qml plugin.json \
  ~/.config/DankMaterialShell/plugins/obsidianSearch/

# Reload (works when plugin is already known to DMS)
dms ipc plugins reload obsidianSearch

# If plugin dir was removed/recreated, DMS needs a full restart to discover it
# dms ipc plugins reload will return PLUGIN_NOT_FOUND in that case
```

## Architecture

**DMS launcher plugin contract** — DMS injects `pluginService` and calls:
- `getItems(query)` → must return results **synchronously** (array of `{name, icon, comment, action}`)
- `executeItem(item)` → called when user selects a result
- `getContextMenuActions(item)` → optional right-click actions
- `signal itemsChanged` → tells DMS the dataset changed, but DMS does **not** re-call `getItems` for the current query from this signal alone
- `pluginService.requestLauncherUpdate(pluginId)` → DMS 1.5+ re-runs launcher search for the current query (used after async CLI results arrive)

**Search backend: Obsidian CLI** — On startup, `resolveCli` finds the small CLI binary (typically `~/.local/bin/obsidian`, never the Electron app). `obsidian vaults verbose` discovers vault names and paths. `getItems` kicks off a debounced `Proc.runCommand` (`search:context` for queries, `recents` for empty) and returns a cache if the query already completed. When stdout arrives, results are cached and `requestLauncherUpdate("obsidianSearch")` refreshes the launcher.

**Hard dependency on the CLI + a running Obsidian instance** — The CLI is a ~20KB socket client (`$XDG_RUNTIME_DIR/.obsidian-cli.sock`, or the Flatpak equivalent). If the CLI is missing or Obsidian is not running, `getItems` returns an empty list and logs to console.

## Key constraints learned during development

- **DMS `getItems` must return synchronously.** Subprocess search is async. Cache results keyed by query and call `pluginService.requestLauncherUpdate("obsidianSearch")` when they arrive so the current query is re-fetched. Do not block the UI with a synchronous CLI spawn.
- **Never invoke `/usr/bin/obsidian` (the Electron app).** It hangs in non-TTY contexts. Identify the CLI by size (~20KB, reject binaries ≥ 1MB) and prefer `~/.local/bin/obsidian`.
- **`vault=<name>` must be the first CLI argument** before the command (`obsidian vault=Notes search query=test`).
- **`SplitParser` loses data on large outputs.** `onRunningChanged` fires before all `onRead` callbacks complete. Always use `StdioCollector` + `onStreamFinished`, or `Proc.runCommand` which already does this.
- **`loadPluginData` treats `""` as falsy**, returning the default value. For the "always active" trigger (empty string), read the `noTrigger` boolean flag separately.
- **File opening is extension-aware.** `.md`/`.canvas`/`.base`/`.pdf` (and extension-less recents entries) open via `obsidian open path=...`. Other file types open with `xdg-open` on the full filesystem path.
- **Consumer-level `onValueChanged` on `ToggleSetting` must guard `if (!isInitialized) return;`.** The toggle's `value` flips from `defaultValue` to the loaded value during initial `loadValue()`, firing the signal before `isInitialized` is set. Without the guard, any consumer side-effects (e.g. cross-saving a sibling key like `trigger`) run during load and cascade through `pluginDataChanged` → `reloadChildValues` before siblings finish initializing. Mirrors the pattern in `DankLauncherKeys`.

## Commits

Use conventional commits (e.g. `feat:`, `fix:`, `refactor:`). Mark breaking changes with `!` (e.g. `feat!:`) or a `BREAKING CHANGE:` footer.

**Never commit without reviewing `README.md` first.** If a change affects features, requirements, usage, or settings, update the README in the same commit (or a preceding one). The README is the user-facing source of truth — out-of-date docs are treated as bugs here.

## Settings persistence

Settings are stored by DMS via `pluginService.loadPluginData` / `savePluginData` with string keys matching `settingKey` in `ObsidianSearchSettings.qml`. The plugin ID is `"obsidianSearch"`.
