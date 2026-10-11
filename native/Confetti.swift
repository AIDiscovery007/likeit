import AppKit
import Darwin
import SwiftUI

final class ConfettiPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

struct ConfettiBurst: View {
    let size: CGSize
    @State private var trigger = false

    var body: some View {
        ZStack {
            cannon(left: true).position(x: 0, y: size.height * 0.72)
            cannon(left: false).position(x: size.width, y: size.height * 0.72)
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
        .onAppear {
            DispatchQueue.main.async { trigger = true }
        }
    }

    private func cannon(left: Bool) -> some View {
        ConfettiCannon(
            trigger: $trigger, num: 60,
            confettis: [.shape(.square), .shape(.slimRectangle), .shape(.circle)],
            confettiSize: 10, rainHeight: size.height * 0.45,
            fadesOut: true, openingAngle: .degrees(left ? 35 : 105),
            closingAngle: .degrees(left ? 75 : 145),
            radius: min(size.width * 0.65, size.height * 0.9),
            repetitions: 1, hapticFeedback: false
        )
        .frame(width: 0, height: 0)
    }
}

private func acknowledge(_ response: String) {
    let data = Array((response + "\n").utf8)
    guard data.withUnsafeBytes({ Darwin.write(STDOUT_FILENO, $0.baseAddress, $0.count) }) == data.count else {
        _exit(1)
    }
    Darwin.close(STDOUT_FILENO)
}

private func skip() -> Never {
    acknowledge("skipped")
    _exit(0)
}

@main
struct ConfettiMain {
    static func main() {
        let startedAt = DispatchTime.now()
        // This deadline also removes the window if the main run loop stalls.
        DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: startedAt + 2.9) { _exit(0) }
        signal(SIGPIPE, SIG_IGN)
        guard CommandLine.arguments.count == 2, CommandLine.arguments[1].hasPrefix("/") else { skip() }
        let lock = open(CommandLine.arguments[1], O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0o600)
        var info = stat()
        guard lock >= 0, fstat(lock, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              flock(lock, LOCK_EX | LOCK_NB) == 0 else { skip() }
        // Never unlink: this descriptor owns the fixed inode until process exit.
        let workspace = NSWorkspace.shared
        guard !workspace.accessibilityDisplayShouldReduceMotion else { skip() }
        let app = NSApplication.shared
        guard app.setActivationPolicy(.accessory) else { skip() }
        let pointer = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(pointer, $0.frame, false) }),
              screen.frame.width > 0, screen.frame.height > 0 else { skip() }

        let panel = ConfettiPanel(
            contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: ConfettiBurst(size: screen.frame.size))

        let finish = {
            panel.orderOut(nil)
            panel.close()
            _exit(0)
        }
        let observer = workspace.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { _ in
            if workspace.accessibilityDisplayShouldReduceMotion { finish() }
        }
        DispatchQueue.main.asyncAfter(deadline: startedAt + 2.1) {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                panel.animator().alphaValue = 0
            }
        }
        DispatchQueue.main.asyncAfter(deadline: startedAt + 2.4, execute: finish)
        DispatchQueue.main.async {
            guard !workspace.accessibilityDisplayShouldReduceMotion else { skip() }
            panel.contentView?.layoutSubtreeIfNeeded()
            panel.orderFrontRegardless()
            panel.displayIfNeeded()
            guard panel.isVisible else { skip() }
            acknowledge("started")
        }
        withExtendedLifetime(observer) { app.run() }
        finish()
    }
}
