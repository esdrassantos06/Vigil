import AVFoundation
import Foundation
@testable import Vigil

/// Live tests play through the real output device. They run at a whisper so a test run does
/// not blast the machine, while the mixer tap still sees a signal well above its threshold.
@MainActor
enum LiveLevel {
    static let quiet: Double = 0.1

    static func hush(_ metronome: MetronomeEngine) { metronome.volume = quiet }
    static func hush(_ tonal: TonalPadEngine) { tonal.master = quiet }
    static func hush(_ drums: DrumEngine) { drums.master = quiet }
}
