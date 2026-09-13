# Docker service labels and "down" actions

**Date:** 2026-09-13
**Status:** approved

## Problem

Docker Desktop (and OrbStack, Colima) publishes every container port from a single host
process. `lsof` reports `com.docker.backend` for all of them, so PortDrop shows the same
headline for every container port and the Kill button would SIGTERM the Docker backend
itself, taking every container with it.

## Goal

1. A row for a Docker-published port names the compose service (or container) behind it.
2. The row offers a "down" action for that one service, or for the whole compose project.
3. Nothing changes for users without Docker, and nothing slows the scan for them.

## Decisions (from brainstorming)

| Question | Decision |
|---|---|
| Row label | Compose service (or container name) becomes the headline; subtitle shows project · container; a Docker chip marks the row. Backend process name and PID move to the tooltip. |
| Action semantics | `down`: stop **and remove** containers and networks. Volumes are never removed. |
| Choosing scope | Row button targets the one service, with the same click-then-confirm pill as Kill. Context menu offers both the service and the whole project. |
| Existing Kill | Replaced by the Docker button on Docker rows. Kill remains in the context menu, labelled as killing the Docker backend. |
| Data source | The `docker` CLI (`docker ps` for reads, `docker compose` / `docker stop` for actions). Engine-socket approach rejected: more code, no compose. |

## Components

### `DockerContainer` / `DockerBinding` (Models/DockerBinding.swift)

```swift
struct DockerContainer: Hashable, Sendable {
    let id: String            // full container ID
    let name: String          // e.g. can-railway-postgres-1
    let project: String?      // com.docker.compose.project
    let service: String?      // com.docker.compose.service
    let hostPorts: Set<UInt16>
}

struct DockerBinding: Hashable, Sendable {
    let container: DockerContainer
    let containerPort: UInt16      // the port inside the container
    var displayName: String        // service ?? name
    var isCompose: Bool            // project != nil && service != nil
}
```

### `DockerInspector` (Services/DockerInspector.swift)

- `static func locateDocker() -> String?` checks, in order: `/usr/local/bin/docker`,
  `/opt/homebrew/bin/docker`, `~/.docker/bin/docker`,
  `/Applications/Docker.app/Contents/Resources/bin/docker`,
  `/Applications/OrbStack.app/Contents/MacOS/xbin/docker`. Result cached for the process
  lifetime.
- `static let hostProcessNames: Set<String>` = `com.docker.backend`, `vpnkit`,
  `OrbStack Helper`, `com.docker.vpnkit`. The inspector only runs when at least one
  scanned port belongs to one of these, so non-Docker users never spawn `docker`.
- `static func parse(_ jsonLines: String) -> [DockerContainer]` parses the output of
  `docker ps --no-trunc --format '{{json .}}'` (one JSON object per line). Pure, tested.
  - `Ports` is a comma-separated list like
    `0.0.0.0:5433->5432/tcp, [::]:5433->5432/tcp, 0.0.0.0:51130->6443/tcp`. Only entries
    with a `host:port->` prefix and `/tcp` suffix count; IPv4/IPv6 twins collapse.
    Entries with no arrow (exposed but unpublished, e.g. `5432/tcp`) are ignored.
  - `Labels` is `k=v,k=v`; values may contain `=` but not `,` for the labels we read.
- `static func bindings(from containers: [DockerContainer]) -> [UInt16: DockerBinding]`
  keyed by host port. If two containers claim the same host port (should not happen), the
  first wins.
- `static func scan() async throws -> [DockerContainer]` runs the CLI on a detached task
  with a 5 s timeout, `HOME` and a `PATH` that includes the docker binary's directory (the
  CLI needs both to find `~/.docker/config.json`, the current context, and
  `cli-plugins/docker-compose`). Non-zero exit or empty output → empty list, no error
  surfaced: a stopped Docker Desktop is normal, not a failure.

### `DockerController` (Services/DockerController.swift)

```swift
enum DockerAction: Hashable, Sendable {
    case downService(project: String, service: String)
    case downProject(project: String)
    case stopContainer(id: String, name: String)
}
```

- `static func arguments(for: DockerAction) -> [String]` — pure, tested:
  - `downService` → `compose -p <project> down <service>`
  - `downProject` → `compose -p <project> down`
  - `stopContainer` → `stop <id>` (never `rm`: removing a non-compose container such as a
    k3d node would destroy state the user did not ask to lose)
- `static func run(_ action: DockerAction) async throws` executes the CLI with a 60 s
  timeout and throws `DockerError.failed(stderr)` on non-zero exit. Compose prints
  progress on stderr even on success, so only the exit status decides.

### `PortMonitor` changes

- `var docker: [UInt16: DockerBinding]` refreshed inside `refresh()` after the lsof scan,
  only when `scanned` contains a host process name; otherwise reset to `[:]`.
- `func dockerBinding(for port: ListeningPort) -> DockerBinding?` — matches on host port
  *and* the row's process being a Docker host process, so a native Postgres on 5432 is
  never mislabelled when a container happens to publish the same number on another
  runtime.
- `func projectContainerCount(_ project: String) -> Int` for the menu label.
- `filteredPorts` also matches service, project, and container name.
- `func perform(_ action: DockerAction) async throws` runs it, waits 250 ms, refreshes.
- Docker failures set nothing on `lastError`; they are silent.

### `PortRowView` changes

- New optional input `docker: DockerBinding?` and `onDocker: (DockerAction) async throws -> Void`.
- When `docker != nil`:
  - headline = `docker.displayName`; icon = `shippingbox` symbol tinted by the kind.
  - second line = KindChip, then a `DockerChip` ("Docker", blue), then subtitle
    `project · container` (compose) or `container` (plain).
  - tooltip adds `com.docker.backend · PID n` and the container ID prefix.
  - action column: Docker button (`shippingbox.and.arrow.backward` or similar) → confirm
    pill "Down" (compose) / "Stop" (plain) → runs the service-level action. Reuses the
    existing `KillState` machine and error caption. ⌥ has no meaning here.
  - context menu: "Down <service>", "Down project <project> (N containers)" (compose) or
    "Stop <container>" (plain), then the existing copy/open/reveal items, then a divider
    and "Kill Docker backend (PID n)" / force variant.
- When `docker == nil` the row is unchanged.

### `PanelView`

Passes `monitor.dockerBinding(for:)` and `monitor.perform` into each row. Nothing else.

## Data flow

```
lsof ──► [ListeningPort] ──► classify ──► services
                │
                └─ any Docker host process? ──► docker ps ──► parse ──► bindings[hostPort]
                                                                            │
PanelView ──► row(port, service, presentation, docker: bindings[port.port]) ◄┘
row button ──► DockerAction ──► DockerController.run ──► refresh
```

## Error handling

| Situation | Behaviour |
|---|---|
| No docker binary / daemon stopped | `docker` map empty; rows render as before. |
| `docker ps` slow | 5 s timeout, then treated as empty. Scan loop never blocks on it beyond that. |
| Compose down fails | Red caption on the row for 4 s, same as kill failures. Row stays. |
| Project has containers without ports | They still count in "(N containers)" and still go down; that is what compose down does. |
| Same host port published by two runtimes | Match requires the row's process to be a Docker host process; first binding wins. |

## Testing

- `DockerInspectorTests`: parse real `docker ps` JSON lines (compose container with
  IPv4+IPv6 twins, k3d container with three published ports and no compose labels,
  container with no ports, exposed-but-unpublished port ignored, malformed line skipped);
  `bindings(from:)` keying and first-wins.
- `DockerControllerTests`: `arguments(for:)` for the three actions.
- `PortMonitorTests`: `dockerBinding(for:)` requires host-process match; search matches
  service and project; `projectContainerCount`.
- Manual: with Docker Desktop running, row for 5433 shows "postgres", chip, and
  "can-railway · can-railway-postgres-1"; Down removes the container and the row
  disappears on the next refresh; project menu shows the correct count.

## Out of scope

- Restarting or `up`-ing services from PortDrop.
- Colima's `ssh`-forwarded ports (process name is `ssh`, too generic to gate on).
- Reading `docker-compose.yml` files or working directories.
- Removing volumes.
