import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct DocumentPicker: UIViewControllerRepresentable {
    enum Mode {
        case folder
        case audioFiles
        /// Single plain-text file (used for importing a yt-dlp cookies.txt export).
        case textFile
    }

    let mode: Mode
    let onPick: ([URL]) -> Void

    // Associated-object key for retaining the coordinator on the picker instance.
    private static var coordinatorKey = "DocumentPickerCoordinator"

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
        case .textFile:
            // cookies.txt exports are plain text but commonly carry no
            // registered UTType of their own — accept .plainText/.text plus
            // an explicit "txt" extension fallback so Files still offers it.
            types = [.plainText, .text, UTType(filenameExtension: "txt") ?? .plainText]
            allowsMultiple = false
        }

        // asCopy: false for folder — we need security-scoped access to the original location.
        // asCopy: true for audio files / text file — iOS copies them into the app's temp
        // directory so no security-scoped resource access is required on the returned URLs.
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: types,
            asCopy: mode != .folder
        )
        picker.allowsMultipleSelection = allowsMultiple
        picker.shouldShowFileExtensions = true
        picker.delegate = context.coordinator
        // Retain the coordinator strongly on the picker so it is not deallocated if SwiftUI
        // recreates the DocumentPicker view before the delegate callback fires.
        objc_setAssociatedObject(
            picker,
            &DocumentPicker.coordinatorKey,
            context.coordinator,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
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
