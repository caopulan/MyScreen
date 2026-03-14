import SwiftUI

struct MonitorTileView: View {
    let source: MonitorSource
    let tile: TileState
    let isFocused: Bool
    let onToggleFocus: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                Circle()
                    .fill(tile.statusColor)
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(source.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(titleMetadata)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Button(action: onToggleFocus) {
                    Image(systemName: isFocused ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                }
                .buttonStyle(.borderless)
                .help(isFocused ? "Exit Focus" : "Focus")

                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help("Remove")
            }

            ZStack {
                Rectangle()
                    .fill(Color.black.opacity(0.92))

                if let preview = tile.previewImage {
                    Image(nsImage: preview)
                        .resizable()
                        .scaledToFit()
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: source.kind == .display ? "display" : "macwindow")
                            .font(.system(size: 24, weight: .medium))
                        Text(tilePlaceholderText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(16 / 10, contentMode: .fit)
        }
        .overlay(alignment: .topLeading) {
            if let errorMessage = tile.errorMessage {
                Text(errorMessage)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.6))
            }
        }
    }

    private var titleMetadata: String {
        switch tile.freshness {
        case .live:
            return source.kind.displayName
        case .stale:
            return "\(source.kind.displayName) · Waiting"
        case .offline:
            return "\(source.kind.displayName) · Offline"
        }
    }

    private var tilePlaceholderText: String {
        if tile.isOffline {
            return "Source unavailable"
        }
        return "Preview pending"
    }
}
