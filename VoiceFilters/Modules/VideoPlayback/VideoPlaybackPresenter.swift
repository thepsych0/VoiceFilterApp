import AVFoundation
import UIKit
import MessageUI

final class VideoPlaybackPresenter {

    weak var viewInput: VideoPlaybackViewInput?

    private(set) var selectedVideoURL: URL?
    private(set) var selectedFilter: VoiceFilter?

    private(set) var engine: AVAudioEngine?
    private(set) var audioPlayer: AVAudioPlayerNode?

    func apply(voiceFilter: VoiceFilter) {
        guard selectedFilter != voiceFilter else { return }
        resetEffects()
        switch voiceFilter {
        case .darthVader:
            applyDarthVaderFilter()
        case .alien:
            applyAlienFilter()
        case .helium:
            applyHeliumFilter()
        case .cave:
            applyCaveFilter()
        case .clear:
            selectedFilter = nil
            return
        }
        selectedFilter = voiceFilter
    }

    func saveEditedVideo() {
        prepareEditedVideo() { [weak self] outputURL in
            guard let self else { return }
            UISaveVideoAtPathToSavedPhotosAlbum(outputURL.path, self, nil, nil)
            self.editedVideoURL = outputURL
            self.viewInput?.hideLoadingOverlay()
            self.viewInput?.showEditedVideoSavedAlert()
        }
    }

    func didRecordVideo(videoURL: URL) {
        self.selectedVideoURL = videoURL
        viewInput?.showVideoRecordedAlert(for: videoURL)
    }

    func didSaveVideo() {
        guard let selectedVideoURL = selectedVideoURL else { return }
        startPlayback(videoURL: selectedVideoURL)
    }

    func didSelectVideo(videoURL: URL) {
        self.selectedVideoURL = videoURL
        startPlayback(videoURL: videoURL)
    }

    func didPressRestart() {
        editedVideoURL = nil
        selectedVideoURL = nil
        selectedFilter = nil
        resetEffects()
        engine?.stop()
        audioPlayer?.stop()
        viewInput?.restart()
    }

    func didPressShareVideo(source: ShareSource) {
        guard let editedVideoURL else {
            prepareEditedVideo { [weak self] outputURL in
                guard let self else { return }
                self.editedVideoURL = outputURL
                self.viewInput?.hideLoadingOverlay()
                self.shareVideo(with: outputURL, to: source)
            }
            return
        }
        shareVideo(with: editedVideoURL, to: source)
    }

    // MARK: - Private

    private func shareVideo(with url: URL, to source: ShareSource) {
        do {
            let video = try Data(contentsOf: URL(fileURLWithPath: url.path))
            switch source {
            case .instagram:
                let pasteboardItems: [String: Any] = [
                    "com.instagram.sharedSticker.backgroundVideo": video,
                ]
                share(video: video, scheme: "instagram-stories://share", pasteboardItems: pasteboardItems)
            }
        } catch {
            print(error)
            return
        }
    }

    private func share(video: Data, scheme: String, pasteboardItems: [String: Any]) {
        if let storiesUrl = URL(string: scheme) {
            if UIApplication.shared.canOpenURL(storiesUrl) {
                UIPasteboard.general.setItems(
                    [pasteboardItems],
                    options: [:]
                )
                UIApplication.shared.open(
                    storiesUrl, options: [:],
                    completionHandler: nil
                )
            } else {
                viewInput?.hideLoadingOverlay()
            }
        }
    }

    private func startPlayback(videoURL: URL) {
        getAudioURL(from: videoURL) { [weak self] audioURL in
            guard let self, let audioURL else { return }
            do {
                try self.prepareEngine(url: audioURL)
            } catch {
                return
            }
            self.viewInput?.playVideo(for: videoURL)
        }
    }

    private func prepareEditedVideo(completion: @escaping (URL) -> Void) {
        guard let selectedVideoURL else { return }

        viewInput?.showLoadingOverlay(text: "Video is being processed")
        engine?.stop()
        audioPlayer?.stop()

        guard let renderedAudioURL = renderAudio() else { return }

        mergeVideoAndAudio(videoUrl: selectedVideoURL, audioUrl: renderedAudioURL) { outputURL in
            completion(outputURL)
        }
    }

    func mergeVideoAndAudio(videoUrl: URL, audioUrl: URL, completion: @escaping (URL) -> Void) {

        let mixComposition = AVMutableComposition()
        var mutableCompositionVideoTrack = [AVMutableCompositionTrack]()
        var mutableCompositionAudioTrack = [AVMutableCompositionTrack]()
        var mutableCompositionAudioOfVideoTrack = [AVMutableCompositionTrack]()


        let aVideoAsset = AVAsset(url: videoUrl)
        let aAudioAsset = AVAsset(url: audioUrl)

        guard let compositionAddVideo = mixComposition.addMutableTrack(
            withMediaType: AVMediaType.video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ), let compositionAddAudio = mixComposition.addMutableTrack(
            withMediaType: AVMediaType.audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ), let compositionAddAudioOfVideo = mixComposition.addMutableTrack(
            withMediaType: AVMediaType.audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            return
        }

        let aVideoAssetTrack: AVAssetTrack = aVideoAsset.tracks(withMediaType: AVMediaType.video)[0]
        let aAudioAssetTrack: AVAssetTrack = aAudioAsset.tracks(withMediaType: AVMediaType.audio)[0]

        compositionAddVideo.preferredTransform = aVideoAssetTrack.preferredTransform

        mutableCompositionVideoTrack.append(compositionAddVideo)
        mutableCompositionAudioTrack.append(compositionAddAudio)
        mutableCompositionAudioOfVideoTrack.append(compositionAddAudioOfVideo)

        do {
            let duration = min(aVideoAssetTrack.timeRange.duration, aAudioAssetTrack.timeRange.duration)

            try mutableCompositionVideoTrack[0].insertTimeRange(
                CMTimeRangeMake(start: CMTime.zero, duration: duration),
                of: aVideoAssetTrack,
                at: CMTime.zero
            )

            try mutableCompositionAudioTrack[0].insertTimeRange(
                CMTimeRangeMake(start: CMTime.zero, duration: duration),
                of: aAudioAssetTrack,
                at: CMTime.zero
            )
        } catch {
            print(error.localizedDescription)
        }

        guard
            let documentDirectory = FileManager.default.urls(
                for: .documentDirectory,
                in: .userDomainMask).first
        else { return }

        let outputURL = documentDirectory.appendingPathComponent("mergedVideo.mov")

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(atPath: outputURL.path)
        }

        guard let exporter = AVAssetExportSession(
            asset: mixComposition,
            presetName: AVAssetExportPresetHighestQuality)
        else { return }
        exporter.outputURL = outputURL
        exporter.outputFileType = AVFileType.mov
        exporter.shouldOptimizeForNetworkUse = true

        exporter.exportAsynchronously {
            DispatchQueue.main.async {
                completion(outputURL)
            }
        }
    }

    private func getAudioURL(from videoURL: URL, completion: @escaping (URL?) -> Void)  {
        let composition = AVMutableComposition()
        do {
            let asset = AVURLAsset(url: videoURL)
            guard let audioAssetTrack = asset.tracks(withMediaType: AVMediaType.audio).first else {
                completion(nil)
                return
            }
            guard let audioCompositionTrack = composition.addMutableTrack(withMediaType: AVMediaType.audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                completion(nil)
                return
            }
            try audioCompositionTrack.insertTimeRange(audioAssetTrack.timeRange, of: audioAssetTrack, at: CMTime.zero)
        } catch {
            return
        }

        let outputURL = URL(fileURLWithPath: NSTemporaryDirectory() + "audio.m4a")
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(atPath: outputURL.path)
        }

        let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough)!
        exportSession.outputFileType = AVFileType.m4a
        exportSession.outputURL = outputURL

        exportSession.exportAsynchronously {
            guard case exportSession.status = AVAssetExportSession.Status.completed else { return }

            DispatchQueue.main.async {
                completion(outputURL)
            }
        }
    }

    private func prepareEngine(url: URL) throws {
        resetEffects()

        let engine = AVAudioEngine()
        self.engine = engine

        let audioFile = try AVAudioFile(forReading: url)
        let audioPlayer = AVAudioPlayerNode()
        self.audioPlayer = audioPlayer

        setupEngineNodes()

        self.audioFile = audioFile
        audioPlayer.scheduleFile(audioFile, at: nil)
    }

    private func setupEngineNodes() {
        guard let engine, let audioPlayer else { return }

        let nodes = [
            audioPlayer,
            pitchControl,
            distortion,
            reverb
        ]
        nodes.forEach { engine.attach($0) }

        for i in 0..<nodes.count {
            guard i < nodes.count - 1 else {
                engine.connect(nodes[i], to: engine.mainMixerNode, format: nil)
                continue
            }
            engine.connect(nodes[i], to: nodes[i + 1], format: nil)
        }
    }

    private func renderAudio() -> URL? {
        guard let audioFile else { return nil }

        try? AVAudioSession.sharedInstance().setCategory(AVAudioSession.Category.playAndRecord, options: .defaultToSpeaker)

        engine?.stop()
        engine?.reset()

        let engine = AVAudioEngine()
        let audioPlayer = AVAudioPlayerNode()
        self.engine = engine
        self.audioPlayer = audioPlayer

        setupEngineNodes()

        audioPlayer.scheduleFile(audioFile, at: nil)

        do {
            let buffCapacity: AVAudioFrameCount = 4096
            try engine.enableManualRenderingMode(.offline, format: audioFile.processingFormat, maximumFrameCount: buffCapacity)
        }
        catch {
            print("Failed to enable manual rendering mode: \(error)")
            return nil
        }

        do {
            try engine.start()
        }
        catch {
            return nil
        }

        audioPlayer.play()

        var outputFile: AVAudioFile?
        do {
            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("altered_audio.m4a")
            if FileManager.default.fileExists(atPath: url.path) {
                try? FileManager.default.removeItem(at: url)
            }

            let recordSettings = audioFile.fileFormat.settings

            outputFile = try AVAudioFile(forWriting: url, settings: recordSettings)
        } catch {
            return nil
        }


        let outputBuff = AVAudioPCMBuffer(
            pcmFormat: engine.manualRenderingFormat,
            frameCapacity: engine.manualRenderingMaximumFrameCount
        )!

        while engine.manualRenderingSampleTime < audioFile.length {
            let remainingSamples = audioFile.length - engine.manualRenderingSampleTime
            let framesToRender = min(outputBuff.frameCapacity, AVAudioFrameCount(remainingSamples))

            do {
                let renderingStatus = try engine.renderOffline(framesToRender, to: outputBuff)

                switch renderingStatus {

                case .success:
                    do {
                        try outputFile?.write(from: outputBuff)
                    }
                    catch {
                        print("Failed to write from file to buffer: \(error)")
                        throw error
                    }

                case .insufficientDataFromInputNode:
                    return nil

                case.cannotDoInCurrentContext:
                    return nil

                case .error:
                    print("An error occured during rendering.")
                    return nil

                @unknown default:
                    return nil
                }
            }
            catch {
                print("Failed to render offline manually: \(error)")
                return nil
            }
        }

        let newURL = outputFile?.url
        outputFile = nil

        audioPlayer.stop()
        engine.stop()
        engine.disableManualRenderingMode()

        return newURL
    }

    private func resetEffects() {
        distortion.wetDryMix = 0
        reverb.wetDryMix = 0
        pitchControl.pitch = 0
    }

    private func applyDarthVaderFilter() {
        pitchControl.pitch = -1000
    }

    private func applyAlienFilter() {
        distortion.wetDryMix = 50
        distortion.loadFactoryPreset(.speechCosmicInterference)
    }

    private func applyHeliumFilter() {
        pitchControl.pitch = 1000
    }

    private func applyCaveFilter() {
        reverb.wetDryMix = 50
        reverb.loadFactoryPreset(.cathedral)
    }

    private var editedVideoURL: URL?
    private let reverb = AVAudioUnitReverb()
    private let pitchControl = AVAudioUnitTimePitch()
    private lazy var distortion = AVAudioUnitDistortion()

    private var audioFile: AVAudioFile?
}
