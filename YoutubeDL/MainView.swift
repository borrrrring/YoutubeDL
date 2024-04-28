//
//  MainView.swift
//
//  Copyright (c) 2020 Changbeom Ahn
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

import Foundation
import SwiftUI
import YoutubeDL
import PythonKit
import FFmpegSupport
import AVFoundation

@available(iOS 13.0.0, *)
struct MainView: View {
    @State var alertMessage: String?
    
    @State var isShowingAlert = false
    
    @State var error: Error? {
        didSet {
            guard error != nil else { return }
            alertMessage = error?.localizedDescription
            isShowingAlert = true
        }
    }
    
    @EnvironmentObject var app: AppModel
    
    @State var indeterminateProgressKey: String?
    
    @State var isTranscodingEnabled = true
    
    @State var isRemuxingEnabled = true
    
    @State var urlString = ""
    
    @State var isExpanded = false
    
    @State var expandOptions = true
    
    @State var formats: ([([Format], String)])?
    
    @State var formatsContinuation: FormatsContinuation?
    
    @State var tasks: ID<[URLSessionDownloadTask]>?
    
    @AppStorage("isIdleTimerDisabled") var isIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
    
    @State private var showBrowser = false
    
    var body: some View {
        List {
            Section {
                Toggle("Keep screen turned on", isOn: $isIdleTimerDisabled)
            }
            
            Section {
                DownloadsView()
            }
            
            Section {
                DisclosureGroup(isExpanded: $isExpanded) {
                    Button("Paste URL") {
                        let pasteBoard = UIPasteboard.general
                        //                guard pasteBoard.hasURLs || pasteBoard.hasStrings else {
                        //                    alert(message: "Nothing to paste")
                        //                    return
                        //                }
                        guard let url = pasteBoard.url ?? pasteBoard.string.flatMap({ URL(string: $0) }) else {
                            alert(message: "Nothing to paste")
                            return
                        }
                        urlString = url.absoluteString
                        self.app.url = url
                    }
                    Button(#"Prepend "y" to URL in Safari"#) {
                        // FIXME: open Safari
                        open(url: URL(string: "https://youtube.com")!)
                    }
                    Button("Download shortcut") {
                        // FIXME: open Shortcuts
                        open(url: URL(string: "https://www.icloud.com/shortcuts/e226114f6e6c4440b9c466d1ebe8fbfc")!)
                    }
                } label: {
                    if #available(iOS 15.0, *) {
                        TextField("Enter URL", text: $urlString)
                            .onSubmit {
                                guard let url = URL(string: urlString) else {
                                    alert(message: "Invalid URL")
                                    return
                                }
                                app.url = url
                            }
                    } else {
                        TextField("Enter URL", text: $urlString)
                    }
                }
            }
            
//            if let key = indeterminateProgressKey {
//                ProgressView(key)
//                    .frame(maxWidth: .infinity)
//            }
            
            if let info = app.info {
                Section {
                    Text(info.title)
                }
                
//                Section {
//                    DisclosureGroup("Options", isExpanded: $expandOptions) {
//                        Toggle("Fast Download", isOn: $app.enableChunkedDownload)
//                        Toggle("Enable Transcoding", isOn: $app.enableTranscoding)
//                        Toggle("Hide Unsupported Formats", isOn: $app.supportedFormatsOnly)
//                        Toggle("Copy to Photos", isOn: $app.exportToPhotos)
//                    }
//                }
            }
           
            if app.showProgress {
                ProgressView(app.progress)
            }
            
            app.youtubeDL.version.map { Text("yt-dlp version \($0)") }
        }
        .onAppear(perform: {
            app.formatSelector = { info in
                indeterminateProgressKey = nil
                app.info = info
                
                let (formats, timeRange): ([Format], TimeRange?) = await withCheckedContinuation { continuation in
                    self.formatsContinuation = continuation
                    self.formats = [([], "Transcode")]
                }
                
                var url: URL?
                if !formats.isEmpty {
                    url = save(info: info)
                }
                
                app.showProgress = true
                
                return (formats, url, timeRange, formats.first?.vbr, "")
            }
            
            UIApplication.shared.isIdleTimerDisabled = isIdleTimerDisabled
        })
        .onChange(of: app.url) { newValue in
            guard let url = newValue else { return }
//            app.showProgress = false
            urlString = url.absoluteString
            indeterminateProgressKey = "Extracting info"
            guard isExpanded else { return }
            isExpanded = false
        }
        .onChange(of: isIdleTimerDisabled) { newValue in
            UIApplication.shared.isIdleTimerDisabled = newValue
        }
        .onReceive(app.$error) {
            error = $0
        }
        .onReceive(app.$exception) {
            alertMessage = $0?.description
            isShowingAlert = alertMessage != nil
        }
        .alert(isPresented: $isShowingAlert) {
            Alert(title: Text(alertMessage ?? "no message?"))
        }
//        .sheet(item: $app.fileURL) { url in
////            TrimView(url: url)
//        }
        .sheet(item: $formats) {
            // FIXME: cancel download
        } content: { formats in
            DownloadOptionsView(formats: formats, duration: Int(ceil(app.info!.duration ?? 0)), continuation: formatsContinuation!)
        }
        .sheet(item: $tasks) { tasks in
            TaskList(tasks: tasks.value)
        }
        .sheet(item: $app.webViewURL) { url in
            WebView(url: url) { url in
                app.webViewURL = nil
                
                Task {
                    await app.startDownload(url: url)
                }
            }
        }
        .sheet(isPresented: $showBrowser) {
            Browser()
        }
        .toolbar {
            Button {
                showBrowser = true
            } label: {
                Image(systemName: "safari")
            }
        }
    }
    
    func open(url: URL) {
        UIApplication.shared.open(url, options: [:]) {
            if !$0 {
                alert(message: "Failed to open \(url)")
            }
        }
    }
   
    func alert(message: String) {
        alertMessage = message
        isShowingAlert = true
    }
    
    func check(info: Info?, continuation: FormatsContinuation) {
        guard let formats = info?.formats else {
            continuation.resume(returning: ([], nil))
            return
        }
        
        formatsContinuation = continuation
        
        let _bestAudio = formats.filter { $0.isAudioOnly && $0.ext == "m4a" }.last
        let _bestVideo = formats.filter {
            $0.isVideoOnly && (isTranscodingEnabled || !$0.isTranscodingNeeded) }.last
        let _best = formats.filter { !$0.isRemuxingNeeded && !$0.isTranscodingNeeded }.last
        print(_best ?? "no best?", _bestVideo ?? "no bestvideo?", _bestAudio ?? "no bestaudio?")
        guard let best = _best, let bestVideo = _bestVideo, let bestAudio = _bestAudio,
              let bestHeight = best.height, let bestVideoHeight = bestVideo.height
//              , bestVideoHeight > bestHeight
        else
        {
            if let best = _best {
                self.formats = [
                    ([best],
                     String(format: NSLocalizedString("BestFormat", comment: "Alert action"),
                            best.height ?? -1)),
                ]
            } else if let bestVideo = _bestVideo, let bestAudio = _bestAudio {
                self.formats = [
                    ([bestVideo, bestAudio],
                     String(format: NSLocalizedString("RemuxingFormat", comment: "Alert action"),
                            bestVideo.ext,
                            bestAudio.ext,
                            bestVideo.height!)),
                ]
            } else {
                continuation.resume(returning: ([], nil))
                DispatchQueue.main.async {
                    self.alert(message: NSLocalizedString("NoSuitableFormat", comment: "Alert message"))
                }
            }
            return
        }

        self.formats = [
            ([best],
             String(format: NSLocalizedString("BestFormat", comment: "Alert action"),
                    bestHeight)),
            ([bestVideo, bestAudio],
             String(format: NSLocalizedString("RemuxingFormat", comment: "Alert action"),
                    bestVideo.ext,
                    bestAudio.ext,
                    bestVideoHeight)),
        ]
    }
    
    func save(info: Info) -> URL? {
        do {
            return try app.save(info: info)
        } catch {
            print(#function, error)
            self.error = error
            return nil
        }
    }
}

extension Array: Identifiable where Element == ([Format], String) {
    public var id: [String] { map(\.0).flatMap { $0.map(\.format_id) } }
}

// FIXME: rename?
struct ID<Value>: Identifiable {
    let value: Value
    let id = UUID()
}

typealias TimeRange = Range<TimeInterval>

typealias FormatsContinuation = CheckedContinuation<([Format], TimeRange?), Never>

struct DownloadOptionsView: View {
    let formats: [([Format], String)]
    
    let duration: Int
    
    let continuation: FormatsContinuation
    
    @AppStorage(wrappedValue: true, "cut") var cut: Bool
    
    @State var start = "0"
    @State var end: String
    @State var length: String
    
    enum Fields: Hashable {
        case start, end, length
    }
    
    @FocusState var focus: Fields?
    
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        Form {
            ForEach(formats, id: \.1) { format in
                Button {
                    let s = seconds(start) ?? 0
                    let e = seconds(end) ?? 0
                    guard duration == 0 || !cut || s < e else {
                        print("invalid time range")
                        return
                    }
                    let timeRange = (duration > 0 && cut) ? TimeInterval(s)..<TimeInterval(e) : nil
                    continuation.resume(returning: (format.0, timeRange))
                    
                    dismiss()
                } label: {
                    Text(format.1)
                }
            }
            
            Section {
                HStack {
                    TextField("Start", text: $start)
                        .multilineTextAlignment(.trailing)
                        .focused($focus, equals: .start)
                    Text("~")
                    TextField("End", text: $end)
                        .multilineTextAlignment(.leading)
                        .focused($focus, equals: .end)
                    TextField("Length", text: $length)
                        .multilineTextAlignment(.trailing)
                        .focused($focus, equals: .length)
                }
                .disabled(!cut)
            } header: {
                Toggle("자르기", isOn: $cut)
            } footer: {
                Text("짧게 자를수록 변환이 빨리 끝납니다.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            .disabled(duration <= 0)
        }
        .onChange(of: start) { newValue in
            updateLength(start: newValue, end: end)
        }
        .onChange(of: end) { newValue in
            guard focus == .end else { return }
            updateLength(start: start, end: newValue)
        }
        .onChange(of: length) { newValue in
            guard focus == .length else { return }
            updateEnd(start: start, length: length)
        }
    }
    
    init(formats: [([Format], String)], duration: Int, continuation: FormatsContinuation) {
        self.formats = formats
        self.duration = duration
        
        self.continuation = continuation
        
        let string = format(duration) ?? ""
        _end = State(initialValue: string)
        _length = State(initialValue: string)
    }

    func updateLength(start: String, end: String) {
        guard let s = seconds(start), let e = seconds(end) else {
            return
        }
        let l = e - s
        length = format(l) ?? length
    }
    
    func updateEnd(start: String, length: String) {
        guard let s = seconds(start), let l = seconds(length) else {
            return
        }
        let e = s + l
        end = format(e) ?? end
    }
}

extension URL: Identifiable {
    public var id: URL { self }
}

//import MobileVLCKit

struct TrimView: View {
    class Model: NSObject, ObservableObject
//    , VLCMediaPlayerDelegate
    {
        let url: URL
        
//        lazy var player: VLCMediaPlayer = {
//            let player = VLCMediaPlayer()
//            player.media = VLCMedia(url: url)
//            player.delegate = self
//            return player
//        }()
        
        init(url: URL) {
            self.url = url
        }
    }
    
    @StateObject var model: Model
    
    @EnvironmentObject var app: AppModel
    
//    var drag: some Gesture {
//        DragGesture()
//            .onChanged { value in
//                let f = value.location.x / (model.player.drawable as! UIView).bounds.width
//                let t = f * CGFloat(model.player.media.length.intValue) / 1000
//                time = Date(timeIntervalSince1970: t)
//            }
//            .onEnded { value in
//                let f = value.location.x / (model.player.drawable as! UIView).bounds.width
//                let t = f * CGFloat(model.player.media.length.intValue)
//                model.player.time = VLCTime(int: Int32(t))
//            }
//    }
    
    @State var time = Date(timeIntervalSince1970: 0)
        
    let timeFormatter: Formatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()
    
    @State var start = ""
    
    @State var length = ""
    
    @State var end = ""
    
    enum FocusedField: Hashable {
        case start, length, end
    }
    
    @FocusState var focus: FocusedField?
    
    var body: some View {
        VStack {
//            Text(time, formatter: timeFormatter)
//            VLCView(player: model.player)
            TextField("Start", text: $start)
                .focused($focus, equals: .start)
            TextField("Length", text: $length)
                .focused($focus, equals: .length)
            TextField("End", text: $end)
                .focused($focus, equals: .end)
            Button {
//                if model.player.isPlaying {
//                    model.player.pause()
//                } else {
//                    model.player.play()
//                }
                Task {
                    await transcode()
                }
            } label: {
                Text(
//                    model.player.isPlaying ? "Pause" :
                        "Transcode")
            }
        }
//        .gesture(drag)
        .onChange(of: start) { newValue in
            updateLength(start: newValue, end: end)
        }
        .onChange(of: end) { newValue in
            guard focus == .end else { return }
            updateLength(start: start, end: newValue)
        }
        .onChange(of: length) { newValue in
            guard focus == .length else { return }
            updateEnd(start: start, length: length)
        }
    }
    
    init(url: URL) {
        _model = StateObject(wrappedValue: Model(url: url))
    }
    
    func transcode() async {
        let s = seconds(start) ?? 0
        let e = seconds(end) ?? 0
        guard s < e else {
            print(#function, "invalid interval:", start, "~", end)
            return
        }
        let out = model.url.deletingPathExtension().appendingPathExtension("mp4")
        try? FileManager.default.removeItem(at: out)
        let pipe = Pipe()
        Task {
            for try await line in pipe.fileHandleForReading.bytes.lines {
                print(#function, line)
            }
        }
        let t0 = Date()
        let ret = ffmpeg("FFmpeg-iOS",
                         "-progress", "pipe:\(pipe.fileHandleForWriting.fileDescriptor)",
                         "-nostats",
                         "-ss", start,
                         "-t", length,
                         "-i", model.url.path,
                         out.path)
        print(#function, ret, "took", Date().timeIntervalSince(t0), "seconds")
        
        let audio = URL(fileURLWithPath: out.path.replacingOccurrences(of: "-otherVideo.mp4", with: "-audioOnly.m4a"))
        let final = URL(fileURLWithPath: out.path.replacingOccurrences(of: "-otherVideo", with: ""))
        let timeRange = CMTimeRange(start: CMTime(seconds: Double(s), preferredTimescale: 1),
                                    end: CMTime(seconds: Double(e), preferredTimescale: 1))
        mux(videoURL: out, audioURL: audio, outputURL: final, timeRange: timeRange)
    }
    
    func mux(videoURL: URL, audioURL: URL, outputURL: URL, timeRange: CMTimeRange) {
        let t0 = ProcessInfo.processInfo.systemUptime
       
        let videoAsset = AVAsset(url: videoURL)
        let audioAsset = AVAsset(url: audioURL)
        
        guard let videoAssetTrack = videoAsset.tracks(withMediaType: .video).first,
              let audioAssetTrack = audioAsset.tracks(withMediaType: .audio).first else {
            print(#function,
                  videoAsset.tracks(withMediaType: .video),
                  audioAsset.tracks(withMediaType: .audio))
            return
        }
        
        let composition = AVMutableComposition()
        let videoCompositionTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        let audioCompositionTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        
        do {
            try videoCompositionTrack?.insertTimeRange(CMTimeRange(start: .zero, duration: videoAssetTrack.timeRange.duration), of: videoAssetTrack, at: .zero)
            try audioCompositionTrack?.insertTimeRange(timeRange, of: audioAssetTrack, at: .zero)
            print(#function, videoAssetTrack.timeRange, audioAssetTrack.timeRange)
        }
        catch {
            print(#function, error)
            return
        }
        
        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            print(#function, "unable to init export session")
            return
        }
        
        session.outputURL = outputURL
        session.outputFileType = .mp4
        print(#function, "merging...")
        
        session.exportAsynchronously {
            print(#function, "finished merge", session.status.rawValue)
            print(#function, "took", ProcessInfo.processInfo.systemUptime - t0, "seconds")
            if session.status == .completed {
                print(#function, "success")
            } else {
                print(#function, session.error ?? "no error?")
            }
        }
    }

    func updateLength(start: String, end: String) {
        guard let s = seconds(start), let e = seconds(end) else {
            return
        }
        let l = e - s
        length = format(l) ?? length
    }
    
    func updateEnd(start: String, length: String) {
        guard let s = seconds(start), let l = seconds(length) else {
            return
        }
        let e = s + l
        end = format(e) ?? end
    }
}
    
func seconds(_ string: String) -> Int? {
    let components = string.split(separator: ":")
    guard components.count <= 3 else {
        print(#function, "too many components:", string)
        return nil
    }
    
    var seconds = 0
    for component in components {
        guard let number = Int(component) else {
            print(#function, "invalid number:", component)
            return nil
        }
        seconds = 60 * seconds + number
    }
    return seconds
}

//struct VLCView: UIViewRepresentable {
//    let player: VLCMediaPlayer
//
//    func makeUIView(context: Context) -> UIView {
//        let view = UIView()
//        player.drawable = view
//        return view
//    }
//
//    func updateUIView(_ uiView: UIView, context: Context) {
//        //
//    }
//}

import WebKit

let handlerName = "YoutubeDL"

struct WebView: UIViewRepresentable {
    let url: URL?
    
    let handler: ((URL) -> Void)?
    
    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        webView.configuration.userContentController.add(context.coordinator, name: handlerName)
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        if let url, webView.url != url {
            print(#function, url)
            webView.load(URLRequest(url: url))
        }
    }
    
    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let handler: ((URL) -> Void)?
    
        init(handler: ((URL) -> Void)?) {
            self.handler = handler
        }
        
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            print(#function, navigationAction.request.url ?? "nil")
            return .allow
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard handler != nil else { return }
            
            Task { @MainActor in
                let source = """
                    var src = document.querySelector("video").src
                    webkit.messageHandlers.\(handlerName).postMessage(src)
                    1
                    """
                var done = false
                while !done {
                    do {
                        _ = try await webView.evaluateJavaScript(source)
                        done = true
                    } catch {
                        print(#function, error)
                    }
                    try await Task.sleep(nanoseconds: 100_000_000)
                }
            }
        }
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            print(#function, message.body)
            guard let string = message.body as? String,
                  let url = URL(string: string) else { return }
            handler?(url)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(handler: handler)
    }
}

struct DownloadsView: View {
    @EnvironmentObject var app: AppModel
    
    var body: some View {
        ForEach(app.downloads) { download in
            NavigationLink(download.lastPathComponent, destination: DetailsView(url: download))
        }
    }
}

struct DetailsView: View {
    let url: URL
    
    @State var info: Info?
    
    @State var isExpanded = false
    
    @State var videoURL: URL?
    
    var body: some View {
        List {
            if let videoURL = videoURL {
                Section {
                    NavigationLink("Trim", destination: TrimView(url: videoURL))
                }
            }
            
            if let info = info {
                DisclosureGroup("\(info.formats.count) Formats", isExpanded: $isExpanded) {
                    ForEach(info.formats) { format in
                        Text(format.format)
                    }
                }
            }
        }
        .task {
            do {
                info = try JSONDecoder().decode(Info.self,
                                                from: try Data(contentsOf: url.appendingPathComponent("Info.json")))
                
                videoURL = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.contentTypeKey], options: .skipsHiddenFiles).first { url in
                    try! url.resourceValues(forKeys: [.contentTypeKey])
                        .contentType?.conforms(to: .movie)
                    ?? false
                }
            } catch {
                print(error)
            }
        }
    }
}

extension Format: Identifiable {
    public var id: String { format_id }
}

//@available(iOS 13.0.0, *)
//struct MainView_Previews: PreviewProvider {
//    static var previews: some View {
//        MainView()
//            .environmentObject(AppModel())
//    }
//}

struct TaskList: View {
    let tasks: [URLSessionDownloadTask]
    
    struct TaskGroup: Identifiable {
        let title: String?
        
        let task: URLSessionDownloadTask?
        
        let children: [TaskGroup]?
        
        var id: String? { task.map { "\($0.taskIdentifier)" } ?? title }
        
        var sortKey: Int { task?.taskIdentifier ?? -1 }
    }
    
    @State var groups: [TaskGroup] = []
    
    var body: some View {
        List(groups, children: \.children) { item in
            if let task = item.task {
                Text("#\(task.taskIdentifier) \(task.originalRequest?.value(forHTTPHeaderField: "Range") ?? "No range")")
            } else {
                Text(item.title ?? "nil")
            }
        }
        .onAppear {
            let groups = Dictionary(grouping: tasks) { task -> String? in
                guard let d = task.taskDescription, let index = d.lastIndex(of: "-") else {
                    return task.taskDescription
                }
                return String(d[..<index])
            }.map { key, value -> TaskGroup in
                print(key ?? "nil", value.map(\.taskIdentifier))
                return TaskGroup(title: key, task: nil,
                          children: Dictionary(grouping: value, by: \.kind).map { key, value -> TaskGroup in
                    let children = value
                        .map { TaskGroup(title: nil, task: $0, children: nil) }
                        .sorted { $0.sortKey < $1.sortKey }
                    print(key, children.map(\.task?.taskIdentifier))
                    return TaskGroup(title: key.description, task: nil,
                                     children: children)
                })
            }
            
            self.groups = groups
        }
    }
}

extension URLSessionDownloadTask: Identifiable {}

struct Browser: View {
    @State private var address = ""
    
    @State private var url = URL(string: "https://instagram.com")
    
    var body: some View {
        VStack {
            TextField("Address", text: $address)
                .onSubmit {
                    guard let url = URL(string: (address.hasPrefix("https://") ? "" : "https://") + address) else { return }
                    self.url = url
                }
                .textInputAutocapitalization(.never)
                .padding()
            WebView(url: url, handler: nil)
        }
    }
}
