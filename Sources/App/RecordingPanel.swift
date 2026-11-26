import SwiftUI
import MSoundEngine
import MSoundShared

/// Vumètre horizontal −60…0 dBFS : vert, orange au-dessus de −18, rouge au-dessus de −6 ; trait de crête retenue.
struct MeterBar: View {
    let level: Float, peak: Float
    private func x(_ db: Float, _ w: CGFloat) -> CGFloat { CGFloat(min(max((db + 60) / 60, 0), 1)) * w }
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3).fill(Theme.ctl)
                LinearGradient(stops: [.init(color: Theme.ok, location: 0), .init(color: Theme.ok, location: 0.69),
                                       .init(color: Theme.warn, location: 0.70), .init(color: Theme.warn, location: 0.89),
                                       .init(color: Theme.danger, location: 0.90), .init(color: Theme.danger, location: 1)],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: g.size.width).mask(alignment: .leading) { Rectangle().frame(width: x(level, g.size.width)) }
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                Rectangle().fill(Theme.text).frame(width: 2).offset(x: max(0, x(peak, g.size.width) - 2))
            }
        }.frame(height: 12)
    }
}

/// Panneau d'enregistrement : durée, vumètres, arrêter ou abandonner.
struct RecordingPanel: View {
    @ObservedObject var rec = Recorder.shared
    var stop: () -> Void
    var body: some View {
        VStack(spacing: 22) {
            HStack(spacing: 8) {
                Circle().fill(Theme.danger).frame(width: 10, height: 10)
                Text(Loc.t("recRecording")).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.text)
            }
            Text(timeString(Int64(rec.elapsed * 1000), rate: 1000, ms: false))
                .font(.system(size: 52, weight: .semibold, design: .monospaced)).foregroundColor(Theme.text)
            VStack(spacing: 8) {
                ForEach(rec.levels.indices, id: \.self) { i in
                    HStack(spacing: 10) {
                        Text(rec.levels.count == 1 ? "" : (i == 0 ? "L" : "R")).font(.system(size: 11, weight: .semibold)).foregroundColor(Theme.text2).frame(width: 12)
                        MeterBar(level: rec.levels[i], peak: rec.peakHold[min(i, rec.peakHold.count - 1)])
                        Text(rec.peakHold[min(i, rec.peakHold.count - 1)] > -99 ? String(format: "%.0f dB", rec.peakHold[min(i, rec.peakHold.count - 1)]) : "−∞")
                            .font(.system(size: 11, design: .monospaced)).foregroundColor(Theme.text2).frame(width: 46, alignment: .trailing)
                    }
                }
            }.frame(maxWidth: 460)
            HStack(spacing: 10) {
                Button(Loc.t("recStop"), action: stop).buttonStyle(FlatButton(primary: true))
                Button(Loc.t("recDiscard")) { rec.stop(save: false) }.buttonStyle(FlatButton())
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 28).frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.card).clipShape(RoundedRectangle(cornerRadius: Theme.radius))
    }
}
