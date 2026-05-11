# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A DMS (DankMaterialShell) launcher plugin that searches Obsidian vault files via the `dsearch` (danksearch) full-text index. Written in QML for the Quickshell framework. No build step — QML files are interpreted at runtime by DMS.

## Deploy and test

```bash
# Copy plugin to DMS plugins directory and reload
cp ObsidianSearch.qml ObsidianSearchSettings.qml plugin.json \
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
- `signal itemsChanged` → tells DMS the dataset changed, but DMS does **not** re-call `getItems` for the current query (only affects next query)

**Search backend: dsearch HTTP API** — On startup, `vaultProcess` reads `obsidian.json` to discover vault names and paths. `getItems` issues a synchronous `XMLHttpRequest` GET to `http://127.0.0.1:43654/search?q=&folder=&type=file&limit=` for each vault. dsearch already maintains an incrementally-updated Bleve index of the filesystem, so the plugin keeps no local cache. Empty queries use `q=*&sort=mtime` to surface recently-modified files.

**Hard dependency on dsearch** — The plugin requires the `dsearch` service to be running and to have the vault path within its indexed roots. If dsearch is unreachable, `getItems` returns an empty list and logs to console.

## Key constraints learned during development

- **DMS `getItems` must return synchronously.** Async results sent later via `itemsChanged` are not displayed for the current query — DMS only re-calls `getItems` on the next query change. Synchronous localhost `XMLHttpRequest` to dsearch satisfies this; subprocess-based approaches (Quickshell `Process`) cannot.
- **Obsidian CLI (`/usr/bin/obsidian`) hangs in non-TTY contexts.** The Electron binary needs a TTY to communicate with the running instance. Do not use it from Quickshell `Process`. Use the `obsidian://` URI scheme via `xdg-open` instead.
- **`SplitParser` loses data on large outputs.** `onRunningChanged` fires before all `onRead` callbacks complete. Always use `StdioCollector` + `onStreamFinished` for any remaining `Process` usage.
- **`loadPluginData` treats `""` as falsy**, returning the default value. For the "always active" trigger (empty string), read the `noTrigger` boolean flag separately.
- **File opening is extension-aware.** Obsidian's URI scheme opens `.md`/`.canvas`/`.base`/`.pdf` natively (stripping `.md` only). Other file types are opened with `xdg-open` on the full filesystem path.

## Commits

Use conventional commits (e.g. `feat:`, `fix:`, `refactor:`). Mark breaking changes with `!` (e.g. `feat!:`) or a `BREAKING CHANGE:` footer.

**Never commit without reviewing `README.md` first.** If a change affects features, requirements, usage, or settings, update the README in the same commit (or a preceding one). The README is the user-facing source of truth — out-of-date docs are treated as bugs here.

## Settings persistence

Settings are stored by DMS via `pluginService.loadPluginData` / `savePluginData` with string keys matching `settingKey` in `ObsidianSearchSettings.qml`. The plugin ID is `"obsidianSearch"`.
