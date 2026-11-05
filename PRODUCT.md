# Product

<!-- impeccable:product-schema 1 -->

## Platform

ios

Native SwiftUI, one codebase for macOS 14+ and iPadOS 17+ (iPad only, landscape-first). macOS is the primary stage machine; iPad compiles and packages but has not run on hardware yet. "ios" here means Apple-native: HIG structure, SF Symbols, system controls and materials. Liquid Glass applies on macOS 26 / iPadOS 26 with a material fallback below that.

## Users

The owner, a developer and musician who plays live in church services and in the studio. He runs Vigil on a laptop (or iPad) on stage, usually in low light, while also playing another instrument. Secondary audience if the repo goes public: other musician-developers who build it themselves.

## Product Purpose

A live performance instrument in one window: a sustained tonal pad (twelve notes, one at a time, crossfaded), an eight-pad drum sampler, a metronome, and MIDI control. Success is a performer who can change key, fire a hit, and keep tempo without looking twice, and who never hears silence because of the software.

## Positioning

Every pad note is its own recording (no pitch shifting), with equal-power crossfades and a sample-accurate pulse locked to the metronome, all on one shared audio engine at the smallest stable buffer. It is a personal stage tool built from source, not a store product, so the owner can fix anything himself.

## Operating Context

- Dark stage, glanced at between phrases, often at arm's length. Hands are frequently busy on another instrument; input arrives from a MIDI controller, the computer keyboard, or a quick tap.
- Typical flow: load a set, pick a pad sound and a drum kit, set tempo, then during the song switch keys on the tonal pad, fire one-shots, and ride pad volume, reverb and pulse.
- Rehearsal and studio use in normal light as well.

## Capabilities and Constraints

- Tonal pad: 12 chromatic notes, latch or hold play mode, up to three stacked layers on faders, 3-band EQ, compressor, reverb, pulse (pump, smooth, gate; quarter to sixteenth), master, pan, cutoff, high-pass, crossfade time.
- Drums: 8 one-shot pads, per-pad volume, colour (9 options), trim, reverb send, overlap or restart voicing; drum bus high-pass and low-pass; hard stop that leaves the tonal pad playing.
- Kits own the 8 pads; sets carry tonal sound, filters, metronome and active kit. Both autosave.
- Metronome: 20 to 300 BPM, six time signatures, tap tempo, four clicks, downbeat accent, double time.
- MIDI: CoreMIDI input with hot-plug, channel filter, MIDI Learn over pads, live controls and metronome; computer keys share the same mapping table.
- Output delay up to 250 ms.
- Seven themes plus System; four UI languages (pt-BR source, en, es, fr) switchable without restart.
- Hard constraints: pad trigger feedback is instantaneous (0 ms, animation never delays it); nothing on the trigger path recomputes blur or gradients; no file over 350 lines; all UI strings go through the String Catalog; contrast is locked by `ThemeTests`.
- Out of scope: AUv3, App Store, iPhone, tonal pad polyphony, set lists, MIDI out.

## Brand Commitments

- Name "Vigil" and the flame mark (`assets/logo-mark.svg`, drawn in code as `FlameMark`).
- Anti-references the owner set: generic church app, button-crowded DAW, SaaS dashboard, visual copy of another app in the genre. Purple and wine are banned.
- Themes are an app preference, not part of a set. A sober default theme opens on first launch; richer themes are opt-in.
- The owner asked (2026-11-05) for a full visual redesign and for Liquid Glass wherever the platform allows it.

## Evidence on Hand

- Factory content: 96 pad sounds, 32 drum kits, 8 metronome clicks, all verified free to use.
- Logo and icon in `assets/`.
- No testimonials, users or press. Nothing to fabricate.

## Product Principles

1. The stage comes first: what a performer needs mid-song is visible on the main screen, at glance size.
2. Sound never waits for the interface, and the interface never hides why there is silence.
3. One screen, no hunting: deep configuration lives in sheets, live controls do not.
4. Built from source and owned: clarity of code is part of the product.

## Accessibility & Inclusion

- Body contrast at least 4.5:1 in every theme, measured on backdrop and both surfaces (enforced by tests).
- 44 pt minimum targets; colour is never the only signal (a playing pad also shows a mark).
- Reduce Motion and Reduce Transparency respected; glass falls back to opaque surfaces when transparency is reduced.
