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
        "inspector": ["fr": "Inspecteur", "en": "Inspector", "es": "Inspector", "it": "Ispettore"],
        "menuEffects": ["fr": "Effets", "en": "Effects", "es": "Efectos", "it": "Effetti"],
        "normalize": ["fr": "Normaliser", "en": "Normalize", "es": "Normalizar", "it": "Normalizza"],
        "fadeIn": ["fr": "Fondu entrant", "en": "Fade in", "es": "Fundido de entrada", "it": "Dissolvenza in entrata"],
        "fadeOut": ["fr": "Fondu sortant", "en": "Fade out", "es": "Fundido de salida", "it": "Dissolvenza in uscita"],
        "gainUp": ["fr": "Gain +3 dB", "en": "Gain +3 dB", "es": "Ganancia +3 dB", "it": "Guadagno +3 dB"],
        "gainDown": ["fr": "Gain −3 dB", "en": "Gain −3 dB", "es": "Ganancia −3 dB", "it": "Guadagno −3 dB"],
        "normShort": ["fr": "Normal.", "en": "Normalize", "es": "Normal.", "it": "Normal."],
        "fadeInShort": ["fr": "Fondu ↗", "en": "Fade in", "es": "Fund. ↗", "it": "Diss. ↗"],
        "fadeOutShort": ["fr": "Fondu ↘", "en": "Fade out", "es": "Fund. ↘", "it": "Diss. ↘"],
        "normalizing": ["fr": "Normalisation…", "en": "Normalizing…", "es": "Normalizando…", "it": "Normalizzazione…"],
        "silentSel": ["fr": "La sélection est muette.", "en": "The selection is silent.", "es": "La selección está en silencio.", "it": "La selezione è muta."],
        "settings": ["fr": "Réglages…", "en": "Settings…", "es": "Ajustes…", "it": "Impostazioni…"],
        "settingsTitle": ["fr": "Réglages", "en": "Settings", "es": "Ajustes", "it": "Impostazioni"],
        "setFinder": ["fr": "Menu du Finder", "en": "Finder menu", "es": "Menú del Finder", "it": "Menu del Finder"],
        "setFinderHint": ["fr": "Formats proposés au clic droit sur un fichier audio. Activez l'extension dans Réglages Système › Extensions › Finder.", "en": "Formats offered when right-clicking an audio file. Enable the extension in System Settings › Extensions › Finder.", "es": "Formatos ofrecidos al hacer clic derecho en un archivo de audio. Active la extensión en Ajustes del Sistema › Extensiones › Finder.", "it": "Formati proposti con il clic destro su un file audio. Attiva l'estensione in Impostazioni di Sistema › Estensioni › Finder."],
        "setQuality": ["fr": "Qualité des formats compressés (MP3, AAC)", "en": "Compressed format quality (MP3, AAC)", "es": "Calidad de los formatos comprimidos (MP3, AAC)", "it": "Qualità dei formati compressi (MP3, AAC)"],
        "setTheme": ["fr": "Thème", "en": "Theme", "es": "Tema", "it": "Tema"],
        "themeSystem": ["fr": "Automatique", "en": "Automatic", "es": "Automático", "it": "Automatico"],
        "themeDark": ["fr": "Sombre", "en": "Dark", "es": "Oscuro", "it": "Scuro"],
        "themeSand": ["fr": "Sable", "en": "Sand", "es": "Arena", "it": "Sabbia"],
        "updTitle": ["fr": "Mises à jour", "en": "Updates", "es": "Actualizaciones", "it": "Aggiornamenti"],
        "updAuto": ["fr": "Installer automatiquement les mises à jour", "en": "Install updates automatically", "es": "Instalar las actualizaciones automáticamente", "it": "Installa gli aggiornamenti automaticamente"],
        "updCheck": ["fr": "Rechercher une mise à jour", "en": "Check for updates", "es": "Buscar actualizaciones", "it": "Cerca aggiornamenti"],
        "updInstall": ["fr": "Installer la version %@", "en": "Install version %@", "es": "Instalar la versión %@", "it": "Installa la versione %@"],
        "updVersion": ["fr": "Version %@", "en": "Version %@", "es": "Versión %@", "it": "Versione %@"],
        "updChecking": ["fr": "Recherche en cours…", "en": "Checking…", "es": "Buscando…", "it": "Ricerca in corso…"],
        "updUpToDate": ["fr": "Vous avez la dernière version (%@).", "en": "You have the latest version (%@).", "es": "Tiene la última versión (%@).", "it": "Hai l'ultima versione (%@)."],
        "updAvailable": ["fr": "La version %@ est disponible.", "en": "Version %@ is available.", "es": "La versión %@ está disponible.", "it": "La versione %@ è disponibile."],
        "updDownloading": ["fr": "Téléchargement et installation…", "en": "Downloading and installing…", "es": "Descargando e instalando…", "it": "Download e installazione…"],
        "updFailed": ["fr": "Échec : %@", "en": "Failed: %@", "es": "Error: %@", "it": "Errore: %@"],
        "updErrNone": ["fr": "Aucune version publiée trouvée.", "en": "No published release found.", "es": "No se encontró ninguna versión publicada.", "it": "Nessuna versione pubblicata trovata."],
        "updErrDownload": ["fr": "Téléchargement impossible.", "en": "Download failed.", "es": "Descarga imposible.", "it": "Download non riuscito."],
        "updErrSig": ["fr": "Signature de la mise à jour invalide.", "en": "Invalid update signature.", "es": "Firma de la actualización no válida.", "it": "Firma dell'aggiornamento non valida."],
        "updErrVersion": ["fr": "Cette version n'est pas plus récente.", "en": "This version is not newer.", "es": "Esta versión no es más reciente.", "it": "Questa versione non è più recente."],
        "updBusy": ["fr": "Installation reportée : un traitement est en cours.", "en": "Installation postponed: a job is running.", "es": "Instalación aplazada: hay un proceso en curso.", "it": "Installazione rimandata: un'operazione è in corso."],
        "aboutVersion": ["fr": "Version %@ (%@)", "en": "Version %@ (%@)", "es": "Versión %@ (%@)", "it": "Versione %@ (%@)"],
        "aboutTagline": ["fr": "Convertir, couper et retoucher vos fichiers audio, du clic droit du Finder à l'éditeur.", "en": "Convert, cut and edit your audio files, from the Finder's right-click to the editor.", "es": "Convierta, corte y retoque sus archivos de audio, del clic derecho del Finder al editor.", "it": "Converti, taglia e ritocca i tuoi file audio, dal clic destro del Finder all'editor."],
        "aboutCollection": ["fr": "Fait partie du DESKTOP MAC TOOLKIT", "en": "Part of the DESKTOP MAC TOOLKIT", "es": "Parte del DESKTOP MAC TOOLKIT", "it": "Parte del DESKTOP MAC TOOLKIT"],
        "aboutAuthors": ["fr": "Starbudweiser & Claude Code (Anthropic)", "en": "Starbudweiser & Claude Code (Anthropic)", "es": "Starbudweiser & Claude Code (Anthropic)", "it": "Starbudweiser & Claude Code (Anthropic)"],
        "aboutLicense": ["fr": "Licence MIT. © 2026 Starbudweiser.", "en": "MIT License. © 2026 Starbudweiser.", "es": "Licencia MIT. © 2026 Starbudweiser.", "it": "Licenza MIT. © 2026 Starbudweiser."],
        "aboutDisclaimer": ["fr": "Fourni en l'état, sans garantie. Gardez une copie de vos fichiers originaux.", "en": "Provided as is, without warranty. Keep a copy of your original files.", "es": "Se ofrece tal cual, sin garantía. Conserve una copia de sus archivos originales.", "it": "Fornito così com'è, senza garanzia. Conserva una copia dei file originali."],
        "aboutCredit": ["fr": "Inspiré de Fission et de Sound Studio, sans lien avec Rogue Amoeba ni Felt Tip.", "en": "Inspired by Fission and Sound Studio, not affiliated with Rogue Amoeba or Felt Tip.", "es": "Inspirado en Fission y Sound Studio, sin relación con Rogue Amoeba ni Felt Tip.", "it": "Ispirato a Fission e Sound Studio, senza legami con Rogue Amoeba o Felt Tip."],
        "support": ["fr": "Soutenir le projet", "en": "Support the project", "es": "Apoyar el proyecto", "it": "Sostieni il progetto"],
        "keepShort": ["fr": "Garder", "en": "Crop", "es": "Recortar", "it": "Ritaglia"],
        "markerShort": ["fr": "Repère", "en": "Marker", "es": "Marcador", "it": "Marcatore"],
        "mergeShort": ["fr": "Ajouter", "en": "Append", "es": "Añadir", "it": "Aggiungi"],
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
    public static var bitrate: Int {
        get { let v = UserDefaults.standard.integer(forKey: "bitrate"); return v > 0 ? v : 256 }
        set { UserDefaults.standard.set(newValue, forKey: "bitrate") }
    }
    public static func displayName(_ f: String) -> String {
        switch f { case "m4a": return "M4A (AAC)"; default: return f.uppercased() }
    }
}
