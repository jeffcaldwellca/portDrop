# Docker Service Labels and Down Actions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rows for Docker-published ports name the compose service behind them and offer a "down" action for that service or its whole compose project.

**Architecture:** A `DockerInspector` runs `docker ps` (only when a Docker host process owns a listening port) and produces bindings keyed by host port. `PortMonitor` merges those into its refresh. `PortRowView` swaps its headline, chip, and action button when a binding exists, and a `DockerController` runs the `docker compose … down` / `docker stop` commands.

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI, XCTest, XcodeGen. Docker CLI at runtime.

**Spec:** `docs/superpowers/specs/2026-09-13-docker-services-design.md`

## Global Constraints

- `SWIFT_STRICT_CONCURRENCY: complete`; every new type is `Sendable`; UI types are `@MainActor`.
- Deployment target macOS 26.0.
- Volumes are never removed. Non-compose containers are only ever `docker stop`ped.
- Docker failures on the read path are silent; the panel must render exactly as today when Docker is absent.
- Test command (run from repo root):
  ```bash
  xcodebuild test -scheme PortDrop -destination 'platform=macOS' -derivedDataPath build/DerivedData -only-testing:PortDropTests 2>&1 | tail -30
  ```
  Regenerate the project after adding files: `xcodegen generate` (targets use directory globs, so new files under `PortDrop/` and `PortDropTests/` are picked up).

---

### Task 1: Models and `docker ps` parser

**Files:**
- Create: `PortDrop/Models/DockerBinding.swift`
- Create: `PortDrop/Services/DockerInspector.swift`
- Test: `PortDropTests/DockerInspectorTests.swift`

**Interfaces:**
- Produces: `DockerContainer`, `DockerBinding`, `DockerInspector.parse(_:) -> [DockerContainer]`, `DockerInspector.bindings(from:) -> [UInt16: DockerBinding]`, `DockerInspector.hostProcessNames`, `DockerInspector.isHostProcess(_:)`.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import PortDrop

final class DockerInspectorTests: XCTestCase {
    static let compose = #"{"ID":"abc123","Labels":"com.docker.compose.config-hash=72b,com.docker.compose.project=can-railway,com.docker.compose.service=postgres,com.docker.compose.version=2.39.4","Names":"can-railway-postgres-1","Ports":"0.0.0.0:5433->5432/tcp, [::]:5433->5432/tcp","State":"running"}"#
    static let k3d = #"{"ID":"def456","Labels":"app=k3d,k3d.role=loadbalancer,maintainer=NGINX Docker Maintainers <docker-maint@nginx.com>","Names":"k3d-canrail-serverlb","Ports":"0.0.0.0:80->80/tcp, [::]:80->80/tcp, 0.0.0.0:443->443/tcp, [::]:443->443/tcp, 0.0.0.0:51130->6443/tcp","State":"running"}"#
    static let noPorts = #"{"ID":"ghi789","Labels":"","Names":"k3d-canrail-agent-0","Ports":"","State":"running"}"#
    static let exposedOnly = #"{"ID":"jkl012","Labels":"","Names":"redis","Ports":"6379/tcp","State":"running"}"#

    func testComposeContainer() {
        let c = DockerInspector.parse(Self.compose)
        XCTAssertEqual(c.count, 1)
        XCTAssertEqual(c[0].id, "abc123")
        XCTAssertEqual(c[0].name, "can-railway-postgres-1")
        XCTAssertEqual(c[0].project, "can-railway")
        XCTAssertEqual(c[0].service, "postgres")
        XCTAssertEqual(c[0].ports, [DockerPortMapping(hostPort: 5433, containerPort: 5432)])
    }

    func testPlainContainerWithManyPorts() {
        let c = DockerInspector.parse(Self.k3d)
        XCTAssertEqual(c.count, 1)
        XCTAssertNil(c[0].project)
        XCTAssertNil(c[0].service)
        XCTAssertEqual(Set(c[0].ports.map(\.hostPort)), [80, 443, 51130])
        XCTAssertEqual(c[0].ports.first { $0.hostPort == 51130 }?.containerPort, 6443)
    }

    func testNoPortsAndExposedOnlyYieldEmptyMappings() {
        let c = DockerInspector.parse([Self.noPorts, Self.exposedOnly].joined(separator: "\n"))
        XCTAssertEqual(c.count, 2)
        XCTAssertTrue(c[0].ports.isEmpty)
        XCTAssertTrue(c[1].ports.isEmpty)
    }

    func testMalformedLineSkipped() {
        let c = DockerInspector.parse("not json\n" + Self.compose + "\n\n")
        XCTAssertEqual(c.map(\.name), ["can-railway-postgres-1"])
    }

    func testBindingsKeyedByHostPortFirstWins() {
        let dup = #"{"ID":"zzz","Labels":"","Names":"other","Ports":"0.0.0.0:5433->1/tcp","State":"running"}"#
        let b = DockerInspector.bindings(from: DockerInspector.parse([Self.compose, Self.k3d, dup].joined(separator: "\n")))
        XCTAssertEqual(Set(b.keys), [5433, 80, 443, 51130])
        XCTAssertEqual(b[5433]?.container.name, "can-railway-postgres-1")
        XCTAssertEqual(b[5433]?.containerPort, 5432)
        XCTAssertEqual(b[5433]?.displayName, "postgres")
        XCTAssertTrue(b[5433]!.isCompose)
        XCTAssertEqual(b[80]?.displayName, "k3d-canrail-serverlb")
        XCTAssertFalse(b[80]!.isCompose)
    }

    func testHostProcessNames() {
        XCTAssertTrue(DockerInspector.isHostProcess("com.docker.backend"))
        XCTAssertTrue(DockerInspector.isHostProcess("com.docke"))   // lsof truncates to 9 chars in some modes
        XCTAssertTrue(DockerInspector.isHostProcess("OrbStack Helper"))
        XCTAssertFalse(DockerInspector.isHostProcess("postgres"))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodegen generate && xcodebuild test -scheme PortDrop -destination 'platform=macOS' -derivedDataPath build/DerivedData -only-testing:PortDropTests/DockerInspectorTests 2>&1 | tail -30`
Expected: compile error, `DockerInspector` not found.

- [ ] **Step 3: Write the models**

`PortDrop/Models/DockerBinding.swift`:

```swift
import Foundation

struct DockerPortMapping: Hashable, Sendable {
    let hostPort: UInt16
    let containerPort: UInt16
}

struct DockerContainer: Hashable, Sendable {
    let id: String
    let name: String
    let project: String?
    let service: String?
    let ports: [DockerPortMapping]

    var isCompose: Bool { project != nil && service != nil }
}

/// One published host port, resolved to the container (and compose service) behind it.
struct DockerBinding: Hashable, Sendable {
    let container: DockerContainer
    let containerPort: UInt16

    var displayName: String { container.service ?? container.name }
    var isCompose: Bool { container.isCompose }
}
```

- [ ] **Step 4: Write the parser**

`PortDrop/Services/DockerInspector.swift`:

```swift
import Foundation

enum DockerInspector {
    /// macOS processes that own the host side of published container ports. lsof truncates
    /// command names to 9 characters in `-F c` output on some systems, so prefixes are matched.
    static let hostProcessNames: [String] = ["com.docker.backend", "com.docker.vpnkit", "vpnkit", "OrbStack Helper"]

    static func isHostProcess(_ processName: String) -> Bool {
        hostProcessNames.contains { $0.hasPrefix(processName) && processName.count >= 5 || processName == $0 }
    }

    /// Parses `docker ps --no-trunc --format '{{json .}}'` output (one JSON object per line).
    static func parse(_ output: String) -> [DockerContainer] {
        output.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = obj["ID"] as? String, let name = obj["Names"] as? String else { return nil }
            let labels = parseLabels(obj["Labels"] as? String ?? "")
            return DockerContainer(id: id, name: name,
                                   project: labels["com.docker.compose.project"],
                                   service: labels["com.docker.compose.service"],
                                   ports: parsePorts(obj["Ports"] as? String ?? ""))
        }
    }

    /// `k=v,k=v`; values may contain `=` but the labels we read never contain `,`.
    static func parseLabels(_ s: String) -> [String: String] {
        var out: [String: String] = [:]
        for pair in s.split(separator: ",") {
            guard let eq = pair.firstIndex(of: "=") else { continue }
            out[String(pair[..<eq])] = String(pair[pair.index(after: eq)...])
        }
        return out
    }

    /// `0.0.0.0:5433->5432/tcp, [::]:5433->5432/tcp, 6379/tcp` → [(5433, 5432)], twins collapsed, unpublished ignored.
    static func parsePorts(_ s: String) -> [DockerPortMapping] {
        var seen: Set<UInt16> = []
        var out: [DockerPortMapping] = []
        for entry in s.split(separator: ",") {
            let e = entry.trimmingCharacters(in: .whitespaces)
            guard e.hasSuffix("/tcp"), let arrow = e.range(of: "->") else { continue }
            let hostSide = e[..<arrow.lowerBound]
            let containerSide = e[arrow.upperBound...].dropLast(4)
            guard let colon = hostSide.lastIndex(of: ":"),
                  let host = UInt16(hostSide[hostSide.index(after: colon)...]),
                  let container = UInt16(containerSide),
                  seen.insert(host).inserted else { continue }
            out.append(DockerPortMapping(hostPort: host, containerPort: container))
        }
        return out
    }

    static func bindings(from containers: [DockerContainer]) -> [UInt16: DockerBinding] {
        var out: [UInt16: DockerBinding] = [:]
        for c in containers {
            for m in c.ports where out[m.hostPort] == nil {
                out[m.hostPort] = DockerBinding(container: c, containerPort: m.containerPort)
            }
        }
        return out
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run the same command as Step 2. Expected: all six `DockerInspectorTests` PASS.

- [ ] **Step 6: Commit**

```bash
git add PortDrop/Models/DockerBinding.swift PortDrop/Services/DockerInspector.swift PortDropTests/DockerInspectorTests.swift
git commit -m "docker: parse docker ps output into per-port container bindings"
```

---

### Task 2: Running the Docker CLI and the down/stop actions

**Files:**
- Modify: `PortDrop/Services/DockerInspector.swift` (add `locateDocker`, `run`, `scan`)
- Create: `PortDrop/Services/DockerController.swift`
- Test: `PortDropTests/DockerControllerTests.swift`

**Interfaces:**
- Consumes: `DockerContainer`, `DockerInspector.parse`.
- Produces: `DockerInspector.locateDocker() -> String?`, `DockerInspector.scan() async -> [DockerContainer]`, `DockerAction`, `DockerController.arguments(for:) -> [String]`, `DockerController.run(_:) async throws`, `DockerError`.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import PortDrop

final class DockerControllerTests: XCTestCase {
    func testDownServiceArguments() {
        XCTAssertEqual(DockerController.arguments(for: .downService(project: "can-railway", service: "postgres")),
                       ["compose", "-p", "can-railway", "down", "postgres"])
    }
    func testDownProjectArguments() {
        XCTAssertEqual(DockerController.arguments(for: .downProject(project: "can-railway")),
                       ["compose", "-p", "can-railway", "down"])
    }
    func testStopContainerArguments() {
        XCTAssertEqual(DockerController.arguments(for: .stopContainer(id: "abc123", name: "redis")), ["stop", "abc123"])
    }
    func testActionsForBindings() {
        let compose = DockerContainer(id: "a", name: "p-postgres-1", project: "p", service: "postgres", ports: [])
        let plain = DockerContainer(id: "b", name: "redis", project: nil, service: nil, ports: [])
        XCTAssertEqual(DockerAction.primary(for: DockerBinding(container: compose, containerPort: 1)),
                       .downService(project: "p", service: "postgres"))
        XCTAssertEqual(DockerAction.project(for: DockerBinding(container: compose, containerPort: 1)), .downProject(project: "p"))
        XCTAssertEqual(DockerAction.primary(for: DockerBinding(container: plain, containerPort: 1)),
                       .stopContainer(id: "b", name: "redis"))
        XCTAssertNil(DockerAction.project(for: DockerBinding(container: plain, containerPort: 1)))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme PortDrop -destination 'platform=macOS' -derivedDataPath build/DerivedData -only-testing:PortDropTests/DockerControllerTests 2>&1 | tail -30`
Expected: compile error, `DockerController` not found.

- [ ] **Step 3: Add CLI execution to `DockerInspector`**

Append inside `enum DockerInspector`:

```swift
    static let candidatePaths: [String] = [
        "/usr/local/bin/docker",
        "/opt/homebrew/bin/docker",
        NSString(string: "~/.docker/bin/docker").expandingTildeInPath,
        "/Applications/Docker.app/Contents/Resources/bin/docker",
        "/Applications/OrbStack.app/Contents/MacOS/xbin/docker",
    ]

    nonisolated(unsafe) private static var cachedPath: String??

    /// First executable docker binary from `candidatePaths`; cached for the process lifetime.
    static func locateDocker() -> String? {
        if let cachedPath { return cachedPath }
        let found = candidatePaths.first { FileManager.default.isExecutableFile(atPath: $0) }
        cachedPath = .some(found)
        return found
    }

    struct CLIResult: Sendable {
        let status: Int32
        let stdout: String
        let stderr: String
    }

    /// Runs the docker CLI with a PATH that includes its own directory (for cli-plugins and credential helpers).
    /// Returns nil when no binary exists or the process does not finish within `timeout`.
    static func run(_ arguments: [String], timeout: Duration) async -> CLIResult? {
        guard let docker = locateDocker() else { return nil }
        return await Task.detached(priority: .userInitiated) { () -> CLIResult? in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: docker)
            p.arguments = arguments
            var env = ProcessInfo.processInfo.environment
            let dir = (docker as NSString).deletingLastPathComponent
            env["PATH"] = [dir, "/usr/local/bin", "/opt/homebrew/bin", env["PATH"] ?? "/usr/bin:/bin"].joined(separator: ":")
            p.environment = env
            let out = Pipe(), err = Pipe()
            p.standardOutput = out
            p.standardError = err
            do { try p.run() } catch { return nil }
            let deadline = DispatchWorkItem { if p.isRunning { p.terminate() } }
            DispatchQueue.global().asyncAfter(deadline: .now() + .seconds(Int(timeout.components.seconds)), execute: deadline)
            let outData = out.fileHandleForReading.readDataToEndOfFile()
            let errData = err.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            deadline.cancel()
            if p.terminationReason == .uncaughtSignal { return nil }
            return CLIResult(status: p.terminationStatus,
                             stdout: String(decoding: outData, as: UTF8.self),
                             stderr: String(decoding: errData, as: UTF8.self))
        }.value
    }

    /// Running containers, or an empty list when Docker is absent, stopped, or slow. Never throws: that is normal.
    static func scan() async -> [DockerContainer] {
        guard let r = await run(["ps", "--no-trunc", "--format", "{{json .}}"], timeout: .seconds(5)), r.status == 0 else { return [] }
        return parse(r.stdout)
    }
```

- [ ] **Step 4: Write `DockerController`**

`PortDrop/Services/DockerController.swift`:

```swift
import Foundation

enum DockerAction: Hashable, Sendable {
    case downService(project: String, service: String)
    case downProject(project: String)
    case stopContainer(id: String, name: String)

    /// What the row button does: down the compose service, or stop the plain container.
    static func primary(for b: DockerBinding) -> DockerAction {
        if let project = b.container.project, let service = b.container.service {
            return .downService(project: project, service: service)
        }
        return .stopContainer(id: b.container.id, name: b.container.name)
    }

    /// Down the whole compose project; nil for containers that are not part of one.
    static func project(for b: DockerBinding) -> DockerAction? {
        b.container.project.map { .downProject(project: $0) }
    }

    var verb: String {
        switch self {
        case .downService, .downProject: "Down"
        case .stopContainer: "Stop"
        }
    }
}

enum DockerError: LocalizedError {
    case noDocker
    case timedOut
    case failed(String)
    var errorDescription: String? {
        switch self {
        case .noDocker: "docker CLI not found"
        case .timedOut: "docker timed out"
        case .failed(let m): m
        }
    }
}

enum DockerController {
    static func arguments(for action: DockerAction) -> [String] {
        switch action {
        case .downService(let project, let service): ["compose", "-p", project, "down", service]
        case .downProject(let project): ["compose", "-p", project, "down"]
        case .stopContainer(let id, _): ["stop", id]
        }
    }

    static func run(_ action: DockerAction) async throws {
        guard DockerInspector.locateDocker() != nil else { throw DockerError.noDocker }
        guard let r = await DockerInspector.run(arguments(for: action), timeout: .seconds(60)) else { throw DockerError.timedOut }
        guard r.status == 0 else {
            // compose writes progress to stderr even on success, so only the exit status decides; the last line is the reason.
            let last = r.stderr.split(separator: "\n").last.map(String.init) ?? "docker exited with status \(r.status)"
            throw DockerError.failed(last.trimmingCharacters(in: .whitespaces))
        }
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run the same command as Step 2. Expected: all four `DockerControllerTests` PASS. Also run the full suite once to be sure nothing else broke.

- [ ] **Step 6: Commit**

```bash
git add PortDrop/Services/DockerInspector.swift PortDrop/Services/DockerController.swift PortDropTests/DockerControllerTests.swift
git commit -m "docker: run the docker CLI for ps, compose down, and stop"
```

---

### Task 3: `PortMonitor` integration

**Files:**
- Modify: `PortDrop/State/PortMonitor.swift`
- Test: `PortDropTests/PortMonitorTests.swift`

**Interfaces:**
- Consumes: `DockerInspector.scan()`, `DockerInspector.bindings(from:)`, `DockerInspector.isHostProcess`, `DockerController.run`, `DockerBinding`, `DockerAction`.
- Produces: `PortMonitor.docker: [UInt16: DockerBinding]`, `PortMonitor.dockerContainers: [DockerContainer]`, `dockerBinding(for:) -> DockerBinding?`, `projectContainerCount(_:) -> Int`, `perform(_:) async throws`.

- [ ] **Step 1: Write the failing tests** (append to `PortMonitorTests`)

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme PortDrop -destination 'platform=macOS' -derivedDataPath build/DerivedData -only-testing:PortDropTests/PortMonitorTests 2>&1 | tail -30`
Expected: compile error, no member `dockerContainers`.

- [ ] **Step 3: Implement**

In `PortMonitor`, after `var services`:

```swift
    /// Running containers from the last `docker ps`; empty when no Docker host process is listening.
    var dockerContainers: [DockerContainer] = []
    /// Published host port → container behind it.
    var docker: [UInt16: DockerBinding] = [:]
```

Replace `filteredPorts` body's filter closure with:

```swift
        return ports.filter { p in
            let binding = dockerBinding(for: p)
            return String(p.port).contains(q)
                || p.processName.lowercased().contains(q)
                || p.user.lowercased().contains(q)
                || (services[p.id]?.kind.label.lowercased().contains(q) ?? false)
                || resolver.presentation(for: p, kind: services[p.id]?.kind ?? .tcp).displayName.lowercased().contains(q)
                || (binding.map { b in
                        b.container.name.lowercased().contains(q)
                        || (b.container.project?.lowercased().contains(q) ?? false)
                        || (b.container.service?.lowercased().contains(q) ?? false)
                    } ?? false)
        }
```

After `service(for:)`:

```swift
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
```

In `refresh()`, after `let classified = await classify(scanned)`:

```swift
            let containers = scanned.contains { DockerInspector.isHostProcess($0.processName) } ? await DockerInspector.scan() : []
```

and after `if services != classified { services = classified }`:

```swift
            if dockerContainers != containers {
                dockerContainers = containers
                docker = DockerInspector.bindings(from: containers)
            }
```

- [ ] **Step 4: Run tests to verify they pass**

Run the full suite. Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add PortDrop/State/PortMonitor.swift PortDropTests/PortMonitorTests.swift
git commit -m "docker: merge container bindings into the port monitor refresh"
```

---

### Task 4: Row UI and panel wiring

**Files:**
- Create: `PortDrop/Views/DockerChip.swift`
- Modify: `PortDrop/Views/PortRowView.swift`
- Modify: `PortDrop/Views/PanelView.swift:143-150` (the `PortRowView(...)` call)
- Modify: `PortDropTests/SmokeTests.swift` (if it constructs `PortRowView`; check first)

**Interfaces:**
- Consumes: `DockerBinding`, `DockerAction.primary(for:)`, `DockerAction.project(for:)`, `DockerAction.verb`, `PortMonitor.dockerBinding(for:)`, `projectContainerCount`, `perform`.

- [ ] **Step 1: `DockerChip`**

```swift
import SwiftUI

struct DockerChip: View {
    static let tint: Color = .blue
    var body: some View {
        Label("Docker", systemImage: "shippingbox")
            .labelStyle(.titleAndIcon)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Self.tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Self.tint.opacity(0.14), in: Capsule())
            .overlay(Capsule().strokeBorder(Self.tint.opacity(0.25), lineWidth: 0.5))
    }
}
```

- [ ] **Step 2: `PortRowView` changes**

Add two stored properties after `onKill`:

```swift
    var docker: DockerBinding? = nil
    var onDocker: (DockerAction) async throws -> Void = { _ in }
```

Headline: replace `Text(presentation.displayName)` with `Text(docker?.displayName ?? presentation.displayName)`.

Icon: replace the `Image(nsImage: presentation.icon)` block's image with

```swift
            Group {
                if docker != nil {
                    Image(systemName: "shippingbox.fill").resizable().foregroundStyle(DockerChip.tint)
                } else {
                    Image(nsImage: presentation.icon).resizable().foregroundStyle(service.kind.tint)
                }
            }
            .aspectRatio(contentMode: .fit)
            .frame(width: 28, height: 28)
```

Second line: after `KindChip(kind: service.kind)` insert `if docker != nil { DockerChip() }`.

`subtitle`:

```swift
    private var subtitle: String {
        guard let docker else { return "\(port.user) · PID \(port.pid)" }
        if let project = docker.container.project { return "\(project) · \(docker.container.name)" }
        return docker.container.name
    }
```

`bindDescription`: append, when `docker` is set,
`"\nvia \(port.processName) · PID \(port.pid) · container \(docker.container.id.prefix(12)) port \(docker.containerPort)"`.

Action column: replace `killButton` with `if docker != nil { dockerButton } else { killButton }` (same `.frame(minWidth:)`).

Add:

```swift
    @ViewBuilder private var dockerButton: some View {
        let action = DockerAction.primary(for: docker!)
        switch killState {
        case .idle, .failed:
            Button { beginConfirm() } label: {
                Image(systemName: "shippingbox.and.arrow.backward")
            }
            .buttonStyle(.accessoryBar)
            .accessibilityLabel("\(action.verb) \(docker!.displayName)")
            .help("\(action.verb) \(docker!.displayName) (click again to confirm; right-click for the whole project)")
        case .confirming:
            Button { performDocker(action) } label: {
                Text(action.verb).font(.caption.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(.red)
            .accessibilityLabel("Confirm \(action.verb.lowercased())")
        case .killing:
            ProgressView().controlSize(.small)
        }
    }

    private func performDocker(_ action: DockerAction) {
        revertTask?.cancel()
        withAnimation(.snappy) { killState = .killing }
        Task {
            do {
                try await onDocker(action)
                killState = .idle
            } catch {
                withAnimation(.snappy) { killState = .failed(error.localizedDescription) }
                try? await Task.sleep(for: .seconds(4))
                if case .failed = killState { withAnimation(.snappy) { killState = .idle } }
            }
        }
    }
```

Context menu: at the top of `contextMenu`, before the URL items:

```swift
        if let docker {
            let primary = DockerAction.primary(for: docker)
            Button("\(primary.verb) \(docker.displayName)") { performDocker(primary) }
            if let project = DockerAction.project(for: docker), case .downProject(let name) = project {
                Button("Down project \(name) (\(projectContainerCount) containers)") { performDocker(project) }
            }
            Divider()
        }
```

and change the trailing kill items to:

```swift
        Divider()
        if docker != nil {
            Button("Kill Docker backend (PID \(port.pid))") { performKill(force: false) }
            Button("Force Kill Docker backend") { performKill(force: true) }
        } else {
            Button("Kill (SIGTERM)") { performKill(force: false) }
            Button("Force Kill (SIGKILL)") { performKill(force: true) }
        }
```

Add a stored `var projectContainerCount: Int = 0` after `onDocker` (the panel passes it in; keeps the row free of the monitor).

- [ ] **Step 3: `PanelView` wiring**

Replace the `PortRowView(...)` call:

```swift
                        let docker = monitor.dockerBinding(for: port)
                        PortRowView(
                            port: port,
                            service: service,
                            presentation: monitor.resolver.presentation(for: port, kind: service.kind),
                            onKill: { force in try await monitor.kill(port, force: force) },
                            docker: docker,
                            onDocker: { action in try await monitor.perform(action) },
                            projectContainerCount: docker?.container.project.map(monitor.projectContainerCount) ?? 0
                        )
```

- [ ] **Step 4: Build and run the full suite**

Run: `xcodebuild test -scheme PortDrop -destination 'platform=macOS' -derivedDataPath build/DerivedData -only-testing:PortDropTests 2>&1 | tail -30`
Expected: BUILD SUCCEEDED, all tests PASS.

- [ ] **Step 5: Manual check** (Docker Desktop running with a compose project up)

Build and launch: `xcodebuild build -scheme PortDrop -configuration Debug -derivedDataPath build/DerivedData 2>&1 | tail -3 && open build/DerivedData/Build/Products/Debug/PortDrop.app`. Open the panel. Confirm: the compose row shows the service name, Docker chip, and `project · container`; hovering shows the backend PID; right-click shows "Down <service>" and "Down project <name> (N containers)"; the row button shows a "Down" pill on click. Non-Docker rows are unchanged. Quit the app afterwards.

- [ ] **Step 6: Commit**

```bash
git add PortDrop/Views/DockerChip.swift PortDrop/Views/PortRowView.swift PortDrop/Views/PanelView.swift
git commit -m "docker: label container rows by compose service and offer down/stop actions"
```

---

### Task 5: Docs

**Files:**
- Modify: `README.md` (feature list)
- Modify: `site/` copy only if the README feature list is mirrored there (grep for "Kill" to find the list)

- [ ] **Step 1: Add a README bullet** under the feature list, wording: "Docker-aware: ports published by Docker Desktop or OrbStack show the compose service behind them, with one-click `docker compose down` for the service or the whole project (plain containers get `docker stop`)."

- [ ] **Step 2: Commit**

```bash
git add README.md site
git commit -m "docs: describe the Docker service labels and down actions"
```
