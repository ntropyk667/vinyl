# Needle Drop Feature Implementation Prompt

## Overview
Add a needle drop button under the Stereo/Mono toggles that cycles through 4 distinct pre-recorded needle drop sounds. Each button press rotates to the next needle drop version, with a bypass state that disables the effect. Master intensity slider controls both the volume and rolloff pace of whichever needle drop is active.

## Assets
4 needle drop audio files located in ~/Desktop/Vinyl/{folder}:
- Each file needs to be edited down to exactly 5 seconds
- Prepended to the start of playback (before music begins)
- Format: WAV, 44.1kHz, mono or stereo (will be converted to match engine format)

## UI Design

### Button
- **Label**: "Needle Drop" (or icon-based if preferred)
- **Placement**: Below Stereo/Mono toggle buttons, vertical stack
- **Behavior**: Tap cycles through states: Needle Drop 1 → Needle Drop 2 → Needle Drop 3 → Needle Drop 4 → Bypass → Needle Drop 1 (loop)
- **Visual State**:
  - Bypass: Grey, disabled appearance
  - Active (1–4): Glows (matches Stereo/Mono active state), displays number or indicator
- **Display**: Show current state (e.g., "ND1", "ND2", "ND3", "ND4", or "OFF")

## Audio Implementation

### Needle Drop Loading
- Load all 4 needle drop files into memory on app startup (cache them)
- Keep them in native format (mono/stereo as recorded)
- No effects processing on needle drops (play raw)

### Playback Integration
- When a needle drop is active (1–4):
  - Prepend the selected 5-second needle drop to the beginning of the main track
  - Expand playback buffer: [5s needle drop] + [original track]
  - Music begins exactly at 5.0 seconds
- When bypass is active:
  - No needle drop prepended, play track normally
- Playback starts at position 0 with needle drop active

### Master Intensity Control
Master intensity slider (0–100) affects needle drops:
1. **Volume**: Multiplies needle drop amplitude by (intensity / 100)
   - At 0% intensity: Needle drop is silent (amplitude = 0)
   - At 100% intensity: Full volume of the needle drop file

2. **Rolloff Pace**: Controls fade-out duration at the end of needle drop (transition to music)
   - At 0% intensity: No fade (abrupt transition at 5.0s)
   - At 50% intensity: 0.5-second fade-out (last 0.5s of needle drop fades to silence)
   - At 100% intensity: 1.5-second fade-out (last 1.5s of needle drop gradually fades)
   - Formula: `fadeOutDuration = (intensity / 100) * 1.5 seconds`

### State Management
- Add `needleDropMode` enum with cases: `.bypass`, `.needleDrop1`, `.needleDrop2`, `.needleDrop3`, `.needleDrop4`
- Add `needleDropIntensity` (0–100) linked to master intensity slider
- Persist needle drop mode preference across sessions
- Needle drop state independent of Stereo/Mono mode

### Seek Behavior
- If user seeks into needle drop portion (0–5s): Play from that point with needle drop active
- If user seeks past 5s: Skip needle drop, start at music portion (no needle drop prepended for mid-track seeks)
- Next track button: Doesn't reset needle drop mode; preserves active needle drop setting for next track

## Technical Integration

### VinylEngine Changes
1. Add `needleDropBuffers: [AVAudioPCMBuffer?]` to store 4 loaded needle drops
2. Add `activeNeedleDropMode: NeedleDropMode` state property
3. Add method `loadNeedleDropFiles()` on app launch
4. Modify `loadTrack()` or main playback buffer setup:
   - Check if `activeNeedleDropMode != .bypass`
   - If active, prepend selected needle drop buffer to track buffer
   - Apply volume scaling based on master intensity
   - Calculate fade-out duration based on intensity
5. Add `applyNeedleDropFade(toBuffer:, intensityPercent:)` to apply fade envelope
6. Connect master intensity slider to needle drop volume/fade calculations

### UI Changes (ConverterView & SampleLibraryView)
1. Add needle drop button under Stereo/Mono buttons
2. Button tap cycles `needleDropMode` to next state
3. Display current mode (e.g., "ND1", "ND2", "ND3", "ND4", "OFF")
4. Update button appearance based on active mode (glow vs. grey)

### Master Intensity Integration
- When master intensity changes:
  - Recalculate needle drop volume scaling
  - Recalculate fade-out duration
  - Apply changes in real-time (if playback is active)

## Implementation Phases

### Phase 1: Asset Preparation & Loading
- Edit 4 needle drop files to exactly 5 seconds
- Load all 4 into memory on app startup
- Test playback of each in isolation

### Phase 2: Core Integration
- Add needle drop mode state to VinylEngine
- Implement needle drop prepending logic
- Test buffer concatenation and seek behavior

### Phase 3: Intensity Control
- Link master intensity slider to needle drop volume
- Implement fade-out duration calculation
- Test intensity scaling (0%, 50%, 100%)

### Phase 4: UI & State
- Add cycling button under Stereo/Mono
- Connect button to mode cycling
- Verify state persistence across tracks/sessions

### Phase 5: Polish & Testing
- Verify no audio artifacts at fade transitions
- Test seeking behavior (into pre-roll, past pre-roll)
- Confirm intensity changes apply in real-time
- Test mode cycling behavior (all 5 states cycle correctly)

## Edge Cases
- Master intensity at 0%: Needle drop should be silent but still consume 5 seconds (or should it skip?)
- Bypass mode: No needle drop, play track normally
- Mode switching: Preserve needle drop mode when switching between converter/library
- Seek to exactly 5.0s: Should land at start of music
- Very short tracks: Ensure needle drop doesn't overflow beyond track duration

## Audio Quality Checks
- No clicks/pops at needle drop fade transition (use smooth envelope)
- Needle drops maintain clarity and don't clip at full intensity
- Fade-out should be smooth (non-linear, perhaps exponential)

## Testing Checklist
- [ ] All 4 needle drops load and play back
- [ ] Cycling button rotates through all 5 states (ND1–ND4, OFF)
- [ ] Master intensity controls volume (0–100%)
- [ ] Master intensity controls fade duration (0–1.5s)
- [ ] Seek behavior works correctly (pre-roll vs. music)
- [ ] Next track preserves needle drop mode
- [ ] Mode switching (converter/library) preserves needle drop state
- [ ] No audio artifacts, clicks, or pops
- [ ] State persists across app restarts
