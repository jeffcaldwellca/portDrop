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
