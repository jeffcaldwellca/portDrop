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
        // `--` keeps a service or container named like a flag (e.g. "--volumes") from being parsed as one.
        case .downService(let project, let service): ["compose", "-p", project, "down", "--", service]
        case .downProject(let project): ["compose", "-p", project, "down"]
        case .stopContainer(let id, _): ["stop", "--", id]
        }
    }

    /// Stops (and for compose, removes) containers. Volumes are never touched: `down` without `-v` keeps them.
    static func run(_ action: DockerAction) async throws {
        guard DockerInspector.locateDocker() != nil else { throw DockerError.noDocker }
        guard let r = await DockerInspector.run(arguments(for: action), timeout: .seconds(60)) else { throw DockerError.timedOut }
        if r.timedOut { throw DockerError.timedOut }
        guard r.status == 0 else {
            // compose writes progress to stderr even on success, so only the exit status decides; the last line is the reason.
            let last = r.stderr.split(separator: "\n").last.map(String.init) ?? "docker exited with status \(r.status)"
            throw DockerError.failed(last.trimmingCharacters(in: .whitespaces))
        }
    }
}
