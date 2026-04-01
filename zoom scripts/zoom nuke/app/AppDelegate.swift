import AppKit
import SwiftUI

// MARK: - Window Style

/// Applies the custom borderless window appearance.
/// `shouldCenter` is true only on first launch; subsequent calls
/// (e.g. from didBecomeMain) pass false so the user's position is preserved.
func applyWindowStyle(_ window: NSWindow, shouldCenter: Bool) {
    let fixedSize = NSSize(width: Layout.windowWidth, height: Layout.windowHeight)
    window.setContentSize(fixedSize)
    window.minSize = fixedSize
    window.maxSize = fixedSize
    window.styleMask = [.borderless, .closable, .miniaturizable, .fullSizeContentView]
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    if #available(macOS 11.0, *) {
        window.titlebarSeparatorStyle = .none
    }
    window.isMovableByWindowBackground = true
    window.backgroundColor = .clear
    window.isOpaque = false
    window.hasShadow = false
    window.collectionBehavior.insert(.fullScreenNone)
    window.isReleasedWhenClosed = false

    window.contentView?.wantsLayer = true
    window.contentView?.layer?.cornerRadius = 24
    if #available(macOS 11.0, *) {
        window.contentView?.layer?.cornerCurve = .continuous
    }
    window.contentView?.layer?.masksToBounds = true

    if shouldCenter { window.center() }
}

// MARK: - Title Bar Drag View

/// Transparent NSView that allows the window to be dragged by the title bar area.
struct TitleBarDragView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
    }
}

// MARK: - Window Accessor

/// Injects the NSWindow reference into SwiftUI via an invisible NSView.
struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { [weak view] in
            guard let window = view?.window else { return }
            onResolve(window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Only resolve in makeNSView to avoid redundant style applications on re-render.
    }
}

// MARK: - App Delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindowObserver: NSObjectProtocol?
    /// Guards applyWindowStyle(shouldCenter:true) so it fires exactly once at launch,
    /// preventing window snap-back if the user repositions the window before a
    /// subsequent didBecomeMain notification fires.
    private var windowStyleApplied = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.async {
            if !self.windowStyleApplied {
                self.windowStyleApplied = true
                NSApp.windows.forEach { applyWindowStyle($0, shouldCenter: true) }
            }
            self.mainWindowObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeMainNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard self != nil, let window = notification.object as? NSWindow else { return }
                applyWindowStyle(window, shouldCenter: false)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let obs = mainWindowObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }
}
