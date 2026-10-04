import Foundation

/// The app was named "Reader" (bundle ID io.github.reader.Reader). Its settings are copied one time to the
/// settings of Scholia. A setting that Scholia already has is kept.
public enum SettingsMigration {
    public static let legacyDomain = "io.github.reader.Reader"
    static let marker = "migratedFromReader"

    public static func copyLegacy(from old: UserDefaults? = UserDefaults(suiteName: legacyDomain), to new: UserDefaults = .standard) {
        guard !new.bool(forKey: marker), let old else { return }
        let keys = ["aboutMe", "promptTemplates", "assistant.agent"]
            + old.dictionaryRepresentation().keys.filter { $0.hasPrefix("assistant.model.") }
        for key in keys where new.object(forKey: key) == nil {
            if let value = old.object(forKey: key) { new.set(value, forKey: key) }
        }
        new.set(true, forKey: marker)
    }
}
