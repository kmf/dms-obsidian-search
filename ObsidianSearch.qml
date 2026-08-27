import QtQuick
import Quickshell
import Quickshell.Io
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

    property bool haveCache: false
    property string cachedQuery: ""
    property var cachedItems: []
    property string pendingQuery: ""
    property string activeQuery: ""
    property var remainingVaults: []
    property var combinedHits: []
    property string activeVault: ""
    property int launchId: 0
    property int stdoutId: 0
    property int cliRetries: 0
    property int lastExitCode: 0
    property bool searchOutDone: false
    property bool searchErrDone: false
    property bool searchExitDone: false
    property bool vaultsReady: false
    property string statusKind: ""  // "", "not-running", "no-cli"

    function notifyChanged() {
        root.itemsChanged();
        try {
            if (root.pluginService)
                root.pluginService.requestLauncherUpdate("obsidianSearch");
        } catch (e) {
            console.warn("[ObsidianSearch] requestLauncherUpdate failed:", e);
        }
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
                root.vaultsReady = false;
                console.warn("[ObsidianSearch] Obsidian CLI not found. Install the CLI (https://obsidian.md/help/cli), not the Electron app at /usr/bin/obsidian.");
                root.setStatus("no-cli");
            }
        }, 0, 3000);
    }

    function refreshVaults() {
        if (!root.cliPath) {
            root.parseVaults("");
            return;
        }
        Proc.runCommand("obsidianSearch.vaults", [root.cliPath, "vaults", "verbose"], (stdout, code) => {
            root.vaultsReady = true;
            if (code !== 0) {
                root.parseVaults(stdout || "");
                if (Object.keys(root.vaultMap).length === 0)
                    root.setStatus("not-running");
                return;
            }
            if (root.statusKind === "not-running" || root.statusKind === "no-cli")
                root.statusKind = "";
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
        if (text.length > 0 && !root.isCliError(text)) {
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

    function statusItems() {
        if (root.statusKind === "no-cli") {
            return [{
                name: "Obsidian CLI not found",
                icon: "error_outline",
                comment: "Enable Command line interface in Obsidian Settings → General, then reload this plugin.",
                action: "launch-obsidian:",
                categories: ["Obsidian"],
                _preScored: 1000
            }];
        }
        if (root.statusKind === "not-running") {
            return [{
                name: "Obsidian isn't running",
                icon: "error_outline",
                comment: "Search only works while the Obsidian app is open. Select to launch it.",
                action: "launch-obsidian:",
                categories: ["Obsidian"],
                _preScored: 1000
            }];
        }
        return [];
    }

    function setStatus(kind) {
        root.statusKind = kind;
        root.haveCache = false;
        root.notifyChanged();
    }

    function getItems(query) {
        if (!root.enabled)
            return [];

        const q = query ? query.trim() : "";

        if (root.statusKind && q === root.pendingQuery)
            return root.statusItems();

        if (root.haveCache && q === root.cachedQuery && !root.statusKind)
            return root.cachedItems;

        const searchingThis = q === root.pendingQuery && (searchDebounce.running || searchProc.running);
        if (!searchingThis) {
            root.pendingQuery = q;
            searchDebounce.restart();
        }

        if (root.statusKind)
            return root.statusItems();
        return [];
    }

    function kickSearch() {
        if (!root.cliPath) {
            root.setStatus("no-cli");
            return;
        }
        if (!root.vaultsReady)
            return;
        if (Object.keys(root.vaultMap).length === 0) {
            root.setStatus("not-running");
            return;
        }

        const q = root.pendingQuery;
        if (searchProc.running && root.activeQuery === q)
            return;

        root.cliRetries = 0;
        root.startVaultQueue(q);
    }

    function startVaultQueue(q) {
        root.activeQuery = q;
        root.combinedHits = [];
        root.remainingVaults = Object.keys(root.vaultMap);
        root.runNextVault();
    }

    function runNextVault() {
        if (root.activeQuery !== root.pendingQuery) {
            root.startVaultQueue(root.pendingQuery);
            return;
        }

        if (root.remainingVaults.length === 0) {
            root.applyResults(root.activeQuery, root.combinedHits);
            return;
        }

        let names = root.remainingVaults.slice();
        let vname = names[0];
        root.remainingVaults = names.slice(1);
        root.activeVault = vname;

        let perVault = Math.max(10, Math.ceil(50 / Math.max(1, Object.keys(root.vaultMap).length)));
        let cmd;
        if (root.activeQuery.length === 0)
            cmd = [root.cliPath, "vault=" + vname, "recents"];
        else
            cmd = [root.cliPath, "vault=" + vname, "search", "query=" + root.activeQuery, "limit=" + perVault, "format=json"];

        root.launchId += 1;
        let id = root.launchId;
        root.searchOutDone = false;
        root.searchErrDone = false;
        root.searchExitDone = false;
        searchProc.running = false;
        searchProc.command = cmd;
        Qt.callLater(function () {
            if (id !== root.launchId)
                return;
            root.stdoutId = id;
            searchProc.running = true;
        });
    }

    function finishSearchIo() {
        if (!root.searchOutDone || !root.searchErrDone || !root.searchExitDone)
            return;
        if (root.stdoutId !== root.launchId)
            return;
        if (root.activeQuery !== root.pendingQuery)
            return;

        let out = "";
        let err = "";
        try {
            out = searchProc.stdout.text || "";
        } catch (e) {}
        try {
            err = searchProc.stderr.text || "";
        } catch (e) {}
        root.handleSearchOutput(out, err, root.lastExitCode);
    }

    function handleSearchOutput(out, err, code) {
        let blob = ((out || "") + "\n" + (err || "")).trim();

        if (root.isNotRunning(blob) || (code !== 0 && root.isCliError(blob))) {
            console.warn("[ObsidianSearch] Obsidian isn't running:", blob.split("\n")[0] || ("exit " + code));
            root.setStatus("not-running");
            return;
        }

        if (code !== 0) {
            console.warn("[ObsidianSearch] CLI error:", blob.split("\n")[0] || ("exit " + code));
            if (root.cliRetries < 2) {
                root.cliRetries += 1;
                retryTimer.restart();
                return;
            }
            root.setStatus("not-running");
            return;
        }

        root.statusKind = "";
        root.cliRetries = 0;
        let hits = root.activeQuery.length === 0
            ? root.parseRecentsOutput(out, root.activeVault)
            : root.parseSearchOutput(out, root.activeVault);
        root.combinedHits = root.combinedHits.concat(hits);
        root.runNextVault();
    }

    function applyResults(q, hits) {
        if (q !== root.pendingQuery)
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

    function isNotRunning(text) {
        let t = (text || "");
        return t.indexOf("unable to find Obsidian") !== -1 || t.indexOf("Please make sure Obsidian is running") !== -1;
    }

    function isCliError(text) {
        let t = (text || "").trim();
        return t.indexOf("Error:") === 0 || t.indexOf("The CLI is unable") !== -1;
    }

    function parseSearchOutput(text, vaultName) {
        let t = (text || "").trim();
        if (!t || t.indexOf("No matches found") === 0)
            return [];

        let data = null;
        if (t.charAt(0) === "[") {
            try {
                data = JSON.parse(t);
            } catch (e) {
                console.warn("[ObsidianSearch] search JSON parse failed:", e);
                data = null;
            }
        }

        let paths = [];
        if (Array.isArray(data)) {
            for (let j = 0; j < data.length; j++) {
                let entry = data[j];
                if (typeof entry === "string")
                    paths.push(entry);
                else if (entry && entry.file)
                    paths.push(entry.file);
            }
        } else {
            let lines = t.split("\n");
            for (let j = 0; j < lines.length; j++) {
                let line = lines[j].trim();
                if (line.length > 0 && line.indexOf("Error:") !== 0)
                    paths.push(line);
            }
        }

        let vpath = root.vaultMap[vaultName] || "";
        let hits = [];
        for (let j = 0; j < paths.length; j++) {
            let note = root.hitFromRelative(paths[j], vaultName, vpath, "");
            if (note)
                hits.push(note);
        }
        return hits;
    }

    function parseRecentsOutput(text, vaultName) {
        let t = (text || "").trim();
        if (!t)
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
            _preScored: 950 - (idx || 0)
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
        if (item.action === "launch-obsidian:") {
            Quickshell.execDetached(["xdg-open", "obsidian://open"]);
            launchWaitTimer.restart();
            return;
        }
        if (item.action.indexOf("open:") !== 0)
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
        if (!item || !item.action || item.action.indexOf("open:") !== 0)
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
            root.vaultsReady = false;
            root.haveCache = false;
            root.cachedItems = [];
            root.statusKind = "";
            root.notifyChanged();
        } else {
            root.resolveCli();
        }
    }

    property var searchProc: Process {
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                if (root.stdoutId !== root.launchId)
                    return;
                root.searchOutDone = true;
                root.finishSearchIo();
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (root.stdoutId !== root.launchId)
                    return;
                root.searchErrDone = true;
                root.finishSearchIo();
            }
        }
        onExited: code => {
            if (root.stdoutId !== root.launchId)
                return;
            root.lastExitCode = code;
            root.searchExitDone = true;
            root.finishSearchIo();
        }
    }

    property var searchDebounce: Timer {
        interval: 80
        repeat: false
        onTriggered: root.kickSearch()
    }

    property var retryTimer: Timer {
        interval: 400
        repeat: false
        onTriggered: {
            if (root.pendingQuery === root.activeQuery)
                root.startVaultQueue(root.pendingQuery);
        }
    }

    property var launchWaitTimer: Timer {
        interval: 2000
        repeat: false
        onTriggered: {
            root.statusKind = "";
            root.vaultsReady = false;
            root.refreshVaults();
            searchDebounce.restart();
        }
    }

    property var startTimer: Timer {
        interval: 500
        running: true
        repeat: false
        onTriggered: root.updateSettings()
    }

    Component.onCompleted: root.updateSettings()

    property var settingsListener: Connections {
        target: root.pluginService
        function onPluginDataChanged(pluginId) {
            if (pluginId === "obsidianSearch")
                root.updateSettings();
        }
    }
}
