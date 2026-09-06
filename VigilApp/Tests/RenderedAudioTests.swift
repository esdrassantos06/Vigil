import AVFoundation
import Foundation
import Testing
@testable import Vigil

/// Measure the rendered signal. These run in real time because the metronome scheduler
/// runs off the wall clock.
@MainActor
@Suite("Rendered audio", .serialized)
struct RenderedAudioTests {

    /// Only presence is checked here. The grid itself is measured offline, where rendering is
    /// deterministic; a threshold detector over the live tap swung between eight and two
    /// onsets in the same window.
    @Test("The metronome makes sound at 240 BPM")
    func metronomeSounds() async throws {
        let graph = AudioGraph()
        let metronome = MetronomeEngine(graph: graph, catalog: FactoryCatalog())
        LiveLevel.hush(metronome)
        let capture = AudioCapture()

        metronome.bpm = 240
        metronome.accentFirst = false
        try graph.start()
        capture.attach(to: graph)
        metronome.start()

        try await Task.sleep(for: .seconds(3))
        metronome.stop()
        capture.detach(from: graph)

        // Only presence is asserted: counting onsets off a live tap is unreliable, and the
        // grid is measured offline instead.
        #expect(!capture.isSilent, "the metronome produced no sound at all")
    }

    /// With the engine running for seconds, scheduling in node time instead of player time
    /// goes silent.
    @Test("Starting late, with the engine already running, still sounds")
    func metronomeStartsLateAndStillSounds() async throws {
        let graph = AudioGraph()
        let metronome = MetronomeEngine(graph: graph, catalog: FactoryCatalog())
        LiveLevel.hush(metronome)
        let capture = AudioCapture()

        try graph.start()
        try await Task.sleep(for: .seconds(3))

        capture.attach(to: graph)
        metronome.bpm = 240
        metronome.start()
        try await Task.sleep(for: .seconds(2))
        metronome.stop()
        capture.detach(from: graph)

        #expect(!capture.isSilent, "silence: the node time versus player time bug is back")
        #expect(capture.onsets().count >= 4)
    }

    @Test("The tonal pad goes quiet after the fade")
    func tonalPadGoesSilent() async throws {
        let graph = AudioGraph()
        let tonal = TonalPadEngine(graph: graph, catalog: FactoryCatalog())
        LiveLevel.hush(tonal)
        try graph.start()
        tonal.crossfade = 0.2

        tonal.toggle(.C)
        try await Task.sleep(for: .milliseconds(600))
        tonal.toggle(.D)
        tonal.toggle(.E)
        tonal.toggle(.E)
        try await Task.sleep(for: .seconds(1))

        let capture = AudioCapture()
        capture.attach(to: graph)
        try await Task.sleep(for: .milliseconds(700))
        capture.detach(from: graph)

        #expect(tonal.activeNote == nil)
        #expect(capture.isSilent, "sound carried on after deselecting")
    }

    /// Stop cuts the drums without touching the tonal pad.
    @Test("Stop silences the drums and leaves the tonal pad playing")
    func stopCutsDrumsOnly() async throws {
        let graph = AudioGraph()
        let drums = DrumEngine(graph: graph)
        LiveLevel.hush(drums)
        let tonal = TonalPadEngine(graph: graph, catalog: FactoryCatalog())
        LiveLevel.hush(tonal)
        let catalog = FactoryCatalog()
        try graph.start()

        let kit = try #require(catalog.kits.first)
        let slot = try #require(kit.slots.first)
        let url = try #require(catalog.url(for: slot.file))
        let pad = try #require(drums.pads.first)
        try drums.load(url: url, into: pad, name: slot.name, source: .native(kit: kit.id, slot: 0))

        tonal.toggle(.C)
        try await Task.sleep(for: .seconds(1))
        drums.trigger(pad)
        drums.stopAll()

        let capture = AudioCapture()
        capture.attach(to: graph)
        try await Task.sleep(for: .milliseconds(500))
        capture.detach(from: graph)

        #expect(tonal.activeNote == .C)
        #expect(!capture.isSilent, "Stop took the tonal pad down with it")
    }

    /// A swap has to stay audible throughout: an equal-power ramp holds the level while one
    /// note replaces the other.
    @Test("Swapping notes never drops to silence")
    func crossfadeHasNoGap() async throws {
        let graph = AudioGraph()
        let tonal = TonalPadEngine(graph: graph, catalog: FactoryCatalog())
        LiveLevel.hush(tonal)
        tonal.master = LiveLevel.quiet
        tonal.crossfade = 0.5
        try graph.start()

        tonal.toggle(.C)
        try await Task.sleep(for: .milliseconds(800))

        let capture = AudioCapture()
        capture.attach(to: graph)
        tonal.toggle(.E)
        try await Task.sleep(for: .milliseconds(900))
        capture.detach(from: graph)

        #expect(!capture.isSilent, "the swap went silent")
        #expect(tonal.activeNote == .E)
    }
}
