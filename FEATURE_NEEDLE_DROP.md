# Feature: Record Needle Drop & Startup

## Overview
New button under Stereo/Mono toggles that adds 5 seconds of pre-roll silence to track playback. During this silence, the user hears a record player needle drop and record startup surface noise that fades and blends into the main track with current EQ/effects settings.

## UI Design

### Button Placement
- Location: Under the Stereo/Mono buttons (vertical stack)
- Label: "Needle Drop" or "Record Start"
- Style: Matches Stereo/Mono toggle buttons (side-by-side or stacked, glows when activated)
- State: Binary toggle (on/off)

### Visual Behavior
- Default: Off (disabled appearance, grey)
- When toggled on: Glows (matches active Stereo/Mono glow style)
- When enabled, track playback adds 5-second pre-roll before music starts

## Audio Implementation

### Components

#### 1. Needle Drop Sound
- Single transient event at start of pre-roll (0.0–0.2 seconds)
- Characteristics:
  - Sharp high-frequency click/scrape
  - Decays quickly (100–200ms)
  - Frequency content: 3–8kHz with presence peak
  - Amplitude: Loud enough to be audible but not jarring (~-6dB relative to music)

#### 2. Record Startup Surface Noise
- Plays during 0.2–5.0 seconds (4.8 seconds total)
- Characteristics:
  - Crackle/hiss similar to vinyl surface noise
  - Lower frequency rumble (60–150Hz) underlay
  - Probabilistic crackle (variable-rate pops like current crackle effect)
  - Amplitude envelope: Starts at ~-12dB, fades to -∞ (silence) at 5.0s
  - Fade-out: Non-linear, heavier fade in final 1.5 seconds so blend is smooth

#### 3. Fade & Blend
- At 5.0s: Music fades in over ~0.5 seconds while startup noise fades out
- Result: Seamless transition where music blends with current effects chain
- Music plays with all active effects (EQ, tubes, mono/stereo, crackle/hiss/rumble)

### Technical Approach

#### Audio Generation
1. Create two separate audio buffers:
   - Needle drop: 0.2s of synthetic high-frequency transient
   - Startup noise: 4.8s of crackle/rumble with fade envelope

2. Use existing effects generation code:
   - Adapt current crackle generation for variable-rate surface noise
   - Use rumble oscillator for low-freq underlay
   - Apply volume fade envelope to startup noise buffer

#### Integration Points
1. **Playback**:
   - When needle drop is enabled, prepend generated audio to track buffer
   - Expand buffer by 5 seconds at start
   - Music starts at sample 5.0s (at 44.1kHz = 220,500 samples)
   - Apply current EQ/tube settings to music portion only (5.0s+)
   - Startup noise gets no effects (pure needle drop + surface noise)

2. **Engine State**:
   - Add `needleDropEnabled` boolean to VinylEngine
   - Add `needleDropActive` boolean to track if currently playing pre-roll
   - Handle seeking: If user seeks into pre-roll portion, play from that point; if seek into music, skip pre-roll

3. **State Management**:
   - Save needle drop preference in app settings
   - Preserve state across mode switches (converter/library)
   - During preview, disable needle drop if it would interfere with clean preview playback

#### Audio Buffer Workflow
1. Load track normally into player buffer
2. If needle drop enabled:
   - Generate needle drop + startup noise pre-roll (5.0s @ 44.1kHz)
   - Concatenate: [pre-roll] + [original track]
   - Set initial playback position to 0 (start of needle drop)
   - Music begins playback at exactly 5.0s
3. Apply EQ/tubes/mono/stereo effects to concatenated buffer
4. Play normally with transport controls

### Sound Design References
- **Needle drop**: Analogous to existing transient sounds; reference from vinyl record players
- **Startup surface noise**: Similar to current crackle/hiss/rumble but layered together with specific fade envelope
- **Blend**: Fade happens in audio engine before speaker output, ensuring smooth crossfade with music

## UI Integration

### Controls Behavior
- Button toggles independently of Stereo/Mono
- When converter mode is active, buttons work normally
- When preview is active, needle drop still applies (user can hear it during preview)
- No additional UI clutter beyond the toggle button

### Transport Behavior
- Playback controls (play/pause, seek, next track) work normally
- Seeking into pre-roll: Play from needle drop
- Seeking past 5s: Skip needle drop, start at music portion
- Next track button: Doesn't add needle drop again (only once per track start)

## Implementation Phases

### Phase 1: Core Audio Generation
- Create needle drop buffer (transient click/scrape)
- Create startup noise buffer (crackle + rumble with fade)
- Test playback via simple test view

### Phase 2: Integration
- Add `needleDropEnabled` state to VinylEngine
- Modify track loading to prepend pre-roll if enabled
- Implement seek logic (skip vs. play from pre-roll)

### Phase 3: UI
- Add toggle button under Stereo/Mono
- Connect to VinylEngine state
- Test with various tracks and presets

### Phase 4: Polish
- Tweak needle drop and startup noise sound design
- Verify blend with different EQ settings
- Test state persistence across mode switches

## Estimated Complexity
- Low-medium: Reuses existing noise generation code, requires buffer manipulation and state management
- Primary challenge: Achieving natural-sounding needle drop and smooth fade/blend
- No new dependencies or major architectural changes needed

## Open Questions
- Should needle drop be per-preset or global? (Recommend: Global toggle, independent of presets)
- Should there be a "strength" slider for startup noise volume? (Recommend: Fixed for now, can add later)
- Should needle drop apply to sample library tracks too, or only converter/loaded files? (Recommend: Both)
- How loud should needle drop be relative to track? (Recommend: -6dB relative to music, user-testable)
