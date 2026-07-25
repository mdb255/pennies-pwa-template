import { useState } from 'react'
import {
    IonPage,
    IonContent,
    IonSpinner,
    IonText,
    IonButton,
    IonIcon,
    IonList,
    IonItemSliding,
    IonItemOptions,
    IonItemOption,
} from '@ionic/react'
import { add } from 'ionicons/icons'
import TopNavBar from '../design-system/top-nav-bar'
import TodoItem from './todo-item'
import EditTodoDialog from './edit-todo-dialog'
import DeleteConfirmDialog from '../reusable/delete-confirm-dialog'
import { dataApi } from '../../rtk/data-api'
import type { Todo } from '../../rtk/todos/todo-model'
import { APP_MENU_ID } from '../routing/app-menu-id'

function TodosScreen() {
    const { data: todos, isLoading, error } = dataApi.useGetTodosQuery({})
    const [updateTodo] = dataApi.useUpdateTodoMutation()
    const [deleteTodo] = dataApi.useDeleteTodoMutation()

    const [editDialogOpen, setEditDialogOpen] = useState(false)
    const [todoIdToEdit, setTodoIdToEdit] = useState<number | undefined>(undefined)
    const [deleteDialogOpen, setDeleteDialogOpen] = useState(false)
    const [todoToDelete, setTodoToDelete] = useState<Todo | undefined>(undefined)

    const handleAdd = () => {
        setTodoIdToEdit(undefined)
        setEditDialogOpen(true)
    }

    const handleEdit = (todo: Todo) => {
        setTodoIdToEdit(todo.id)
        setEditDialogOpen(true)
    }

    const handleToggle = async (todo: Todo) => {
        try {
            await updateTodo({ id: todo.id, updates: { is_completed: !todo.is_completed } }).unwrap()
        } catch (err) {
            console.error('Failed to toggle todo:', err)
        }
    }

    const handleDeleteRequest = (todo: Todo) => {
        setTodoToDelete(todo)
        setDeleteDialogOpen(true)
    }

    const handleConfirmDelete = async () => {
        if (todoToDelete) {
            try {
                await deleteTodo(todoToDelete.id).unwrap()
                setDeleteDialogOpen(false)
                setTodoToDelete(undefined)
            } catch (err) {
                console.error('Failed to delete todo:', err)
            }
        }
    }

    return (
        <IonPage>
            <TopNavBar title="Todos" showBackButton={false} menuId={APP_MENU_ID}>
                <IonButton fill="clear" color="light" onClick={handleAdd} aria-label="add todo">
                    <IonIcon icon={add} />
                </IonButton>
            </TopNavBar>
            <IonContent>
                {isLoading && (
                    <div className="flex justify-center py-8">
                        <IonSpinner name="crescent" />
                    </div>
                )}

                {error && (
                    <IonText color="danger" className="block ion-padding mt-4">
                        <p>Failed to load todos. Please try again.</p>
                    </IonText>
                )}

                {!isLoading && !error && todos?.length === 0 && (
                    <div className="text-center py-8 ion-padding text-secondary">
                        <p>No todos yet. Tap + to add your first one.</p>
                    </div>
                )}

                {!isLoading && !error && todos && todos.length > 0 && (
                    <IonList>
                        {todos.map((todo) => (
                            <IonItemSliding key={todo.id}>
                                <TodoItem
                                    todo={todo}
                                    onToggle={handleToggle}
                                    onEdit={handleEdit}
                                />
                                <IonItemOptions side="end">
                                    <IonItemOption color="danger" onClick={() => handleDeleteRequest(todo)}>
                                        Delete
                                    </IonItemOption>
                                </IonItemOptions>
                            </IonItemSliding>
                        ))}
                    </IonList>
                )}
            </IonContent>

            <EditTodoDialog
                open={editDialogOpen}
                todoId={todoIdToEdit}
                onClose={() => {
                    setEditDialogOpen(false)
                    setTodoIdToEdit(undefined)
                }}
            />

            <DeleteConfirmDialog
                open={deleteDialogOpen}
                itemName={todoToDelete?.title || ''}
                itemType="Todo"
                onConfirm={handleConfirmDelete}
                onCancel={() => {
                    setDeleteDialogOpen(false)
                    setTodoToDelete(undefined)
                }}
            />
        </IonPage>
    )
}

export default TodosScreen
