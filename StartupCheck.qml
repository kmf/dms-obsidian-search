import QtQuick
import Quickshell
import qs.Common

QtObject {
    function check(done) {
        const home = Quickshell.env("HOME") || "/home";
        Proc.runCommand("obsidianSearch.depCheck", [
            "sh", "-c",
            'is_cli() { [ -x "$1" ] || return 1; sz=$(wc -c < "$1" 2>/dev/null); [ "$sz" -gt 1000 ] && [ "$sz" -lt 1000000 ]; }; ' +
            'for p in "$@"; do is_cli "$p" && exit 0; done; ' +
            'w=$(command -v obsidian 2>/dev/null) || exit 1; ' +
            'is_cli "$w"',
            "obsidian-cli-check",
            home + "/.local/bin/obsidian",
            home + "/bin/obsidian",
            "/usr/local/bin/obsidian"
        ], (stdout, exitCode) => {
            if (exitCode === 0) {
                done(null);
                return;
            }
            done({
                "title": "Obsidian CLI is required",
                "details": "This plugin uses the Obsidian CLI, a small binary that talks to a running Obsidian instance — not the Electron app at /usr/bin/obsidian.\n\nInstall it from Obsidian (see https://obsidian.md/help/cli). It is typically placed at ~/.local/bin/obsidian.\n\nObsidian itself must be running for search to work."
            });
        });
    }
}
