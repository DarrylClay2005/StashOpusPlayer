import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct DocumentPicker: UIViewControllerRepresentable {
    enum Mode {
        case folder
        case audioFiles
    }

    let mode: Mode
    let onPick: ([URL]) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let types: [UTType]
        let allowsMultiple: Bool

        switch mode {
        case .folder:
            types = [.folder]
            allowsMultiple = false
        case .audioFiles:
            types = [
                .audio,
                .mp3,
                .mpeg4Audio,
                .aiff,
                .wav,
                UTType(filenameExtension: "flac") ?? .audio,
                UTType(filenameExtension: "opus") ?? .audio,
                UTType(filenameExtension: "caf") ?? .audio
            ]
            allowsMultiple = true
        }

        // asCopy: false for folder — we need security-scoped access to the original location.
        // asCopy: true for audio files — iOS copies them into the app's temp directory so no
        // security-scoped resource access is required on the returned URLs.
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: types,
            asCopy: mode == .audioFiles
        )
        picker.allowsMultipleSelection = allowsMultiple
        picker.shouldShowFileExtensions = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: ([URL]) -> Void

        init(onPick: @escaping ([URL]) -> Void) {
            self.onPick = onPick
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(urls)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {}
    }
}
