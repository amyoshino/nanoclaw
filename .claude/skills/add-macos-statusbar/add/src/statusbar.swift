import AppKit

class StatusBarController: NSObject {
    private var statusItem: NSStatusItem!
    private var isRunning = false
    private var timer: Timer?

    /// Derive the NanoClaw project root from the binary location.
    /// The binary is compiled to {project}/dist/statusbar, so the parent of
    /// the parent directory is the project root.
    private static let projectRoot: String = {
        let binary = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        return binary.deletingLastPathComponent().deletingLastPathComponent().path
    }()

    /// Find the v2 plist by scanning LaunchAgents for com.nanoclaw-v2-*.plist
    private static func findPlistPath() -> String? {
        let dir = "\(NSHomeDirectory())/Library/LaunchAgents"
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return nil }
        guard let name = files.first(where: { $0.hasPrefix("com.nanoclaw-v2-") && $0.hasSuffix(".plist") }) else { return nil }
        return "\(dir)/\(name)"
    }

    /// Extract the launchd label from a plist path (strip directory and .plist extension).
    private static func serviceLabel(from path: String) -> String {
        return URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    }

    override init() {
        super.init()
        setupStatusItem()
        isRunning = checkRunning()
        updateMenu()
        // Poll every 5 seconds to reflect external state changes
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let current = self.checkRunning()
            if current != self.isRunning {
                self.isRunning = current
                self.updateMenu()
            }
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            if let image = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: "NanoClaw") {
                image.isTemplate = true
                button.image = image
            } else {
                button.title = "⚡"
            }
            button.toolTip = "NanoClaw"
        }
    }

    private func checkRunning() -> Bool {
        guard let plistPath = StatusBarController.findPlistPath() else { return false }
        let label = StatusBarController.serviceLabel(from: plistPath)
        let task = Process()
        task.launchPath = "/bin/launchctl"
        task.arguments = ["list", label]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        guard (try? task.run()) != nil else { return false }
        task.waitUntilExit()
        if task.terminationStatus != 0 { return false }
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        // launchctl list <label> returns a plist-style dict; "PID" key is only present when actively running
        guard output.contains("\"PID\"") else { return false }
        return checkContainerRuntimeRunning()
    }

    /// Returns true if the container runtime (Docker) is responsive.
    /// Uses a 5-second timeout so a closed daemon doesn't stall the poll loop.
    private func checkContainerRuntimeRunning() -> Bool {
        let docker = findExecutable("docker") ?? "/usr/local/bin/docker"
        let task = Process()
        task.launchPath = docker
        task.arguments = ["info"]
        task.standardOutput = Pipe()
        task.standardError = Pipe()
        guard (try? task.run()) != nil else { return false }
        let deadline = Date().addingTimeInterval(5.0)
        while task.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        if task.isRunning {
            task.terminate()
            return false
        }
        return task.terminationStatus == 0
    }

    private func findExecutable(_ name: String) -> String? {
        let task = Process()
        task.launchPath = "/usr/bin/which"
        task.arguments = [name]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        guard (try? task.run()) != nil else { return nil }
        task.waitUntilExit()
        guard task.terminationStatus == 0 else { return nil }
        let path = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return path?.isEmpty == false ? path : nil
    }

    private func updateMenu() {
        let menu = NSMenu()

        // Status row with colored dot
        let statusItem = NSMenuItem()
        let dot = "● "
        let dotColor: NSColor = isRunning ? .systemGreen : .systemRed
        let attr = NSMutableAttributedString(string: dot, attributes: [.foregroundColor: dotColor])
        let label = isRunning ? "NanoClaw is running" : "NanoClaw is stopped"
        attr.append(NSAttributedString(string: label, attributes: [.foregroundColor: NSColor.labelColor]))
        statusItem.attributedTitle = attr
        statusItem.isEnabled = false
        menu.addItem(statusItem)

        menu.addItem(NSMenuItem.separator())

        if isRunning {
            let stop = NSMenuItem(title: "Stop", action: #selector(stopService), keyEquivalent: "")
            stop.target = self
            menu.addItem(stop)

            let restart = NSMenuItem(title: "Restart", action: #selector(restartService), keyEquivalent: "r")
            restart.target = self
            menu.addItem(restart)
        } else {
            let start = NSMenuItem(title: "Start", action: #selector(startService), keyEquivalent: "")
            start.target = self
            menu.addItem(start)
        }

        menu.addItem(NSMenuItem.separator())

        let logs = NSMenuItem(title: "View Logs", action: #selector(viewLogs), keyEquivalent: "")
        logs.target = self
        menu.addItem(logs)

        self.statusItem.menu = menu
    }

    @objc private func startService() {
        guard let plistPath = StatusBarController.findPlistPath() else { return }
        run("/bin/launchctl", ["bootstrap", "gui/\(getuid())", plistPath])
        refresh(after: 2)
    }

    @objc private func stopService() {
        guard let plistPath = StatusBarController.findPlistPath() else { return }
        let label = StatusBarController.serviceLabel(from: plistPath)
        run("/bin/launchctl", ["bootout", "gui/\(getuid())/\(label)"])
        refresh(after: 2)
    }

    @objc private func restartService() {
        guard let plistPath = StatusBarController.findPlistPath() else { return }
        let label = StatusBarController.serviceLabel(from: plistPath)
        run("/bin/launchctl", ["kickstart", "-k", "gui/\(getuid())/\(label)"])
        refresh(after: 3)
    }

    @objc private func viewLogs() {
        let logPath = "\(StatusBarController.projectRoot)/logs/nanoclaw.log"
        NSWorkspace.shared.open(URL(fileURLWithPath: logPath))
    }

    private func refresh(after seconds: Double) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self else { return }
            self.isRunning = self.checkRunning()
            self.updateMenu()
        }
    }

    @discardableResult
    private func run(_ path: String, _ args: [String]) -> Int32 {
        let task = Process()
        task.launchPath = path
        task.arguments = args
        task.standardOutput = Pipe()
        task.standardError = Pipe()
        try? task.run()
        task.waitUntilExit()
        return task.terminationStatus
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let controller = StatusBarController()
app.run()
