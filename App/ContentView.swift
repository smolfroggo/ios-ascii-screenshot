import PhotosUI
import SwiftUI

struct ContentView: View {
  @State private var model = CaptureModel()
  @State private var photo: PhotosPickerItem?
  @State private var query = ""
  @Environment(\.scenePhase) private var phase

  var body: some View {
    NavigationStack {
      List {
        Section("Screen") {
          if model.captureAvailable {
            Button(model.capturing ? "Stop" : "Start capturing") { model.capturing ? model.stop() : model.start() }
          } else {
            Text("Live capture needs ScreenCaptureKit, which the iOS Simulator doesn't have. Run on an iOS 27 device.")
              .font(.footnote).foregroundStyle(.secondary)
          }
          Picker("Capture scale", selection: $model.scale) {
            Text("1x").tag(1.0); Text("2x").tag(2.0); Text("3x").tag(3.0)
          }
          .pickerStyle(.segmented)
          .disabled(model.capturing)
          Stepper("Columns: \(model.columns)", value: $model.columns, in: 40...240, step: 10)
            .disabled(model.capturing)
          PhotosPicker("Read a screenshot…", selection: $photo, matching: .images)
          LabeledContent("Frames read", value: "\(model.update.read)")
          LabeledContent("Unchanged", value: "\(model.update.unchanged)")
          LabeledContent("Last frame", value: String(format: "%.0f ms", model.update.ms))
          Text(model.status).font(.footnote).accessibilityIdentifier("status")
        }
        Section("Search history") {
          TextField("invoice, \"exact phrase\", a OR b", text: $query)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .onSubmit { Task { await model.search(query) } }
          ForEach(model.hits) { hit in
            Button {
              Task { await model.show(hit.start) }
            } label: {
              VStack(alignment: .leading) {
                Text("\(hit.start.formatted(date: .abbreviated, time: .standard)) · \(hit.frames) frame\(hit.frames == 1 ? "" : "s")")
                  .font(.caption).foregroundStyle(.secondary)
                Text(hit.line).lineLimit(2)
              }
            }
          }
        }
        if !model.update.ascii.isEmpty {
          Section("Now (\(model.update.size.0)x\(model.update.size.1))") { AsciiView(text: model.update.ascii) }
        }
      }
      .navigationTitle("ASCII Screen")
      .sheet(isPresented: Binding(get: { model.shown != nil }, set: { if !$0 { model.shown = nil } })) {
        if let shown = model.shown {
          NavigationStack {
            AsciiView(text: shown.ascii)
              .padding()
              .navigationTitle(shown.time.formatted(date: .abbreviated, time: .standard))
              .navigationBarTitleDisplayMode(.inline)
          }
        }
      }
    }
    .onChange(of: photo) { _, item in
      guard let item else { return }
      Task {
        if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
          await model.process(image)
        }
      }
    }
    .onChange(of: phase) { _, p in if p != .active { model.flush() } }
    .task { await runLaunchArguments() }
  }

  /// `-readImage <path>` and `-search <query>`: drive the pipeline from `simctl launch` (the Simulator can't capture).
  private func runLaunchArguments() async {
    let args = ProcessInfo.processInfo.arguments
    func value(_ flag: String) -> String? { args.firstIndex(of: flag).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } }
    if let path = value("-readImage"), let image = UIImage(contentsOfFile: path) { await model.process(image) }
    if let q = value("-search") {
      query = q
      await model.search(q)
      if let first = model.hits.first { await model.show(first.start) }
    }
  }
}

struct AsciiView: View {
  let text: String
  var body: some View {
    ScrollView([.horizontal, .vertical]) {
      Text(text)
        .font(.system(size: 7, design: .monospaced))
        .fixedSize()
        .textSelection(.enabled)
        .accessibilityIdentifier("ascii")
    }
    .frame(minHeight: 420)
  }
}
