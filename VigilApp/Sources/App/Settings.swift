import Foundation
import SwiftUI

enum ThemePreference: String, Codable, CaseIterable, Sendable {
    case system, light, dark

    var label: String {
        switch self {
        case .system: "Sistema"
        case .light: "Claro"
        case .dark: "Escuro"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

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

    static let cutoffRange = 1_200.0...12_000.0
    static let highpassRange = 20.0...1_200.0
    static let crossfadeRange = 0.2...8.0
    static let bpmRange = 20.0...300.0
}

/// Error whose message follows the chosen language rather than the system one.
protocol VigilError: LocalizedError {
    var messageKey: String.LocalizationValue { get }
}

extension VigilError {
    var errorDescription: String? { String(localized: messageKey) }
}
