//
//  Scopes.swift
//  Todo
//
//  Created by Mikhail Apurin on 2026-08-17.
//

import ScopedState

struct AppScope {
    let addTodo: Connection<() -> Void>

    let todos: Connection<[Todo.ID]>

    let todoScope: ConfiguredConnection<TodoScope, Todo.ID>
}

struct TodoScope {
    let delete: Connection<() -> Void>

    let isCompleted: WritableConnection<Bool>

    let title: Connection<String>
}
