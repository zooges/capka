import AVFoundation
import Foundation
import Speech
import SwiftUI

/// On-device speech-to-text that appends into the composer draft. Uses the
/// system Speech framework (same recognition stack the keyboard dictation
/// taps into) — there is no public API to open the IME mic programmatically.
@MainActor
@Observable
final class VoiceDictation {
  var isListening = false
  var error: String?

  private var recognizer: SFSpeechRecognizer?
  private var request: SFSpeechAudioBufferRecognitionRequest?
  private var task: SFSpeechRecognitionTask?
  private let engine = AVAudioEngine()
  private var tapInstalled = false
  /// Text already committed into the draft before this session started.
  private var baseText = ""
  private var onPartial: ((String) -> Void)?

  func toggle(into draft: Binding<String>) {
    if isListening {
      stop()
    } else {
      start(into: draft)
    }
  }

  func start(into draft: Binding<String>) {
    error = nil
    Task {
      let ok = await Self.requestPermissions()
      guard ok else {
        error = "需要麦克风和语音识别权限才能语音输入。请在系统设置中开启。"
        return
      }
      beginSession(into: draft)
    }
  }

  func stop() {
    teardown(deactivateSession: true)
  }

  private func teardown(deactivateSession: Bool) {
    if engine.isRunning {
      engine.stop()
    }
    if tapInstalled {
      engine.inputNode.removeTap(onBus: 0)
      tapInstalled = false
    }
    request?.endAudio()
    task?.cancel()
    task = nil
    request = nil
    isListening = false
    onPartial = nil
    if deactivateSession {
      try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
  }

  private func beginSession(into draft: Binding<String>) {
    teardown(deactivateSession: false)

    #if targetEnvironment(simulator)
    // Simulator audio input is often unavailable; fail with a clear message.
    if AVAudioSession.sharedInstance().availableInputs?.isEmpty != false {
      // Still try — some simulators have a virtual mic.
    }
    #endif

    let locale = Locale(identifier: "zh-CN")
    recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer()
    guard let recognizer, recognizer.isAvailable else {
      error = "当前设备暂不支持语音识别"
      return
    }

    baseText = draft.wrappedValue
    if !baseText.isEmpty, !baseText.hasSuffix(" "), !baseText.hasSuffix("\n") {
      baseText += " "
    }
    onPartial = { partial in
      draft.wrappedValue = self.baseText + partial
    }

    let req = SFSpeechAudioBufferRecognitionRequest()
    req.shouldReportPartialResults = true
    if #available(iOS 16, *) {
      // Prefer on-device when available; fall back to network silently.
      req.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
    }
    request = req

    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(
        .playAndRecord,
        mode: .measurement,
        options: [.duckOthers, .defaultToSpeaker, .allowBluetooth]
      )
      try session.setActive(true, options: .notifyOthersOnDeactivation)
    } catch {
      self.error = "无法启动麦克风：\((error as NSError).localizedDescription)"
      return
    }

    let input = engine.inputNode
    // Prefer the hardware input format; `outputFormat` can report 0 channels
    // right after category changes on some devices / the simulator.
    var format = input.inputFormat(forBus: 0)
    if format.sampleRate <= 0 || format.channelCount == 0 {
      format = input.outputFormat(forBus: 0)
    }
    guard format.sampleRate > 0, format.channelCount > 0 else {
      self.error = "无法访问麦克风。模拟器通常不支持，请在真机上试用。"
      teardown(deactivateSession: true)
      return
    }

    input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
      self?.request?.append(buffer)
    }
    tapInstalled = true

    engine.prepare()
    do {
      try engine.start()
    } catch {
      self.error = "无法启动录音：\((error as NSError).localizedDescription)"
      teardown(deactivateSession: true)
      return
    }

    isListening = true
    task = recognizer.recognitionTask(with: req) { [weak self] result, err in
      Task { @MainActor in
        guard let self else { return }
        if let result {
          self.onPartial?(result.bestTranscription.formattedString)
          if result.isFinal { self.stop() }
        }
        if let err {
          let ns = err as NSError
          // 1 / 216 / 301 = cancelled / no speech / request dismissed — ignore when stopping.
          let ignore = [1, 216, 301].contains(ns.code) || !self.isListening
          if !ignore {
            self.error = Self.friendlySpeechError(ns)
            self.stop()
          }
        }
      }
    }
  }

  private static func friendlySpeechError(_ error: NSError) -> String {
    // Common Speech / Siri assistant codes.
    switch error.code {
    case 1101, 1107, 1110, 203:
      return "语音识别失败，请重试。若在模拟器上，请改用真机。"
    case 1117:
      return "没有检测到语音，请靠近麦克风后重试"
    default:
      let msg = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
      if msg.isEmpty { return "语音识别中断，请重试" }
      return msg
    }
  }

  private static func requestPermissions() async -> Bool {
    let mic = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
      AVAudioSession.sharedInstance().requestRecordPermission { cont.resume(returning: $0) }
    }
    guard mic else { return false }

    let speechStatus = SFSpeechRecognizer.authorizationStatus()
    if speechStatus == .authorized { return true }
    if speechStatus == .denied || speechStatus == .restricted { return false }

    return await withCheckedContinuation { cont in
      SFSpeechRecognizer.requestAuthorization { status in
        cont.resume(returning: status == .authorized)
      }
    }
  }
}
