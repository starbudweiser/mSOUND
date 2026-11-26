import Foundation

/// Textes de l'interface dans les 4 langues (fr, en, es, it). Autre langue système : anglais.
public enum Loc {
    public static var lang: String = {
        for l in Locale.preferredLanguages {
            let c = String(l.prefix(2))
            if ["fr", "en", "es", "it"].contains(c) { return c }
        }
        return "en"
    }()

    private static let table: [String: [String: String]] = [
        "convertTo": ["fr": "Convertir en %@ — mSOUND", "en": "Convert to %@ — mSOUND",
                      "es": "Convertir a %@ — mSOUND", "it": "Converti in %@ — mSOUND"],
        "cancel": ["fr": "Annuler", "en": "Cancel", "es": "Cancelar", "it": "Annulla"],
        "showInFinder": ["fr": "Afficher dans le Finder", "en": "Show in Finder", "es": "Mostrar en el Finder", "it": "Mostra nel Finder"],
        "waiting": ["fr": "En attente", "en": "Waiting", "es": "En espera", "it": "In attesa"],
        "running": ["fr": "En cours", "en": "Converting", "es": "Convirtiendo", "it": "In corso"],
        "done": ["fr": "Terminé", "en": "Done", "es": "Terminado", "it": "Completato"],
        "failed": ["fr": "Échec", "en": "Failed", "es": "Error", "it": "Errore"],
        "cancelled": ["fr": "Annulé", "en": "Cancelled", "es": "Cancelado", "it": "Annullato"],
        "summary": ["fr": "%d sur %d terminés", "en": "%d of %d done", "es": "%d de %d terminados", "it": "%d di %d completati"],
        "sameFormat": ["fr": "Déjà dans ce format", "en": "Already in this format", "es": "Ya está en este formato", "it": "Già in questo formato"],
    ]

    public static func t(_ key: String) -> String { table[key]?[lang] ?? table[key]?["en"] ?? key }
    public static func t(_ key: String, _ args: CVarArg...) -> String { String(format: t(key), arguments: args) }
}

public enum Prefs {
    /// Formats proposés par défaut dans le menu Finder (ordre d'affichage).
    public static let defaultMenuFormats = ["mp3", "m4a", "flac", "wav", "aiff", "alac"]
    public static let audioExtensions: Set<String> = ["wav", "wave", "aif", "aiff", "flac", "mp3", "m4a", "aac", "caf"]

    /// Domaine de préférences de l'appli à partir de l'identifiant de l'appli ou de son extension (…finder).
    public static func appDomain(forBundleID id: String) -> String {
        id.hasSuffix(".finder") ? String(id.dropLast(7)) : id
    }
    /// Schéma d'URL de l'appli : « msound » (version installée) ou « msound-dev ».
    public static func urlScheme(forDomain d: String) -> String { d.hasSuffix(".dev") ? "msound-dev" : "msound" }

    public static func menuFormats(domain: String) -> [String] {
        let saved = UserDefaults(suiteName: domain)?.stringArray(forKey: "menuFormats")
        return (saved?.isEmpty == false ? saved! : defaultMenuFormats)
    }
    public static func displayName(_ f: String) -> String {
        switch f { case "m4a": return "M4A (AAC)"; default: return f.uppercased() }
    }
}
