//
//  ValueDefinition.swift
//  ScopedState
//
//  Created by Mikhail Apurin on 2026-08-16.
//

public protocol ValueDefinition<Configuration, Value>: SendableMetatype {
    associatedtype Configuration

    associatedtype Value
}

public protocol WritableValueDefinition<Configuration, Value>: ValueDefinition {}

public struct ReadOnlyValueDefinition<Configuration, Value>: ValueDefinition {}

public struct ReadWriteValueDefinition<Configuration, Value>: WritableValueDefinition {}
