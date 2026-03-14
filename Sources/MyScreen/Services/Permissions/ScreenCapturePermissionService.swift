import CoreGraphics
import Foundation

final class ScreenCapturePermissionService {
    func currentStatus() -> ScreenCapturePermissionStatus {
        CGPreflightScreenCaptureAccess() ? .granted : .unknown
    }

    @MainActor
    func requestAccess() async -> ScreenCapturePermissionStatus {
        let granted = CGRequestScreenCaptureAccess()
        return granted ? .granted : .denied
    }
}
