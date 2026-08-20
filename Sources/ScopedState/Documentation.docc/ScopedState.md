# ``ScopedState``

Connect state declared in SwiftUI views to external sources through scopes in
the SwiftUI environment.

## Overview

ScopedState separates the interface a view consumes from the implementation
that supplies it. A scope declares the available state and operations as
connection definitions. A container provides the root scope, and
``ScopedState`` resolves individual connections with static key paths.

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

The container decides how each connection is backed. Built-in factories adapt
Observation, Swift Concurrency, Combine, constants, and property-local state.
Custom sessions can integrate other update mechanisms.

Use child scopes to add context to a smaller part of a view hierarchy. A
configured child scope can represent one entity without requiring every view
and operation in that subtree to accept the entity identifier.

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
