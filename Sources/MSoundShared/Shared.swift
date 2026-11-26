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
        "cut": ["fr": "Couper", "en": "Cut", "es": "Cortar", "it": "Taglia"],
        "copy": ["fr": "Copier", "en": "Copy", "es": "Copiar", "it": "Copia"],
        "paste": ["fr": "Coller", "en": "Paste", "es": "Pegar", "it": "Incolla"],
        "delete": ["fr": "Supprimer", "en": "Delete", "es": "Eliminar", "it": "Elimina"],
        "keep": ["fr": "Garder la sélection", "en": "Keep selection", "es": "Conservar selección", "it": "Mantieni selezione"],
        "split": ["fr": "Séparer ici", "en": "Split here", "es": "Dividir aquí", "it": "Dividi qui"],
        "marker": ["fr": "Ajouter un repère", "en": "Add marker", "es": "Añadir marcador", "it": "Aggiungi marcatore"],
        "merge": ["fr": "Fusionner un fichier à la fin…", "en": "Append a file…", "es": "Añadir un archivo al final…", "it": "Aggiungi un file in coda…"],
        "undo": ["fr": "Annuler", "en": "Undo", "es": "Deshacer", "it": "Annulla"],
        "redo": ["fr": "Rétablir", "en": "Redo", "es": "Rehacer", "it": "Ripeti"],
        "zoomIn": ["fr": "Zoom avant", "en": "Zoom in", "es": "Acercar", "it": "Ingrandisci"],
        "zoomOut": ["fr": "Zoom arrière", "en": "Zoom out", "es": "Alejar", "it": "Riduci"],
        "fit": ["fr": "Tout afficher", "en": "Show all", "es": "Mostrar todo", "it": "Mostra tutto"],
        "markers": ["fr": "Repères", "en": "Markers", "es": "Marcadores", "it": "Marcatori"],
        "markerName": ["fr": "Repère %d", "en": "Marker %d", "es": "Marcador %d", "it": "Marcatore %d"],
        "detectSilences": ["fr": "Repères aux silences", "en": "Markers at silences", "es": "Marcadores en silencios", "it": "Marcatori ai silenzi"],
        "noMarkers": ["fr": "Aucun repère.\nTouche M pour en ajouter un.", "en": "No markers.\nPress M to add one.", "es": "Sin marcadores.\nPulsa M para añadir uno.", "it": "Nessun marcatore.\nPremi M per aggiungerne uno."],
        "noSelection": ["fr": "Aucune sélection.\nGlissez sur la forme d'onde.", "en": "No selection.\nDrag across the waveform.", "es": "Sin selección.\nArrastra sobre la forma de onda.", "it": "Nessuna selezione.\nTrascina sulla forma d'onda."],
        "dropHint": ["fr": "Déposez un fichier audio pour l'ouvrir", "en": "Drop an audio file to open it", "es": "Suelta un archivo de audio para abrirlo", "it": "Rilascia un file audio per aprirlo"],
        "montage": ["fr": "Montage", "en": "Edit", "es": "Montaje", "it": "Montaggio"],
        "segments": ["fr": "Segments", "en": "Segments", "es": "Segmentos", "it": "Segmenti"],
        "file": ["fr": "Fichier", "en": "File", "es": "Archivo", "it": "File"],
        "selection": ["fr": "Sélection", "en": "Selection", "es": "Selección", "it": "Selezione"],
        "whole": ["fr": "Tout le fichier", "en": "Whole file", "es": "Archivo completo", "it": "Intero file"],
        "duration": ["fr": "Durée", "en": "Duration", "es": "Duración", "it": "Durata"],
        "sampleRate": ["fr": "Fréquence", "en": "Sample rate", "es": "Frecuencia", "it": "Frequenza"],
        "channels": ["fr": "Canaux", "en": "Channels", "es": "Canales", "it": "Canali"],
        "bitDepth": ["fr": "Profondeur", "en": "Bit depth", "es": "Profundidad", "it": "Profondità"],
        "size": ["fr": "Poids", "en": "Size", "es": "Tamaño", "it": "Dimensione"],
        "start": ["fr": "Début", "en": "Start", "es": "Inicio", "it": "Inizio"],
        "end": ["fr": "Fin", "en": "End", "es": "Fin", "it": "Fine"],
        "exportTitle": ["fr": "Convertir / exporter", "en": "Convert / export", "es": "Convertir / exportar", "it": "Converti / esporta"],
        "quality": ["fr": "Qualité", "en": "Quality", "es": "Calidad", "it": "Qualità"],
        "scope": ["fr": "Portée", "en": "Scope", "es": "Alcance", "it": "Ambito"],
        "exportSelection": ["fr": "Exporter la sélection", "en": "Export selection", "es": "Exportar selección", "it": "Esporta selezione"],
        "exportWhole": ["fr": "Exporter le fichier", "en": "Export file", "es": "Exportar archivo", "it": "Esporta file"],
        "edited": ["fr": "édité", "en": "edited", "es": "editado", "it": "modificato"],
        "selSuffix": ["fr": "sélection", "en": "selection", "es": "selección", "it": "selezione"],
        "loading": ["fr": "Calcul des formes d'onde…", "en": "Computing waveforms…", "es": "Calculando formas de onda…", "it": "Calcolo delle forme d'onda…"],
        "mergeMismatch": ["fr": "Fusion impossible : nombre de canaux ou fréquence différents.", "en": "Cannot merge: different channel count or sample rate.", "es": "No se puede unir: canales o frecuencia distintos.", "it": "Impossibile unire: canali o frequenza diversi."],
        "editWith": ["fr": "Éditer avec mSOUND", "en": "Edit with mSOUND", "es": "Editar con mSOUND", "it": "Modifica con mSOUND"],
        "about": ["fr": "À propos de mSOUND", "en": "About mSOUND", "es": "Acerca de mSOUND", "it": "Informazioni su mSOUND"],
        "quit": ["fr": "Quitter mSOUND", "en": "Quit mSOUND", "es": "Salir de mSOUND", "it": "Esci da mSOUND"],
        "menuFile": ["fr": "Fichier", "en": "File", "es": "Archivo", "it": "File"],
        "menuEdit": ["fr": "Édition", "en": "Edit", "es": "Edición", "it": "Modifica"],
        "menuPlay": ["fr": "Lecture", "en": "Playback", "es": "Reproducción", "it": "Riproduzione"],
        "menuWindow": ["fr": "Fenêtre", "en": "Window", "es": "Ventana", "it": "Finestra"],
        "open": ["fr": "Ouvrir…", "en": "Open…", "es": "Abrir…", "it": "Apri…"],
        "close": ["fr": "Fermer", "en": "Close", "es": "Cerrar", "it": "Chiudi"],
        "export": ["fr": "Exporter", "en": "Export", "es": "Exportar", "it": "Esporta"],
        "selectAll": ["fr": "Tout sélectionner", "en": "Select all", "es": "Seleccionar todo", "it": "Seleziona tutto"],
        "playPause": ["fr": "Lecture / Pause", "en": "Play / Pause", "es": "Reproducir / Pausa", "it": "Riproduci / Pausa"],
        "toStart": ["fr": "Aller au début", "en": "Go to start", "es": "Ir al inicio", "it": "Vai all'inizio"],
        "toEnd": ["fr": "Aller à la fin", "en": "Go to end", "es": "Ir al final", "it": "Vai alla fine"],
        "openFailed": ["fr": "Impossible d'ouvrir ce fichier audio.", "en": "Cannot open this audio file.", "es": "No se puede abrir este archivo de audio.", "it": "Impossibile aprire questo file audio."],
    ]

    public static func t(_ key: String) -> String { table[key]?[lang] ?? table[key]?["en"] ?? key }
    public static func t(_ key: String, _ args: CVarArg...) -> String { String(format: t(key), arguments: args) }
}

public enum Prefs {
    /// Formats proposés par défaut dans le menu Finder (ordre d'affichage).
    public static let defaultMenuFormats = ["mp3", "m4a", "flac", "wav", "aiff", "alac", "edit"]
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
