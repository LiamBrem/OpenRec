//
//  ScreenRecorder.swift
//  OpenRec
//

import Foundation
import Combine
import ScreenCaptureKit
import AVFoundation
import AppKit
import UniformTypeIdentifiers

@MainActor
class ScreenRecorder: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var errorMessage: String?
    @Published var lastSavedURL: URL?

    private var stream: SCStream?
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var streamOutput: RecordingOutput?

    func startRecording() async {
        guard let outputURL = await chooseSaveURL() else { return }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first else {
                errorMessage = "No display found"
                return
            }

            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            config.width = display.width
            config.height = display.height
            config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
            config.queueDepth = 5
            config.capturesAudio = false
            // Match the pixel format AVAssetWriter/HEVC expects
            config.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange

            // Remove existing file if user confirmed overwrite in the panel
            try? FileManager.default.removeItem(at: outputURL)

            assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: .mov)

            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.hevc,
                AVVideoWidthKey: config.width,
                AVVideoHeightKey: config.height,
                AVVideoCompressionPropertiesKey: [
                    AVVideoQualityKey: 0.7
                ]
            ]
            videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            videoInput?.expectsMediaDataInRealTime = true

            if let videoInput, assetWriter?.canAdd(videoInput) == true {
                assetWriter?.add(videoInput)
            }

            streamOutput = RecordingOutput(assetWriter: assetWriter!, videoInput: videoInput!)
            assetWriter?.startWriting()

            stream = SCStream(filter: filter, configuration: config, delegate: nil)
            try stream?.addStreamOutput(streamOutput!, type: .screen, sampleHandlerQueue: .global())
            try await stream?.startCapture()

            isRecording = true
            errorMessage = nil

        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stopRecording() async {
        do {
            try await stream?.stopCapture()
        } catch {
            errorMessage = error.localizedDescription
        }

        stream = nil
        isRecording = false

        videoInput?.markAsFinished()
        await assetWriter?.finishWriting()

        lastSavedURL = assetWriter?.outputURL
        assetWriter = nil
        videoInput = nil
        streamOutput = nil
    }

    private func chooseSaveURL() async -> URL? {
        let panel = NSSavePanel()
        panel.title = "Save Recording"
        panel.allowedContentTypes = [UTType.movie]
        panel.canCreateDirectories = true

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        panel.nameFieldStringValue = "Recording \(formatter.string(from: Date())).mov"

        let response = panel.runModal()
        return response == .OK ? panel.url : nil
    }
}

private class RecordingOutput: NSObject, SCStreamOutput {
    private let assetWriter: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private var sessionStarted = false

    init(assetWriter: AVAssetWriter, videoInput: AVAssetWriterInput) {
        self.assetWriter = assetWriter
        self.videoInput = videoInput
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              buffer.isValid,
              videoInput.isReadyForMoreMediaData else { return }

        if !sessionStarted {
            assetWriter.startSession(atSourceTime: buffer.presentationTimeStamp)
            sessionStarted = true
        }

        videoInput.append(buffer)
    }
}
