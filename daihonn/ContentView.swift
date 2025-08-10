//
//  ContentView.swift
//  daihonn
//
//  Created by Keiju Hiramoto on 2025/08/10.
//

import SwiftUI
import AVFoundation
import Photos

class CameraManager: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var errorMessage: String? = nil
    
    private let session = AVCaptureSession()
    private let movieOutput = AVCaptureMovieFileOutput()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    
    private var videoDeviceInput: AVCaptureDeviceInput?
    private var recordingURL: URL?
    
    override init() {
        super.init()
        configureSession()
    }
    
    private func configureSession() {
        session.beginConfiguration()
        
        // Add video input
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            errorMessage = "No front camera available."
            session.commitConfiguration()
            return
        }
        
        do {
            let videoInput = try AVCaptureDeviceInput(device: videoDevice)
            if session.canAddInput(videoInput) {
                session.addInput(videoInput)
                videoDeviceInput = videoInput
            } else {
                errorMessage = "Cannot add video input."
                session.commitConfiguration()
                return
            }
        } catch {
            errorMessage = "Error creating video input: \(error.localizedDescription)"
            session.commitConfiguration()
            return
        }
        
        // Add movie output
        if session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
        } else {
            errorMessage = "Cannot add movie output."
            session.commitConfiguration()
            return
        }
        
        session.commitConfiguration()
    }
    
    func startSession() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            if !session.isRunning {
                DispatchQueue.global(qos: .userInitiated).async { self.session.startRunning() }
            }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted {
                    if !self.session.isRunning {
                        DispatchQueue.global(qos: .userInitiated).async { self.session.startRunning() }
                    }
                } else {
                    DispatchQueue.main.async { self.errorMessage = "カメラの権限がありません。設定から許可してください。" }
                }
            }
        default:
            DispatchQueue.main.async { self.errorMessage = "カメラの権限がありません。設定から許可してください。" }
        }
    }
    
    func stopSession() {
        if session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async {
                self.session.stopRunning()
            }
        }
    }
    
    func getPreviewLayer() -> AVCaptureVideoPreviewLayer {
        if let layer = previewLayer {
            return layer
        }
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        previewLayer = layer
        return layer
    }
    
    func startRecording() {
        guard !movieOutput.isRecording else { return }

        // Ensure microphone permission and add input lazily
        func addMicIfNeeded() -> Bool {
            if Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") == nil {
                self.errorMessage = "Info.plist に NSMicrophoneUsageDescription がありません。録音は無効化されます。"
                return false
            }
            // Check if an audio input is already present
            if self.session.inputs.contains(where: { ($0 as? AVCaptureDeviceInput)?.device.hasMediaType(.audio) == true }) {
                return true
            }
            guard let audioDevice = AVCaptureDevice.default(for: .audio) else {
                self.errorMessage = "No audio device available."
                return false
            }
            do {
                let audioInput = try AVCaptureDeviceInput(device: audioDevice)
                self.session.beginConfiguration()
                if self.session.canAddInput(audioInput) { self.session.addInput(audioInput) }
                self.session.commitConfiguration()
                return true
            } catch {
                self.errorMessage = "Error creating audio input: \(error.localizedDescription)"
                return false
            }
        }

        let audioPermission = AVAudioSession.sharedInstance().recordPermission
        switch audioPermission {
        case .granted:
            guard addMicIfNeeded() else { return }
            let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
            movieOutput.startRecording(to: tmpURL, recordingDelegate: self)
            DispatchQueue.main.async { self.isRecording = true }
        case .undetermined:
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                if granted {
                    _ = addMicIfNeeded()
                    let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
                    self.movieOutput.startRecording(to: tmpURL, recordingDelegate: self)
                    DispatchQueue.main.async { self.isRecording = true }
                } else {
                    DispatchQueue.main.async { self.errorMessage = "マイクの権限がありません。設定から許可してください。" }
                }
            }
        case .denied:
            DispatchQueue.main.async { self.errorMessage = "マイクの権限がありません。設定から許可してください。" }
        @unknown default:
            DispatchQueue.main.async { self.errorMessage = "マイク権限の状態を取得できません。" }
        }
    }
    
    func stopRecording() {
        if movieOutput.isRecording {
            movieOutput.stopRecording()
        }
    }
}

extension CameraManager: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput,
                    didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection],
                    error: Error?) {
        DispatchQueue.main.async {
            self.isRecording = false
        }
        if let error = error {
            DispatchQueue.main.async {
                self.errorMessage = "Recording error: \(error.localizedDescription)"
            }
            return
        }

        // Save to Photos
        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async { self.errorMessage = "フォトライブラリへの保存権限がありません。" }
                return
            }
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: outputFileURL)
            }) { success, err in
                if !success {
                    DispatchQueue.main.async { self.errorMessage = err?.localizedDescription ?? "保存に失敗しました" }
                }
            }
        }
    }
}

struct CameraPreviewView: UIViewRepresentable {
    @ObservedObject var cameraManager: CameraManager
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        let previewLayer = cameraManager.getPreviewLayer()
        previewLayer.frame = UIScreen.main.bounds
        view.layer.addSublayer(previewLayer)
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        cameraManager.getPreviewLayer().frame = uiView.bounds
    }
}

import UIKit

struct CenteredTextEditor: UIViewRepresentable {
    @Binding var text: String
    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.backgroundColor = .clear
        tv.textAlignment = .center
        tv.font = .preferredFont(forTextStyle: .title2)
        tv.textColor = .white
        tv.adjustsFontForContentSizeCategory = true
        tv.delegate = context.coordinator
        return tv
    }
    func updateUIView(_ uiView: UITextView, context: Context) { uiView.text = text }
    func makeCoordinator() -> Coord { Coord(self) }
    final class Coord: NSObject, UITextViewDelegate {
        var parent: CenteredTextEditor
        init(_ p: CenteredTextEditor) { parent = p }
        func textViewDidChange(_ textView: UITextView) { parent.text = textView.text }
    }
}

struct PromptArea: View {
    @Binding var text: String
    @Binding var isEditing: Bool

    var body: some View {

        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.45))
            if isEditing {
                CenteredTextEditor(text: $text).padding()
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack {
                        Spacer()
                        Text(text)
                            .font(.title2)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .padding()
                            .frame(maxWidth: .infinity)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, minHeight: 240)
                }
            }
        }
        Spacer()
    }
}

struct TeleprompterRecorderView: View {
    @StateObject private var cameraManager = CameraManager()
    @State private var teleprompterText: String = "This is your teleprompter text. You can edit this text to suit your speech or presentation. The text will scroll automatically while recording."
    @State private var isEditing: Bool = false
    @State private var showError: Bool = false
    
    var body: some View {
        ZStack {
            CameraPreviewView(cameraManager: cameraManager)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    if isEditing {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        isEditing = false
                    }
                }
            
            VStack {
                //Spacer()
                PromptArea(text: $teleprompterText, isEditing: $isEditing)
                    .frame(height: 240)
                    .padding(.horizontal, 12)

                HStack(spacing: 16) {
                    Button(isEditing ? "完了" : "編集") {
                        if isEditing {
                            // Dismiss keyboard before leaving edit mode
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                            isEditing = false
                        } else {
                            isEditing = true
                        }
                    }
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(Color.white.opacity(0.85))
                        .clipShape(Capsule())

                    Button(action: {
                        if cameraManager.isRecording {
                            cameraManager.stopRecording()
                        } else {
                            cameraManager.startRecording()
                        }
                    }) {
                        Image(systemName: cameraManager.isRecording ? "stop.circle.fill" : "record.circle.fill")
                            .resizable()
                            .frame(width: 60, height: 60)
                            .foregroundColor(cameraManager.isRecording ? .red : .green)
                    }
                }
                .padding(.top, 8)
                .background(Color.black.opacity(0.5))
            }
        }
        .onAppear {
            cameraManager.startSession()
        }
        .onDisappear {
            cameraManager.stopSession()
        }
        .onReceive(cameraManager.$errorMessage) { msg in
            showError = (msg != nil)
        }
        .alert("エラー", isPresented: $showError, actions: {
            Button("OK") { cameraManager.errorMessage = nil }
        }, message: {
            Text(cameraManager.errorMessage ?? "")
        })
    }
}

struct ContentView: View {
    var body: some View {
        TeleprompterRecorderView()
    }
}

#Preview {
    ContentView()
}
