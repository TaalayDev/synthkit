import AVFoundation
import Flutter
import UIKit

@available(iOS 13.0, *)
public class SynthKitPlugin: NSObject, FlutterPlugin {
  private let engine = AppleSynthKitEngine()

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "synthkit", binaryMessenger: registrar.messenger())
    let instance = SynthKitPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    do {
      switch call.method {
      case "getBackendName":
        result("native-ios")
      case "initialize":
        let args = try Self.arguments(call.arguments)
        try engine.initialize(masterVolume: Self.doubleValue(args["masterVolume"], fallback: 0.8))
        result(nil)
      case "disposeEngine":
        engine.disposeEngine()
        result(nil)
      case "setMasterVolume":
        let args = try Self.arguments(call.arguments)
        engine.setMasterVolume(Self.doubleValue(args["volume"], fallback: 0.8))
        result(nil)
      case "createSynth":
        let args = try Self.arguments(call.arguments)
        let synthId = try engine.createSynth(spec: try AppleSynthSpec(args: args))
        result(synthId)
      case "updateSynth":
        let args = try Self.arguments(call.arguments)
        let synthId = try Self.stringValue(args["synthId"], key: "synthId")
        try engine.updateSynth(id: synthId, spec: try AppleSynthSpec(args: args))
        result(nil)
      case "triggerNote":
        let args = try Self.arguments(call.arguments)
        let synthId = try Self.stringValue(args["synthId"], key: "synthId")
        try engine.triggerNote(
          synthId: synthId,
          frequencyHz: Self.doubleValue(args["frequencyHz"], fallback: 440),
          durationMs: Self.intValue(args["durationMs"], fallback: 500),
          velocity: Self.doubleValue(args["velocity"], fallback: 1),
          delayMs: Self.intValue(args["delayMs"], fallback: 0)
        )
        result(nil)
      case "cancelScheduledNotes":
        let args = (call.arguments as? [String: Any]) ?? [:]
        engine.cancelScheduledNotes(synthId: args["synthId"] as? String)
        result(nil)
      case "panic":
        engine.panic()
        result(nil)
      case "disposeSynth":
        let args = try Self.arguments(call.arguments)
        let synthId = try Self.stringValue(args["synthId"], key: "synthId")
        engine.disposeSynth(id: synthId)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    } catch {
      result(
        FlutterError(
          code: "synthkit/error",
          message: error.localizedDescription,
          details: nil
        )
      )
    }
  }

  private static func arguments(_ raw: Any?) throws -> [String: Any] {
    guard let args = raw as? [String: Any] else {
      throw SynthKitError.invalidArguments("Expected a method argument map.")
    }
    return args
  }

  private static func stringValue(_ raw: Any?, key: String) throws -> String {
    guard let value = raw as? String, !value.isEmpty else {
      throw SynthKitError.invalidArguments("Missing \(key).")
    }
    return value
  }

  private static func doubleValue(_ raw: Any?, fallback: Double) -> Double {
    if let value = raw as? Double {
      return value
    }
    if let value = raw as? NSNumber {
      return value.doubleValue
    }
    return fallback
  }

  private static func intValue(_ raw: Any?, fallback: Int) -> Int {
    if let value = raw as? Int {
      return value
    }
    if let value = raw as? NSNumber {
      return value.intValue
    }
    return fallback
  }
}

@available(iOS 13.0, *)
private final class AppleSynthKitEngine {
  private var audioEngine: AVAudioEngine?
  private var synths: [String: AppleSynthHandle] = [:]
  private var nextSynthId = 1

  func initialize(masterVolume: Double) throws {
    if audioEngine == nil {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
      try session.setActive(true)

      let engine = AVAudioEngine()
      engine.mainMixerNode.outputVolume = Float(clampUnit(masterVolume))
      audioEngine = engine
    } else {
      setMasterVolume(masterVolume)
    }
  }

  func disposeEngine() {
    panic()
    for synthId in Array(synths.keys) {
      disposeSynth(id: synthId)
    }
    audioEngine?.stop()
    audioEngine?.reset()
    audioEngine = nil
    try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
  }

  func setMasterVolume(_ volume: Double) {
    audioEngine?.mainMixerNode.outputVolume = Float(clampUnit(volume))
  }

  func createSynth(spec: AppleSynthSpec) throws -> String {
    try ensureInitialized()
    let synthId = "ios_synth_\(nextSynthId)"
    nextSynthId += 1
    synths[synthId] = try makeSynthHandle(id: synthId, spec: spec)
    return synthId
  }

  func updateSynth(id: String, spec: AppleSynthSpec) throws {
    try ensureInitialized()
    guard let handle = synths[id] else {
      throw SynthKitError.unknownSynth(id)
    }
    cancelScheduledNotes(synthId: id)
    handle.state.update(spec: spec)
  }

  func triggerNote(
    synthId: String,
    frequencyHz: Double,
    durationMs: Int,
    velocity: Double,
    delayMs: Int
  ) throws {
    guard let handle = synths[synthId] else {
      throw SynthKitError.unknownSynth(synthId)
    }
    let playback: () -> Void = { [weak self] in
      self?.play(handle: handle, frequencyHz: frequencyHz, durationMs: durationMs, velocity: velocity)
    }
    if delayMs <= 0 {
      playback()
      return
    }
    schedule(on: handle, afterMs: delayMs, block: playback)
  }

  func cancelScheduledNotes(synthId: String?) {
    if let synthId, let handle = synths[synthId] {
      cancel(handle: handle)
      return
    }
    for handle in synths.values {
      cancel(handle: handle)
    }
  }

  func panic() {
    cancelScheduledNotes(synthId: nil)
    for handle in synths.values {
      handle.state.panic()
    }
  }

  func disposeSynth(id: String) {
    guard let handle = synths.removeValue(forKey: id) else {
      return
    }
    cancel(handle: handle)
    handle.state.panic()
    detach(handle: handle)
  }

  private func ensureInitialized() throws {
    if audioEngine == nil {
      throw SynthKitError.invalidArguments("Call initialize() before using the plugin.")
    }
  }

  private func makeSynthHandle(id: String, spec: AppleSynthSpec) throws -> AppleSynthHandle {
    guard let engine = audioEngine else {
      throw SynthKitError.invalidArguments("Audio engine is not ready.")
    }

    let sampleRate = resolveSampleRate(for: engine)
    let channelCount = resolveChannelCount(for: engine)
    guard let format = AVAudioFormat(
      standardFormatWithSampleRate: sampleRate,
      channels: channelCount
    ) else {
      throw SynthKitError.engineFailure("Unable to configure the Apple audio format.")
    }

    let state = AppleSourceSynthState(sampleRate: sampleRate, spec: spec)
    let sourceNode = AVAudioSourceNode { _, _, frameCount, audioBufferList -> OSStatus in
      state.render(frameCount: Int(frameCount), audioBufferList: audioBufferList)
    }

    engine.attach(sourceNode)
    engine.connect(sourceNode, to: engine.mainMixerNode, format: format)

    do {
      if !engine.isRunning {
        engine.prepare()
        try engine.start()
      }
    } catch {
      engine.disconnectNodeOutput(sourceNode)
      engine.detach(sourceNode)
      throw SynthKitError.engineFailure(
        "Failed to start the Apple audio engine: \(error.localizedDescription)"
      )
    }

    return AppleSynthHandle(id: id, state: state, sourceNode: sourceNode)
  }

  private func play(handle: AppleSynthHandle, frequencyHz: Double, durationMs: Int, velocity: Double) {
    handle.state.triggerNote(
      frequencyHz: frequencyHz,
      durationMs: durationMs,
      velocity: velocity
    )
  }

  private func schedule(on handle: AppleSynthHandle, afterMs delayMs: Int, block: @escaping () -> Void) {
    let workId = UUID()
    let workItem = DispatchWorkItem { [weak self] in
      handle.scheduled.removeValue(forKey: workId)
      block()
      self?.synths[handle.id] = handle
    }
    handle.scheduled[workId] = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(delayMs), execute: workItem)
  }

  private func cancel(handle: AppleSynthHandle) {
    for workItem in handle.scheduled.values {
      workItem.cancel()
    }
    handle.scheduled.removeAll()
  }

  private func detach(handle: AppleSynthHandle) {
    guard let engine = audioEngine else {
      return
    }
    engine.disconnectNodeOutput(handle.sourceNode)
    engine.detach(handle.sourceNode)
  }

  private func resolveSampleRate(for engine: AVAudioEngine) -> Double {
    let outputSampleRate = engine.outputNode.inputFormat(forBus: 0).sampleRate
    if outputSampleRate > 0 {
      return outputSampleRate
    }
    let mixerSampleRate = engine.mainMixerNode.outputFormat(forBus: 0).sampleRate
    if mixerSampleRate > 0 {
      return mixerSampleRate
    }
    return 44_100
  }

  private func resolveChannelCount(for engine: AVAudioEngine) -> AVAudioChannelCount {
    let mixerChannels = engine.mainMixerNode.outputFormat(forBus: 0).channelCount
    if mixerChannels > 0 {
      return mixerChannels
    }
    let outputChannels = engine.outputNode.inputFormat(forBus: 0).channelCount
    if outputChannels > 0 {
      return outputChannels
    }
    return 2
  }
}

@available(iOS 13.0, *)
private final class AppleSynthHandle {
  init(
    id: String,
    state: AppleSourceSynthState,
    sourceNode: AVAudioSourceNode
  ) {
    self.id = id
    self.state = state
    self.sourceNode = sourceNode
  }

  let id: String
  let state: AppleSourceSynthState
  let sourceNode: AVAudioSourceNode
  var scheduled: [UUID: DispatchWorkItem] = [:]
}

@available(iOS 13.0, *)
private final class AppleSourceSynthState {
  init(sampleRate: Double, spec: AppleSynthSpec) {
    self.sampleRate = max(1, sampleRate)
    self.spec = spec
  }

  private enum EnvelopeStage {
    case idle
    case attack
    case decay
    case sustain
    case release
  }

  private let lock = NSLock()
  private let sampleRate: Double
  private var spec: AppleSynthSpec
  private var phase: Double = 0
  private var frequencyHz: Double = 440
  private var noteAmplitude: Double = 0
  private var currentLevel: Double = 0
  private var activeFrames: Int = 0
  private var releaseAfterFrames: Int = 0
  private var releaseTriggered = false
  private var filterState: Double = 0
  private var stage: EnvelopeStage = .idle
  private var stageFrameIndex: Int = 0
  private var stageFrameCount: Int = 0
  private var stageStartLevel: Double = 0
  private var stageEndLevel: Double = 0

  func update(spec: AppleSynthSpec) {
    lock.lock()
    self.spec = spec
    lock.unlock()
  }

  func triggerNote(frequencyHz: Double, durationMs: Int, velocity: Double) {
    lock.lock()
    self.frequencyHz = max(1, frequencyHz)
    noteAmplitude = clampUnit(spec.volume) * clampUnit(velocity)
    releaseAfterFrames = max(0, frames(for: Double(durationMs) / 1000))
    releaseTriggered = false
    activeFrames = 0
    currentLevel = 0
    phase = 0
    filterState = 0
    beginAttack()
    lock.unlock()
  }

  func panic() {
    lock.lock()
    currentLevel = 0
    noteAmplitude = 0
    filterState = 0
    stage = .idle
    stageFrameIndex = 0
    stageFrameCount = 0
    activeFrames = 0
    releaseTriggered = false
    lock.unlock()
  }

  func render(frameCount: Int, audioBufferList: UnsafeMutablePointer<AudioBufferList>) -> OSStatus {
    lock.lock()
    defer { lock.unlock() }

    let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
    guard !buffers.isEmpty else {
      return 0
    }

    let channels = buffers.compactMap { buffer -> UnsafeMutablePointer<Float>? in
      guard let data = buffer.mData else {
        return nil
      }
      return data.assumingMemoryBound(to: Float.self)
    }

    guard !channels.isEmpty else {
      return 0
    }

    for frame in 0..<frameCount {
      let sample = nextSample()
      for channel in channels {
        channel[frame] = sample
      }
    }

    return 0
  }

  private func nextSample() -> Float {
    guard stage != .idle else {
      return 0
    }

    if !releaseTriggered && activeFrames >= releaseAfterFrames {
      beginRelease()
    }

    let envelopeLevel = nextEnvelopeLevel()
    let rawSample = waveformSample() * envelopeLevel * noteAmplitude
    activeFrames += 1

    if spec.filter.enabled {
      return Float(applyLowPass(to: rawSample))
    }
    return Float(rawSample)
  }

  private func waveformSample() -> Double {
    let sample: Double
    switch spec.waveform {
    case "square":
      sample = phase < 0.5 ? 1 : -1
    case "triangle":
      sample = 1 - 4 * abs(phase - 0.5)
    case "sawtooth":
      sample = (2 * phase) - 1
    default:
      sample = sin(phase * 2 * .pi)
    }

    phase += frequencyHz / sampleRate
    phase.formTruncatingRemainder(dividingBy: 1)
    if phase < 0 {
      phase += 1
    }
    return sample
  }

  private func applyLowPass(to input: Double) -> Double {
    let cutoffHz = max(20, min(spec.filter.cutoffHz, sampleRate * 0.45))
    let rc = 1 / (2 * Double.pi * cutoffHz)
    let dt = 1 / sampleRate
    let alpha = dt / (rc + dt)
    filterState += alpha * (input - filterState)
    return filterState
  }

  private func nextEnvelopeLevel() -> Double {
    switch stage {
    case .idle:
      return 0
    case .sustain:
      currentLevel = clampUnit(spec.envelope.sustain)
      return currentLevel
    case .attack, .decay, .release:
      guard stageFrameCount > 0 else {
        advanceStage()
        return currentLevel
      }

      let progress = Double(stageFrameIndex + 1) / Double(stageFrameCount)
      currentLevel = stageStartLevel + ((stageEndLevel - stageStartLevel) * progress)
      stageFrameIndex += 1

      if stageFrameIndex >= stageFrameCount {
        currentLevel = stageEndLevel
        advanceStage()
      }

      return currentLevel
    }
  }

  private func advanceStage() {
    switch stage {
    case .attack:
      beginDecay()
    case .decay:
      stage = .sustain
      stageFrameIndex = 0
      stageFrameCount = 0
      stageStartLevel = currentLevel
      stageEndLevel = currentLevel
    case .release:
      stage = .idle
      currentLevel = 0
      noteAmplitude = 0
      stageFrameIndex = 0
      stageFrameCount = 0
    case .idle, .sustain:
      break
    }
  }

  private func beginAttack() {
    configureStage(
      .attack,
      frameCount: frames(for: spec.envelope.attackSeconds),
      targetLevel: 1
    ) {
      currentLevel = 1
      beginDecay()
    }
  }

  private func beginDecay() {
    configureStage(
      .decay,
      frameCount: frames(for: spec.envelope.decaySeconds),
      targetLevel: clampUnit(spec.envelope.sustain)
    ) {
      currentLevel = clampUnit(spec.envelope.sustain)
      stage = .sustain
      stageFrameIndex = 0
      stageFrameCount = 0
    }
  }

  private func beginRelease() {
    releaseTriggered = true
    configureStage(
      .release,
      frameCount: frames(for: spec.envelope.releaseSeconds),
      targetLevel: 0
    ) {
      currentLevel = 0
      noteAmplitude = 0
      stage = .idle
      stageFrameIndex = 0
      stageFrameCount = 0
    }
  }

  private func configureStage(
    _ nextStage: EnvelopeStage,
    frameCount: Int,
    targetLevel: Double,
    immediate: () -> Void
  ) {
    if frameCount <= 0 {
      immediate()
      return
    }

    stage = nextStage
    stageFrameIndex = 0
    stageFrameCount = frameCount
    stageStartLevel = currentLevel
    stageEndLevel = targetLevel
  }

  private func frames(for seconds: Double) -> Int {
    Int((max(0, seconds) * sampleRate).rounded())
  }
}

private struct AppleSynthSpec {
  init(args: [String: Any]) throws {
    waveform = args["waveform"] as? String ?? "sine"
    volume = SynthKitNumeric.double(args["volume"], fallback: 0.8)
    envelope = try AppleEnvelopeSpec(args: args["envelope"] as? [String: Any] ?? [:])
    filter = try AppleFilterSpec(args: args["filter"] as? [String: Any] ?? [:])
  }

  let waveform: String
  let volume: Double
  let envelope: AppleEnvelopeSpec
  let filter: AppleFilterSpec
}

private struct AppleEnvelopeSpec {
  init(args: [String: Any]) throws {
    attackSeconds = Double(SynthKitNumeric.int(args["attackMs"], fallback: 10)) / 1000
    decaySeconds = Double(SynthKitNumeric.int(args["decayMs"], fallback: 120)) / 1000
    sustain = SynthKitNumeric.double(args["sustain"], fallback: 0.75)
    releaseSeconds = Double(SynthKitNumeric.int(args["releaseMs"], fallback: 240)) / 1000
  }

  let attackSeconds: Double
  let decaySeconds: Double
  let sustain: Double
  let releaseSeconds: Double
}

private struct AppleFilterSpec {
  init(args: [String: Any]) throws {
    enabled = args["enabled"] as? Bool ?? false
    cutoffHz = SynthKitNumeric.double(args["cutoffHz"], fallback: 1800)
  }

  let enabled: Bool
  let cutoffHz: Double
}

private enum SynthKitError: LocalizedError {
  case invalidArguments(String)
  case unknownSynth(String)
  case engineFailure(String)

  var errorDescription: String? {
    switch self {
    case .invalidArguments(let message):
      return message
    case .unknownSynth(let synthId):
      return "Unknown synth id: \(synthId)"
    case .engineFailure(let message):
      return message
    }
  }
}

private enum SynthKitNumeric {
  static func double(_ raw: Any?, fallback: Double) -> Double {
    if let value = raw as? Double {
      return value
    }
    if let value = raw as? NSNumber {
      return value.doubleValue
    }
    return fallback
  }

  static func int(_ raw: Any?, fallback: Int) -> Int {
    if let value = raw as? Int {
      return value
    }
    if let value = raw as? NSNumber {
      return value.intValue
    }
    return fallback
  }
}

private func clampUnit(_ value: Double) -> Double {
  max(0, min(1, value))
}
