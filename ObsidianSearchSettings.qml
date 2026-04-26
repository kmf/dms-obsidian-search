import QtQuick
import qs.Common
import qs.Modules.Plugins
import qs.Widgets

PluginSettings {
    id: root
    pluginId: "obsidianSearch"

    StyledText {
        width: parent.width
        text: "Obsidian Vault Search"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    ToggleSetting {
        settingKey: "enabled"
        label: "Enable Plugin"
        description: "Search notes from your Obsidian vaults in the launcher"
        defaultValue: true
    }

    StringSetting {
        settingKey: "vaultPath"
        label: "Vault Path"
        description: "Manual vault path (e.g. /home/user/Documents/notes). Leave empty to auto-detect."
        defaultValue: ""
    }

    ToggleSetting {
        settingKey: "isFlatpak"
        label: "Obsidian as Flatpak"
        description: "Enable if Obsidian is installed via Flatpak"
        defaultValue: false
    }

    ToggleSetting {
        id: noTriggerToggle
        settingKey: "noTrigger"
        label: "Always Active (No Trigger)"
        description: value ? "Notes always appear in the launcher." : "Use a trigger keyword to search notes."
        defaultValue: false
        onValueChanged: {
            if (value) {
                root.saveValue("trigger", "");
            } else {
                root.saveValue("trigger", triggerSetting.value || "note");
            }
        }
    }

    StringSetting {
        id: triggerSetting
        visible: !noTriggerToggle.value
        settingKey: "trigger"
        label: "Search Trigger"
        description: "Example: '\\note' or 'ob'"
        defaultValue: "note"
    }
}
