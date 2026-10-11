import UserNotifications
import XCTest
@testable import PortDrop

final class PortMonitorTests: XCTestCase {
    func p(_ pid: pid_t, _ port: UInt16) -> ListeningPort {
        ListeningPort(pid: pid, processName: "x", user: "u", port: port, bindAddress: "*", ipVersions: [.v4])
    }
    func testNewIDs() {
        let old = [p(1, 80), p(2, 443)]
        let new = [p(2, 443), p(3, 3000)]
        XCTAssertEqual(PortMonitor.newIDs(old: old, new: new), ["3:3000"])
    }
    func testNoNewIDsWhenUnchanged() {
        let a = [p(1, 80)]
        XCTAssertEqual(PortMonitor.newIDs(old: a, new: a), [])
    }
    @MainActor func testFilter() {
        let m = PortMonitor(autoStart: false)
        m.ports = [p(1, 80), p(2, 5432)]
        m.services = ["1:80": ServiceInfo(kind: .http, url: nil), "2:5432": ServiceInfo(kind: .postgres, url: nil)]
        m.searchText = "postg"
        XCTAssertEqual(m.filteredPorts.map(\.port), [5432])
        m.searchText = "80"
        XCTAssertEqual(m.filteredPorts.map(\.port), [80])
        m.searchText = ""
        XCTAssertEqual(m.filteredPorts.count, 2)
    }

    @MainActor func testDockerBindingRequiresHostProcess() {
        let m = PortMonitor(autoStart: false)
        let c = DockerContainer(id: "a", name: "p-postgres-1", project: "p", service: "postgres", ports: [.init(hostPort: 5432, containerPort: 5432)])
        m.dockerContainers = [c]
        m.docker = DockerInspector.bindings(from: [c])
        let native = ListeningPort(pid: 1, processName: "postgres", user: "u", port: 5432, bindAddress: "*", ipVersions: [.v4])
        let backend = ListeningPort(pid: 2, processName: "com.docker.backend", user: "u", port: 5432, bindAddress: "*", ipVersions: [.v6])
        XCTAssertNil(m.dockerBinding(for: native))
        XCTAssertEqual(m.dockerBinding(for: backend)?.displayName, "postgres")
    }

    @MainActor func testSearchMatchesDockerNames() {
        let m = PortMonitor(autoStart: false)
        let c = DockerContainer(id: "a", name: "can-railway-postgres-1", project: "can-railway", service: "postgres", ports: [.init(hostPort: 5433, containerPort: 5432)])
        m.dockerContainers = [c]
        m.docker = DockerInspector.bindings(from: [c])
        m.ports = [ListeningPort(pid: 2, processName: "com.docker.backend", user: "u", port: 5433, bindAddress: "*", ipVersions: [.v6]), p(1, 80)]
        m.searchText = "railway"
        XCTAssertEqual(m.filteredPorts.map(\.port), [5433])
        m.searchText = "postgres"
        XCTAssertEqual(m.filteredPorts.map(\.port), [5433])
    }

    @MainActor func testProjectContainerCount() {
        let m = PortMonitor(autoStart: false)
        m.dockerContainers = [
            DockerContainer(id: "a", name: "x-db-1", project: "x", service: "db", ports: []),
            DockerContainer(id: "b", name: "x-web-1", project: "x", service: "web", ports: []),
            DockerContainer(id: "c", name: "loose", project: nil, service: nil, ports: []),
        ]
        XCTAssertEqual(m.projectContainerCount("x"), 2)
        XCTAssertEqual(m.projectContainerCount("nope"), 0)
    }

    // MARK: - Refresh behaviour (scanner and probe injected)

    final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var n = 0
        @discardableResult func bump() -> Int { lock.lock(); defer { lock.unlock() }; n += 1; return n }
        var value: Int { lock.lock(); defer { lock.unlock() }; return n }
    }

    @MainActor func monitor(ports: [ListeningPort], system: [ListeningPort] = []) -> PortMonitor {
        let suite = "PortDropTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let m = PortMonitor(autoStart: false, defaults: defaults)
        m.scanPorts = { ports }
        m.scanSystemPorts = { system }
        m.probe = { _, _ in false }
        return m
    }

    @MainActor func testSystemPortsStayHiddenUntilToggled() async {
        let root = ListeningPort(pid: 7, processName: "sshd", user: "root", port: 22, bindAddress: "*", ipVersions: [.v4])
        let m = monitor(ports: [p(1, 8080)], system: [p(1, 8080), root])
        await m.refresh()
        XCTAssertEqual(m.ports.map(\.port), [8080])

        m.showSystemPorts = true
        await m.refresh()
        XCTAssertEqual(m.ports.map(\.id), ["7:22", "1:8080"], "merged by pid:port, sorted by port")
        XCTAssertEqual(m.ports.first?.user, "root")
    }

    @MainActor func testSlowStarterIsReprobedUntilItAnswers() async {
        let m = monitor(ports: [p(1, 9999)])
        let calls = Counter()
        m.probe = { _, _ in calls.bump() >= 3 }
        await m.refresh()
        await m.refresh()
        XCTAssertEqual(m.services["1:9999"]?.kind, .tcp)
        await m.refresh()
        XCTAssertEqual(m.services["1:9999"]?.kind, .http)
        await m.refresh()
        XCTAssertEqual(calls.value, 3, "a hit is cached")
    }

    @MainActor func testSilentPortStopsBeingProbed() async {
        let m = monitor(ports: [p(1, 9999)])
        let calls = Counter()
        m.probe = { _, _ in calls.bump(); return false }
        for _ in 0..<(PortMonitor.maxProbeAttempts + 5) { await m.refresh() }
        XCTAssertEqual(calls.value, PortMonitor.maxProbeAttempts)
    }

    @MainActor func testOpeningThePanelSwitchesToTheFastIntervalImmediately() async throws {
        let m = monitor(ports: [])
        let scans = Counter()
        m.scanPorts = { scans.bump(); return [] }
        m.hiddenInterval = .seconds(30)
        m.visibleInterval = .milliseconds(50)
        m.start()
        defer { m.stop() }
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(scans.value, 1, "one scan, then the long background sleep")

        m.isPanelVisible = true
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertGreaterThanOrEqual(scans.value, 4, "the background sleep must not delay the fast cadence")
    }

    func testNotificationBodyNamesTheDockerService() {
        let c = DockerContainer(id: "a", name: "shop-db-1", project: "shop", service: "db", ports: [.init(hostPort: 5433, containerPort: 5432)])
        let backend = ListeningPort(pid: 2, processName: "com.docker.backend", user: "u", port: 5433, bindAddress: "*", ipVersions: [.v6])
        XCTAssertEqual(PortMonitor.notificationBody(for: backend, docker: DockerBinding(container: c, containerPort: 5432)),
                       "db (Docker, shop) started listening")
        XCTAssertEqual(PortMonitor.notificationBody(for: p(1, 80), docker: nil), "x (PID 1) started listening")
    }

    func named(_ pid: pid_t, _ port: UInt16, _ name: String) -> ListeningPort {
        ListeningPort(pid: pid, processName: name, user: "u", port: port, bindAddress: "*", ipVersions: [.v4])
    }

    @MainActor func testHiddenProcessLeavesTheListAtOnceAndStaysOut() async {
        let m = monitor(ports: [named(1, 5000, "ControlCenter"), named(1, 7000, "ControlCenter"), named(2, 3000, "node")])
        await m.refresh()
        XCTAssertEqual(m.ports.count, 3)

        m.hide("ControlCenter")
        XCTAssertEqual(m.ports.map(\.port), [3000], "no refresh needed")
        await m.refresh()
        XCTAssertEqual(m.ports.map(\.port), [3000])
        XCTAssertEqual(m.hiddenProcessNames, ["ControlCenter"])

        m.unhide("ControlCenter")
        await m.refresh()
        XCTAssertEqual(m.ports.count, 3)
    }

    @MainActor func testHiddenProcessesPersist() async {
        let suite = "PortDropTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        PortMonitor(autoStart: false, defaults: defaults).hide("rapportd")
        let m = PortMonitor(autoStart: false, defaults: defaults)
        XCTAssertEqual(m.hiddenProcessNames, ["rapportd"])
        m.unhideAll()
        XCTAssertTrue(PortMonitor(autoStart: false, defaults: defaults).hiddenProcessNames.isEmpty)
    }

    // MARK: - Notification actions

    final class Box<T>: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: T
        init(_ value: T) { stored = value }
        var value: T {
            get { lock.lock(); defer { lock.unlock() }; return stored }
            set { lock.lock(); stored = newValue; lock.unlock() }
        }
    }

    /// A monitor with notifications on, whose scan results and delivered requests the test controls.
    @MainActor func notifyingMonitor() -> (PortMonitor, Box<[ListeningPort]>, Box<[UNNotificationRequest]>) {
        let suite = "PortDropTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "notifyOnNewPorts")
        let m = PortMonitor(autoStart: false, defaults: defaults)
        let scan = Box<[ListeningPort]>([])
        let sent = Box<[UNNotificationRequest]>([])
        m.scanPorts = { scan.value }
        m.probe = { _, _ in false }
        m.canOpenURL = { _ in true }
        m.deliver = { sent.value.append($0) }
        return (m, scan, sent)
    }

    @MainActor func testNewPortNotificationOffersOpenAndKill() async {
        let (m, scan, sent) = notifyingMonitor()
        await m.refresh()
        scan.value = [p(1, 8080)]
        await m.refresh()
        XCTAssertEqual(sent.value.count, 1)
        let content = sent.value[0].content
        XCTAssertEqual(content.title, "New service on port 8080")
        XCTAssertEqual(content.categoryIdentifier, PortNotification.openAndKill)
        XCTAssertEqual(content.userInfo["portID"] as? String, "1:8080")
    }

    @MainActor func testNotificationWithoutAURLOffersOnlyKill() async {
        let (m, scan, sent) = notifyingMonitor()
        await m.refresh()
        scan.value = [p(1, 40000)]
        await m.refresh()
        XCTAssertEqual(sent.value.first?.content.categoryIdentifier, PortNotification.killOnly)
    }

    func testDockerNotificationsNeverOfferKill() {
        XCTAssertEqual(PortNotification.category(canOpen: true, isDocker: true), PortNotification.openOnly)
        XCTAssertNil(PortNotification.category(canOpen: false, isDocker: true))
        XCTAssertEqual(PortNotification.category(canOpen: true, isDocker: false), PortNotification.openAndKill)
        XCTAssertEqual(PortNotification.category(canOpen: false, isDocker: false), PortNotification.killOnly)
    }

    @MainActor func testOpenActionOpensTheServiceURL() async {
        let (m, scan, _) = notifyingMonitor()
        let opened = Box<[URL]>([])
        m.openURL = { opened.value.append($0) }
        scan.value = [p(1, 8080)]
        await m.refresh()
        await m.handleNotificationAction(PortNotification.openAction, portID: "1:8080")
        XCTAssertEqual(opened.value, [URL(string: "http://localhost:8080")!])
    }

    @MainActor func testKillActionKillsOnlyAProcessStillInTheList() async throws {
        let (m, scan, _) = notifyingMonitor()
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/sleep")
        proc.arguments = ["60"]
        try proc.run()
        addTeardownBlock { if proc.isRunning { Darwin.kill(proc.processIdentifier, SIGKILL) } }
        let id = "\(proc.processIdentifier):9999"

        await m.handleNotificationAction(PortNotification.killAction, portID: id)
        XCTAssertTrue(proc.isRunning, "not in the list (stale notification, or the pid was reused): leave it alone")

        scan.value = [p(proc.processIdentifier, 9999)]
        await m.refresh()
        await m.handleNotificationAction(PortNotification.killAction, portID: id)
        proc.waitUntilExit()
        XCTAssertEqual(proc.terminationReason, .uncaughtSignal)
    }

    @MainActor func testKillActionThatFailsSaysSo() async throws {
        let (m, scan, sent) = notifyingMonitor()
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/sh")
        proc.arguments = ["-c", "trap '' TERM; echo ready; while :; do sleep 1; done"]
        let out = Pipe()
        proc.standardOutput = out
        try proc.run()
        addTeardownBlock { if proc.isRunning { Darwin.kill(proc.processIdentifier, SIGKILL) } }
        _ = out.fileHandleForReading.availableData
        scan.value = [p(proc.processIdentifier, 9999)]
        await m.refresh()

        await m.handleNotificationAction(PortNotification.killAction, portID: "\(proc.processIdentifier):9999")
        XCTAssertEqual(sent.value.last?.content.title, "Could not kill x on port 9999")
    }
}
