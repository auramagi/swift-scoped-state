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
  - [Scopes](#scopes)
  - [Connections](#connections)
  - [Connection Sources](#connection-sources)
  - [`@ScopedState` Property Wrapper](#scopedstate-property-wrapper)
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

### Documentation

- [API Reference](https://auramagi.github.io/swift-scoped-state/documentation/scopedstate/)

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

### Scopes

A scope is a Swift type that contains connection definitions. It doesn't require any protocol conformances.

Scopes serve to provide semantic grouping for state or actions that belong together. A `RootScope` or an `AppScope` suggests global state, while a `ProductScope` or a `BookScope` suggest state that is specifically tied to a particular product or a book.

```swift
struct ProductScope {
  var name: Connection<String>

  var isFavorite: WritableConnection<Bool>

  var reviews: Connection<[Review.ID]>

  var reviewScope: ConfiguredConnection<ReviewScope, Review.ID>

  var buy: Connection<() -> Void>
}
```

In this example, state is product-scoped, meaning that it implies knowledge of which product it represents. Views aren't required to have this knowledge, but get to use simple state like `name` or `isFavorite`. 

Scopes can declare connections that resolve to other child scopes. This connection can be unconfigured when the parent scope contains all necessary context, or configured when it needs another value. In the example above, reviewScope is configured by a Review.ID and resolves a ReviewScope for that review. Views under the child scope can then use review-specific state without receiving the review ID themselves.

```swift
ReviewView()
  .scope(\ProductScope.reviewScope, configuration: reviewID)
```

Scopes are injected and resolved through the SwiftUI environment. Injecting a new scope instance when one of the same type already exists in the environment will override it for child views, following the normal SwiftUI rules.

| Modifier | Description |
|---|---|
| [`container(_:scope:)`](https://auramagi.github.io/swift-scoped-state/documentation/scopedstate/swiftuicore/view/container(_:scope:)) | Inject a scope from a container instance and a key path |
| [`scope(_:)`](https://auramagi.github.io/swift-scoped-state/documentation/scopedstate/swiftuicore/view/scope(_:)) | Inject a child scope by resolving a connection from another scope |
| [`scope(_:configuration:)`](https://auramagi.github.io/swift-scoped-state/documentation/scopedstate/swiftuicore/view/scope(_:configuration:)) | Inject a child scope by resolving a connection from another scope using a configratiuon value |

### Connections

A connection is a definition that creates a session between one `@ScopedState` property and its source. Its type records three parts of that contract: whether configuration is required, which value is delivered, and whether the value can be written back.

|  | Read-Only | Read-Write |
|---|---|---|
| Not configured |  [`Connection`](https://auramagi.github.io/swift-scoped-state/documentation/scopedstate/connection) | [`WritableConnection`](https://auramagi.github.io/swift-scoped-state/documentation/scopedstate/writableconnection) |
| Configured | [`ConfiguredConnection`](https://auramagi.github.io/swift-scoped-state/documentation/scopedstate/configuredconnection) | [`WritableConfiguredConnection`](https://auramagi.github.io/swift-scoped-state/documentation/scopedstate/writableconfiguredconnection) |

Unconfigured connections need no runtime input. Configured connections accept an `Equatable` value such as an entity ID, route, or filter. If that configuration changes while the view keeps its identity, ScopedState reconfigures and reactivates the existing session instead of requiring a new view.

Read-only controls replacement of the connected value. It doesn't make a referenced object immutable. A read-only connection to a model can still expose bindings to that object's writable properties while preventing the view from replacing the model itself:

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

A writable connection exposes `Binding<Value>` as the property's projection, so `$isCompleted` can be passed directly to SwiftUI controls. A writable definition can also be stored behind a read-only declaration when a particular scope shouldn't expose its write operation. Prefer the narrowest declaration that the consuming views need.

### Connection Sources

Connection factories adapt common state sources into connection definitions. Use leading-dot syntax when a property's declared type supplies enough context, or spell the `Connections` namespace explicitly when it doesn't:

```swift
let inferred = Connections.constant(42)

let declared: Connection<Int> = .constant(42)
```

When a source has a synchronous current-value getter, prefer that overload to a captured initial value. The session starts observation before reading the getter, which avoids a gap where the source could change between the initial read and subscription. Use an initial value for event streams that have no current-value API.

#### Observation

Use `observation` for state managed by Swift Observation. The closure form tracks every observable property read while computing the value and evaluates again after one of those dependencies changes. The key-path forms connect a single property and infer write access from the key path:

```swift
let summary: Connection<String> = .observation {
  "\(todo.title) — \(todo.isCompleted ? "Completed" : "Open")"
}

let isCompleted: WritableConnection<Bool> = .observation(todo, \.isCompleted)

let title: Connection<String> = .observation(todo, \.title)
```

#### Swift Concurrency

Use `async` to consume a nonthrowing `AsyncSequence`. A connection starts a new iteration when it activates and cancels the task when it deactivates. Supply either a fixed initial value or a synchronous getter for the source's current value:

```swift
let message: Connection<Message> = .async(
  messageUpdates,
  initialValue: initialMessage
)
```

The asynchronous sequence factories require iOS 18, macOS 15, tvOS 18, watchOS 11, or visionOS 2 even though the rest of the package supports the earlier versions listed above.

#### Combine

Use `subject` for two-way access to a `CurrentValueSubject`, or `publisher` for a read-only stream whose failure type is `Never`. As with asynchronous sequences, a publisher connection needs either an initial value or a synchronous current-value getter:

```swift
let status: WritableConnection<Status> = .subject(statusSubject)

let progress: Connection<Double> = .publisher(
  progressPublisher,
  initialValue: 0
)
```

#### Constants and Local State

Use `constant` for values and actions that don't change during a connection's lifetime. Use `initial` when the state belongs to the consuming property rather than to an external store:

```swift
let buildNumber: Connection<Int> = .constant(42)

let selection: WritableConnection<Todo.ID?> = .initial(nil)
```

Each `@ScopedState` property connected through `initial` owns an independent value. That value resets when the connection identity is recreated, so it is appropriate for scoped UI state but not for data that must outlive the view.

#### Custom

Use `readOnly` or `readWrite` when the built-in factories don't match the source. The factory returns a `ConnectionSession`, which must provide an initial value synchronously and may also provide observation, refresh, reconfiguration, and write operations:

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

The example only reads and writes the source; it doesn't observe changes made elsewhere. For an observed source, return a `CancellationToken` from `activate` and send later values through the supplied yield closure. ScopedState owns that token and cancels it when the session is replaced or its view state is destroyed.

### `@ScopedState` Property Wrapper

`@ScopedState` selects a connection from the nearest scope of the inferred type. Before SwiftUI evaluates the view's `body`, the property wrapper resolves the scope, activates the connection if needed, and installs its synchronous initial value. Later source updates invalidate or replace that value through SwiftUI's state system.

The key path and the scope provider form the connection's identity. Replacing the provider or its scope value creates a new session; changing only a configured connection's configuration reconfigures its current session. In either case, ScopedState cancels the previous observation before activating the next one.

The wrapped property always reads as `Value`. Its projected value reflects the declaration:

- `WritableConnection` and `WritableConfiguredConnection` expose `Binding<Value>`.
- Read-only connections expose a projection only for writable members of reference values; they don't expose a binding that can replace the root value.

A consuming view must have a matching `.container` or `.scope` provider above it. Keep the key path semantic—`\SettingsScope.isEnabled` says more about the view's dependency than the source technology used to implement it.

### Containers

A container is a reference type that owns the concrete dependencies behind a root scope. It may hold stores, clients, coordinators, or child containers; ScopedState only requires a key path to the scope value it provides.

Attach the container at the boundary where its scope becomes valid:

```swift
@State private var container = AppContainer()

var body: some View {
  ContentView()
    .container(container, scope: \.appScope)
}
```

Keep the container's identity stable, usually with `@State`. Descendants can derive narrower scopes with `.scope(_:)` or `.scope(_:configuration:)`; the modifier keeps the child connection active for the lifetime of that part of the view hierarchy. In practice, containers own implementations, scopes declare interfaces, and views select only the connections they use.

## Advanced Usage

### Adding Write Access

The `set` transformation adds or replaces a connection's write operation without changing how it reads. This is useful when an existing publisher, asynchronous sequence, or mapped connection already describes the update path:

```swift
let progress: WritableConnection<Double> = .publisher(
  progressPublisher,
  currentValue: { progressStore.progress }
)
.set { progressStore.progress = $0 }
```

A write is forwarded to the supplied closure; it doesn't silently become a second source of truth inside `@ScopedState`. The source should publish the resulting value or make it available through its current-value getter. If it can't do either, use a custom session that defines the intended local update behavior.

### `ObservableObject` Support

When a connection delivers an `ObservableObject`, `@ScopedState` observes its `objectWillChange` publisher for the active connection lifetime. The view can read the model directly and create member bindings from a read-only connection:

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

This keeps ownership in the container while giving the view the update behavior it would expect from an observed object. The connection remains read-only at the root: `$model.count` can mutate `count`, but the view can't replace `model`. Use a writable connection only when replacing the object is part of the view's contract.

### Previews with `PreviewTrait`

A preview needs the same scope provider as the running view. A `PreviewModifier` can create the container once, attach its scope, and package that setup as a reusable trait:

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

Define separate traits for meaningful states—such as populated, empty, loading, or failed—by changing the container created in `makeSharedContext()`. Apply the trait at the highest view that needs the scope; child views then exercise the same connection path they use in the app.

## License

ScopedState is available under the MIT license. See [LICENSE](LICENSE).
