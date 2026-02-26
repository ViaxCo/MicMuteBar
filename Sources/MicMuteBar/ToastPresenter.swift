import AppKit
import SwiftUI

@MainActor
final class ToastPresenter {
    static let shared = ToastPresenter()

    private var panel: NSPanel?
    private var dismissTask: DispatchWorkItem?

    private init() {}

    func showMuteChanged(isMuted: Bool, deviceName: String) {
        show(
            title: isMuted ? "Microphone Muted" : "Microphone Live",
            subtitle: deviceName,
            symbolName: isMuted ? "mic.slash.fill" : "mic.fill",
            tint: isMuted ? .systemRed : .systemGreen
        )
    }

    func showError(_ message: String) {
        show(
            title: "Mic Toggle Failed",
            subtitle: message,
            symbolName: "exclamationmark.triangle.fill",
            tint: .systemOrange
        )
    }

    private func show(title: String, subtitle: String, symbolName: String, tint: NSColor) {
        dismissTask?.cancel()

        let rootView = ToastBubbleView(
            title: title,
            subtitle: subtitle,
            symbolName: symbolName,
            tint: Color(nsColor: tint)
        )
        let host = NSHostingController(rootView: rootView)

        let panel = panel ?? makePanel()
        panel.contentViewController = host
        panel.layoutIfNeeded()

        let targetSize = host.view.fittingSize
        position(panel: panel, contentSize: targetSize)

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }

        let dismissTask = DispatchWorkItem { [weak panel] in
            guard let panel else { return }
            Task { @MainActor in
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.15
                    panel.animator().alphaValue = 0
                }, completionHandler: {
                    Task { @MainActor in
                        panel.orderOut(nil)
                    }
                })
            }
        }
        self.dismissTask = dismissTask
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: dismissTask)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 72),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        self.panel = panel
        return panel
    }

    private func position(panel: NSPanel, contentSize: NSSize) {
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }

        let frame = NSRect(origin: .zero, size: NSSize(width: max(260, contentSize.width), height: max(64, contentSize.height)))
        let visible = screen.visibleFrame
        let origin = NSPoint(
            x: visible.midX - frame.width / 2,
            y: visible.maxY - frame.height - 28
        )

        panel.setFrame(NSRect(origin: origin, size: frame.size), display: true)
    }
}

private struct ToastBubbleView: View {
    let title: String
    let subtitle: String
    let symbolName: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbolName)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        )
        .padding(6)
    }
}
