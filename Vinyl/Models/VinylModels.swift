import Foundation

struct VinylParameters {
    var wowDepth: Float = 35
    var flutter: Float = 25
    var warpWow: Float = 10
    var speedDrift: Float = 15
    var trackingWeight: Float = 50
    var crackle: Float = 40
    var hiss: Float = 30
    var rumble: Float = 35
    var pressedNoise: Float = 20
    var hfRolloff: Float = 30
    var saturation: Float = 40
    var riaaVariance: Float = 20
    var stereoWidth: Float = 75
    var innerGrooveDistortion: Float = 25
    var azimuthError: Float = 15
    var roomResonance: Float = 20
    var wear: Float = 20
    var masterIntensity: Float = 30

    // MARK: Independent amplifier-section parameters
    //
    // These 5 parameters used to share a variable with another slider in the
    // UI (e.g., moving "air rolloff" was literally the same variable as "hf
    // rolloff"). That caused the two sliders to move together visually and
    // prevented independent DSP control.
    //
    // Each parameter below now has its own identity AND drives its own DSP
    // node in VinylEngine.updateAmpParams():
    //   airRolloff        -> tubeAirEQ    (treble softening around the tube)
    //   microphonics      -> microEQ      (tube vibration resonance bloom)
    //   speakerCoupling   -> speakerEQ    (impedance-interaction dip)
    //   outputTransformer -> xformerEQ    (low-end bloom at 80-120 Hz)
    //   classADrive       -> satNode      (cubic soft-clip dynamic compression)
    //
    // Defaults match the values of the parameters they were previously
    // linked to, so the app's out-of-the-box sound is unchanged.
    var airRolloff: Float = 30
    var microphonics: Float = 20
    var speakerCoupling: Float = 20
    var outputTransformer: Float = 35
    var classADrive: Float = 40
}

struct VinylPreset: Identifiable {
    let id: String
    let name: String
    let description: String
    let params: VinylParameters
}

extension VinylPreset {
    static let all: [VinylPreset] = [custom, audiophile, lowEarFatigue, needleDrop, podcast, jazz, electronic, era78rpm]
    static let custom = VinylPreset(id:"custom", name:"custom", description:"default settings", params:VinylParameters())
    static let audiophile = VinylPreset(id:"audiophile", name:"audiophile", description:"pristine high-end deck", params:{ var p = VinylParameters(); p.wear=5; p.masterIntensity=20; p.wowDepth=10; p.flutter=5; p.warpWow=0; p.speedDrift=5; p.trackingWeight=60; p.crackle=5; p.hiss=10; p.rumble=10; p.pressedNoise=5; p.hfRolloff=8; p.saturation=30; p.riaaVariance=10; p.stereoWidth=90; p.innerGrooveDistortion=5; p.azimuthError=5; p.roomResonance=15; p.airRolloff=p.hfRolloff; p.microphonics=p.roomResonance; p.speakerCoupling=p.roomResonance; p.outputTransformer=p.rumble; p.classADrive=p.saturation; return p }())
    static let lowEarFatigue = VinylPreset(id:"fatigue", name:"low ear fatigue", description:"warm, smooth, long sessions", params:{ var p = VinylParameters(); p.wear=15; p.masterIntensity=25; p.wowDepth=20; p.flutter=5; p.warpWow=0; p.speedDrift=5; p.trackingWeight=50; p.crackle=8; p.hiss=35; p.rumble=20; p.pressedNoise=15; p.hfRolloff=45; p.saturation=65; p.riaaVariance=30; p.stereoWidth=70; p.innerGrooveDistortion=5; p.azimuthError=5; p.roomResonance=25; p.airRolloff=p.hfRolloff; p.microphonics=p.roomResonance; p.speakerCoupling=p.roomResonance; p.outputTransformer=p.rumble; p.classADrive=p.saturation; return p }())
    static let needleDrop = VinylPreset(id:"needledrop", name:"needle drop", description:"stylus mechanics, physical feel", params:{ var p = VinylParameters(); p.wear=30; p.masterIntensity=60; p.wowDepth=65; p.flutter=70; p.warpWow=30; p.speedDrift=40; p.trackingWeight=35; p.crackle=40; p.hiss=25; p.rumble=30; p.pressedNoise=20; p.hfRolloff=25; p.saturation=30; p.riaaVariance=25; p.stereoWidth=75; p.innerGrooveDistortion=65; p.azimuthError=45; p.roomResonance=20; p.airRolloff=p.hfRolloff; p.microphonics=p.roomResonance; p.speakerCoupling=p.roomResonance; p.outputTransformer=p.rumble; p.classADrive=p.saturation; return p }())
    static let podcast = VinylPreset(id:"podcast", name:"podcast", description:"warm, clear, soothing listen", params:{ var p = VinylParameters(); p.wear=15; p.masterIntensity=30; p.wowDepth=8; p.flutter=4; p.warpWow=2; p.speedDrift=8; p.trackingWeight=50; p.crackle=28; p.hiss=45; p.rumble=12; p.pressedNoise=10; p.hfRolloff=18; p.saturation=40; p.riaaVariance=15; p.stereoWidth=85; p.innerGrooveDistortion=5; p.azimuthError=5; p.roomResonance=18; p.airRolloff=p.hfRolloff; p.microphonics=p.roomResonance; p.speakerCoupling=p.roomResonance; p.outputTransformer=p.rumble; p.classADrive=p.saturation; return p }())
    static let jazz = VinylPreset(id:"jazz", name:"jazz", description:"warm, intimate, lightly worn", params:{ var p = VinylParameters(); p.wear=25; p.masterIntensity=40; p.wowDepth=25; p.flutter=10; p.warpWow=5; p.speedDrift=10; p.trackingWeight=50; p.crackle=25; p.hiss=40; p.rumble=30; p.pressedNoise=20; p.hfRolloff=35; p.saturation=55; p.riaaVariance=25; p.stereoWidth=65; p.innerGrooveDistortion=15; p.azimuthError=10; p.roomResonance=35; p.airRolloff=p.hfRolloff; p.microphonics=p.roomResonance; p.speakerCoupling=p.roomResonance; p.outputTransformer=p.rumble; p.classADrive=p.saturation; return p }())
    static let electronic = VinylPreset(id:"electronic", name:"electronic", description:"clean, wide, subtle warmth", params:{ var p = VinylParameters(); p.wear=10; p.masterIntensity=25; p.wowDepth=5; p.flutter=3; p.warpWow=0; p.speedDrift=3; p.trackingWeight=60; p.crackle=5; p.hiss=15; p.rumble=10; p.pressedNoise=8; p.hfRolloff=12; p.saturation=35; p.riaaVariance=15; p.stereoWidth=95; p.innerGrooveDistortion=3; p.azimuthError=3; p.roomResonance=10; p.airRolloff=p.hfRolloff; p.microphonics=p.roomResonance; p.speakerCoupling=p.roomResonance; p.outputTransformer=p.rumble; p.classADrive=p.saturation; return p }())
    static let era78rpm = VinylPreset(id:"78rpm", name:"78 rpm era", description:"pre-war shellac sound", params:{ var p = VinylParameters(); p.wear=60; p.masterIntensity=70; p.wowDepth=35; p.flutter=45; p.warpWow=15; p.speedDrift=25; p.trackingWeight=50; p.crackle=60; p.hiss=80; p.rumble=50; p.pressedNoise=80; p.hfRolloff=85; p.saturation=80; p.riaaVariance=70; p.stereoWidth=20; p.innerGrooveDistortion=70; p.azimuthError=30; p.roomResonance=60; p.airRolloff=p.hfRolloff; p.microphonics=p.roomResonance; p.speakerCoupling=p.roomResonance; p.outputTransformer=p.rumble; p.classADrive=p.saturation; return p }())
}

struct SampleTrack: Identifiable, Equatable {
    let id: String
    let title: String
    let artist: String
    let genre: String
    let filename: String
    let defaultPresetID: String
}

extension SampleTrack {
    static let library: [SampleTrack] = [
        SampleTrack(id:"france", title:"One Night In France", artist:"HoliznaCC0", genre:"lo-fi / nostalgic", filename:"one_night_in_france", defaultPresetID:"electronic"),
        SampleTrack(id:"easiness", title:"Easiness", artist:"Dee Yan-Key", genre:"jazz / swing", filename:"easiness", defaultPresetID:"jazz"),
        SampleTrack(id:"neon", title:"A Neon Flesh", artist:"Kai Engel", genre:"ambient piano", filename:"a_neon_flesh", defaultPresetID:"fatigue"),
        SampleTrack(id:"srv", title:"not SRV", artist:"unknown", genre:"blues / guitar", filename:"not_srv", defaultPresetID:"needledrop"),
        SampleTrack(id:"keller", title:"Jim Keller: Moore's Law", artist:"Lex Fridman", genre:"podcast", filename:"lex_fridman_jim_keller_2019", defaultPresetID:"podcast"),
        SampleTrack(id:"sagan", title:"Pale Blue Dot", artist:"Carl Sagan", genre:"podcast", filename:"Carl Sagans - Pale Blue Dot", defaultPresetID:"podcast"),
    ]
}
