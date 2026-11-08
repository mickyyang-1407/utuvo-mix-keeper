import AppKit
import MixKeeperCore

enum Jumper {
    static func jump(to target: JumpTarget) {
        switch target {
        case .desktop(let url):
            NSWorkspace.shared.open(url)
        case .terminalTab(let tty):
            let script = """
            tell application "Terminal"
              activate
              repeat with w in windows
                repeat with t in tabs of w
                  if tty of t is "\(tty)" then
                    set selected of t to true
                    set index of w to 1
                    return
                  end if
                end repeat
              end repeat
            end tell
            """
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            try? process.run()
        case .bringClaudeForward:
            NSRunningApplication.runningApplications(withBundleIdentifier: "com.anthropic.claudefordesktop").first?.activate()
        }
    }
}
