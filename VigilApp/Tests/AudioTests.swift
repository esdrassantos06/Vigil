import AVFoundation
import Foundation
import Testing
@testable import Vigil

@MainActor
@Suite("Audio")
struct AudioEngineTests {

    @Test("A fresh AudioGraph starts without throwing")
    func graphStarts() throws {
        let graph = AudioGraph()
        try graph.start()
        #expect(graph.engine.isRunning)
    }

    @Test("Every factory click loads in the connection format", arguments: ClickSound.allCases)
    func clickBuffersMatchConnection(sound: ClickSound) throws {
        let graph = AudioGraph()
        let metronome = MetronomeEngine(graph: graph, catalog: FactoryCatalog())
        metronome.sound = sound

        let expected = graph.mixer.outputFormat(forBus: 0).sampleRate
        let normal = try #require(metronome.normalBuffer)
        let accent = try #require(metronome.accentBuffer)
        #expect(normal.format.sampleRate == expected)
        #expect(accent.format.sampleRate == expected)
        #expect(normal.frameLength > 0)
        #expect(accent.frameLength > 0)
    }


    @Test("Double time doubles the click rate")
    func doubleTime() {
        let graph = AudioGraph()
        let metronome = MetronomeEngine(graph: graph, catalog: FactoryCatalog())
        metronome.bpm = 120

        let normal = metronome.samplesPerBeat
        metronome.doubleTime = true
        #expect(metronome.samplesPerBeat == normal / 2)
    }

    @Test("Eighth-note signatures halve the interval")
    func eighthNoteFeel() {
        let graph = AudioGraph()
        let metronome = MetronomeEngine(graph: graph, catalog: FactoryCatalog())
        metronome.bpm = 120

        metronome.timeSignature = .fourFour
        let quarter = metronome.samplesPerBeat
        metronome.timeSignature = .sixEight
        #expect(metronome.samplesPerBeat == quarter / 2)
    }

    @Test("Tap tempo converges and respects the range")
    func tapTempo() {
        let graph = AudioGraph()
        let metronome = MetronomeEngine(graph: graph, catalog: FactoryCatalog())
        for _ in 0..<4 {
            metronome.tap()
            Thread.sleep(forTimeInterval: 0.5)
        }
        #expect(abs(metronome.bpm - 120) <= 4)
        #expect(Settings.bpmRange.contains(metronome.bpm))
    }

    @Test("Switching notes fast then stopping leaves no player running")
    func noOrphanPlayer() async throws {
        let graph = AudioGraph()
        let tonal = TonalPadEngine(graph: graph, catalog: FactoryCatalog())
        try graph.start()
        tonal.crossfade = 0.2

        tonal.toggle(.C)
        tonal.toggle(.D)
        tonal.toggle(.E)
        #expect(tonal.activeNote == .E)

        tonal.toggle(.E)
        try await Task.sleep(for: .milliseconds(500))
        #expect(tonal.activeNote == nil)
    }

    @Test("isAssigned derives from an observed property")
    func isAssignedIsObservable() throws {
        let graph = AudioGraph()
        let drums = DrumEngine(graph: graph)
        let pad = try #require(drums.pads.first)
        #expect(!pad.isAssigned)

        let catalog = FactoryCatalog()
        let kit = try #require(catalog.kits.first)
        let slot = try #require(kit.slots.first)
        let url = try #require(catalog.url(for: slot.file))
        try drums.load(url: url, into: pad, name: slot.name, source: .native(kit: kit.id, slot: 0))

        #expect(pad.isAssigned)
        #expect(pad.source == .native(kit: kit.id, slot: 0))

        drums.clear(pad)
        #expect(!pad.isAssigned)
    }

    @Test("Pad gain is volume times master times velocity")
    func padGain() throws {
        let graph = AudioGraph()
        let drums = DrumEngine(graph: graph)
        let pad = try #require(drums.pads.first)
        pad.volume = 0.5
        drums.master = 0.5
        pad.velocity = 0.5
        pad.applyGain()
        #expect(abs(pad.player.volume - 0.125) < 0.0001)
    }
}
