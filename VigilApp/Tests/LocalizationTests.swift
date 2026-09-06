import Foundation
import Testing
@testable import Vigil

/// Guards against a toast that silently falls back to its Portuguese key because the catalog
/// entry uses a different format specifier than the one Swift generates.
@Suite("Localization")
struct LocalizationTests {

    private func english(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: Language.en.bundle, locale: Language.en.locale)
    }

    @Test("Every language ships a bundle")
    func bundlesExist() {
        for language in Language.allCases {
            #expect(language.bundle != Bundle.main, "missing \(language.code).lproj")
        }
    }

    @Test("Plain toasts translate")
    func plainToasts() {
        #expect(english("Som de fábrica não encontrado.") == "Factory sound not found.")
        #expect(english("Não foi possível iniciar o áudio.") == "Could not start audio.")
    }

    @Test("Toasts with one argument translate")
    func oneArgument() {
        let name = "Memes"
        #expect(english("Kit \(name) carregado.") == "Kit Memes loaded.")
        #expect(english("\(name) importado.") == "Memes imported.")
    }

    @Test("Toasts with two and three arguments translate")
    func manyArguments() {
        let sample = "kick"
        let pad = "D1"
        #expect(english("\(sample) no pad \(pad).") == "kick on pad D1.")

        let target = "C"
        let binding = "the A key"
        let owner = "D"
        #expect(english("\(target) recebeu \(binding).") == "C now uses the A key.")
        #expect(english("\(target) recebeu \(binding), que era de \(owner).")
            == "C now uses the A key, taken from D.")
    }

    @Test("Counted toast translates")
    func countedToast() {
        let missing = 3
        #expect(english("\(missing) pad(s) sem som: o arquivo não foi encontrado.")
            == "3 pad(s) with no sound: the file was not found.")
    }

    @Test("Set toasts translate")
    func setToasts() {
        let name = "Memes"
        #expect(english("Set \(name) salvo.") == "Set Memes saved.")
        #expect(english("Set \(name) carregado.") == "Set Memes loaded.")
        #expect(english("Set \(name) apagado.") == "Set Memes deleted.")
    }

    @Test("Counted interpolation uses the integer specifier")
    func integerInterpolation() {
        let channel = 7
        #expect(english("· canal \(channel)") == "· channel 7")
        #expect(english("\(channel) entradas") == "7 inputs")
    }

    @Test("Errors translate through messageKey")
    func errors() {
        #expect(english(AudioError.bufferAllocationFailed.messageKey) == "Could not load the audio.")
        #expect(english(MidiError.clientFailed.messageKey) == "Could not open MIDI.")
        #expect(english(LibraryError.accessDenied("song.wav").messageKey)
            == "Could not read song.wav. If it is in iCloud, download the file before importing.")
    }
}
