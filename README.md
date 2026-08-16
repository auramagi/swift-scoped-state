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
  - [Documentation](#documentation)
- [Basic Usage](#basic-usage)
  - [Root Scope](#root-scope)
  - [Child Scopes](#child-scopes)
- [How It Works](#how-it-works)
  - [`@ScopedState` Property Wrapper](#scopedstate-property-wrapper)
  - [Scopes](#scopes)
  - [Connections](#connections)
  - [Connection Sources](#connection-sources)
  - [Containers](#containers)
- [Advanced Usage and Techniques](#advanced-usage-and-techniques)
- [License](#license)

## Overview

ScopedState separates the interface a view consumes from the implementation that supplies it. Views identify state with static key paths instead of receiving a concrete container, starting subscriptions, or passing context through each initializer.

- **`@ScopedState`** — Resolves a connection and exposes its current value to a view.
- **Scopes** — Define the state and operations available to a view hierarchy.
- **Connections** — Define how values are initialized, updated, and optionally written back.
- **Connection sources** — Adapt Observation, asynchronous sequences, Combine, or custom implementations.
- **Containers** — Assemble connections into scopes and provide them at the appropriate point in the hierarchy.

The complete path from scope declaration to environment injection stays compact.

```swift
@MainActor struct HomeScope {
    let roomScope: ConfiguredConnection<RoomScope, Room.ID>
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

struct HomeView: View {
    @State private var container = HomeContainer()

    let rooms: [Room]

    var body: some View {
        ForEach(rooms) { room in
            RoomView()
                .scope(\HomeScope.roomScope, configuration: room.id)
        }
        .container(container, scope: \.homeScope)
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
.package(url: "https://github.com/auramagi/swift-scoped-state", from: "0.1.0-b.7"),
```

Then add the `ScopedState` product to the dependencies of your target.

```swift
.product(name: "ScopedState", package: "swift-scoped-state")
```

### Documentation

- [ScopedState Documentation](https://auramagi.github.io/swift-scoped-state/documentation/scopedstate/)

## Basic Usage

The following walkthrough is abridged from the included Todo project. It starts with the interface seen by views and introduces the container only at the point where the root scope enters the hierarchy.

### Root Scope

`AppScope` is the interface available to the todo list. Its properties are connection definitions, not the values themselves: `addTodo` connects to an action, while `todos` connects to a read-only list of IDs.

```swift
@MainActor struct AppScope {
    let addTodo: Connection<() -> Void>

    let todos: Connection<[Todo.ID]>
}
```

`TodoListView` selects those definitions using static key paths. The wrapped properties expose the values delivered by the connections, so the body works with an ordinary closure and an array.

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

`ContentView` owns a stable container and provides its `AppScope` around the todo list. The consuming views depend on the scope type, not on `AppContainer` itself.

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

`AppScope` also provides a child scope for one todo. Its `ConfiguredConnection` accepts a `Todo.ID`, which identifies the todo represented by that scope.

```swift
@MainActor struct AppScope {
    // ...
    let todoScope: ConfiguredConnection<TodoScope, Todo.ID>
}

@MainActor struct TodoScope {
    let delete: Connection<() -> Void>

    let isCompleted: WritableConnection<Bool>

    let title: Connection<String>
}
```

Because `TodoScope` represents one particular todo, the ID is already implied. It can expose `title`, `isCompleted`, and `delete` without making every operation accept the ID again.

`TodoListView` injects that scope around each row, using the todo ID as its configuration.

```swift
ForEach(todos, id: \.self) { id in
    TodoRow()
        .scope(\AppScope.todoScope, configuration: id)
}
```

Inside that subtree, `TodoRow` declares state and operations in terms of one todo without receiving or passing the ID itself.

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

The external implementation uses `Todo.ID` to resolve the child scope. `TodoRow` sees only state and operations already scoped to that todo.

The complete sample project, including the Observation-backed container, is available in [Examples/Todo](Examples/Todo).

## How It Works

### `@ScopedState` Property Wrapper

`@State` declares a value that belongs to a SwiftUI view hierarchy. `@Environment` accesses a value created elsewhere and provided through context. APIs such as `@AppStorage`, `@SceneStorage`, Core Data's `@FetchRequest`, and SwiftData's `@Query` sit somewhere between the two: a view declares the state it needs, while a key or query connects that state to an external source.

`@ScopedState` follows that model. A view identifies state through a static key path, and a container puts the corresponding scope into the SwiftUI environment. The property wrapper resolves the connection, retains its current value for the lifetime of the view's state, and receives later updates from the external source. Writable connections also send changes back to that source.

As a `DynamicProperty`, `@ScopedState` participates in SwiftUI's update cycle. It uses SwiftUI state to keep the active connection and current value across view updates, rather than asking the view to initialize and retain that machinery itself.

The connection follows the lifetime of the SwiftUI state that declares it. This is not the same as view appearance: SwiftUI may retain state for a view that is temporarily off-screen, such as a view in a navigation hierarchy.

### Scopes

A scope groups state and operations that share context. `TodoScope` doesn't merely collect todo-related APIs; it represents one particular todo. That context lets it expose `title`, `isCompleted`, and `delete` instead of APIs that repeatedly accept a `Todo.ID`.

Scopes are ordinary types containing statically declared connections. They require no protocol or registration, and they form the interface between views and containers without exposing a concrete container type to the consuming view. A root scope can describe a broad view hierarchy, while a child scope represents more specific context within it.

Scope types and key paths make the available connections explicit and checked by the compiler. Resolution does not depend on string keys, runtime casts, or a service lookup.

### Connections

A connection describes how scoped state receives its initial value and later updates. It may also describe how changes are written back to the external source. The definition stored in a scope is not itself an active subscription; `@ScopedState` uses it to establish a connection for that property and SwiftUI state lifetime.

A configured connection is established with an `Equatable` configuration. If that configuration changes while the SwiftUI state remains alive, the connection updates to represent the new context.

| Type | Capability |
| --- | --- |
| `Connection<Value>` | Read-only connection |
| `WritableConnection<Value>` | Writable connection |
| `ConfiguredConnection<Value, Configuration>` | Read-only connection with configuration |
| `WritableConfiguredConnection<Value, Configuration>` | Writable connection with configuration |

Writable connections are a superset of read-only connections. A scope property declared as `Connection<Value>` can receive either kind; a property declared as `WritableConnection<Value>` requires a writable connection. The type declared by the scope determines which write access is exposed to the consuming view.

For a writable scoped property, the projected value is a `Binding<Value>`. It can be passed directly to SwiftUI controls or used to replace the root through `$property.wrappedValue`. A read-only scoped property does not expose that root binding.

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

The read-only projection exposes bindings to writable object properties such as `title`, but it does not expose a binding that replaces `model` itself. With `WritableConnection<EditorModel>`, the projection is a `Binding<EditorModel>` and supports both.

### Connection Sources

Connection definitions can adapt several kinds of external sources. Each built-in factory combines a value available when the connection starts with a way to receive later updates; writable factories also provide a way to send values back.

#### Observation

An observation expression tracks every `@Observable` property it reads and is reevaluated when one of them changes. Use the closure form for a value derived from several properties, or a key-path overload to connect to one property. A writable key path produces a writable connection, which can also satisfy a read-only declaration.

```swift
let summary: Connection<String> = .observation {
    "\(todo.title) — \(todo.isCompleted ? "Completed" : "Open")"
}

let isCompleted: WritableConnection<Bool> = .observation(todo, \.isCompleted)

let title: Connection<String> = .observation(todo, \.title)
```

#### Swift Concurrency

An asynchronous sequence can provide later updates after an initial or synchronously fetched value. The sequence expression is evaluated whenever observation starts, and its task is cancelled when that observation ends. Concurrency connections require iOS 18, macOS 15, tvOS 18, watchOS 11, or visionOS 2.

```swift
let message: Connection<Message> = .async(
    messageUpdates,
    initialValue: initialMessage
)
```

#### Combine

A `CurrentValueSubject` provides a current value, later updates, and a write operation, so `.subject` creates a writable connection. Other publishers create read-only connections and require an initial value or synchronous current-value getter. Combine connection sources must have `Failure == Never`.

```swift
let status: WritableConnection<Status> = .subject(statusSubject)

let progress: Connection<Double> = .publisher(
    progressPublisher,
    initialValue: 0
)
```

#### Constants and Local State

Use `.constant` for immutable values and actions. An `.initial` connection instead gives every connected property independent writable state that begins with the supplied value.

```swift
let buildNumber: Connection<Int> = .constant(42)

let selection: WritableConnection<Todo.ID?> = .initial(nil)
```

The state created by `.initial` is not shared between connected properties and resets when a connection is recreated.

#### Custom

For sources without a built-in adapter, `.readOnly` and `.readWrite` construct a connection from a custom `ConnectionSession`. A session provides the starting value, later updates, optional writes, and any cancellation needed by its observation mechanism.

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

Activation returns an initial value and an optional `CancellationToken`. An active session can then yield `.value(newValue)` for a pushed update, or `.invalidate` when the value should be refreshed during a later SwiftUI update.

Factories are exposed through the `Connections` namespace. When the expected connection type is known, Swift also allows the shorter leading-dot syntax used throughout the examples.

```swift
let inferred = Connections.constant(42)

let declared: Connection<Int> = .constant(42)
```

### Containers

A container is a reference type that provides a scope. It may own external storage, assemble connections from other dependencies, create state for a particular scope, or provide a self-contained mock. ScopedState does not require a container protocol or prescribe its internal architecture.

The `.container(_:scope:)` modifier takes a key path to the provided scope. Only the scope type enters the environment; the concrete container type remains at the injection site. Container identity and the key path together identify that provision, so a computed scope property is evaluated only when either one changes.

Containers provide connection definitions. The corresponding `@ScopedState` properties establish and retain the active connections as part of SwiftUI's state lifecycle.

A configured child-scope connection can create a narrower container and retain it for that subtree. The [Todo example](Examples/Todo/Todo/AppContainer.swift) uses this pattern: `AppContainer` provides the root scope, while `todoScope` creates a `TodoContainer` for the selected ID.

## Advanced Usage and Techniques

### Adding Write Access

The `.set` modifier adds or replaces write behavior without changing how a connection receives values. This is useful when the read source and write operation are separate—for example, a publisher paired with a command on a store.

```swift
let progress: WritableConnection<Double> = .publisher(
    progressPublisher,
    currentValue: { progressStore.progress }
)
.set { progressStore.progress = $0 }
```

### `ObservableObject` Support

An `ObservableObject` can publish internal changes without the connection delivering a replacement object. When the connected value conforms to `ObservableObject`, `@ScopedState` observes its `objectWillChange` publisher in addition to updates delivered by the connection.

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

No special connection constructor is required. Changes published by `model` update `CounterView`; if the connection later delivers a different object, `@ScopedState` transfers observation to the new instance.

### Previews with `PreviewTrait`

A `PreviewModifier` is one way to provide the same scope setup to several previews. Its shared context can create and retain the preview container, while a custom `PreviewTrait` keeps each preview declaration short.

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

This is a convenience technique rather than a requirement of the library. The Todo project also defines an empty-scope trait in [AppContainer.swift](Examples/Todo/Todo/AppContainer.swift), allowing the same view to be previewed against distinct container state.

## License

ScopedState is available under the MIT license. See [LICENSE](LICENSE).
