import Photos
import SwiftUI
import UIKit

struct CameraCaptureView: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss

    var onImage: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) { }

    func makeCoordinator() -> Coordinator {
        Coordinator(onImage: onImage, dismiss: dismiss)
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let onImage: (UIImage) -> Void
        private let dismiss: DismissAction

        init(onImage: @escaping (UIImage) -> Void, dismiss: DismissAction) {
            self.onImage = onImage
            self.dismiss = dismiss
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                onImage(image)
            }
            dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }
    }
}

struct FitCheckPhotoPreview: View {
    var data: Data?
    var height: CGFloat = 220

    var body: some View {
        Group {
            if let data, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct FitCheckInlineStatus: View {
    var message: String
    var isLoading = false
    var systemImage = "info.circle"

    var body: some View {
        if !message.isEmpty || isLoading {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: systemImage)
                        .foregroundStyle(.secondary)
                }
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

struct FitCheckNoMatchDiagnosticsView: View {
    var reasons: [String]

    var body: some View {
        if !reasons.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label("Why no outfit matched", systemImage: "exclamationmark.triangle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)

                ForEach(reasons, id: \.self) { reason in
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
        }
    }
}

struct FitCheckSaveImageButton: View {
    var data: Data
    var title = "Save Image"

    @State private var isSaving = false
    @State private var status = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                Task {
                    await saveImage()
                }
            } label: {
                FitCheckButtonLabel(
                    title: isSaving ? "Saving" : title,
                    systemImage: "square.and.arrow.down",
                    isLoading: isSaving
                )
            }
            .buttonStyle(.bordered)
            .disabled(isSaving)

            if !status.isEmpty {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @MainActor
    private func saveImage() async {
        guard let image = UIImage(data: data) else {
            status = "Image could not be read."
            return
        }

        isSaving = true
        defer {
            isSaving = false
        }

        do {
            try await saveToPhotoLibrary(image)
            status = "Saved to Photos."
        } catch {
            status = error.localizedDescription
        }
    }

    private func saveToPhotoLibrary(_ image: UIImage) async throws {
        let currentStatus = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        let authorizedStatus: PHAuthorizationStatus
        if currentStatus == .notDetermined {
            authorizedStatus = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        } else {
            authorizedStatus = currentStatus
        }

        guard authorizedStatus == .authorized || authorizedStatus == .limited else {
            throw FitCheckImageSaveError.permissionDenied
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            } completionHandler: { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: FitCheckImageSaveError.saveFailed)
                }
            }
        }
    }
}

private enum FitCheckImageSaveError: LocalizedError {
    case permissionDenied
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Allow photo library access to save avatar images."
        case .saveFailed:
            return "Image could not be saved."
        }
    }
}

struct FitCheckButtonLabel: View {
    var title: String
    var systemImage: String
    var isLoading = false

    var body: some View {
        if isLoading {
            HStack {
                ProgressView()
                    .controlSize(.small)
                Text(title)
            }
        } else {
            Label(title, systemImage: systemImage)
        }
    }
}

extension UIImage {
    func fitcheckPreparedJPEGData(maxDimension: CGFloat = 1280, compressionQuality: CGFloat = 0.78) -> Data? {
        fitcheckScaled(maxDimension: maxDimension).jpegData(compressionQuality: compressionQuality)
    }

    private func fitcheckScaled(maxDimension: CGFloat) -> UIImage {
        let longestSide = max(size.width, size.height)
        guard longestSide > maxDimension else { return self }

        let scale = maxDimension / longestSide
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1

        return UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}

extension Data {
    var fitcheckImageMimeType: String {
        if starts(with: [0x89, 0x50, 0x4E, 0x47]) {
            return "image/png"
        }

        if starts(with: [0x52, 0x49, 0x46, 0x46]) {
            return "image/webp"
        }

        return "image/jpeg"
    }
}
