import QtQuick
import Quickshell
import Quickshell.Io
import qs.Services

QtObject {
    id: root

    property var pluginService: null
    property string trigger: "note"
    property bool enabled: true
    property bool isFlatpak: false
    property string customVaultPath: ""

    signal itemsChanged

    property string homeDir: Quickshell.env("HOME") || "/home"
    property var vaultMap: ({})  // vault name -> vault path
    property string dsearchUrl: "http://127.0.0.1:43654/search"

    // Read obsidian.json to discover vaults
    property var vaultProcess: Process {
        command: ["cat", root.getObsidianConfigPath()]
        running: false

        stdout: StdioCollector {
            onStreamFinished: {
                root.parseVaults(text);
            }
        }

        onExited: exitCode => {
            if (exitCode !== 0 && root.customVaultPath.length > 0)
                root.parseVaults("");
        }
    }

    function getObsidianConfigPath() {
        return root.isFlatpak
            ? root.homeDir + "/.var/app/md.obsidian.Obsidian/config/obsidian/obsidian.json"
            : root.homeDir + "/.config/obsidian/obsidian.json";
    }

    function refreshVaults() {
        root.vaultProcess.command = ["cat", root.getObsidianConfigPath()];
        root.vaultProcess.running = true;
    }

    function parseVaults(rawData) {
        let newMap = {};

        if (root.customVaultPath.length > 0) {
            let name = root.customVaultPath.split('/').pop();
            newMap[name] = root.customVaultPath;
        }

        try {
            if (rawData.length > 0) {
                const data = JSON.parse(rawData);
                if (data && data.vaults) {
                    for (var key in data.vaults) {
                        let entry = data.vaults[key];
                        if (entry && entry.path) {
                            let name = entry.path.split('/').pop();
                            newMap[name] = entry.path;
                        }
                    }
                }
            }
        } catch (e) {
            if (root.customVaultPath.length === 0)
                console.warn("[ObsidianSearch] Failed to parse obsidian.json:", e);
        }

        root.vaultMap = newMap;
        root.itemsChanged();
    }

    // Synchronous localhost call to dsearch HTTP API.
    // Sync XHR blocks JS, but localhost is sub-ms and DMS requires sync getItems.
    function dsearchQuery(q, folder, limit) {
        let params = "type=file&limit=" + limit + "&folder=" + encodeURIComponent(folder);
        if (q.length === 0)
            params = "q=*&sort=mtime&" + params;
        else
            params = "q=" + encodeURIComponent(q) + "&" + params;

        let xhr = new XMLHttpRequest();
        try {
            xhr.open("GET", root.dsearchUrl + "?" + params, false);
            xhr.send();
            if (xhr.status === 200) {
                let data = JSON.parse(xhr.responseText);
                return data.hits || [];
            }
            console.warn("[ObsidianSearch] dsearch HTTP", xhr.status);
        } catch (e) {
            console.warn("[ObsidianSearch] dsearch unreachable:", e);
        }
        return [];
    }

    function getItems(query) {
        if (!root.enabled)
            return [];

        let names = Object.keys(root.vaultMap);
        if (names.length === 0)
            return [];

        const q = query ? query.trim() : "";
        let perVault = Math.max(10, Math.ceil(50 / names.length));
        let all = [];

        for (let i = 0; i < names.length; i++) {
            let vname = names[i];
            let vpath = root.vaultMap[vname];
            let hits = dsearchQuery(q, vpath, perVault);
            for (let j = 0; j < hits.length; j++) {
                let fullPath = hits[j].id;
                if (!fullPath || fullPath.indexOf(vpath + "/") !== 0)
                    continue;
                let relative = fullPath.substring(vpath.length + 1);
                let fileName = relative.split('/').pop();
                let dot = fileName.lastIndexOf('.');
                let ext = dot >= 0 ? fileName.substring(dot + 1).toLowerCase() : "";
                let title = dot >= 0 ? fileName.substring(0, dot) : fileName;
                let folder = relative.includes('/') ? relative.substring(0, relative.lastIndexOf('/')) : "";
                all.push({
                    title: title,
                    folder: folder,
                    relative: relative,
                    fullPath: fullPath,
                    vault: vname,
                    ext: ext,
                    score: hits[j].score || 0
                });
            }
        }

        if (names.length > 1 && q.length > 0)
            all.sort((a, b) => b.score - a.score);

        return all.slice(0, 50).map(noteToItem);
    }

    function noteToItem(note) {
        let comment = note.vault;
        if (note.folder)
            comment += " / " + note.folder;
        return {
            name: note.title,
            icon: iconForExt(note.ext),
            comment: comment,
            action: "open:" + note.vault + ":" + note.relative,
            _fullPath: note.fullPath,
            _ext: note.ext
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

        // Files Obsidian opens natively go through the URI scheme; everything
        // else opens with the system default app via the full filesystem path.
        if (ext === "md" || ext === "canvas" || ext === "base" || ext === "pdf") {
            let target = ext === "md" ? filePath.replace(/\.md$/, '') : filePath;
            let uri = "obsidian://open?vault=" + encodeURIComponent(vaultName) + "&file=" + encodeURIComponent(target);
            Quickshell.execDetached(["xdg-open", uri]);
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
        root.isFlatpak = root.pluginService.loadPluginData("obsidianSearch", "isFlatpak", false);
        root.customVaultPath = root.pluginService.loadPluginData("obsidianSearch", "vaultPath", "");

        let noTrigger = root.pluginService.loadPluginData("obsidianSearch", "noTrigger", false);
        root.trigger = noTrigger ? "" : root.pluginService.loadPluginData("obsidianSearch", "trigger", "note");

        if (!root.enabled) {
            root.vaultMap = {};
            root.itemsChanged();
        } else {
            root.refreshVaults();
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
        onTriggered: root.refreshVaults()
    }
}
