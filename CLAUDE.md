# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Working Rule

**Always explain the planned changes and ask for confirmation before modifying any code.** This applies to every change, no matter how small.

## Build

```bash
xcodebuild -scheme Vinyl -destination 'platform=iOS Simulator,name=iPhone 16' build
```

There are no unit tests in this project.

## Architecture

Vinyl is a SwiftUI iOS app that applies real-time vinyl record simulation to audio. Two modes: **library** (plays bundled sample tracks) and **converter** (processes user-supplied audio files into vinyl-processed WAVs).

### File Map

| File | Responsibility |
|------|---------------|
| `Vinyl/Audio/VinylEngine.swift` | Entire audio engine and all DSP. The only `@Published` source of truth. ~1900 lines. |
| `Vinyl/Models/VinylModels.swift` | Data structs: `VinylParameters`, `CompressorParameters`, `VinylPreset`, `SampleTrack`. |
| `Vinyl/Views/ContentView.swift` | Root view, portrait/landscape layout switch, all toggle buttons (bypass, stereo/mono, EQ, COMP, needle drop). |
| `Vinyl/Views/ControlsViews.swift` | All effect UI: `EffectSectionsView`, `EffectSlider`, `CompressorView`, `GraphicEQView`, `PresetsView`, `MasterControlsView`. |
| `Vinyl/Views/TransportView.swift` | Playback transport (play/pause, scrub bar, skip). |
| `Vinyl/Views/ConverterView.swift` | Converter UI (file picker, convert button, progress, share). |
| `Vinyl/Podcast/` | RSS podcast player: `PodcastView`, `PodcastDetailView`, `RSSFeedParser`, `PodcastStorageManager`, `PodcastSearch`, `PodcastModels`. |

### AVAudioEngine Signal Chain (live playback)

```
playerNode → timePitch → hpFilter → riaaEQ → tubeWarmthEQ → tubeAirEQ
  → microEQ → xformerEQ → speakerEQ → satNode → lpFilter → roomEQ
  → masterMixer ←(hissPlayer, rumblePlayer, cracklePlayer)
  → userEQ → compGainNode → mainMixerNode
```

- `timePitch` (`AVAudioUnitTimePitch`): wow/flutter/warp modulation at 50ms ticks via `wowTimer`
- Noise players loop procedurally-generated pink noise, rumble sine, and probabilistic crackle bursts
- `userEQ` (`AVAudioUnitEQ`, 12-band): the user-facing graphic EQ
- `compGainNode` (`AVAudioMixerNode`): software compressor — its `.volume` is driven dynamically by a read tap on `userEQ`'s output

### Software Compressor

`AVAudioUnitDynamicsProcessor` **does not exist on iOS** (macOS-only — do not use it). The compressor is implemented entirely in Swift:

- `userEQ.installTap(onBus: 0, ...)` fires `processCompressorTap(_:)` on the audio render thread each buffer
- RMS → soft-knee gain computer (`compressorComputeGain`, Giannoulis et al. 2012) → IIR attack/release smoothing → `compGainNode.volume`
- Feed-forward design (measures before gain reduction)
- Offline render uses `applyCompressorInPlace(_:gainState:)` instead — taps don't fire during manual offline rendering

### Key Design Decisions

- `CompressorParameters` is intentionally **separate from** `VinylParameters`. Compressor settings are not part of any preset and persist across preset changes.
- **Wear has an additive model**: `effectiveParam = min(param + wear, 100)`. Wear shifts rumble, crackle, hfRolloff, riaaVariance, wowDepth, and warpWow upward. Hiss is equipment noise — unaffected by wear.
- The **5 amplifier parameters** (`airRolloff`, `microphonics`, `speakerCoupling`, `outputTransformer`, `classADrive`) each have their own `VinylParameters` field and their own audio node. They are intentionally decoupled from the similarly-named vinyl simulation parameters to allow independent adjustment.
- Sliders in the amplifier section use `isDisabled` + `onInteract` to re-enable a powered-down tube stage when the user drags a dimmed slider.

### Bypass

`toggleBypass()` sets `isBypassed`, then calls `updateVinylParams()`, `updateAmpParams()`, `updateCompressor()`, `scheduleNoiseUpdate()`, and re-seeks. All effect nodes are zeroed but the engine graph stays connected. The compressor tap is removed while bypassed.

### Needle Drop

Two bundled WAVs (`needle_drop_1`, `needle_drop_4`) are prepended to `audioBuffer` in `rebuildBufferWithNeedleDrop()`. `needleDropFrameCount` tracks the music start frame. On bypass, playback skips past the drop frames. Drop samples are resampled to the music's sample rate via `AVAudioConverter` to prevent pitch artifacts on 48 kHz tracks.

### Offline Converter

`performOfflineRender()` builds a second `AVAudioEngine` (`offEngine`) with a duplicate EQ chain and runs `enableManualRenderingMode(.offline, ...)`. Wow/flutter is pre-baked via `prebakeWowFlutter()` (variable-rate linear interpolation). Compressor applied per-chunk via `applyCompressorInPlace`. Output: 32-bit float stereo WAV in the app's Documents directory.

### Podcast Mode

Podcasts download via `URLSessionDownloadTask` to a temp file, opened with `AVAudioFile`, and read in 10-minute chunks to limit RAM. `podcastChunkStartTime` tracks the chunk offset within the episode; `duration` always reflects the full episode. Chunk loading happens in `loadPodcastChunk(at:)`, called from `startPlayback()` when `podcastFileURL != nil`.

### Layout

Portrait layout activates when `geo.size.width < 600`. The left column (bypass, stereo/mono, EQ toggle, COMP toggle, needle drop) is fixed at 130pt wide. Landscape shows a record view in the left column and stacks converter + library + podcast + controls in the right column.
