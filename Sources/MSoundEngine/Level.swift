import Foundation
import Accelerate

/// Mesures de niveau pour les vumètres.
public enum Level {
    /// Crête absolue d'un bloc, en dBFS (−120 pour le silence).
    public static func peakDB(_ p: UnsafePointer<Float>, count: Int) -> Float {
        guard count > 0 else { return -120 }
        var m: Float = 0
        vDSP_maxmgv(p, 1, &m, vDSP_Length(count))
        return m > 1e-6 ? 20 * log10(m) : -120
    }

    /// Ballistique d'un vumètre : montée immédiate, retombée de `fallDBPerSecond` (par défaut 24 dB/s).
    public static func ballistic(previous: Float, new: Float, dt: Double, fallDBPerSecond: Float = 24) -> Float {
        new >= previous ? new : max(new, previous - fallDBPerSecond * Float(dt))
    }
}
