import AVFoundation
import SwiftUI
import VisionKit

struct BarcodeScanner: View {
    var scanned: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var allowed: Bool?
    var body: some View {
        VStack(spacing: 0) {
            LogSheetHeader(title: "Scan book", color: "rose", close: { dismiss() })
            Group {
                if allowed == true, DataScannerViewController.isSupported, DataScannerViewController.isAvailable {
                    ScannerRepresentable(scanned: scanned).ignoresSafeArea(edges: .bottom)
                } else if allowed == nil {
                    ProgressView()
                } else {
                    ContentUnavailableView(
                        "Camera unavailable",
                        systemImage: "barcode.viewfinder",
                        description: Text("Allow camera access in Settings, or enter the ISBN manually.")
                    )
                }
            }.task { allowed = await AVCaptureDevice.requestAccess(for: .video) }
        }.presentationDetents([.large]).careSheetStyle()
    }
}

struct ScannerRepresentable: UIViewControllerRepresentable {
    var scanned: (String) -> Void
    func makeCoordinator() -> Coordinator {
        Coordinator(scanned: scanned)
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        do { try scanner.startScanning() } catch { context.coordinator.error = error }
        return scanner
    }

    func updateUIViewController(_: DataScannerViewController, context _: Context) {}
    @MainActor final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var scanned: (String) -> Void
        var didScan = false
        var error: Error?
        init(scanned: @escaping (String) -> Void) {
            self.scanned = scanned
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems _: [RecognizedItem]
        ) {
            guard !didScan else { return }
            for item in addedItems {
                if case let .barcode(barcode) = item,
                   let value = barcode
                   .payloadStringValue
                {
                    didScan = true; dataScanner.stopScanning(); scanned(value); break
                }
            }
        }
    }
}
