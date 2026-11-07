import Foundation
import Observation
import UIKit

struct SearchHit: Identifiable, Sendable {
  let id = UUID()
  var start: Date, end: Date, frames: Int, line: String
}

@MainActor
@Observable
final class CaptureModel {
  var status = "idle"
  var capturing = false
  var update = FrameProcessor.Update(ascii: "")
  var columns = 80
  var scale = 2.0
  var hits: [SearchHit] = []
  var shown: (time: Date, ascii: String)?

  static let historyDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("history", isDirectory: true)

  private var processor: FrameProcessor
  private var capture: AnyObject?

  init() { processor = Self.makeProcessor(columns: 80) }

  private static func makeProcessor(columns: Int) -> FrameProcessor {
    var opts = Options()
    opts.width = columns
    opts.cursor = false
    return FrameProcessor(opts: opts, historyDir: historyDir)
  }

  private func freshProcessor() {
    processor.stop()
    processor = Self.makeProcessor(columns: columns)
    processor.onUpdate = { [weak self] u in Task { @MainActor in self?.update = u } }
  }

  var captureAvailable: Bool {
    #if canImport(ScreenCaptureKit)
    true
    #else
    false
    #endif
  }

  func start() {
    #if canImport(ScreenCaptureKit)
    freshProcessor()
    let c = ScreenCapture(processor: processor, scale: scale)
    c.onState = { [weak self] s, on in Task { @MainActor in self?.status = s; self?.capturing = on } }
    capture = c
    status = "pick Entire Screen"
    c.start()
    #endif
  }

  func stop() {
    #if canImport(ScreenCaptureKit)
    (capture as? ScreenCapture)?.stop()
    #endif
    capture = nil
    capturing = false
  }

  func process(_ image: UIImage) async {
    guard let cg = image.cgImage else { status = "can't read image"; return }
    if !capturing { freshProcessor() }
    status = "reading image…"
    let changed = await processor.process(image: cg)
    _ = try? await processor.run { try $0.history.flush() }
    status = changed ? String(format: "image read in %.0f ms", update.ms) : "image unchanged"
  }

  func search(_ query: String) async {
    let q = query.trimmingCharacters(in: .whitespaces)
    guard !q.isEmpty else { hits = []; return }
    do {
      hits = try await processor.run { p in
        try p.history.flush()
        return try p.history.search(q, from: .distantPast, to: Date(), limit: 50)
          .map { SearchHit(start: $0.start, end: $0.end, frames: $0.frames, line: $0.line) }
      }
      status = "\(hits.count) match\(hits.count == 1 ? "" : "es") for \(q)"
    } catch {
      hits = []
      status = "search failed: \(error.localizedDescription)"
    }
  }

  func show(_ time: Date) async {
    let cols = columns
    if let found = try? await processor.run({ p -> (Date, String)? in
      p.history.frame(at: time).map { ($0.0, History.display($0.1, columns: cols, rows: nil)) }
    }) {
      shown = (found.0, found.1)
    }
  }

  func flush() {
    Task { _ = try? await processor.run { try $0.history.flush() } }
  }
}
