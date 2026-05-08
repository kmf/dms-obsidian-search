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
    property var cachedNotes: []
    property var vaultMap: ({})  // vault name -> vault path
    property int _pendingScans: 0

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

    // Index .md files in each vault
    property Component scanComponent: Component {
        Process {
            id: scanProcess

            property string vaultName: ""
            property string vaultPath: ""

            running: false
            command: ["find", vaultPath, "-type", "f",
                      "(", "-name", "*.md", "-o", "-name", "*.pdf", "-o", "-name", "*.base", ")",
                      "-not", "-path", "*/.obsidian/*", "-not", "-path", "*/.trash/*"]

            stdout: StdioCollector {
                onStreamFinished: {
                    root.onScanFinished(scanProcess.vaultName, scanProcess.vaultPath, text);
                    scanProcess.destroy();
                }
            }

            onExited: exitCode => {
                if (exitCode !== 0) {
                    console.warn("[ObsidianSearch] find failed for", vaultPath, "exit:", exitCode);
                    root._pendingScans--;
                    if (root._pendingScans <= 0)
                        root.itemsChanged();
                    scanProcess.destroy();
                }
            }
        }
    }

    // Build content index: first 30 lines of each .md via awk (fast, single process)
    property Component contentIndexComponent: Component {
        Process {
            id: contentProcess

            property string vaultName: ""
            property string vaultPath: ""

            running: false
            command: ["sh", "-c",
                "find '" + vaultPath + "' -type f \\( -name '*.md' -o -name '*.base' \\) " +
                "-not -path '*/.obsidian/*' -not -path '*/.trash/*' " +
                "-print0 | xargs -0 awk " +
                "'FNR==1{if(NR>1) print \"\"; printf \"%s\\t\", FILENAME} " +
                "FNR<=30{printf \"%s \", $0} END{print \"\"}'"]

            stdout: StdioCollector {
                onStreamFinished: {
                    root.onContentIndexFinished(contentProcess.vaultName, contentProcess.vaultPath, text);
                    contentProcess.destroy();
                }
            }

            onExited: exitCode => {
                if (exitCode !== 0) {
                    console.warn("[ObsidianSearch] content index failed, exit:", exitCode);
                    root._pendingScans--;
                    if (root._pendingScans <= 0)
                        root.itemsChanged();
                    contentProcess.destroy();
                }
            }
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
        root.scanAllVaults();
    }

    function scanAllVaults() {
        root.cachedNotes = [];
        let names = Object.keys(root.vaultMap);
        // We run both find (for the file list) and content index
        root._pendingScans = names.length * 2;
        if (names.length === 0) {
            root.itemsChanged();
            return;
        }
        for (let i = 0; i < names.length; i++) {
            let name = names[i];
            let path = root.vaultMap[name];

            let findProc = scanComponent.createObject(root, {
                vaultName: name,
                vaultPath: path
            });
            findProc.running = true;

            let contentProc = contentIndexComponent.createObject(root, {
                vaultName: name,
                vaultPath: path
            });
            contentProc.running = true;
        }
    }

    // Map fullPath -> content snippet for searching
    property var _contentIndex: ({})

    function onScanFinished(vaultName, vaultPath, data) {
        let lines = data.trim().split("\n");
        let notes = [];
        for (let i = 0; i < lines.length; i++) {
            let fullPath = lines[i].trim();
            if (fullPath.length === 0)
                continue;
            let relative = fullPath.substring(vaultPath.length + 1);
            let fileName = relative.split('/').pop();
            let type = "md";
            if (fileName.endsWith(".pdf")) type = "pdf";
            else if (fileName.endsWith(".base")) type = "base";
            let title = fileName.replace(/\.(md|pdf|base)$/, '');
            let folder = relative.includes('/') ? relative.substring(0, relative.lastIndexOf('/')) : "";
            notes.push({
                title: title,
                folder: folder,
                relative: relative,
                fullPath: fullPath,
                vault: vaultName,
                vaultPath: vaultPath,
                type: type
            });
        }
        root.cachedNotes = root.cachedNotes.concat(notes);
        root._pendingScans--;
        if (root._pendingScans <= 0)
            root.itemsChanged();
    }

    function onContentIndexFinished(vaultName, vaultPath, data) {
        let lines = data.split("\n");
        let idx = root._contentIndex;
        for (let i = 0; i < lines.length; i++) {
            let line = lines[i];
            let tabPos = line.indexOf("\t");
            if (tabPos < 0)
                continue;
            let fullPath = line.substring(0, tabPos);
            let content = line.substring(tabPos + 1).toLowerCase();
            idx[fullPath] = content;
        }
        root._contentIndex = idx;
        root._pendingScans--;
        if (root._pendingScans <= 0)
            root.itemsChanged();
    }

    function getItems(query) {
        if (!root.enabled)
            return [];

        const q = query ? query.trim().toLowerCase() : "";
        if (q === "")
            return root.cachedNotes.slice(0, 50).map(noteToItem);

        let results = [];
        let contentResults = [];

        for (let i = 0; i < root.cachedNotes.length; i++) {
            let n = root.cachedNotes[i];
            // Title/folder match — primary results
            if (n.title.toLowerCase().includes(q) || n.folder.toLowerCase().includes(q)) {
                results.push(noteToItem(n));
            }
            // Content match — secondary results
            else if (q.length >= 3 && root._contentIndex[n.fullPath] &&
                     root._contentIndex[n.fullPath].includes(q)) {
                let item = noteToItem(n);
                item.comment = "Content match - " + item.comment;
                contentResults.push(item);
            }
        }

        return results.concat(contentResults).slice(0, 50);
    }

    function noteToItem(note) {
        let comment = note.vault;
        if (note.folder)
            comment += " / " + note.folder;
        let icon = "description";
        if (note.type === "pdf") icon = "picture_as_pdf";
        else if (note.type === "base") icon = "dataset";
        return {
            name: note.title,
            icon: icon,
            comment: comment,
            action: "open:" + note.vault + ":" + note.relative,
            _fullPath: note.fullPath
        };
    }

    function executeItem(item) {
        if (!item || !item.action)
            return;
        let parts = item.action.replace("open:", "").split(":");
        let vaultName = parts[0];
        let filePath = parts.slice(1).join(":");
        let fileNoExt = filePath.replace(/\.md$/, '');
        let uri = "obsidian://open?vault=" + encodeURIComponent(vaultName) + "&file=" + encodeURIComponent(fileNoExt);
        Quickshell.execDetached(["xdg-open", uri]);
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

    // Settings management
    function updateSettings() {
        if (!root.pluginService)
            return;

        root.enabled = root.pluginService.loadPluginData("obsidianSearch", "enabled", true);
        root.isFlatpak = root.pluginService.loadPluginData("obsidianSearch", "isFlatpak", false);
        root.customVaultPath = root.pluginService.loadPluginData("obsidianSearch", "vaultPath", "");

        let noTrigger = root.pluginService.loadPluginData("obsidianSearch", "noTrigger", false);
        root.trigger = noTrigger ? "" : root.pluginService.loadPluginData("obsidianSearch", "trigger", "note");

        if (!root.enabled) {
            root.cachedNotes = [];
            root._contentIndex = {};
            root.itemsChanged();
        } else {
            root._contentIndex = {};
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

    property var refreshTimer: Timer {
        interval: 300000
        running: root.enabled
        repeat: true
        onTriggered: root.refreshVaults()
    }
}
