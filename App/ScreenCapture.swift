#if canImport(ScreenCaptureKit)
import CoreMedia
import ScreenCaptureKit

/// iOS 27 screen capture: the system content picker -> SCStream -> FrameProcessor.
final class ScreenCapture: NSObject, SCContentSharingPickerObserver, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
  let processor: FrameProcessor
  let scale: Double
  var onState: (@Sendable (String, Bool) -> Void)?
  private var stream: SCStream?
  private let queue = DispatchQueue(label: "ascii-screen.capture", qos: .utility)

  init(processor: FrameProcessor, scale: Double) {
    self.processor = processor
    self.scale = scale
    super.init()
  }

  func start() {
    let picker = SCContentSharingPicker.shared
    picker.add(self)
    picker.isActive = true
    picker.present(using: .display)
  }

  func stop() {
    let s = stream
    stream = nil
    processor.stop()
    Task { try? await s?.stopCapture() }
    SCContentSharingPicker.shared.remove(self)
    SCContentSharingPicker.shared.isActive = false
    onState?("stopped", false)
  }

  func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
    onState?("picker cancelled", false)
  }

  func contentSharingPickerStartDidFailWithError(_ error: Error) {
    onState?("picker failed: \(error.localizedDescription)", false)
  }

  func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
    if let old = self.stream { Task { try? await old.stopCapture() } }
    let cfg = SCStreamConfiguration()
    // Scale is relative to points, like the macOS service's --scale (iPhones are 3x, so 3 = native pixels).
    cfg.width = Int(filter.contentRect.width * scale)
    cfg.height = Int(filter.contentRect.height * scale)
    let s = SCStream(filter: filter, configuration: cfg, delegate: self)
    do {
      try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
    } catch {
      onState?("cannot add stream output: \(error.localizedDescription)", false)
      return
    }
    self.stream = s
    Task {
      do {
        try await s.startCapture()
        processor.start()
        onState?("capturing \(cfg.width)x\(cfg.height)", true)
      } catch {
        onState?("cannot start capture: \(error.localizedDescription)", false)
      }
    }
  }

  func stream(_ s: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
    guard type == .screen, sb.isValid,
          let info = (CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]])?.first,
          let raw = info[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete,
          let pb = sb.imageBuffer else { return }
    processor.submit(pb)
  }

  func stream(_ stream: SCStream, didStopWithError error: Error) {
    processor.stop()
    onState?("capture stopped: \(error.localizedDescription)", false)
  }
}
#endif
