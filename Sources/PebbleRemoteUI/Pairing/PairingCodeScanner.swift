#if os(iOS)
import AVFoundation
import SwiftUI
import Vision
import VisionKit

/// The camera reading the pairing code the Mac shows (VisionKit's data scanner, QR codes only). iOS only; this file
/// is not compiled by the macOS type-check, so it keeps to long-standing API.
struct PairingCodeScanner: UIViewControllerRepresentable {
    /// Called once per newly recognized code with its text.
    let onCode: (String) -> Void

    /// The hardware can scan (Neural Engine and a camera).
    static var isSupported: Bool { DataScannerViewController.isSupported }

    /// Asks for the camera the first time; true when scanning can start.
    static func requestCamera() async -> Bool {
        guard DataScannerViewController.isSupported else { return false }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else { return false }
        default:
            return false
        }
        return DataScannerViewController.isAvailable
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        context.coordinator.onCode = onCode
        if !scanner.isScanning {
            try? scanner.startScanning()
        }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onCode: onCode)
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onCode: (String) -> Void

        init(onCode: @escaping (String) -> Void) {
            self.onCode = onCode
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            for item in addedItems {
                if case .barcode(let barcode) = item, let text = barcode.payloadStringValue {
                    onCode(text)
                    return
                }
            }
        }
    }
}
#endif
