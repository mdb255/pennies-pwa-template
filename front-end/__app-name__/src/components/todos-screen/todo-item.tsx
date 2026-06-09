import { IonItem, IonCheckbox, IonLabel } from '@ionic/react'
import type { Todo } from '../../rtk/todos/todo-model'

interface TodoItemProps {
    todo: Todo
    onToggle: (todo: Todo) => void
    onEdit: (todo: Todo) => void
}

function TodoItem({ todo, onToggle, onEdit }: TodoItemProps) {
    return (
        <IonItem button onClick={() => onEdit(todo)} detail={false}>
            <IonCheckbox
                slot="start"
                checked={todo.is_completed}
                onClick={(e) => {
                    e.stopPropagation()
                    onToggle(todo)
                }}
            />
            <IonLabel className={todo.is_completed ? 'line-through opacity-50' : ''}>
                <h2>{todo.title}</h2>
                {todo.description && (
                    <p className="text-sm">{todo.description}</p>
                )}
            </IonLabel>
        </IonItem>
    )
}

export default TodoItem
