import { useState, useEffect } from 'react'
import {
    IonModal,
    IonHeader,
    IonToolbar,
    IonTitle,
    IonContent,
    IonItem,
    IonInput,
    IonTextarea,
    IonLabel,
    IonButton,
    IonSpinner,
    IonButtons,
} from '@ionic/react'
import { appApi } from '../../rtk/app-api'
import type { TodoCreate, TodoUpdate } from '../../rtk/todos/todo-model'
import BackButton from '../design-system/back-button'
import ConfirmCloseDialog from '../reusable/confirm-close-dialog'

interface EditTodoDialogProps {
    open: boolean
    todoId?: number
    onClose: () => void
}

function EditTodoDialog({ open, todoId, onClose }: EditTodoDialogProps) {
    const isEditMode = todoId !== undefined

    const { data: todo, isLoading: isLoadingTodo } = appApi.useGetTodoQuery(todoId!, {
        skip: !isEditMode,
    })
    const [createTodo, { isLoading: isCreating }] = appApi.useCreateTodoMutation()
    const [updateTodo, { isLoading: isUpdating }] = appApi.useUpdateTodoMutation()

    const [title, setTitle] = useState('')
    const [description, setDescription] = useState('')
    const [isDirty, setIsDirty] = useState(false)
    const [showConfirmClose, setShowConfirmClose] = useState(false)

    useEffect(() => {
        if (open) {
            if (isEditMode && todo) {
                setTitle(todo.title)
                setDescription(todo.description || '')
                setIsDirty(false)
            } else if (!isEditMode) {
                setTitle('')
                setDescription('')
                setIsDirty(false)
            }
        }
    }, [open, isEditMode, todo])

    const handleClose = () => {
        if (isDirty) {
            setShowConfirmClose(true)
        } else {
            onClose()
        }
    }

    const handleConfirmClose = () => {
        setShowConfirmClose(false)
        setIsDirty(false)
        onClose()
    }

    const handleSubmit = async () => {
        try {
            if (isEditMode) {
                const updates: TodoUpdate = {
                    title: title.trim(),
                    description: description.trim() || null,
                }
                await updateTodo({ id: todoId, updates }).unwrap()
            } else {
                const data: TodoCreate = {
                    title: title.trim(),
                    description: description.trim() || null,
                }
                await createTodo(data).unwrap()
            }
            setIsDirty(false)
            onClose()
        } catch (err) {
            console.error('Failed to save todo:', err)
        }
    }

    const isLoading = isLoadingTodo || isCreating || isUpdating
    const canSubmit = title.trim() !== '' && !isLoading

    return (
        <>
            <IonModal isOpen={open} onDidDismiss={handleClose}>
                <IonHeader>
                    <IonToolbar>
                        <IonButtons slot="start">
                            <BackButton onClick={handleClose} tooltip="Cancel" />
                        </IonButtons>
                        <IonTitle className="ion-text-start">{isEditMode ? 'Edit Todo' : 'New Todo'}</IonTitle>
                        <IonButtons slot="end">
                            <IonButton onClick={handleSubmit} disabled={!canSubmit}>
                                {isLoading ? <IonSpinner name="crescent" /> : isEditMode ? 'Save' : 'Create'}
                            </IonButton>
                        </IonButtons>
                    </IonToolbar>
                </IonHeader>
                <IonContent className="ion-padding">
                    {isLoadingTodo ? (
                        <div className="flex justify-center items-center py-12">
                            <IonSpinner name="crescent" />
                        </div>
                    ) : (
                        <div className="flex flex-col gap-3 pt-2">
                            <IonItem>
                                <IonLabel position="stacked">Title *</IonLabel>
                                <IonInput
                                    value={title}
                                    onIonInput={(e) => {
                                        setTitle((e.target as HTMLIonInputElement).value as string ?? '')
                                        setIsDirty(true)
                                    }}
                                    required
                                    autofocus
                                />
                            </IonItem>
                            <IonItem>
                                <IonLabel position="stacked">Description</IonLabel>
                                <IonTextarea
                                    value={description}
                                    onIonInput={(e) => {
                                        setDescription((e.target as HTMLIonTextareaElement).value as string ?? '')
                                        setIsDirty(true)
                                    }}
                                    rows={4}
                                />
                            </IonItem>
                        </div>
                    )}
                </IonContent>
            </IonModal>

            <ConfirmCloseDialog
                open={showConfirmClose}
                onConfirm={handleConfirmClose}
                onCancel={() => setShowConfirmClose(false)}
            />
        </>
    )
}

export default EditTodoDialog
