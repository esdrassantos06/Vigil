import Foundation
import SwiftUI

/// Kept out of `Settings`: loading a set must not change the app language.
enum Language: String, Codable, CaseIterable, Sendable {
    case pt, en, es, fr

    var label: String {
        switch self {
        case .pt: "Português"
        case .en: "English"
        case .es: "Español"
        case .fr: "Français"
        }
    }

    var code: String {
        switch self {
        case .pt: "pt-BR"
        case .en: "en"
        case .es: "es"
        case .fr: "fr"
        }
    }

    var locale: Locale { Locale(identifier: code) }

    /// `String(localized:)` alone will not switch `.lproj`; it needs the language bundle.
    var bundle: Bundle {
        guard let path = Bundle.main.path(forResource: code, ofType: "lproj"),
              let bundle = Bundle(path: path)
        else { return .main }
        return bundle
    }
}

struct Settings: Codable, Equatable {
    var padMaster: Double = 0.8
    var padPan: Double = 0
    var cutoff: Double = 12_000
    var highpass: Double = 20
    var crossfade: Double = 1.5

    var drumMaster: Double = 1.0
    var drumPan: Double = 0

    var sharps = true
    var major = true

    var bpm: Double = 120
    var timeSignature: TimeSignature = .fourFour
    var clickSound: ClickSound = .logic
    var accentFirst = true
    var doubleTime = false
    var metronomeVolume: Double = 0.8
    var metronomePan: Double = 0

    var padReverb: Double = 0
    var pulse: PulseShape?
    var pulseRate: PulseRate = .eighth
    var pulseDepth: Double = 0.5

    var padLow: Double = 0
    var padMid: Double = 0
    var padHigh: Double = 0
    var padCompressor = false
    var compressorThreshold: Double = -20
    var compressorGain: Double = 0
    var padMainLevel: Double = 1
    var padLayers: [PadLayer] = []
    /// True plays a note until it is pressed again; false plays it while the key is down.
    var padLatch = true
    var sustainInverted = false

    var drumHighpass: Double = 20
    var drumCutoff: Double = 20_000
    var drumReverb: DrumReverb = .mediumHall
    var drumReverbLevel: Double = 1

    /// Seconds added to every output, to line Vigil up with other gear.
    var outputDelay: Double = 0

    init() {}

    /// Every key is optional so settings and sets saved by an older build keep loading.
    /// A missing key would otherwise fail the whole set, and the next save would drop it.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) throws -> T {
            try container.decodeIfPresent(T.self, forKey: key) ?? fallback
        }
        let base = Settings()
        padMaster = try value(.padMaster, base.padMaster)
        padPan = try value(.padPan, base.padPan)
        cutoff = try value(.cutoff, base.cutoff)
        highpass = try value(.highpass, base.highpass)
        crossfade = try value(.crossfade, base.crossfade)
        drumMaster = try value(.drumMaster, base.drumMaster)
        drumPan = try value(.drumPan, base.drumPan)
        sharps = try value(.sharps, base.sharps)
        major = try value(.major, base.major)
        bpm = try value(.bpm, base.bpm)
        timeSignature = try value(.timeSignature, base.timeSignature)
        clickSound = try value(.clickSound, base.clickSound)
        accentFirst = try value(.accentFirst, base.accentFirst)
        doubleTime = try value(.doubleTime, base.doubleTime)
        metronomeVolume = try value(.metronomeVolume, base.metronomeVolume)
        metronomePan = try value(.metronomePan, base.metronomePan)
        padReverb = try value(.padReverb, base.padReverb)
        pulse = try container.decodeIfPresent(PulseShape.self, forKey: .pulse)
        pulseRate = try value(.pulseRate, base.pulseRate)
        pulseDepth = try value(.pulseDepth, base.pulseDepth)
        padLow = try value(.padLow, base.padLow)
        padMid = try value(.padMid, base.padMid)
        padHigh = try value(.padHigh, base.padHigh)
        padCompressor = try value(.padCompressor, base.padCompressor)
        compressorThreshold = try value(.compressorThreshold, base.compressorThreshold)
        compressorGain = try value(.compressorGain, base.compressorGain)
        padMainLevel = try value(.padMainLevel, base.padMainLevel)
        padLayers = try value(.padLayers, base.padLayers)
        padLatch = try value(.padLatch, base.padLatch)
        sustainInverted = try value(.sustainInverted, base.sustainInverted)
        drumHighpass = try value(.drumHighpass, base.drumHighpass)
        drumCutoff = try value(.drumCutoff, base.drumCutoff)
        drumReverb = try value(.drumReverb, base.drumReverb)
        drumReverbLevel = try value(.drumReverbLevel, base.drumReverbLevel)
        outputDelay = try value(.outputDelay, base.outputDelay)
    }

    /// A stored value can sit outside the range after the range itself changes.
    func clamped() -> Settings {
        var copy = self
        copy.cutoff = min(max(cutoff, Self.cutoffRange.lowerBound), Self.cutoffRange.upperBound)
        copy.highpass = min(max(highpass, Self.highpassRange.lowerBound), Self.highpassRange.upperBound)
        copy.crossfade = min(max(crossfade, Self.crossfadeRange.lowerBound), Self.crossfadeRange.upperBound)
        copy.bpm = min(max(bpm, Self.bpmRange.lowerBound), Self.bpmRange.upperBound)
        copy.drumCutoff = min(max(drumCutoff, Self.drumCutoffRange.lowerBound), Self.drumCutoffRange.upperBound)
        copy.drumHighpass = min(max(drumHighpass, Self.highpassRange.lowerBound), Self.highpassRange.upperBound)
        copy.outputDelay = min(max(outputDelay, Self.outputDelayRange.lowerBound), Self.outputDelayRange.upperBound)
        copy.padLayers = Array(padLayers.prefix(Self.maxExtraLayers))
        return copy
    }

    static let cutoffRange = 800.0...6_000.0
    static let highpassRange = 20.0...1_200.0
    static let crossfadeRange = 0.2...8.0
    static let bpmRange = 20.0...300.0
    static let drumCutoffRange = 800.0...20_000.0
    static let toneRange = -12.0...12.0
    static let thresholdRange = -40.0...0.0
    static let makeupRange = 0.0...20.0
    static let outputDelayRange = 0.0...0.25
    static let maxExtraLayers = 3
}

/// A pad timbre stacked on the main one, with its own fader.
struct PadLayer: Codable, Equatable, Sendable {
    var soundID: String
    var level: Double
}

/// Room for the drum reverb send, from Apple's factory presets.
enum DrumReverb: String, CaseIterable, Codable, Sendable {
    case smallRoom, mediumRoom, mediumHall, largeHall, plate, cathedral

    var label: String {
        switch self {
        case .smallRoom: "Sala pequena"
        case .mediumRoom: "Sala média"
        case .mediumHall: "Hall médio"
        case .largeHall: "Hall grande"
        case .plate: "Plate"
        case .cathedral: "Catedral"
        }
    }
}

/// Error whose message follows the chosen language rather than the system one.
protocol VigilError: LocalizedError {
    var messageKey: String.LocalizationValue { get }
}

extension VigilError {
    var errorDescription: String? { String(localized: messageKey) }
}
