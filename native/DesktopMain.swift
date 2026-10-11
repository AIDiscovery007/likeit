import AppKit
import SwiftUI
import Darwin

final class DesktopWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { NSApp.terminate(nil) } else { super.keyDown(with: event) }
    }
}

final class DesktopDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow?
    private var previousApp = NSWorkspace.shared.frontmostApplication
    private let model = DesktopModel()
    private var mode = "system"
    private var receivedOpen = false
    private var motionObserver: NSObjectProtocol?
    private var lock: Int32 = -1

    func applicationDidFinishLaunching(_ notification: Notification) {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("com.likeit.desktop")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        lock = Darwin.open(directory.appendingPathComponent("desktop.lock").path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard lock >= 0, flock(lock, LOCK_EX | LOCK_NB) == 0 else {
            NSRunningApplication.runningApplications(withBundleIdentifier: "com.likeit.desktop").first(where: { $0.processIdentifier != getpid() })?.activate(options: [])
            NSApp.terminate(nil)
            return
        }
        let menu = NSMenu()
        let item = NSMenuItem()
        let applicationMenu = NSMenu()
        applicationMenu.addItem(withTitle: "退出 Likeit Desktop", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = applicationMenu
        menu.addItem(item)
        NSApp.mainMenu = menu
        motionObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in self?.updateMotion() }
        showWindow()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.last, url.scheme == "likeit-desktop", url.host == "open", let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        mode = components.queryItems?.first(where: { $0.name == "mode" })?.value ?? "system"
        if !receivedOpen, let bundle = components.queryItems?.first(where: { $0.name == "returnBundle" })?.value, bundle != "com.likeit.desktop" {
            previousApp = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first
        }
        receivedOpen = true
        updateMotion()
        if window != nil { activate() }
    }

    private func showWindow() {
        let pointer = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(pointer, $0.frame, false) }) ?? NSScreen.main else { NSApp.terminate(nil); return }
        let window = DesktopWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.backgroundColor = .black
        window.delegate = self
        window.contentView = NSHostingView(rootView: DesktopView(model: model, exit: { NSApp.terminate(nil) }))
        self.window = window
        updateMotion()
        activate()
    }

    private func updateMotion() {
        let enabled = desktopMotionEnabled(mode: mode, reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        model.audioStatus = enabled ? "实时律动尚未接入" : "桌面动效已关闭 · 不采集音频"
    }

    private func activate() {
        NSApp.presentationOptions = [.autoHideDock, .autoHideMenuBar]
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { activate(); return false }
    func windowShouldClose(_ sender: NSWindow) -> Bool { NSApp.terminate(nil); return false }
    func applicationWillTerminate(_ notification: Notification) {
        let restore = NSApp.isActive
        if let motionObserver { NSWorkspace.shared.notificationCenter.removeObserver(motionObserver) }
        window?.orderOut(nil)
        window?.close()
        window = nil
        if lock >= 0 { Darwin.close(lock); lock = -1 }
        if restore, let previousApp, !previousApp.isTerminated { previousApp.activate(options: []) }
    }
}

@main
struct DesktopMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = DesktopDelegate()
        app.setActivationPolicy(.regular)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
