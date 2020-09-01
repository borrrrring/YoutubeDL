//
//  DownloadViewController.swift
//  Hello World
//
//  Created by Changbeom Ahn on 2020/03/14.
//  Copyright © 2020 Jane Developer. All rights reserved.
//

import UIKit
import Photos
import AVKit

class DownloadViewController: UIViewController {

    var info: Info?
    
    @IBOutlet weak var progressView: UIProgressView!
    
    var documentInteractionController: UIDocumentInteractionController?
    
    override func viewDidLoad() {
        super.viewDidLoad()

        PHPhotoLibrary.shared().register(self)
    }
    
    @IBAction
    func handlePan(_ sender: UIPanGestureRecognizer) {
        print(#function, sender)
    }
    
    @IBAction func crop(_ sender: UIBarButtonItem) {
//        let fetchOptions = PHFetchOptions()
//        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "modificationDate", ascending: true)]
//        let videos = PHAsset.fetchAssets(with: .video, options: fetchOptions)
//        let video = videos[videos.count - 1]
//        print(video)
//
//        video.requestContentEditingInput(with: nil) { (contentEditingInput, info) in
//            print(contentEditingInput?.audiovisualAsset, info)
//            guard let input = contentEditingInput,
//                let asset = input.audiovisualAsset
//                else { return }

        do {
            let location = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("video")
                .appendingPathExtension("mp4")
            
        let asset = AVURLAsset(url: location)
            print(asset)
            let compatiblePresets = AVAssetExportSession.exportPresets(compatibleWith: asset)
            print(compatiblePresets)
            if compatiblePresets.contains(AVAssetExportPresetHighestQuality) {
                //                let output = PHContentEditingOutput(contentEditingInput: input)
                do {
                    let url = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("out.mp4")
                    
                    try? FileManager.default.removeItem(at: url)
                    
                    let composition = AVMutableComposition()
                    guard let videoCompositionTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
                        let audioCompositionTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
                        else { fatalError() }
                    
                    let videoAssetTrack = asset.tracks(withMediaType: .video)[0]
                    let audioAssetTrack = asset.tracks(withMediaType: .audio)[0]
                    
                    let timeRange = CMTimeRange(start: .zero, duration: CMTime(seconds: 30, preferredTimescale: asset.duration.timescale))
                    
                    try videoCompositionTrack.insertTimeRange(timeRange, of: videoAssetTrack, at: .zero)
                    try audioCompositionTrack.insertTimeRange(timeRange, of: audioAssetTrack, at: .zero)
                    
                    videoCompositionTrack.scaleTimeRange(timeRange, toDuration: CMTime(seconds: 60, preferredTimescale: asset.duration.timescale))
                    
                    let transform = videoAssetTrack.preferredTransform
                    let isPortrait = transform.a == 0 && transform.d == 0 && abs(transform.b) == 1 && abs(transform.c) == 1
                    
                    let videoCompositionInstruction = AVMutableVideoCompositionInstruction()
                    videoCompositionInstruction.timeRange = videoCompositionTrack.timeRange
                    
                    let videoLayerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoCompositionTrack)
                    
                    print(videoAssetTrack.preferredTransform)
                    let translate = CGAffineTransform(translationX: -videoAssetTrack.naturalSize.width / 3, y: 0)
                    videoLayerInstruction.setTransform(
                        translate
//                        transform
                        , at: .zero)
                    videoCompositionInstruction.layerInstructions = [videoLayerInstruction]
                    
                    let videoComposition = AVMutableVideoComposition()
                    videoComposition.instructions = [videoCompositionInstruction]
                    
                    let size = videoAssetTrack.naturalSize
                    videoComposition.renderSize =
                        CGSize(width: size.width / 2, height: size.height)
//                        size.applying(scale.inverted())
                    videoComposition.renderScale = 1
                    videoComposition.frameDuration =
                        videoAssetTrack.minFrameDuration
//                        CMTime(seconds: 1, preferredTimescale: 30)
                    
                    let mainQueue = DispatchQueue(label: "main")
                    let videoQueue = DispatchQueue(label: "video")
                    let audioQueue = DispatchQueue(label: "audio")

                    var cancelled = false
                    
                    struct Context {
                        let reader: AVAssetReader
                        let writer: AVAssetWriter
                        
                        let readerVideoOutput: AVAssetReaderOutput
                        let writerVideoInput: AVAssetWriterInput
                    
                        let readerAudioOutput: AVAssetReaderOutput
                        let writerAudioInput: AVAssetWriterInput
                    }
                    
                    func setupAssetReaderAndAssetWriter() throws -> Context {
                        let reader = try AVAssetReader(asset:
                            composition
//                            asset
                        )
                        
                        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)

                        guard let localComposition = reader.asset as? AVComposition else { fatalError() }
                        let readerVideoOutput =
                            AVAssetReaderVideoCompositionOutput(videoTracks: localComposition.tracks(withMediaType: .video), videoSettings: nil)
//                            AVAssetReaderTrackOutput(track: videoAssetTrack, outputSettings: nil)
                        
                        readerVideoOutput.alwaysCopiesSampleData = false
                        
                        readerVideoOutput.videoComposition = videoComposition
//                        if reader.canAdd(readerVideoOutput) {
                            reader.add(readerVideoOutput)
//                        }

                        let writerVideoInput = AVAssetWriterInput(mediaType: .video, outputSettings: nil)
//                        if writer.canAdd(writerVideoInput) {
                            writer.add(writerVideoInput)
//                        }
                        
                        let readerAudioOutput =
                            AVAssetReaderTrackOutput(track:
                                audioCompositionTrack
//                                audioAssetTrack
                                , outputSettings: nil)
                        
                        readerAudioOutput.alwaysCopiesSampleData = false
                        
//                        if reader.canAdd(readerAudioOutput) {
                            reader.add(readerAudioOutput)
//                        }
                        
                        let writerAudioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: nil)
//                        if writer.canAdd(writerAudioInput) {
                            writer.add(writerAudioInput)
//                        }
                        
                        return Context(reader: reader, writer: writer, readerVideoOutput: readerVideoOutput, writerVideoInput: writerVideoInput, readerAudioOutput: readerAudioOutput, writerAudioInput: writerAudioInput)
                    }
                    
                    func readingAndWritingDidFinish(successfully success: Bool, error: Error?, context: Context?) {
                        if !success {
                            context?.reader.cancelReading()
                            context?.writer.cancelWriting()
                            
                            print(error)
                        } else {
                            PHPhotoLibrary.shared().performChanges({
                                let changeRequest = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                                //                            changeRequest.contentEditingOutput = output
                            }) { (success, error) in
                                print(success, error)

                                DispatchQueue.main.async {
                                    URL(string: "instagram://camera").map { UIApplication.shared.open($0, options: [:], completionHandler: nil)}
                                }
                            }
                        }
                    }
                    
                    func startAssetReaderAndAssetWriter(context: Context) throws {
                        guard context.reader.startReading() else { throw context.reader.error! }

                        guard context.writer.startWriting() else { throw context.writer.error! }
                        
                        let dispatchGroup = DispatchGroup()

                        context.writer.startSession(atSourceTime: .zero)
                        
                        var videoFinished = false
                        var audioFinished = false
                        
                        dispatchGroup.enter()
                        
                        context.writerVideoInput.requestMediaDataWhenReady(on: videoQueue) {
                            if videoFinished {
                                return
                            }
                            var completedOrFailed = false
                            
                            while context.writerVideoInput.isReadyForMoreMediaData && !completedOrFailed {
                                guard let sampleBuffer = context.readerVideoOutput.copyNextSampleBuffer() else {
                                    completedOrFailed = true
                                    continue
                                }
                                completedOrFailed = !context.writerVideoInput.append(sampleBuffer)
                            }
                            
                            if completedOrFailed {
                                let oldFinished = videoFinished
                                videoFinished = true
                                if !oldFinished {
                                    context.writerVideoInput.markAsFinished()
                                }
                                dispatchGroup.leave()
                            }
                        }

                        dispatchGroup.enter()
                        
                        context.writerAudioInput.requestMediaDataWhenReady(on: audioQueue) {
                            if audioFinished {
                                return
                            }
                            var completedOrFailed = false
                            
                            while context.writerAudioInput.isReadyForMoreMediaData && !completedOrFailed {
                                guard let sampleBuffer = context.readerAudioOutput.copyNextSampleBuffer() else {
                                    completedOrFailed = true
                                    continue
                                }
                                completedOrFailed = !context.writerAudioInput.append(sampleBuffer)
                            }

                            if completedOrFailed {
                                let oldFinished = audioFinished
                                audioFinished = true
                                if !oldFinished {
                                    context.writerAudioInput.markAsFinished()
                                }
                                audioFinished = true
                                dispatchGroup.leave()
                            }
                        }
                        
                        dispatchGroup.notify(queue: mainQueue) {
                            if cancelled {
                                context.reader.cancelReading()
                                context.writer.cancelWriting()
                            } else {
                                do {
                                    guard context.reader.status != .failed else { throw context.reader.error! }
                                    context.writer.finishWriting {
                                        let success = context.writer.status != .failed
                                        readingAndWritingDidFinish(successfully: success, error: success ? nil : context.writer.error, context: context)
                                    }
                                }
                                catch {
                                    readingAndWritingDidFinish(successfully: false, error: error, context: context)
                                }
                            }
                        }
                    }
                    
                    composition
//                    asset
                        .loadValuesAsynchronously(forKeys: ["tracks"]) {
                        mainQueue.async {
                            guard !cancelled else { return }
                            
                            do {
                                var localError: NSError?
                                guard asset.statusOfValue(forKey: "tracks", error: &localError) == .loaded else { throw localError! }
                                
                                try? FileManager.default.removeItem(at: url)
                                
                                let context = try setupAssetReaderAndAssetWriter()
                                
                                try startAssetReaderAndAssetWriter(context: context)
                            }
                            catch {
                                readingAndWritingDidFinish(successfully: false, error: error, context: nil)
                            }
                        }
                    }
                    
//                    let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality)
//                    exportSession?.outputURL = url
//                    exportSession?.outputFileType =
//                        //                        .mov
//                        .mp4
//
//                    exportSession?.videoComposition = videoComposition
//
//                    exportSession?.exportAsynchronously {
//                        switch exportSession?.status {
//                        case .failed:
//                            print("failed:", exportSession?.error)
//                        case .cancelled:
//                            print("canceled")
//                        default:
//                            PHPhotoLibrary.shared().performChanges({
//                                let changeRequest = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
//                                //                            changeRequest.contentEditingOutput = output
//                            }) { (success, error) in
//                                print(success, error)
//                            }
////                            DispatchQueue.main.async {
////                                self.present(UIActivityViewController(activityItems: [url], applicationActivities: nil), animated: true, completion: nil)
////                            }
//                        }
//                    }
                }
                catch {
                    print(error)
                }
            }
            }
            catch {
                print(error)
//            }

        }
    }
    
    // MARK: - Navigation

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        switch segue.identifier {
        case "formats":
            let viewController = segue.destination as? FormatTableViewController
            viewController?.formats = info?.formats ?? []
        default:
            assertionFailure()
        }
    }
}

extension DownloadViewController: PHPhotoLibraryChangeObserver {
    func photoLibraryDidChange(_ changeInstance: PHChange) {
        print(changeInstance)
    }
}

extension DownloadViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        print(#function, gestureRecognizer, otherGestureRecognizer)
        return true
    }
}