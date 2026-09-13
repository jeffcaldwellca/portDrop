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
        didSet { if isPanelVisible && !oldValue { Task { await refresh() } } }
    }
    var notifyOnNewPorts: Bool {
        get { UserDefaults.standard.bool(forKey: Self.notifyKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.notifyKey)
            if newValue { requestNotificationAuthorization() }
        }
    }

    let resolver = ProcessInfoResolver()

    private static let notifyKey = "notifyOnNewPorts"
    private var hasScannedOnce = false
    private var probeCache: [String: Bool] = [:]
    private var loopTask: Task<Void, Never>?

    init(autoStart: Bool = true) {
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

    func stop() { loopTask?.cancel(); loopTask = nil }

    func start() {
        guard loopTask == nil else { return }
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                let interval: Duration = self.isPanelVisible ? .seconds(2) : .seconds(10)
                try? await Task.sleep(for: interval)
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
            let scanned = try await PortScanner.scan()
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
                for p in scanned where fresh.contains(p.id) { notify(p) }
            }
            hasScannedOnce = true
        } catch {
            lastError = error.localizedDescription
        }
    }

    func kill(_ port: ListeningPort, force: Bool) async throws {
        try await ProcessKiller.kill(pid: port.pid, force: force)
        try? await Task.sleep(for: .milliseconds(250))
        await refresh()
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
                if let cached = probeCache[p.id] {
                    out[p.id] = cached ? ServiceClassifier.httpInfo(port: p.port, bindAddress: p.bindAddress) : info
                } else {
                    out[p.id] = info
                    toProbe.append(p)
                }
            } else {
                out[p.id] = info
            }
        }
        let results = await withTaskGroup(of: (String, Bool).self) { group in
            for p in toProbe {
                group.addTask {
                    (p.id, await HTTPProbe.respondsToHTTP(host: ServiceClassifier.host(for: p.bindAddress), port: p.port))
                }
            }
            var r: [(String, Bool)] = []
            for await item in group { r.append(item) }
            return r
        }
        for (id, ok) in results {
            probeCache[id] = ok
            if ok, let p = toProbe.first(where: { $0.id == id }) {
                out[id] = ServiceClassifier.httpInfo(port: p.port, bindAddress: p.bindAddress)
            }
        }
        probeCache = probeCache.filter { key, _ in scanned.contains { $0.id == key } }
        return out
    }

    private func requestNotificationAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func notify(_ p: ListeningPort) {
        let content = UNMutableNotificationContent()
        content.title = "New service on port \(p.port)"
        content.body = "\(p.processName) (PID \(p.pid)) started listening"
        let req = UNNotificationRequest(identifier: p.id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}
