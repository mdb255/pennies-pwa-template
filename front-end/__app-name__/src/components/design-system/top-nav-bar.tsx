import { IonHeader, IonToolbar, IonTitle, IonButtons, IonButton, IonMenuToggle, IonIcon } from '@ionic/react'
import { ReactNode } from 'react'
import { menu } from 'ionicons/icons'
import BackButton from './back-button'

interface TopNavBarProps {
    children?: ReactNode
    showBackButton?: boolean
    /** Menu id for hamburger trigger (tab landing screens). Shown on the left when showBackButton is false. */
    menuId?: string
    /** Left-aligned title (e.g. for tab landing screens). Shown to the right of the menu button when present. */
    title?: ReactNode
    startContent?: ReactNode
}

function TopNavBar({
    children,
    showBackButton = true,
    menuId,
    title,
    startContent,
}: TopNavBarProps) {
    const hasStartContent = showBackButton || !!menuId || (!!startContent && !title)
    const startSlotContent = showBackButton ? (
        <BackButton />
    ) : menuId ? (
        <IonMenuToggle menu={menuId}>
            <IonButton
                fill="clear"
                color="light"
                aria-label="Menu"
            >
                <IonIcon icon={menu} />
            </IonButton>
        </IonMenuToggle>
    ) : startContent && !title ? (
        startContent
    ) : null
    return (
        <IonHeader>
            <IonToolbar className={!hasStartContent ? 'toolbar-no-start' : undefined}>
                {hasStartContent && (
                    <IonButtons slot="start" className="gap-1 items-center">
                        {startSlotContent}
                    </IonButtons>
                )}
                {title != null && title !== '' && (
                    <IonTitle className="ion-text-start">{title}</IonTitle>
                )}
                {children && (
                    <IonButtons slot="end" className="flex items-center gap-1">
                        {children}
                    </IonButtons>
                )}
            </IonToolbar>
        </IonHeader>
    )
}

export default TopNavBar
