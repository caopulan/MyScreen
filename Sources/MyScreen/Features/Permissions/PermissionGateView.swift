import SwiftUI

struct PermissionGateView: View {
    let status: ScreenCapturePermissionStatus
    let isRequestInFlight: Bool
    let onRequest: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "display.trianglebadge.exclamationmark")
                .font(.system(size: 44, weight: .medium))
                .foregroundStyle(.tint)

            Text("Screen Recording Permission Required")
                .font(.title2.weight(.semibold))

            Text(descriptionText)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 520)

            Button(action: onRequest) {
                Text(status == .denied ? "Open Permission Prompt" : "Request Permission")
                    .frame(minWidth: 180)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isRequestInFlight)

            if status == .denied {
                Text("If macOS does not show the prompt again, reopen System Settings > Privacy & Security > Screen & System Audio Recording.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 520)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var descriptionText: String {
        switch status {
        case .unknown:
            "MyScreen needs access to screen recording so it can build the monitoring wall for displays and app windows."
        case .denied:
            "Permission is currently denied. Grant access to let MyScreen enumerate displays and windows and render live previews."
        case .granted:
            "Permission granted."
        }
    }
}
