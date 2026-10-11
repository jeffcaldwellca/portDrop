import Foundation
import Observation
import UserNotifications

@MainActor
@Observable
final class PortMonitor {
    var ports: [ListeningPort] = []
    var services: [String: ServiceInfo] = [:]
    /// Running containers from the last `docker ps`; empty when no Docker host process is listening.
    var dockerContainers: [DockerContainer] = []
    /// Published host port → container behind it.
    var docker: [UInt16: DockerBinding] = [:]
    var lastError: String?
    var isScanning = false
    var searchText = ""
    var isPanelVisible = false {
        didSet {
            guard isPanelVisible && !oldValue else { return }
            // With the loop running, cut its background sleep short so the fast cadence starts now.
            if loopTask != nil { sleepTask?.cancel() } else { Task { await refresh() } }
        }
    }
    var notifyOnNewPorts: Bool {
        get { defaults.bool(forKey: Self.notifyKey) }
        set {
            defaults.set(newValue, forKey: Self.notifyKey)
            if newValue { requestNotificationAuthorization() }
        }
    }
    /// Also list listeners owned by root and other users, which lsof cannot see without root.
    var showSystemPorts: Bool {
        didSet {
            guard showSystemPorts != oldValue else { return }
            defaults.set(showSystemPorts, forKey: Self.systemKey)
            hasScannedOnce = false   // the rows this adds are not new services; don't notify for them
        }
    }

    let resolver = ProcessInfoResolver()

    @ObservationIgnored var scanPorts: @Sendable () async throws -> [ListeningPort] = { try await PortScanner.scan() }
    @ObservationIgnored var scanSystemPorts: @Sendable () async -> [ListeningPort] = { await SystemPortScanner.scan() }
    @ObservationIgnored var probe: @Sendable (_ host: String, _ port: UInt16) async -> Bool = { await HTTPProbe.respondsToHTTP(host: $0, port: $1) }
    @ObservationIgnored var visibleInterval: Duration = .seconds(2)
    @ObservationIgnored var hiddenInterval: Duration = .seconds(10)

    /// A listener that is still starting up may not answer the first probe, so a miss is retried on later
    /// scans; after this many the port is taken to be something other than HTTP and left alone.
    static let maxProbeAttempts = 10

    private static let notifyKey = "notifyOnNewPorts"
    private static let systemKey = "showSystemPorts"
    private let defaults: UserDefaults
    private var hasScannedOnce = false
    private var probeHits: Set<String> = []
    private var probeMisses: [String: Int] = [:]
    private var loopTask: Task<Void, Never>?
    private var sleepTask: Task<Void, Never>?

    init(autoStart: Bool = true, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        showSystemPorts = defaults.bool(forKey: Self.systemKey)
        if autoStart { start() }
    }

    var filteredPorts: [ListeningPort] {
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return ports }
        return ports.filter { p in
            String(p.port).contains(q)
                || p.processName.lowercased().contains(q)
                || p.user.lowercased().contains(q)
                || (services[p.id]?.kind.label.lowercased().contains(q) ?? false)
                || resolver.presentation(for: p, kind: services[p.id]?.kind ?? .tcp).displayName.lowercased().contains(q)
                || (dockerBinding(for: p).map { b in
                        b.container.name.lowercased().contains(q)
                        || (b.container.project?.lowercased().contains(q) ?? false)
                        || (b.container.service?.lowercased().contains(q) ?? false)
                    } ?? false)
        }
    }

    func service(for port: ListeningPort) -> ServiceInfo {
        services[port.id] ?? ServiceClassifier.classify(port, docker: dockerBinding(for: port))
    }

    /// A row is Docker-backed only when its process is the Docker host *and* a container publishes that port,
    /// so a native Postgres on 5432 is never mislabelled by a container on another runtime.
    func dockerBinding(for port: ListeningPort) -> DockerBinding? {
        guard DockerInspector.isHostProcess(port.processName) else { return nil }
        return docker[port.port]
    }

    func projectContainerCount(_ project: String) -> Int {
        dockerContainers.filter { $0.project == project }.count
    }

    func perform(_ action: DockerAction) async throws {
        try await DockerController.run(action)
        try? await Task.sleep(for: .milliseconds(250))
        await refresh()
    }

    func stop() {
        loopTask?.cancel(); loopTask = nil
        sleepTask?.cancel(); sleepTask = nil
    }

    func start() {
        guard loopTask == nil else { return }
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                let interval = self.isPanelVisible ? self.visibleInterval : self.hiddenInterval
                // Its own task, so opening the panel can end the sleep without cancelling the loop.
                let sleep = Task { _ = try? await Task.sleep(for: interval) }
                self.sleepTask = sleep
                await sleep.value
            }
        }
    }

    func refresh() async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }
        do {
            // `docker ps` runs alongside lsof when the last scan saw a Docker host process, so a slow daemon
            // does not hold the list back; the first appearance of Docker costs one extra sequential call.
            let expectDocker = ports.contains { DockerInspector.isHostProcess($0.processName) }
            async let early: [DockerContainer] = expectDocker ? DockerInspector.scan() : []
            async let system: [ListeningPort] = showSystemPorts ? scanSystemPorts() : []
            let own = try await scanPorts()
            let scanned = Self.merge(own: own, system: await system)
            var containers = await early
            if !expectDocker, scanned.contains(where: { DockerInspector.isHostProcess($0.processName) }) {
                containers = await DockerInspector.scan()
            }
            let bindings = DockerInspector.bindings(from: containers)
            let classified = await classify(scanned, bindings: bindings)
            let fresh = Self.newIDs(old: ports, new: scanned)
            if ports != scanned { ports = scanned }          // avoid redraws (and label re-renders) when nothing changed
            if services != classified { services = classified }
            if dockerContainers != containers {
                dockerContainers = containers
                docker = bindings
            }
            lastError = nil
            resolver.evict(pidsNotIn: Set(scanned.map(\.pid)))
            if hasScannedOnce && notifyOnNewPorts {
                for p in scanned where fresh.contains(p.id) { notify(p, docker: dockerBinding(for: p)) }
            }
            hasScannedOnce = true
        } catch {
            lastError = error.localizedDescription
        }
    }

    func kill(_ port: ListeningPort, force: Bool) async throws {
        try await ProcessKiller.kill(pid: port.pid, force: force)
        let exited = await ProcessKiller.waitForExit(pid: port.pid, timeout: force ? .seconds(1) : .seconds(3))
        await refresh()
        if !exited { throw KillError.stillRunning }
    }

    /// lsof's rows win; netstat only contributes the listeners lsof could not see.
    nonisolated static func merge(own: [ListeningPort], system: [ListeningPort]) -> [ListeningPort] {
        guard !system.isEmpty else { return own }
        let seen = Set(own.map(\.id))
        return (own + system.filter { !seen.contains($0.id) }).sorted { ($0.port, $0.pid) < ($1.port, $1.pid) }
    }

    nonisolated static func newIDs(old: [ListeningPort], new: [ListeningPort]) -> Set<String> {
        Set(new.map(\.id)).subtracting(old.map(\.id))
    }

    private func classify(_ scanned: [ListeningPort], bindings: [UInt16: DockerBinding]) async -> [String: ServiceInfo] {
        var out: [String: ServiceInfo] = [:]
        var toProbe: [ListeningPort] = []
        for p in scanned {
            let binding = DockerInspector.isHostProcess(p.processName) ? bindings[p.port] : nil
            let info = ServiceClassifier.classify(p, docker: binding)
            if info.kind == .tcp {
                if probeHits.contains(p.id) {
                    out[p.id] = ServiceClassifier.httpInfo(port: p.port, bindAddress: p.bindAddress)
                } else {
                    out[p.id] = info
                    if probeMisses[p.id, default: 0] < Self.maxProbeAttempts { toProbe.append(p) }
                }
            } else {
                out[p.id] = info
            }
        }
        let probe = probe
        let results = await withTaskGroup(of: (String, Bool).self) { group in
            for p in toProbe {
                group.addTask {
                    (p.id, await probe(ServiceClassifier.host(for: p.bindAddress), p.port))
                }
            }
            var r: [(String, Bool)] = []
            for await item in group { r.append(item) }
            return r
        }
        for (id, ok) in results {
            guard ok else { probeMisses[id, default: 0] += 1; continue }
            probeHits.insert(id)
            probeMisses[id] = nil
            if let p = toProbe.first(where: { $0.id == id }) {
                out[id] = ServiceClassifier.httpInfo(port: p.port, bindAddress: p.bindAddress)
            }
        }
        let live = Set(scanned.map(\.id))
        probeHits.formIntersection(live)
        probeMisses = probeMisses.filter { live.contains($0.key) }
        return out
    }

    private func requestNotificationAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// A Docker row is named for its service: the process behind it is always the same backend.
    nonisolated static func notificationBody(for p: ListeningPort, docker: DockerBinding?) -> String {
        guard let docker else { return "\(p.processName) (PID \(p.pid)) started listening" }
        let context = (["Docker"] + [docker.container.project].compactMap { $0 }).joined(separator: ", ")
        return "\(docker.displayName) (\(context)) started listening"
    }

    private func notify(_ p: ListeningPort, docker: DockerBinding?) {
        let content = UNMutableNotificationContent()
        content.title = "New service on port \(p.port)"
        content.body = Self.notificationBody(for: p, docker: docker)
        let req = UNNotificationRequest(identifier: p.id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}
