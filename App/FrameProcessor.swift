import CoreGraphics
import CoreVideo
import Foundation
import VideoToolbox

/// Runs tetratorus' incremental `Pipeline` on the newest screen frame once per `interval` and keeps
/// changed frames in `History` (the same gzip + SQLite format as the macOS service).
///
/// iOS has no `SCStreamConfiguration.minimumFrameInterval`, `queueDepth` or `pixelFormat`, so frames are
/// throttled here, and each one is copied into an app-owned BGRA buffer before the system's buffer is released
/// (`Pipeline` keeps the previous frame to diff against).
final class FrameProcessor: @unchecked Sendable {
  struct Update: Sendable {
    var ascii: String
    var read = 0
    var unchanged = 0
    var ms = 0.0
    var size = (0, 0)
  }

  let pipeline: Pipeline
  let history: History
  var onUpdate: (@Sendable (Update) -> Void)?

  private let lock = NSLock()
  private var latest: CVPixelBuffer?
  private let queue = DispatchQueue(label: "ascii-screen.process", qos: .utility)
  private var timer: DispatchSourceTimer?
  private var transfer: VTPixelTransferSession?
  private var pool: CVPixelBufferPool?
  private var poolSize = (0, 0)
  private var lastSaved: (obs: [Obs], lines: [DLine])?
  private var update = Update(ascii: "")

  init(opts: Options, historyDir: URL) {
    pipeline = Pipeline(opts)
    history = History(dir: historyDir, keepDays: opts.keepDays)
  }

  /// Called from the capture queue for every delivered frame; only the newest one is kept.
  func submit(_ pb: CVPixelBuffer) {
    lock.lock()
    latest = pb
    lock.unlock()
  }

  func start() {
    stop()
    let interval = pipeline.opts.interval
    let t = DispatchSource.makeTimerSource(queue: queue)
    t.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(Int(interval * 100)))
    t.setEventHandler { [weak self] in self?.tick() }
    t.resume()
    timer = t
  }

  func stop() {
    timer?.cancel()
    timer = nil
    lock.lock()
    latest = nil
    lock.unlock()
    queue.async { [history] in
      do { try history.flush() } catch { log("cannot write history: \(error.localizedDescription)") }
    }
  }

  /// Runs `body` on the processing queue, which owns the pipeline and history.
  func run<T: Sendable>(_ body: @escaping @Sendable (FrameProcessor) throws -> T) async throws -> T {
    try await withCheckedThrowingContinuation { c in
      queue.async { c.resume(with: Result { try body(self) }) }
    }
  }

  func process(image: CGImage) async -> Bool {
    (try? await run { $0.handle(bgraBuffer(from: image)) }) ?? false
  }

  private func tick() {
    lock.lock()
    let pb = latest
    latest = nil
    lock.unlock()
    guard let pb, let own = copyToBGRA(pb) else { return }
    handle(own)
  }

  /// Returns false when the frame was pixel-identical to the previous one (nothing re-read).
  @discardableResult
  private func handle(_ pb: CVPixelBuffer?) -> Bool {
    guard let pb else { return false }
    let t0 = Date()
    // Vision autoreleases per call; drain every frame so a long capture doesn't creep.
    let changed = autoreleasepool { pipeline.process(pb) }
    guard changed else {
      update.unchanged += 1
      onUpdate?(update)
      return false
    }
    let frame = pipeline.frame(cursor: nil)
    if lastSaved.map({ $0.obs != frame.obs || $0.lines != frame.lines }) ?? true {
      lastSaved = (frame.obs, frame.lines)
      do { try history.record(frame.encode()) } catch { log("cannot write history: \(error.localizedDescription)") }
    }
    update.read += 1
    update.ms = Date().timeIntervalSince(t0) * 1000
    update.size = pipeline.imageSize
    update.ascii = frame.render(columns: pipeline.opts.width, rows: pipeline.canvasHeight)
    onUpdate?(update)
    return true
  }

  private func copyToBGRA(_ src: CVPixelBuffer) -> CVPixelBuffer? {
    let w = CVPixelBufferGetWidth(src), h = CVPixelBufferGetHeight(src)
    if pool == nil || poolSize != (w, h) {
      let attrs: [CFString: Any] = [
        kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey: w, kCVPixelBufferHeightKey: h,
        kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
      ]
      pool = nil
      CVPixelBufferPoolCreate(nil, nil, attrs as CFDictionary, &pool)
      poolSize = (w, h)
    }
    if transfer == nil { VTPixelTransferSessionCreate(allocator: nil, pixelTransferSessionOut: &transfer) }
    guard let pool, let transfer else { return nil }
    var dst: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(nil, pool, &dst)
    guard let dst, VTPixelTransferSessionTransferImage(transfer, from: src, to: dst) == noErr else { return nil }
    return dst
  }
}

func bgraBuffer(from image: CGImage) -> CVPixelBuffer? {
  var pb: CVPixelBuffer?
  CVPixelBufferCreate(nil, image.width, image.height, kCVPixelFormatType_32BGRA,
                      [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &pb)
  guard let pb else { return nil }
  CVPixelBufferLockBaseAddress(pb, [])
  defer { CVPixelBufferUnlockBaseAddress(pb, []) }
  guard let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pb), width: image.width, height: image.height,
                            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pb),
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
  else { return nil }
  ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
  return pb
}
