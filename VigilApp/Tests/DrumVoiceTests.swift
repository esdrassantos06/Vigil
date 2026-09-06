import AVFoundation
import Foundation
import Testing
@testable import Vigil

@MainActor
@Suite("Drum voices")
struct DrumVoiceTests {
    private func loadedPad() throws -> (DrumEngine, DrumPad, AudioGraph) {
        let graph = AudioGraph()
        let drums = DrumEngine(graph: graph)
        let catalog = FactoryCatalog()
        let kit = try #require(catalog.kit(id: "WorshipDrums") ?? catalog.kits.first)
        let slot = try #require(kit.slots.first { $0.name == "Kick" } ?? kit.slots.first)
        let url = try #require(catalog.url(for: slot.file))
        let pad = drums.pads[0]
        try drums.load(url: url, into: pad, name: slot.name, source: .native(kit: kit.id, slot: 0))
        return (drums, pad, graph)
    }

    @Test("Hitting the same pad again leaves the previous tail sounding")
    func retriggerKeepsTail() throws {
        let (drums, pad, graph) = try loadedPad()
        try graph.start()

        drums.trigger(pad)
        let first = try #require(pad.voices.first { $0.isPlaying })

        drums.trigger(pad)
        let second = try #require(pad.voices.first { $0.isPlaying && $0 !== first })

        #expect(first.isPlaying)
        #expect(second !== first)
    }

    @Test("Velocity belongs to the voice, so an old tail keeps its own level")
    func velocityPerVoice() throws {
        let (drums, pad, _) = try loadedPad()
        drums.trigger(pad, velocity: 1)
        let loud = try #require(pad.voices.first)
        drums.trigger(pad, velocity: 0.2)
        let quiet = pad.voices[1]

        #expect(loud.volume > quiet.volume)
    }

    @Test("Stop silences every voice")
    func stopAllVoices() throws {
        let (drums, pad, graph) = try loadedPad()
        try graph.start()
        drums.trigger(pad)
        drums.trigger(pad)

        drums.stopAll()
        #expect(pad.voices.allSatisfy { !$0.isPlaying })
    }

    @Test("Overlapping is the default, like a drum program's poly play mode")
    func defaultsToOverlap() throws {
        let (_, pad, _) = try loadedPad()
        #expect(pad.voicing == .poly)
    }

    @Test("A pad set to mono restarts instead of stacking")
    func monoRestarts() throws {
        let (drums, pad, graph) = try loadedPad()
        try graph.start()
        pad.voicing = .mono

        drums.trigger(pad)
        drums.trigger(pad)
        drums.trigger(pad)

        #expect(pad.voices.filter(\.isPlaying).count == 1)
    }

    @Test("Switching a stacked pad to mono silences the tails it had already stacked")
    func monoClearsStack() throws {
        let (drums, pad, graph) = try loadedPad()
        try graph.start()
        drums.trigger(pad)
        drums.trigger(pad)
        #expect(pad.voices.filter(\.isPlaying).count == 2)

        pad.voicing = .mono
        drums.trigger(pad)
        #expect(pad.voices.filter(\.isPlaying).count == 1)
    }

    @Test("A slot saved before the setting existed loads as overlapping")
    func decodesOlderSlot() throws {
        let json = Data(#"{"source":{"empty":{}},"color":"menta","volume":1}"#.utf8)
        let slot = try JSONDecoder().decode(StoredSlot.self, from: json)
        #expect(slot.voicing == .poly)
    }
}
