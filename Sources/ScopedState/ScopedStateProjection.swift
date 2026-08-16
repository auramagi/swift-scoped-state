//
//  ScopedStateProjection.swift
//  ScopedState
//
//  Created by Mikhail Apurin on 2026-08-16.
//

import SwiftUI

/// The projected value of a read-only scoped property.
///
/// A read-only projection doesn't allow replacement of its root value. When
/// the root is a reference type, dynamic-member lookup still exposes bindings
/// to properties with public setters.
///
/// ```swift
/// @ScopedState(\EditorScope.model) private var model
///
/// TextField("Title", text: $model.title)
/// ```
@MainActor @dynamicMemberLookup public struct ScopedStateProjection<Base> {
    let base: Binding<Base>

    /// Returns a binding to a writable property of the connected object.
    ///
    /// - Parameter keyPath: A reference-writable key path from the connected
    ///   object to one of its properties.
    public subscript<Value>(dynamicMember keyPath: ReferenceWritableKeyPath<Base, Value>) -> Binding<Value> {
        base[dynamicMember: keyPath]
    }
}

/// Defines the projected-value behavior of ``ScopedState``.
///
/// The built-in ``ReadOnlyValueProjection`` and ``ReadWriteValueProjection``
/// types provide the projection semantics used by public scoped-state
/// initializers.
public protocol ValueProjection<Value>: SendableMetatype {
    /// The connected value represented by the projection.
    associatedtype Value

    /// The value exposed by the property wrapper's `$` projection.
    associatedtype ProjectedValue

    /// Whether assigning through the root projection writes to the connection.
    static var forwardsRootReplacement: Bool { get }

    /// Converts the underlying scoped-state projection to the public projection.
    ///
    /// - Parameter projection: The underlying projection for the connected value.
    /// - Returns: The projected value exposed to the consuming view.
    @MainActor static func transformProjection(_ projection: ScopedStateProjection<Value>) -> ProjectedValue
}

/// Projection behavior for read-only connected values.
public enum ReadOnlyValueProjection<Value>: ValueProjection {
    /// A Boolean value indicating that root replacement stays local to the
    /// projection and isn't forwarded to the connection.
    public static var forwardsRootReplacement: Bool { false }

    /// Preserves a projection that only supports writable object members.
    ///
    /// - Parameter projection: The underlying scoped-state projection.
    /// - Returns: The read-only projection.
    @MainActor public static func transformProjection(_ projection: ScopedStateProjection<Value>) -> ScopedStateProjection<Value> {
        projection
    }
}

/// Projection behavior for writable connected values.
public enum ReadWriteValueProjection<Value>: ValueProjection {
    /// A Boolean value indicating that root replacement is forwarded to the
    /// connection.
    public static var forwardsRootReplacement: Bool { true }

    /// Exposes the root projection as a writable SwiftUI binding.
    ///
    /// - Parameter projection: The underlying scoped-state projection.
    /// - Returns: A binding to the connected value.
    @MainActor public static func transformProjection(_ projection: ScopedStateProjection<Value>) -> Binding<Value> {
        projection.base
    }
}
