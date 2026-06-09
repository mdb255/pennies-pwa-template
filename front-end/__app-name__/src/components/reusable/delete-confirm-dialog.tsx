import OsIonAlert from '../design-system/os-ion-alert'

interface DeleteConfirmDialogProps {
    open: boolean
    itemName: string
    itemType?: string
    onConfirm: () => void
    onCancel: () => void
}

function DeleteConfirmDialog({
    open,
    itemName,
    itemType = 'item',
    onConfirm,
    onCancel,
}: DeleteConfirmDialogProps) {
    return (
        <OsIonAlert
            isOpen={open}
            onDidDismiss={() => onCancel()}
            header={`Delete ${itemType}?`}
            message={`Are you sure you want to delete ${itemName || 'this item'}? This action cannot be undone.`}
            buttons={[
                { text: 'Cancel', role: 'cancel', handler: () => onCancel() },
                { text: 'Delete', role: 'destructive', handler: () => onConfirm() },
            ]}
        />
    )
}

export default DeleteConfirmDialog
