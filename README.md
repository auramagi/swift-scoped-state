# ScopedState

ScopedState lets SwiftUI views declare state connected to external sources. Each connection belongs to a scope, which is supplied by containers and is resolved through the environment.

[![Documentation](https://img.shields.io/badge/Documentation-DocC-blue)](https://auramagi.github.io/swift-scoped-state/documentation/scopedstate/)
![Platforms](https://img.shields.io/badge/Platforms-iOS%20%7C%20macOS%20%7C%20tvOS%20%7C%20watchOS%20%7C%20visionOS-lightgrey)
![Swift](https://img.shields.io/badge/Swift-6.2%2B-F05138)
[![Tests](https://github.com/auramagi/swift-scoped-state/actions/workflows/tests.yml/badge.svg?branch=main)](https://github.com/auramagi/swift-scoped-state/actions/workflows/tests.yml)

## Contents

- [Overview](#overview)
- [Getting Started](#getting-started)
  - [Documentation](#documentation)
  - [Requirements](#requirements)
  - [Installation](#installation)
- [How It Works](#how-it-works)
  - [`@ScopedState` Property Wrapper](#scopedstate-property-wrapper)
  - [Scopes](#scopes)
  - [Connections](#connections)
  - [Connection Sources](#connection-sources)
  - [Containers](#containers)
- [Advanced Usage](#advanced-usage)
- [License](#license)

## Overview

Some application state follows a particular view's lifetime even though its initial value and updates come from an external source.

To solve this problem, a **connection** to a source can be defined within a **scope**. A view then accesses that connection by declaring state with the **`@ScopedState`** property wrapper and the corresponding key path. **Read-only** connections provide immutable values to a view's `body`, while **read-write** ones provide writable two-way values using SwiftUI `Binding`.

When the view appears, ScopedState resolves this connection and keeps it active until the view is destroyed, applying updates as they arrive.

```swift
struct TodoScope {
  /// Todo title. Read-only value.
  let title: Connection<String>

  /// Todo completion state. Read-write value.
  let isCompleted: WritableConnection<Bool>
}

struct TodoRow: View {
  @ScopedState(\TodoScope.title) private var title

  @ScopedState(\TodoScope.isCompleted) private var isCompleted

  var body: some View {
    Toggle(isOn: $isCompleted) {
      Text(title)
    }
  }
}
```

Scopes can provide connections to **child scopes**. In the todo example, an app-wide scope provides a connection to todo-specific scopes. This connection is defined as being **configured** by the todo ID, since it needs to know which todo item to represent.

```swift
struct AppScope {
  // All todos.
  let todos: Connection<[Todo.ID]>

  // Scope for a single todo, configured by its ID.
  let todoScope: ConfiguredConnection<TodoScope, Todo.ID>
}

struct TodoListView: View {
  @ScopedState(\AppScope.todos) private var todos

  var body: some View {
    List(todos, id: \.self) { id in
      TodoRow()
        .scope(\AppScope.todoScope, configuration: id)
    }
  }
}
```

A parent view uses a **container** to create scope instances containing concrete connection implementations, then injects them into the environment.

```swift
class AppContainer {
  var appScope: AppScope { ... }
}

struct AppView: View {
  @State private var container = AppContainer()

  var body: some View {
    TodoListView()
      .container(container, scope: \.appScope)
  }
}
```

## Getting Started

### Requirements

| Tool or platform | Minimum version |
| --- | --- |
| Swift | 6.2 |
| Xcode | 26.0 |
| iOS | 17.0 |
| macOS | 14.0 |
| tvOS | 17.0 |
| watchOS | 10.0 |
| visionOS | 1.0 |

### Documentation

- [API Reference](https://auramagi.github.io/swift-scoped-state/documentation/scopedstate/)

### Installation

#### Xcode

In Xcode, choose **File → Add Package Dependencies** and enter:

```
https://github.com/auramagi/swift-scoped-state
```

Add the `ScopedState` product to your target, then choose the dependency rule for the project.

#### Swift Package Manager

Add ScopedState to the package dependencies:

```swift
.package(url: "https://github.com/auramagi/swift-scoped-state", from: "0.1.0-b.7"),
```

Add the `ScopedState` product to each target that imports it:

```swift
.product(name: "ScopedState", package: "swift-scoped-state"),
```

## How It Works

### `@ScopedState` Property Wrapper

`@ScopedState` activates the connection selected by its key path. The current scope comes from the SwiftUI environment; the view does not look up or retain the container that supplied it.

The wrapper stores the connection's current value in SwiftUI state and applies later updates from the source. A writable connection also sends local changes back to that source.

Connection lifetime follows the SwiftUI state that declared the property, not necessarily the view's visible lifetime. SwiftUI can preserve that state while a view is off-screen, such as in a navigation stack. Treat connection activation and cancellation as state-lifecycle events rather than appearance events.

### Scopes

A scope is an ordinary Swift type with statically declared connections; it requires no protocol or registration. Group connections that share context in the same scope. `TodoScope`, for example, represents one selected todo, so `title` and `isCompleted` do not need a `Todo.ID` parameter.

A root scope can cover a broad hierarchy. A child scope narrows that context for a screen, row, or other subtree. In the overview, each ID configures `AppScope.todoScope`, and `.scope(_:configuration:)` injects the resulting `TodoScope` around its row. If the ID changes while the row state remains alive, ScopedState reconnects the child scope with the new ID.

Views select connections with typed key paths, so access to a connection outside the current scope fails at compile time. The [Todo project](Examples/Todo) shows root and configured child scopes together. Use a child scope when a subtree should receive selected context once instead of passing that context through each property or initializer.

### Connections

A connection stored in a scope is a definition, not an active subscription. It defines how to load a value and receive updates. A writable connection also defines how to send changes to the source. `@ScopedState` activates that definition for the lifetime of the property.

A configured connection pairs the definition with an `Equatable` configuration. ScopedState reconnects when that configuration changes while the property remains alive.

|  | Read-Only | Read-Write |
|---|---|---|
| Not configured |  `Connection<Value>` | `WritableConnection<Value>` |
| Configured | `ConfiguredConnection<Value, Configuration>` | `WritableConfiguredConnection<Value, Configuration>` |

A writable connection can satisfy a read-only scope property, but a read-only connection cannot satisfy a writable one. The type declared in the scope determines the access granted to the view.

Writable state exposes a `Binding<Value>` as its projected value. Pass it to SwiftUI controls, or use `$property.wrappedValue` to replace the root value. Read-only state has no root binding. Declare a connection read-only unless the consuming view needs to replace its value.

#### Read-Only Objects and Bindings

For a reference type, read-only access prevents replacement of the connected object; it does not make the object's properties immutable.

```swift
@Observable final class EditorModel {
  var title = ""
}

struct EditorScope {
  let model: Connection<EditorModel>
}

struct EditorView: View {
  @ScopedState(\EditorScope.model) private var model

  var body: some View {
    TextField("Title", text: $model.title)
  }
}
```

Here, `$model.title` remains writable, but the view cannot replace `model`. Declare `model` as a `WritableConnection<EditorModel>` only if the view also needs to replace the object.

### Connection Sources

Choose a connection factory that matches the source of truth. Each factory supplies an initial value and later updates; writable factories also define how changes return to the source.

#### Observation

An observation expression tracks the `@Observable` properties it reads and reevaluates when any of them change. Use a closure for a derived value and a key path for one property. A writable key path creates a writable connection, which can still satisfy a read-only declaration.

```swift
let summary: Connection<String> = .observation {
  "\(todo.title) — \(todo.isCompleted ? "Completed" : "Open")"
}

let isCompleted: WritableConnection<Bool> = .observation(todo, \.isCompleted)

let title: Connection<String> = .observation(todo, \.title)
```

#### Swift Concurrency

Use an asynchronous sequence when a value has an initial or synchronously fetched value followed by asynchronous updates. ScopedState evaluates the sequence expression when the connection activates and cancels its task when the connection ends.

Concurrency connections require iOS 18, macOS 15, tvOS 18, watchOS 11, or visionOS 2.

```swift
let message: Connection<Message> = .async(
  messageUpdates,
  initialValue: initialMessage
)
```

#### Combine

A `CurrentValueSubject` provides a current value, publishes updates, and accepts writes, so `.subject` creates a writable connection. Other publishers create read-only connections and require either an initial value or a synchronous current-value getter. Combine sources must use `Failure == Never`.

```swift
let status: WritableConnection<Status> = .subject(statusSubject)

let progress: Connection<Double> = .publisher(
  progressPublisher,
  initialValue: 0
)
```

#### Constants and Local State

Use `.constant` for fixed values and actions. Use `.initial` when each connected property should own independent writable state with the supplied starting value.

```swift
let buildNumber: Connection<Int> = .constant(42)

let selection: WritableConnection<Todo.ID?> = .initial(nil)
```

State created by `.initial` is not shared between properties. It resets when the connection is recreated, so use an external source when state must outlive the connection.

#### Custom

For another data source, `.readOnly` and `.readWrite` build a connection from a `ConnectionSession`. The session supplies the starting value, emits updates, handles optional writes, and cancels observation.

```swift
let count: WritableConnection<Int> = .readWrite {
  ConnectionSession(
    activate: { _ in
      (initialValue: source.count, observation: nil)
    },
    setValue: { source.count = $0 }
  )
}
```

Activation returns an initial value and an optional `CancellationToken`. While active, the session can yield `.value(newValue)` to push an update or `.invalidate` to request a refresh during a later SwiftUI update.

Factories are defined in the `Connections` namespace. Use leading-dot syntax when the declaration provides the expected connection type:

```swift
let inferred = Connections.constant(42)

let declared: Connection<Int> = .constant(42)
```

### Containers

A container can be any reference type that builds a scope. It may own storage, assemble connections from dependencies, create state for a selected context, or provide a self-contained mock. ScopedState requires no container protocol and does not prescribe its internal design; the overview therefore shows only the injection boundary.

The `.container(_:scope:)` modifier selects a scope with a key path and places only that scope type in the environment. The concrete container remains at the injection site. ScopedState identifies the provision by container identity and key path, so it reevaluates a computed scope property only when either changes.

Each `@ScopedState` property then activates and retains its own connection according to SwiftUI's state lifecycle. A configured child-scope connection can retain a narrower container for its subtree. In the [Todo container](Examples/Todo/Todo/AppContainer.swift), `AppContainer` supplies the root scope and creates a `TodoContainer` for the selected ID.

Keep the root container's identity stable across view updates, commonly with `@State`, and expose only the scopes descendants need.

## Advanced Usage

### Adding Write Access

The `.set` modifier adds or replaces write behavior without changing how the connection receives values. Use it when reads and writes use different APIs, such as a publisher paired with a store command.

```swift
let progress: WritableConnection<Double> = .publisher(
  progressPublisher,
  currentValue: { progressStore.progress }
)
.set { progressStore.progress = $0 }
```

### `ObservableObject` Support

For a connected `ObservableObject`, `@ScopedState` observes `objectWillChange` in addition to connection updates. A property change can therefore refresh the view without replacing the connected object.

```swift
final class CounterModel: ObservableObject {
  @Published var count = 0
}

struct CounterScope {
  let model: Connection<CounterModel>
}

struct CounterView: View {
  @ScopedState(\CounterScope.model) private var model

  var body: some View {
    Stepper("Count: \(model.count)", value: $model.count)
  }
}
```

No separate factory is required. Changes published by `model` update `CounterView`; if the connection later supplies another object, `@ScopedState` switches observation to that instance.

### Previews with `PreviewTrait`

A `PreviewModifier` can reuse one container setup across several previews. Its shared context retains the container, and a custom `PreviewTrait` applies that context at each declaration.

```swift
struct SampleAppScopePreviewModifier: PreviewModifier {
  static func makeSharedContext() -> AppContainer {
    AppContainer()
  }

  func body(content: Content, context: AppContainer) -> some View {
    content
      .container(context, scope: \.appScope)
  }
}

extension PreviewTrait where T == Preview.ViewTraits {
  static var sampleAppScope: Self {
    .modifier(SampleAppScopePreviewModifier())
  }
}

#Preview("Sample", traits: .sampleAppScope) {
  TodoListView()
}
```

Use a separate trait for each meaningful preview state. The Todo project defines sample and empty traits in [AppContainer.swift](Examples/Todo/Todo/AppContainer.swift), allowing the same view to run against either container state.

## License

ScopedState uses the MIT license. See [LICENSE](LICENSE).
