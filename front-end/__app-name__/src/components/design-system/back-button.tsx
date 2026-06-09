import { IonButton, IonIcon, useIonRouter } from '@ionic/react'
import { arrowBack } from 'ionicons/icons'

interface BackButtonProps {
    tooltip?: string
    onClick?: () => void
}

function BackButton({ tooltip = 'Go back', onClick }: BackButtonProps) {
    const ionRouter = useIonRouter()

    const handleClick = () => {
        if (onClick) {
            onClick()
        } else {
            ionRouter.goBack()
        }
    }

    return (
        <IonButton
            fill="clear"
            color="light"
            onClick={handleClick}
            aria-label={tooltip}
        >
            <IonIcon icon={arrowBack} slot="start" />
        </IonButton>
    )
}

export default BackButton
