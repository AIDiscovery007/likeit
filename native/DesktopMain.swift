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
    private var session: DesktopSession?
    private let audio = DesktopAudio()
    private var snapshot: DesktopSnapshot?
    private var terminating = false
    private var allowAudio = false {
        didSet { model.motionEnabled = allowAudio }
    }
    private var mode = "off"
    private var lyricsSource = "netease"
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
        let themes = NSMenuItem(title: "音响主题", action: nil, keyEquivalent: "")
        let themeMenu = NSMenu(title: "音响主题")
        for (index, theme) in DesktopTheme.allCases.enumerated() {
            let choice = themeMenu.addItem(withTitle: theme.title, action: #selector(selectTheme(_:)), keyEquivalent: String(index + 1))
            choice.target = self
            choice.representedObject = theme.rawValue
            choice.keyEquivalentModifierMask = [.command]
        }
        themes.submenu = themeMenu
        menu.addItem(themes)
        NSApp.mainMenu = menu
        motionObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in self?.updateMotion() }
        showWindow()
        session = DesktopSession(model: model, lyricsSource: lyricsSource)
        audio.output = { [weak self] features, message in
            guard let self, !self.terminating, self.allowAudio else { return }
            if self.model.low != features.low { self.model.low = features.low }
            if self.model.mid != features.mid { self.model.mid = features.mid }
            if self.model.high != features.high { self.model.high = features.high }
            if self.model.audioStatus != message { self.model.audioStatus = message }
            if self.model.canRetryAudio != self.audio.canRetry { self.model.canRetryAudio = self.audio.canRetry }
        }
        session?.sourceChanged = { [weak self] value in
            self?.snapshot = value
            self?.updateMotion()
        }
        session?.start()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.last, url.scheme == "likeit-desktop", url.host == "open", let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        if let theme = components.queryItems?.first(where: { $0.name == "theme" }) {
            model.selectTheme(theme.value ?? "")
        }
        if let selection = components.queryItems?.first(where: { $0.name == "lyricsSource" }) {
            let source = selection.value == "community" ? "community" : "netease"
            if source != lyricsSource {
                lyricsSource = source
                session?.setLyricsSource(source)
            }
        }
        if let selection = components.queryItems?.first(where: { $0.name == "mode" }) {
            mode = selection.value ?? "system"
        }
        if let bundle = components.queryItems?.first(where: { $0.name == "returnBundle" })?.value, bundle != "com.likeit.desktop",
           let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first, !app.isTerminated {
            previousApp = app
        }
        updateMotion()
        if window != nil { activate() }
    }

    @objc private func selectTheme(_ sender: NSMenuItem) {
        model.selectTheme(sender.representedObject as? String)
    }

    private func showWindow() {
        let pointer = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(pointer, $0.frame, false) }) ?? NSScreen.main else { NSApp.terminate(nil); return }
        let window = DesktopWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.backgroundColor = .black
        window.delegate = self
        window.contentView = NSHostingView(rootView: DesktopView(model: model, retryAudio: { [weak self] in self?.retryAudio() }, exit: { NSApp.terminate(nil) }))
        self.window = window
        updateMotion()
        activate()
    }

    private func retryAudio() {
        updateMotion()
        guard !terminating, allowAudio else { return }
        audio.retry()
        model.canRetryAudio = audio.canRetry
    }

    private func updateMotion() {
        guard !terminating else { return }
        let enabled = desktopMotionEnabled(mode: mode, reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        let visible = window?.occlusionState.contains(.visible) == true
        session?.setVisible(visible)
        allowAudio = enabled && visible && snapshot?.playing == true && snapshot.map { ProcessInfo.processInfo.systemUptime - $0.sampledAt <= 5 } == true
        let reason = !enabled ? "桌面动效已关闭 · 不采集音频" : !visible ? "桌面不可见 · 采集已停止" : "等待网易云播放 · 保持静态"
        if !allowAudio {
            model.canRetryAudio = false
            model.low = 0; model.mid = 0; model.high = 0
            model.audioStatus = reason
        }
        audio.update(pid: allowAudio ? snapshot?.pid : nil, reason: reason)
    }

    func applicationDidBecomeActive(_ notification: Notification) { updateMotion() }
    func applicationDidResignActive(_ notification: Notification) { updateMotion() }
    func windowDidChangeOcclusionState(_ notification: Notification) { updateMotion() }

    private func activate() {
        NSApp.presentationOptions = [.autoHideDock, .autoHideMenuBar]
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { activate(); return false }
    func windowShouldClose(_ sender: NSWindow) -> Bool { NSApp.terminate(nil); return false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminating else { return .terminateLater }
        terminating = true
        let restore = NSApp.isActive
        allowAudio = false
        session?.stop(); session = nil
        if let motionObserver { NSWorkspace.shared.notificationCenter.removeObserver(motionObserver) }
        window?.orderOut(nil)
        window?.close()
        window = nil
        if restore, let previousApp, !previousApp.isTerminated { previousApp.activate(options: []) }
        // Hide immediately, allow orderly HAL teardown, and never let a pending system prompt trap exit.
        let deadline = DispatchWorkItem { sender.reply(toApplicationShouldTerminate: true) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: deadline)
        audio.stop { deadline.cancel(); sender.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        if lock >= 0 { Darwin.close(lock); lock = -1 }
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
