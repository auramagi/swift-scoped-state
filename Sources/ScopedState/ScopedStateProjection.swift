//
//  ScopedStateProjection.swift
//  ScopedState
//
//  Created by Mikhail Apurin on 2026-08-16.
//

import SwiftUI

/// The projected value of a read-only scoped property.
///
/// Use `$property.member` to bind to a writable member. The projection accepts
/// reference-writable key paths, so member writes don't require replacing the
/// root value. It doesn't expose a binding to the root itself.
///
/// ```swift
/// @ScopedState(\EditorScope.model) private var model
///
/// TextField("Title", text: $model.title)
/// ```
@MainActor @dynamicMemberLookup public struct ScopedStateProjection<Base> {
    let base: Binding<Base>

    /// Returns a binding to a member that can be set without mutating the root.
    ///
    /// - Parameter keyPath: A reference-writable key path to the member.
    public subscript<Value>(dynamicMember keyPath: ReferenceWritableKeyPath<Base, Value>) -> Binding<Value> {
        base[dynamicMember: keyPath]
    }
}

/// Determines what ``ScopedState`` exposes through `$property`.
///
/// ``ScopedState`` initializers select ``ReadOnlyValueProjection`` or
/// ``ReadWriteValueProjection`` based on the connection declaration.
public protocol ValueProjection<Value>: SendableMetatype {
    /// The connected value represented by the projection.
    associatedtype Value

    /// The value exposed by the property wrapper's `$` projection.
    associatedtype ProjectedValue

    /// Whether assigning through the root projection writes to the connection.
    static var forwardsRootReplacement: Bool { get }

    /// Converts the stored value's projection to the type exposed by `$property`.
    ///
    /// - Parameter projection: The underlying projection for the connected value.
    @MainActor static func transformProjection(_ projection: ScopedStateProjection<Value>) -> ProjectedValue
}

/// Projection behavior for read-only connected values.
public enum ReadOnlyValueProjection<Value>: ValueProjection {
    /// Keeps root writeback from member bindings local to scoped state.
    public static var forwardsRootReplacement: Bool { false }

    /// Returns the member-only projection unchanged.
    ///
    /// - Parameter projection: The underlying scoped-state projection.
    @MainActor public static func transformProjection(_ projection: ScopedStateProjection<Value>) -> ScopedStateProjection<Value> {
        projection
    }
}

/// Projection behavior for writable connected values.
public enum ReadWriteValueProjection<Value>: ValueProjection {
    /// Forwards root replacement to the connection's setter.
    public static var forwardsRootReplacement: Bool { true }

    /// Exposes the root projection as a writable SwiftUI binding.
    ///
    /// - Parameter projection: The underlying scoped-state projection.
    /// - Returns: A binding to the connected value.
    @MainActor public static func transformProjection(_ projection: ScopedStateProjection<Value>) -> Binding<Value> {
        projection.base
    }
}
