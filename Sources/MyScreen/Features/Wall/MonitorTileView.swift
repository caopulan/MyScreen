import SwiftUI

struct MonitorTileView: View {
    let source: MonitorSource
    let tile: TileState
    let isFocused: Bool
    let isBeingDragged: Bool
    let isDropTarget: Bool
    let onActivate: () -> Void
    let onToggleFocus: () -> Void
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color.black)

            if let preview = tile.previewImage {
                Image(nsImage: preview)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: source.kind == .display ? "display" : "macwindow")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                    Text(tilePlaceholderText)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.52))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            LinearGradient(
                colors: [Color.black.opacity(0.72), Color.black.opacity(0.32), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 86)

            header
        }
        .aspectRatio(16 / 10, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(borderColor, lineWidth: borderWidth)
        )
        .overlay {
            if isDropTarget && !isBeingDragged {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.04))
            }
        }
        .shadow(color: Color.black.opacity(isBeingDragged ? 0.42 : 0), radius: isBeingDragged ? 18 : 0, y: isBeingDragged ? 12 : 0)
        .scaleEffect(isBeingDragged ? 0.985 : 1)
        .opacity(isBeingDragged ? 0.76 : 1)
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture(perform: onActivate)
        .overlay(alignment: .topLeading) {
            if let errorMessage = tile.errorMessage {
                Text(errorMessage)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.6))
                    .padding(10)
            }
        }
    }

    private var borderColor: Color {
        if isDropTarget {
            return Color.white.opacity(0.26)
        }
        if isFocused {
            return Color.accentColor
        }
        return Color.white.opacity(0.08)
    }

    private var borderWidth: CGFloat {
        if isFocused {
            return 2
        }
        if isDropTarget {
            return 1.5
        }
        return 1
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            SourceIconView(source: source, size: 18, padding: 5, backgroundOpacity: 0.18)

            VStack(alignment: .leading, spacing: 2) {
                Text(source.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.94))
                    .lineLimit(1)
                Text(titleMetadata)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }

            Spacer(minLength: 0)

            Circle()
                .fill(tile.statusColor)
                .frame(width: 8, height: 8)

            Button(action: onToggleFocus) {
                Image(systemName: isFocused ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.white.opacity(0.82))
            .help(isFocused ? "Exit Focus" : "Focus")

            Button(role: .destructive, action: onRemove) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.white.opacity(0.82))
            .help("Remove")
        }
        .padding(10)
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
