import AppKit
import SwiftUI
import MixKeeperCore

struct CardInfo: Identifiable {
    var id: String
    var kind: CardKind
    var project: String
    var branch: String
    var source: String
    var title: String
    var since: Date
}

private struct CardView: View {
    let card: CardInfo
    let now: Date
    let onOpen: () -> Void
    let onClose: () -> Void

    private var waited: String { L.waited(seconds: now.timeIntervalSince(card.since)) }

    private var accent: Color {
        card.kind == .done ? Color(red: 0.08, green: 0.56, blue: 0.51) : Color(red: 0.87, green: 0.33, blue: 0.25)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(card.kind.title).font(.system(size: 11, weight: .semibold)).foregroundStyle(accent)
                    Text(card.branch.isEmpty ? card.project : "\(card.project)｜\(card.branch)")
                        .font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    if !card.title.isEmpty {
                        Text(card.title).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Text("\(card.source) · \(waited)").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .frame(width: 300, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button(action: onClose) {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary).padding(8)
            }
            .buttonStyle(.plain)
        }
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .windowBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.black.opacity(0.12)))
    }
}

private struct CardStack: View {
    let cards: [CardInfo]
    let onOpen: (CardInfo) -> Void
    let onClose: (CardInfo) -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(spacing: 8) {
                ForEach(cards) { card in
                    CardView(card: card, now: context.date, onOpen: { onOpen(card) }, onClose: { onClose(card) })
                }
            }
            .padding(8)
            .fixedSize()
        }
    }
}

private final class ClickThroughHost<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// 發文、文件用：用和螢幕上同一套卡片畫面輸出 PNG（2x）。
func snapshotCards(_ cards: [CardInfo], to url: URL) throws {
    let host = NSHostingView(rootView: CardStack(cards: cards, onOpen: { _ in }, onClose: { _ in }))
    host.appearance = NSAppearance(named: .aqua)
    host.frame = NSRect(origin: .zero, size: host.fittingSize)
    host.layoutSubtreeIfNeeded()
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(host.frame.width * 2), pixelsHigh: Int(host.frame.height * 2),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = host.frame.size
    host.cacheDisplay(in: host.bounds, to: rep)
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}

final class CardPanel {
    private let panel = KeeperPanel(size: NSSize(width: 316, height: 100))
    var onOpen: (CardInfo) -> Void = { _ in }
    var onClose: (CardInfo) -> Void = { _ in }

    func show(_ cards: [CardInfo], beside petFrame: NSRect) {
        guard !cards.isEmpty else { panel.orderOut(nil); return }
        let host = ClickThroughHost(rootView: CardStack(cards: cards, onOpen: onOpen, onClose: onClose))
        panel.contentView = host
        let size = host.fittingSize
        let screen = NSScreen.screens.first { $0.frame.intersects(petFrame) }?.visibleFrame ?? petFrame
        var x = petFrame.maxX
        if x + size.width > screen.maxX { x = petFrame.minX - size.width }
        let y = min(max(petFrame.minY, screen.minY), screen.maxY - size.height)
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        panel.orderFrontRegardless()
    }
}
