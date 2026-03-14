import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    var permissionStatus: ScreenCapturePermissionStatus
    var selectedSources: [MonitorSource]
    var tiles: [String: TileState]
    var wallLayout: WallLayoutState
    var isPermissionRequestInFlight = false

    private let permissionService: ScreenCapturePermissionService
    private let snapshotStore: WallSessionSnapshotStore

    init(
        permissionService: ScreenCapturePermissionService = ScreenCapturePermissionService(),
        snapshotStore: WallSessionSnapshotStore = WallSessionSnapshotStore()
    ) {
        self.permissionService = permissionService
        self.snapshotStore = snapshotStore

        let snapshot = snapshotStore.load() ?? .empty
        self.permissionStatus = permissionService.currentStatus()
        self.selectedSources = snapshot.selectedSources
        self.wallLayout = WallLayoutState(
            activeSourceIDs: snapshot.selectedSources.map(\.id),
            focusedSourceID: snapshot.focusedSourceID,
            grid: WallGridCalculator.calculate(for: snapshot.selectedSources.count, in: snapshot.windowSize.cgSize),
            windowSize: snapshot.windowSize
        )
        self.tiles = Dictionary(
            uniqueKeysWithValues: snapshot.selectedSources.map { source in
                (
                    source.id,
                    TileState.placeholder(
                        sourceID: source.id,
                        fpsTier: .balanced,
                        freshness: source.isAvailable ? .stale : .offline,
                        lastFrameAt: source.lastSeenAt
                    )
                )
            }
        )
    }

    func bootstrap() {
        permissionStatus = permissionService.currentStatus()
        ensureTileStateCoverage()
    }

    func requestScreenCapturePermission() async {
        guard !isPermissionRequestInFlight else { return }
        isPermissionRequestInFlight = true
        permissionStatus = await permissionService.requestAccess()
        isPermissionRequestInFlight = false
    }

    func updateWindowSize(_ size: CGSize) {
        let codableSize = CodableSize(size)
        guard wallLayout.windowSize != codableSize else { return }
        wallLayout.windowSize = codableSize
        wallLayout.grid = WallGridCalculator.calculate(for: selectedSources.count, in: size)
        persistSnapshot()
    }

    func setFocusedSourceID(_ sourceID: String?) {
        wallLayout.focusedSourceID = sourceID
        persistSnapshot()
    }

    func replaceSelectedSources(_ sources: [MonitorSource]) {
        selectedSources = sources
        wallLayout.activeSourceIDs = sources.map(\.id)
        wallLayout.grid = WallGridCalculator.calculate(for: sources.count, in: wallLayout.windowSize.cgSize)
        ensureTileStateCoverage()
        persistSnapshot()
    }

    func removeSource(id: String) {
        selectedSources.removeAll { $0.id == id }
        wallLayout.activeSourceIDs.removeAll { $0 == id }
        tiles.removeValue(forKey: id)
        if wallLayout.focusedSourceID == id {
            wallLayout.focusedSourceID = nil
        }
        wallLayout.grid = WallGridCalculator.calculate(for: selectedSources.count, in: wallLayout.windowSize.cgSize)
        persistSnapshot()
    }

    private func ensureTileStateCoverage() {
        for source in selectedSources {
            if tiles[source.id] == nil {
                tiles[source.id] = TileState.placeholder(
                    sourceID: source.id,
                    fpsTier: .balanced,
                    freshness: source.isAvailable ? .stale : .offline,
                    lastFrameAt: source.lastSeenAt
                )
            }
        }
    }

    private func persistSnapshot() {
        snapshotStore.save(
            WallSessionSnapshot(
                selectedSources: selectedSources,
                focusedSourceID: wallLayout.focusedSourceID,
                windowSize: wallLayout.windowSize
            )
        )
    }
}
