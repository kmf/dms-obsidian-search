import QtQuick
import Quickshell
import qs.Common
import qs.Services

QtObject {
    id: root

    property var pluginService: null
    property string trigger: "note"
    property bool enabled: true
    property string customVaultPath: ""
    property string customCliPath: ""

    signal itemsChanged

    property string homeDir: Quickshell.env("HOME") || "/home"
    property string cliPath: ""
    property var vaultMap: ({})  // vault name -> vault path

    property int searchGen: 0
    property bool haveCache: false
    property string cachedQuery: ""
    property var cachedItems: []

    function notifyChanged() {
        root.itemsChanged();
        if (root.pluginService && typeof root.pluginService.requestLauncherUpdate === "function")
            root.pluginService.requestLauncherUpdate("obsidianSearch");
    }

    // The Electron app at /usr/bin/obsidian hangs in non-TTY contexts. The CLI
    // is a small (~20KB) socket client, typically installed to ~/.local/bin.
    function resolveCli() {
        let args = [
            "sh", "-c",
            'is_cli() { [ -x "$1" ] || return 1; sz=$(wc -c < "$1" 2>/dev/null); [ "$sz" -gt 1000 ] && [ "$sz" -lt 1000000 ]; }; ' +
            'for p in "$@"; do is_cli "$p" && printf "%s\\n" "$p" && exit 0; done; ' +
            'w=$(command -v obsidian 2>/dev/null) || exit 1; ' +
            'is_cli "$w" && printf "%s\\n" "$w" && exit 0; exit 1',
            "obsidian-cli-find"
        ];
        let custom = root.customCliPath.trim();
        if (custom.indexOf("~/") === 0)
            custom = root.homeDir + custom.substring(1);
        if (custom.length > 0)
            args.push(custom);
        args.push(root.homeDir + "/.local/bin/obsidian");
        args.push(root.homeDir + "/bin/obsidian");
        args.push("/usr/local/bin/obsidian");

        Proc.runCommand("obsidianSearch.resolveCli", args, (stdout, code) => {
            let path = (stdout || "").trim().split("\n")[0] || "";
            if (code === 0 && path.length > 0) {
                root.cliPath = path;
                root.refreshVaults();
            } else {
                root.cliPath = "";
                root.vaultMap = {};
                root.haveCache = false;
                console.warn("[ObsidianSearch] Obsidian CLI not found. Install the CLI (https://obsidian.md/help/cli), not the Electron app at /usr/bin/obsidian.");
                root.notifyChanged();
            }
        }, 0, 3000);
    }

    function refreshVaults() {
        if (!root.cliPath) {
            root.parseVaults("");
            return;
        }
        Proc.runCommand("obsidianSearch.vaults", [root.cliPath, "vaults", "verbose"], (stdout, code) => {
            root.parseVaults(stdout || "");
        }, 0, 5000);
    }

    function parseVaults(rawData) {
        let newMap = {};

        if (root.customVaultPath.length > 0) {
            let name = root.customVaultPath.split('/').pop();
            newMap[name] = root.customVaultPath;
        }

        let text = (rawData || "").trim();
        if (text.length > 0 && text.indexOf("Error:") !== 0 && text.indexOf("The CLI is unable") !== 0) {
            let lines = text.split("\n");
            for (let i = 0; i < lines.length; i++) {
                let line = lines[i];
                if (!line || line.length === 0)
                    continue;
                let tab = line.indexOf("\t");
                let name = tab >= 0 ? line.substring(0, tab) : line;
                let vpath = tab >= 0 ? line.substring(tab + 1) : "";
                if (name.length > 0)
                    newMap[name] = vpath;
            }
        }

        root.vaultMap = newMap;
        root.haveCache = false;
        root.notifyChanged();
    }

    function getItems(query) {
        if (!root.enabled)
            return [];

        const q = query ? query.trim() : "";
        if (root.haveCache && q === root.cachedQuery)
            return root.cachedItems;

        root.startSearch(q);
        return [];
    }

    function startSearch(q) {
        root.searchGen += 1;
        const gen = root.searchGen;
        const names = Object.keys(root.vaultMap);

        if (!root.cliPath || names.length === 0) {
            if (gen === root.searchGen) {
                root.cachedQuery = q;
                root.cachedItems = [];
                root.haveCache = true;
            }
            return;
        }

        const perVault = Math.max(10, Math.ceil(50 / names.length));
        let remaining = names.length;
        let combined = [];

        for (let i = 0; i < names.length; i++) {
            const vname = names[i];
            let cmd;
            if (q.length === 0)
                cmd = [root.cliPath, "vault=" + vname, "recents"];
            else
                cmd = [root.cliPath, "vault=" + vname, "search:context", "query=" + q, "limit=" + perVault, "format=json"];

            Proc.runCommand("obsidianSearch.search." + vname, cmd, (stdout, code) => {
                if (gen !== root.searchGen)
                    return;
                if (q.length === 0)
                    combined = combined.concat(root.parseRecentsOutput(stdout, vname));
                else
                    combined = combined.concat(root.parseSearchOutput(stdout, vname));
                remaining -= 1;
                if (remaining <= 0)
                    root.applyResults(gen, q, combined);
            }, 150, 8000);
        }
    }

    function applyResults(gen, q, hits) {
        if (gen !== root.searchGen)
            return;
        let items = [];
        let n = Math.min(50, hits.length);
        for (let i = 0; i < n; i++)
            items.push(root.noteToItem(hits[i], i));
        root.cachedQuery = q;
        root.cachedItems = items;
        root.haveCache = true;
        root.notifyChanged();
    }

    function parseSearchOutput(text, vaultName) {
        let t = (text || "").trim();
        if (!t || t.indexOf("No matches found") === 0 || t.indexOf("Error:") === 0 || t.indexOf("The CLI is unable") === 0)
            return [];

        let data;
        try {
            data = JSON.parse(t);
        } catch (e) {
            console.warn("[ObsidianSearch] search JSON parse failed:", e);
            return [];
        }
        if (!Array.isArray(data))
            return [];

        let vpath = root.vaultMap[vaultName] || "";
        let hits = [];
        for (let j = 0; j < data.length; j++) {
            let entry = data[j];
            let relative = "";
            let snippet = "";
            if (typeof entry === "string") {
                relative = entry;
            } else if (entry && entry.file) {
                relative = entry.file;
                let matches = entry.matches || [];
                if (matches.length > 0 && matches[0] && matches[0].text)
                    snippet = ("" + matches[0].text).trim();
            }
            let note = root.hitFromRelative(relative, vaultName, vpath, snippet);
            if (note)
                hits.push(note);
        }
        return hits;
    }

    function parseRecentsOutput(text, vaultName) {
        let t = (text || "").trim();
        if (!t || t.indexOf("Error:") === 0 || t.indexOf("The CLI is unable") === 0)
            return [];

        let vpath = root.vaultMap[vaultName] || "";
        let lines = t.split("\n");
        let hits = [];
        for (let j = 0; j < lines.length; j++) {
            let relative = lines[j].trim();
            let note = root.hitFromRelative(relative, vaultName, vpath, "");
            if (note)
                hits.push(note);
        }
        return hits;
    }

    function hitFromRelative(relative, vaultName, vpath, snippet) {
        if (!relative || relative.length === 0)
            return null;
        let fileName = relative.split('/').pop();
        let dot = fileName.lastIndexOf('.');
        let ext = dot >= 0 ? fileName.substring(dot + 1).toLowerCase() : "";
        let title = dot >= 0 ? fileName.substring(0, dot) : fileName;
        let folder = relative.includes('/') ? relative.substring(0, relative.lastIndexOf('/')) : "";
        let fullPath = vpath ? (vpath + "/" + relative) : relative;
        return {
            title: title,
            folder: folder,
            relative: relative,
            fullPath: fullPath,
            vault: vaultName,
            ext: ext,
            snippet: snippet
        };
    }

    function noteToItem(note, idx) {
        let comment = note.snippet || "";
        if (comment.length > 100)
            comment = comment.substring(0, 97) + "...";
        if (!comment) {
            comment = note.vault;
            if (note.folder)
                comment += " / " + note.folder;
        }
        return {
            name: note.title,
            icon: iconForExt(note.ext),
            comment: comment,
            action: "open:" + note.vault + ":" + note.relative,
            categories: ["Obsidian"],
            _fullPath: note.fullPath,
            _ext: note.ext,
            _preScored: 900 - (idx || 0)
        };
    }

    function iconForExt(ext) {
        switch (ext) {
        case "md":     return "description";
        case "pdf":    return "picture_as_pdf";
        case "base":   return "dataset";
        case "canvas": return "schema";
        case "png": case "jpg": case "jpeg": case "gif": case "webp": case "svg": case "bmp":
            return "image";
        case "mp4": case "mov": case "webm": case "mkv": case "avi":
            return "movie";
        case "mp3": case "wav": case "ogg": case "flac": case "m4a":
            return "music_note";
        case "txt": case "log":
            return "text_snippet";
        case "json": case "yaml": case "yml": case "toml": case "xml":
            return "data_object";
        case "zip": case "tar": case "gz": case "7z":
            return "folder_zip";
        default:
            return "description";
        }
    }

    function executeItem(item) {
        if (!item || !item.action)
            return;
        let parts = item.action.replace("open:", "").split(":");
        let vaultName = parts[0];
        let filePath = parts.slice(1).join(":");
        let ext = (item._ext || "").toLowerCase();

        // Files Obsidian opens natively go through the CLI (or URI fallback);
        // everything else opens with the system default app.
        if (ext === "md" || ext === "canvas" || ext === "base" || ext === "pdf" || ext === "") {
            if (root.cliPath) {
                Quickshell.execDetached([root.cliPath, "vault=" + vaultName, "open", "path=" + filePath]);
            } else {
                let target = ext === "md" ? filePath.replace(/\.md$/, '') : filePath;
                let uri = "obsidian://open?vault=" + encodeURIComponent(vaultName) + "&file=" + encodeURIComponent(target);
                Quickshell.execDetached(["xdg-open", uri]);
            }
        } else {
            Quickshell.execDetached(["xdg-open", item._fullPath]);
        }
    }

    function getContextMenuActions(item) {
        if (!item || !item.action)
            return [];
        return [
            {
                icon: "content_copy",
                text: "Copy path",
                action: () => {
                    let fullPath = item._fullPath || "";
                    Quickshell.execDetached(["sh", "-c", "echo -n '" + fullPath.replace(/'/g, "'\\''") + "' | dms cl copy"]);
                }
            },
            {
                icon: "folder_open",
                text: "Open folder",
                action: () => {
                    let fullPath = item._fullPath || "";
                    let dir = fullPath.substring(0, fullPath.lastIndexOf('/'));
                    Quickshell.execDetached(["xdg-open", dir]);
                }
            }
        ];
    }

    function updateSettings() {
        if (!root.pluginService)
            return;

        root.enabled = root.pluginService.loadPluginData("obsidianSearch", "enabled", true);
        root.customVaultPath = root.pluginService.loadPluginData("obsidianSearch", "vaultPath", "");
        root.customCliPath = root.pluginService.loadPluginData("obsidianSearch", "cliPath", "");

        let noTrigger = root.pluginService.loadPluginData("obsidianSearch", "noTrigger", false);
        root.trigger = noTrigger ? "" : root.pluginService.loadPluginData("obsidianSearch", "trigger", "note");
        SettingsData.setPluginAllowWithoutTrigger("obsidianSearch", noTrigger);

        if (!root.enabled) {
            root.vaultMap = {};
            root.haveCache = false;
            root.cachedItems = [];
            root.notifyChanged();
        } else {
            root.resolveCli();
        }
    }

    Component.onCompleted: root.updateSettings()

    property var settingsListener: Connections {
        target: root.pluginService
        function onPluginDataChanged(pluginId) {
            if (pluginId === "obsidianSearch")
                root.updateSettings();
        }
    }

    property var initTimer: Timer {
        interval: 500
        running: true
        repeat: false
        onTriggered: {
            if (root.enabled)
                root.resolveCli();
        }
    }
}
