//
//  ContentView.swift
//  OpenRec
//
//  Created by Liam Brem on 3/26/26.
//

import SwiftUI
import Combine
import CoreGraphics

struct ContentView: View {
    @StateObject private var recorder = ScreenRecorder()

    var body: some View {
        VStack(spacing: 16) {
            Text(recorder.isRecording ? "Recording..." : "Ready")
                .font(.headline)
                .foregroundStyle(recorder.isRecording ? .red : .primary)

            Button(action: {
                Task {
                    if recorder.isRecording {
                        await recorder.stopRecording()
                    } else {
                        await recorder.startRecording()
                    }
                }
            }) {
                Label(
                    recorder.isRecording ? "Stop Recording" : "Start Recording",
                    systemImage: recorder.isRecording ? "stop.circle.fill" : "record.circle"
                )
                .font(.title2)
            }
            .buttonStyle(.borderedProminent)
            .tint(recorder.isRecording ? .red : .accentColor)

            if let url = recorder.lastSavedURL, !recorder.isRecording {
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                .font(.caption)
            }

            if let error = recorder.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(13)
        .frame(minWidth: 300)
        .onAppear {
            CGRequestScreenCaptureAccess()
        }
    }
}

#Preview {
    ContentView()
}
