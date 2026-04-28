# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A DMS (DankMaterialShell) launcher plugin that searches Obsidian vault notes. Written in QML for the Quickshell framework. No build step — QML files are interpreted at runtime by DMS.

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

**Two-phase startup indexing:**
1. `scanComponent` — runs `find` to list all `.md` files, populates `cachedNotes`
2. `contentIndexComponent` — runs `find` + `head -c 500` to extract first 500 chars of each file into `_contentIndex` map

Both use dynamic `Component.createObject()` with `StdioCollector` for reliable stdout collection. `_pendingScans` tracks completion of both phases before emitting `itemsChanged`.

**Search in `getItems`** is purely synchronous — filters `cachedNotes` by title/folder, then checks `_contentIndex[fullPath]` for content matches (3+ char queries).

## Key constraints learned during development

- **Obsidian CLI (`/usr/bin/obsidian`) hangs in non-TTY contexts.** The Electron binary needs a TTY to communicate with the running instance. Do not use it from Quickshell `Process`.
- **`SplitParser` loses data on large outputs.** `onRunningChanged` fires before all `onRead` callbacks complete. Always use `StdioCollector` + `onStreamFinished`.
- **Reusable `Process` objects don't reset `StdioCollector`** between runs. Use dynamic `Component.createObject()` + `destroy()` for processes that run multiple times.
- **`onExited` races with `StdioCollector.onStreamFinished`.** Only call `destroy()` in `onExited` for non-zero exit codes. Let `onStreamFinished` handle the success path.
- **`loadPluginData` treats `""` as falsy**, returning the default value. For the "always active" trigger (empty string), read the `noTrigger` boolean flag separately.
- **Content search must be synchronous.** Async grep results via `itemsChanged` never display because DMS doesn't re-call `getItems` for an unchanged query.

## Commits

Use conventional commits (e.g. `feat:`, `fix:`, `refactor:`).

## Settings persistence

Settings are stored by DMS via `pluginService.loadPluginData` / `savePluginData` with string keys matching `settingKey` in `ObsidianSearchSettings.qml`. The plugin ID is `"obsidianSearch"`.
