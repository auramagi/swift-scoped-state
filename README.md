# ScopedState

ScopedState lets SwiftUI views declare state connected to external sources. Containers supply scopes through the environment, and views select connections from those scopes.

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

A **scope** declares **connections** to external sources. A view selects a connection with the **`@ScopedState`** property wrapper and a key path. Read-only connections let the view read the value. Writable connections also provide a SwiftUI `Binding` for writing back to the source.

ScopedState resolves the connection before SwiftUI evaluates the view's body. It keeps the connection active for the lifetime of the view's state and applies updates as they arrive. That state can outlive the view's appearance on screen, for example in a navigation stack.

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

Scopes can also provide connections to **child scopes**. Here, `AppScope` provides a `TodoScope` for each todo. The connection takes a todo ID as its **configuration** to select which item it represents.

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

A **container** assembles the connections into a scope. A parent view provides that scope through the environment with `.container(_:scope:)`.

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
- [Abstracting SwiftUI State with Scopes](https://apurin.me/articles/abstracting-swiftui-state-with-scopes/)

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
.package(url: "https://github.com/auramagi/swift-scoped-state", from: "0.1.0"),
```

Add the `ScopedState` product to each target that imports it:

```swift
.product(name: "ScopedState", package: "swift-scoped-state"),
```

## How It Works

### Scopes

A scope is a Swift type that contains connection definitions. It doesn't require any protocol conformances.

Scopes group related state and actions. A `RootScope` or `AppScope` might provide state for the whole app, while a `ProductScope` or `BookScope` might represent one product or book.

```swift
struct ProductScope {
  var name: Connection<String>

  var isFavorite: WritableConnection<Bool>

  var reviews: Connection<[Review.ID]>

  var reviewScope: ConfiguredConnection<ReviewScope, Review.ID>

  var buy: Connection<() -> Void>
}
```

This `ProductScope` represents a particular product. Its views can read `name`, change `isFavorite`, or call `buy` without passing a product ID to each operation.

A child-scope connection needs no configuration if the parent scope already has enough context to select it. Otherwise, the caller supplies a configuration value. Here, `reviewScope` takes a `Review.ID` and resolves a `ReviewScope` for that review. Descendant views use the review's state without receiving the ID themselves.

```swift
ReviewView()
  .scope(\ProductScope.reviewScope, configuration: reviewID)
```

Scopes use the SwiftUI environment. Providing a scope overrides any ancestor's scope of the same type for descendant views.

| Modifier | Description |
|---|---|
| [`container(_:scope:)`](https://auramagi.github.io/swift-scoped-state/documentation/scopedstate/swiftuicore/view/container(_:scope:)) | Inject a scope from a container instance and a key path |
| [`scope(_:)`](https://auramagi.github.io/swift-scoped-state/documentation/scopedstate/swiftuicore/view/scope(_:)) | Inject a child scope by resolving a connection from another scope |
| [`scope(_:configuration:)`](https://auramagi.github.io/swift-scoped-state/documentation/scopedstate/swiftuicore/view/scope(_:configuration:)) | Inject a child scope by resolving a connection from another scope using a configuration value |

### Connections

A connection definition creates a session between one `@ScopedState` property and its source. Its type specifies the value it supplies, whether it takes a configuration, and whether it accepts writes.

|  | Read-Only | Read-Write |
|---|---|---|
| Not configured |  [`Connection`](https://auramagi.github.io/swift-scoped-state/documentation/scopedstate/connection) | [`WritableConnection`](https://auramagi.github.io/swift-scoped-state/documentation/scopedstate/writableconnection) |
| Configured | [`ConfiguredConnection`](https://auramagi.github.io/swift-scoped-state/documentation/scopedstate/configuredconnection) | [`WritableConfiguredConnection`](https://auramagi.github.io/swift-scoped-state/documentation/scopedstate/writableconfiguredconnection) |

Unconfigured connections need no runtime input. Configured connections accept an `Equatable` value such as an entity ID, route, or filter. When that value changes, ScopedState reconfigures and reactivates the existing session. The view can keep its identity.

Read-only connections prevent replacement of the connected value. An object's properties can still be writable. In this example, the view can edit `title` through a binding but can't replace `model`:

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

A writable connection exposes `Binding<Value>` through `$property`, so you can pass `$isCompleted` to a SwiftUI control. You can also assign a writable definition to a read-only scope property to withhold root write access from its views.

### Connection Sources

Connection factories create definitions for common sources. When the declared type is a connection, call the factory with a leading dot. Otherwise, use `Connections`:

```swift
let inferred = Connections.constant(42)

let declared: Connection<Int> = .constant(42)
```

When a source has a synchronous current-value getter, prefer that overload to a captured initial value. The session starts observation before reading the getter, which avoids a gap where the source could change between the initial read and subscription. Use an initial value for event streams that have no current-value API.

#### Observation

Use `observation` for state managed by Swift Observation. The closure form tracks the observable properties it reads. After a tracked property changes, the connection evaluates the closure again during the next SwiftUI update. The key-path forms connect a single property, with write access determined by the key path:

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

The asynchronous sequence factories require iOS 18, macOS 15, tvOS 18, watchOS 11, or visionOS 2. Other connection sources support the earlier versions listed in Requirements.

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

Each `@ScopedState` property connected through `initial` owns an independent value that resets when the connection identity changes. Use an external store for data that must outlive the property's state.

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

A consuming view must have a matching `.container` or `.scope` provider above it. A key path such as `\SettingsScope.isEnabled` identifies the state the view needs without specifying how the container supplies it.

### Containers

A container is an object that provides a scope. It can hold stores, clients, or child containers, but ScopedState places no requirements on those dependencies. It only needs a key path to the scope.

Provide the container's scope above the views that use it:

```swift
@State private var container = AppContainer()

var body: some View {
  ContentView()
    .container(container, scope: \.appScope)
}
```

Keep the container's identity stable, usually with `@State`. Descendants can derive child scopes with `.scope(_:)` or `.scope(_:configuration:)`. Each modifier keeps its connection active for the lifetime of its SwiftUI state.

## Advanced Usage

### Adding Write Access

The `set` transformation adds or replaces a connection's setter. It keeps the connection's existing source of updates:

```swift
let progress: WritableConnection<Double> = .publisher(
  progressPublisher,
  currentValue: { progressStore.progress }
)
.set { progressStore.progress = $0 }
```

Writes call the supplied closure. They don't directly update the value stored by `@ScopedState`. The source must deliver the resulting change through the connection's update mechanism. A custom session can yield the new value or invalidate the stored value and return a new one from `refresh`.

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

Changes to `count` update the view. The read-only connection lets `$model.count` mutate the property without letting the view replace `model`. Declare a writable connection if the view also needs to replace the object.

### Previews with `PreviewTrait`

A preview needs a provider for each scope its views use. A `PreviewModifier` can create a shared container and provide its scope through a reusable trait:

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

Define traits for populated, empty, loading, or failed previews by changing the container created in `makeSharedContext()`. Apply the trait to the preview that contains the consuming views. Its descendants resolve connections as they do in the app.

## License

ScopedState is available under the MIT license. See [LICENSE](LICENSE).
