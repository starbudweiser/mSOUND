import Foundation

/// Formats de sortie gérés par le moteur.
public enum AudioFormat: String, CaseIterable, Sendable, Codable {
    case mp3, m4a, flac, wav, aiff, alac

    public var fileExtension: String {
        switch self {
        case .mp3: return "mp3"
        case .m4a, .alac: return "m4a"
        case .flac: return "flac"
        case .wav: return "wav"
        case .aiff: return "aiff"
        }
    }

    /// Nom affiché dans le menu Finder et l'interface.
    public var displayName: String {
        switch self {
        case .mp3: return "MP3"
        case .m4a: return "M4A (AAC)"
        case .flac: return "FLAC"
        case .wav: return "WAV"
        case .aiff: return "AIFF"
        case .alac: return "ALAC"
        }
    }

    public var isLossless: Bool {
        switch self {
        case .mp3, .m4a: return false
        default: return true
        }
    }
}

public struct ConvertOptions: Sendable {
    /// Débit en kb/s pour MP3 et AAC.
    public var bitrateKbps: Int = 256
    /// Nil = fréquence de la source.
    public var sampleRate: Double? = nil
    /// Portion à exporter, en secondes. Nil = tout le fichier.
    public var range: ClosedRange<Double>? = nil
    /// Dossier de sortie. Nil = à côté de l'original.
    public var outputDirectory: URL? = nil
    public init() {}
}

public enum ConvertError: Error, LocalizedError, Equatable {
    case unreadable(String)
    case sameFormat
    case encoderFailed(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .unreadable(let s): return "Fichier illisible : \(s)"
        case .sameFormat: return "Le fichier est déjà dans ce format."
        case .encoderFailed(let s): return "Échec de l'encodage : \(s)"
        case .cancelled: return "Annulé"
        }
    }
}
