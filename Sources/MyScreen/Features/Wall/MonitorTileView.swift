import SwiftUI

struct MonitorTileView: View {
    let source: MonitorSource
    let tile: TileState
    let isFocused: Bool
    let onToggleFocus: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(source.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text(source.kind.displayName)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                statusBadge
            }

            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(nsColor: .controlBackgroundColor))

                if let preview = tile.previewImage {
                    Image(nsImage: preview)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: source.kind == .display ? "display" : "macwindow")
                            .font(.system(size: 26, weight: .medium))
                        Text(tilePlaceholderText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(16 / 10, contentMode: .fit)

            HStack {
                Text(lastFrameText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button(isFocused ? "Exit Focus" : "Focus", action: onToggleFocus)
                Button("Remove", role: .destructive, action: onRemove)
            }
            .buttonStyle(.borderless)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(nsColor: .underPageBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(isFocused ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: isFocused ? 2 : 1)
        )
    }

    private var statusBadge: some View {
        Text(tile.statusLabel)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(tile.statusColor.opacity(0.16))
            .foregroundStyle(tile.statusColor)
            .clipShape(Capsule())
    }

    private var lastFrameText: String {
        if let lastFrameAt = tile.lastFrameAt {
            "Last frame \(lastFrameAt.formatted(date: .omitted, time: .standard))"
        } else if source.isAvailable {
            "Waiting for first frame"
        } else {
            "Source offline"
        }
    }

    private var tilePlaceholderText: String {
        if tile.isOffline {
            return "Source unavailable"
        }
        return "Preview pending"
    }
}
