# ``ScopedState``

Connect state declared in SwiftUI views to external sources through scopes in
the SwiftUI environment.

## Overview

A scope declares the connections available to a view. A container supplies
their implementations and provides the scope through the environment.
``ScopedState`` selects a connection with a key path and retains its value for
the lifetime of the view's SwiftUI state.

```swift
struct SettingsScope {
    let isEnabled: WritableConnection<Bool>
}

struct SettingsView: View {
    @ScopedState(\SettingsScope.isEnabled) private var isEnabled

    var body: some View {
        Toggle("Enabled", isOn: $isEnabled)
    }
}

SettingsView()
    .container(container, scope: \.settingsScope)
```

Connections can receive updates through Observation, asynchronous sequences,
or Combine. They can also supply constants or give each consuming property its
own writable value. Use a custom session for other sources.

A child scope can represent a particular entity. For example, configure a
`RoomScope` with a room ID so its views can read the room's name and change its
settings without passing the ID to each operation.

## Topics

### Declaring and Providing State

- ``ScopedState``
- ``ScopedStateProjection``
- ``SwiftUICore/View/container(_:scope:)``
- ``SwiftUICore/View/scope(_:)``
- ``SwiftUICore/View/scope(_:configuration:)``

### Connection Declarations

- ``Connection``
- ``WritableConnection``
- ``ConfiguredConnection``
- ``WritableConfiguredConnection``

### Creating Connections

- ``Connections``
- ``ConnectionDefinition/constant(_:)``
- ``ConnectionDefinition/initial(_:)``
- ``ConnectionDefinition/observation(_:)``
- ``ConnectionDefinition/observation(_:_:)->ConnectionDefinition<EmptyConfiguration,WrappedValue>``
- ``ConnectionDefinition/observation(_:_:)->WritableConnectionDefinition<EmptyConfiguration,WrappedValue>``
- ``ConnectionDefinition/async(_:initialValue:)``
- ``ConnectionDefinition/async(_:currentValue:)``
- ``ConnectionDefinition/subject(_:)``
- ``ConnectionDefinition/publisher(_:initialValue:)``
- ``ConnectionDefinition/publisher(_:currentValue:)``
- ``ConnectionDefinition/readOnly(_:)->ConnectionDefinition<Configuration,Value>``
- ``ConnectionDefinition/readOnly(_:)->ConnectionDefinition<EmptyConfiguration,Value>``
- ``ConnectionDefinition/readWrite(_:)->WritableConnectionDefinition<Configuration,Value>``
- ``ConnectionDefinition/readWrite(_:)->WritableConnectionDefinition<EmptyConfiguration,Value>``

### Transforming Connections

- ``ConnectionDefinition/map(_:)``
- ``ConnectionDefinition/set(_:)``
- ``WritableConnectionDefinition/map(get:set:)``

### Custom Connection Sessions

- ``ConnectionSession``
- ``ConnectionSession/Update``
- ``CancellationToken``

### Supporting Connection Types

- ``ConnectionDefinition``
- ``WritableConnectionDefinition``
- ``ReadOnlyConnectionDefinition``
- ``ReadWriteConnectionDefinition``
- ``EmptyConfiguration``
- ``ValueProjection``
- ``ReadOnlyValueProjection``
- ``ReadWriteValueProjection``
