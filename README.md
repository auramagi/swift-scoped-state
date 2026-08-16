# ScopedState

ScopedState allows SwiftUI views to declare state connected to external sources through statically declared scopes carried by the SwiftUI environment.

[![Documentation](https://img.shields.io/badge/Documentation-DocC-blue)](https://auramagi.github.io/swift-scoped-state/documentation/scopedstate/)
![Platforms](https://img.shields.io/badge/Platforms-iOS%20%7C%20macOS%20%7C%20tvOS%20%7C%20watchOS%20%7C%20visionOS-lightgrey)
![Swift](https://img.shields.io/badge/Swift-6.2%2B-F05138)
[![Tests](https://github.com/auramagi/swift-scoped-state/actions/workflows/tests.yml/badge.svg?branch=main)](https://github.com/auramagi/swift-scoped-state/actions/workflows/tests.yml)

## Contents

- [Overview](#overview)
- [Getting Started](#getting-started)
  - [Requirements](#requirements)
  - [Installation](#installation)
- [Basic Usage](#basic-usage)
  - [Root Scope](#root-scope)
  - [Child Scopes](#child-scopes)
- [How It Works](#how-it-works)
  - [The `@ScopedState` Property Wrapper](#scopedstate-property-wrapper)
  - [Scopes](#scopes)
  - [Connections](#connections)
  - [Connection Sources](#connection-sources)
  - [Containers](#containers)
- [Advanced Usage and Techniques](#advanced-usage-and-techniques)
- [License](#license)

## Overview

ScopedState separates the state a view declares from the implementation that supplies it. Its main pieces are:

- **`@ScopedState`** — Selects and retains connected state for a view.
- **Scopes** — Declare the state and operations available to a view hierarchy.
- **Connections** — Describe how values are initialized, updated, and optionally written back.
- **Connection sources** — Adapt external values and update mechanisms into connections.
- **Containers** — Assemble connections into scopes and provide them to a view hierarchy.

The complete path from scope declaration to environment injection stays compact.

```swift
@MainActor struct HomeScope {
    let room: ConfiguredConnection<RoomScope, Room.ID>
}

@MainActor struct RoomScope {
    let isLightOn: WritableConnection<Bool>

    let name: Connection<String>
}

struct RoomView: View {
    @ScopedState(\RoomScope.isLightOn) private var isLightOn

    @ScopedState(\RoomScope.name) private var name

    var body: some View {
        Toggle(name, isOn: $isLightOn)
    }
}

ForEach(rooms) { room in
    RoomView()
        .scope(\HomeScope.room, configuration: room.id)
}
.container(container, scope: \.homeScope)
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

### Installation

#### Xcode

In Xcode, select **File → Add Package Dependencies** and enter:

```
https://github.com/auramagi/swift-scoped-state
```

Add the `ScopedState` product to your target. Choose the dependency rule appropriate for your project.

#### Swift Package Manager

Add ScopedState to the package dependencies in `Package.swift`.

```swift
.package(url: "https://github.com/auramagi/swift-scoped-state", from: "0.1.0-b.6"),
```

Then add the `ScopedState` product to the dependencies of your target.

```swift
.product(name: "ScopedState", package: "swift-scoped-state")
```

## Basic Usage

### Root Scope

`AppScope` declares the state and operations available to the todo list.

```swift
@MainActor struct AppScope {
    let addTodo: Connection<() -> Void>

    let todos: Connection<[Todo.ID]>
}
```

`TodoListView` selects the connections it needs using static key paths.

```swift
struct TodoListView: View {
    @ScopedState(\AppScope.addTodo) private var addTodo

    @ScopedState(\AppScope.todos) private var todos

    var body: some View {
        List {
            ForEach(todos, id: \.self) { id in
                // ...
            }
        }
        .toolbar {
            Button("Add Todo", systemImage: "plus", action: addTodo)
        }
    }
}
```

`ContentView` owns the container and provides `AppScope` around the todo list.

```swift
struct ContentView: View {
    @State private var container = AppContainer()

    var body: some View {
        TodoListView()
            .container(container, scope: \.appScope)
    }
}
```

### Child Scopes

`AppScope` also provides a child scope configured for one todo.

```swift
@MainActor struct AppScope {
    let addTodo: Connection<() -> Void>

    let todos: Connection<[Todo.ID]>

    let todoScope: ConfiguredConnection<TodoScope, Todo.ID>
}

@MainActor struct TodoScope {
    let delete: Connection<() -> Void>

    let isCompleted: WritableConnection<Bool>

    let title: Connection<String>
}
```

`TodoListView` injects that scope around each row, using the todo ID as its configuration.

```swift
ForEach(todos, id: \.self) { id in
    TodoRow()
        .scope(\AppScope.todoScope, configuration: id)
}
```

`TodoRow` declares its state and operations in terms of one todo. It doesn't receive or pass the ID itself.

```swift
struct TodoRow: View {
    @ScopedState(\TodoScope.delete) private var delete

    @ScopedState(\TodoScope.isCompleted) private var isCompleted

    @ScopedState(\TodoScope.title) private var title

    var body: some View {
        Toggle(isOn: $isCompleted) {
            Text(title)
        }
        .swipeActions {
            Button("Delete", systemImage: "trash", role: .destructive, action: delete)
        }
    }
}
```

The external implementation uses `Todo.ID` to determine which todo the child scope represents. `TodoRow` sees only the resulting state and operations.

The complete project is available in [Examples/Todo](Examples/Todo).

## How It Works

### `@ScopedState` Property Wrapper

`@State` declares a value that belongs to a SwiftUI view hierarchy. `@Environment` accesses a value created elsewhere and provided through context. APIs such as `@AppStorage`, `@SceneStorage`, Core Data's `@FetchRequest`, and SwiftData's `@Query` sit somewhere between the two: a view declares the state it needs, while a key or query connects that state to an external source.

`@ScopedState` follows that model. A view identifies state through a static key path. A container puts the corresponding scope into the SwiftUI environment. The property wrapper resolves the connection, retains its current value for the lifetime of the view's state, and receives later updates from the external source. Writable connections also send changes back to that source.

`@ScopedState` is a `DynamicProperty`. It resolves its scope from the SwiftUI environment and uses SwiftUI state to retain the active connection and current value across view updates.

A connection follows the lifetime of the SwiftUI state that declares it. This is not the same as view appearance: SwiftUI may retain state for a view that is temporarily off-screen, such as a view in a navigation hierarchy.

### Scopes

A scope groups state and operations that share context. `TodoScope` doesn't merely collect todo-related APIs; it represents one particular todo. That context lets it expose `title`, `isCompleted`, and `delete` instead of APIs that repeatedly accept a `Todo.ID`.

Scopes are ordinary types containing statically declared connections. They form the interface between views and containers without exposing a concrete container type to the consuming view.

Scope types and key paths make available connections explicit and checked by the compiler. Resolution does not depend on string keys, runtime casts, or a service lookup.

### Connections

A connection describes how scoped state receives its initial value and later updates. It may also describe how changes are written back to the external source.

| Type | Capability |
| --- | --- |
| `Connection<Value>` | Read-only connection |
| `WritableConnection<Value>` | Writable connection |
| `ConfiguredConnection<Value, Configuration>` | Read-only connection with configuration |
| `WritableConfiguredConnection<Value, Configuration>` | Writable connection with configuration |

Writable connections are a superset of read-only connections. A scope property declared as `Connection<Value>` can receive either kind; a property declared as `WritableConnection<Value>` requires a writable connection.

#### Read-Only Objects and Bindings

Read-only controls whether a view can replace the connected root value. It does not make properties of a connected object immutable.

```swift
@Observable final class EditorModel {
    var title = ""
}

@MainActor struct EditorScope {
    let model: Connection<EditorModel>
}

struct EditorView: View {
    @ScopedState(\EditorScope.model) private var model

    var body: some View {
        TextField("Title", text: $model.title)
    }
}
```

The read-only projection exposes bindings to writable object properties such as `title`, but it does not expose a binding that replaces `model` itself. `WritableConnection<EditorModel>` would expose both.

### Connection Sources

Connection definitions can adapt several kinds of external sources.

#### Observation

An observation expression tracks every `@Observable` property it reads. Key-path overloads connect to one property; a writable key path produces a writable connection, which can also satisfy a read-only declaration.

```swift
let summary: Connection<String> = .observation {
    "\(todo.title) — \(todo.isCompleted ? "Completed" : "Open")"
}

let isCompleted: WritableConnection<Bool> = .observation(todo, \.isCompleted)

let title: Connection<String> = .observation(todo, \.title)
```

#### Swift Concurrency

An asynchronous sequence can provide later updates after an initial or synchronously fetched value. Concurrency connections require iOS 18, macOS 15, tvOS 18, watchOS 11, or visionOS 2.

```swift
let message: Connection<Message> = .async(
    messageUpdates,
    initialValue: initialMessage
)
```

#### Combine

A current-value subject provides both observation and writing. Other publishers require an initial value or synchronous current-value getter.

```swift
let status: WritableConnection<Status> = .subject(statusSubject)

let progress: Connection<Double> = .publisher(
    progressPublisher,
    initialValue: 0
)
```

#### Constants and Local State

Use a constant for immutable values and actions. An initial connection instead gives every connected property independent writable state.

```swift
let buildNumber: Connection<Int> = .constant(42)

let selection: WritableConnection<Todo.ID?> = .initial(nil)
```

#### Custom

For sources without a built-in adapter, `.readOnly` and `.readWrite` construct a connection from a custom `ConnectionSession`.

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

Factories are exposed through the `Connections` namespace. When the expected connection type is known, Swift also allows the shorter leading-dot syntax used throughout the examples.

```swift
let inferred = Connections.constant(42)

let declared: Connection<Int> = .constant(42)
```

### Containers

A container is a reference type that provides a scope. It may own external storage, assemble connections from other dependencies, create state for a particular scope, or provide a self-contained mock. ScopedState does not prescribe its internal architecture.

Containers provide connection definitions. The corresponding `@ScopedState` property creates and retains an active connection as part of SwiftUI's state lifecycle. A concrete Observation-backed implementation is available in the [Todo example](Examples/Todo/Todo/AppContainer.swift).

## Advanced Usage and Techniques

### Adding Write Access

The `.set` modifier adds write behavior to a connection whose source is otherwise read-only.

```swift
let progress: WritableConnection<Double> = .publisher(
    progressPublisher,
    currentValue: { progressStore.progress }
)
.set { progressStore.progress = $0 }
```

### `ObservableObject` Support

When the connected value conforms to `ObservableObject`, `@ScopedState` automatically observes its `objectWillChange` publisher in addition to updates delivered by the connection.

```swift
final class CounterModel: ObservableObject {
    @Published var count = 0
}

@MainActor struct CounterScope {
    let model: Connection<CounterModel>
}

struct CounterView: View {
    @ScopedState(\CounterScope.model) private var model

    var body: some View {
        Stepper("Count: \(model.count)", value: $model.count)
    }
}
```

No special connection constructor is required. If the connection later delivers a different object, `@ScopedState` transfers observation to the new instance.

### Previews with `PreviewTrait`

A `PreviewModifier` is one way to provide a scope to several previews. Its shared context can create and retain the preview container, while a custom trait keeps each preview declaration short.

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

The Todo project also defines an empty-scope trait in [AppContainer.swift](Examples/Todo/Todo/AppContainer.swift).

## License

ScopedState is available under the MIT license. See [LICENSE](LICENSE).
