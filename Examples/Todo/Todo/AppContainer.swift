//
//  AppContainer.swift
//  Todo
//
//  Created by Mikhail Apurin on 2026-08-17.
//

import Observation
import ScopedState
import SwiftUI

@MainActor final class AppContainer {
    private let store: TodoStore

    init(todos: [Todo] = Todo.samples) {
        self.store = TodoStore(todos: todos)
    }

    var appScope: AppScope {
        AppScope(
            addTodo: .constant(store.addTodo),
            todos: .observation { [self] in store.todoIDs },
            todoScope: .readOnly { [self] id in
                let container = TodoContainer(store: store, todoID: id)

                return .init(
                    activate: { _ in
                        (initialValue: container.scope, observation: nil)
                    },
                    reconfigure: container.update(todoID:)
                )
            }
        )
    }
}

@MainActor @Observable private final class TodoStore {
    private var todos: [Todo]

    init(todos: [Todo]) {
        self.todos = todos
    }

    var todoIDs: [Todo.ID] {
        todos.map(\.id)
    }

    func addTodo() {
        todos.append(Todo(title: "New Todo"))
    }

    func todo(id: Todo.ID) -> Todo {
        guard let todo = todos.first(where: { $0.id == id }) else {
            preconditionFailure("A TodoScope was requested for an unknown todo")
        }
        return todo
    }

    func delete(id: Todo.ID) {
        todos.removeAll { $0.id == id }
    }
}

@MainActor private final class TodoContainer {
    let store: TodoStore

    var todoID: Todo.ID

    init(store: TodoStore, todoID: Todo.ID) {
        self.store = store
        self.todoID = todoID
    }

    var scope: TodoScope {
        let todo = store.todo(id: todoID)

        return TodoScope(
            delete: .constant(delete),
            isCompleted: .observation(todo, \.isCompleted),
            title: .observation(todo, \.title)
        )
    }

    func update(todoID: Todo.ID) {
        self.todoID = todoID
    }

    func delete() {
        store.delete(id: todoID)
    }
}

struct SampleAppScopePreviewModifier: PreviewModifier {
    static func makeSharedContext() -> AppContainer {
        AppContainer()
    }

    func body(content: Content, context: AppContainer) -> some View {
        content
            .container(context, scope: \.appScope)
    }
}

struct EmptyAppScopePreviewModifier: PreviewModifier {
    static func makeSharedContext() -> AppContainer {
        AppContainer(todos: [])
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

    static var emptyAppScope: Self {
        .modifier(EmptyAppScopePreviewModifier())
    }
}
