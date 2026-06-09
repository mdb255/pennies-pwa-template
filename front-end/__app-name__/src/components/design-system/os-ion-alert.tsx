import { IonAlert, isPlatform } from '@ionic/react'
import type { ComponentProps } from 'react'

const ALERT_BUTTONS_NORMAL_CLASS = 'os-alert-buttons-normal'

type IonAlertProps = ComponentProps<typeof IonAlert>

interface OsIonAlertProps extends Omit<IonAlertProps, 'mode' | 'cssClass'> {
    mode?: IonAlertProps['mode']
    cssClass?: string
}

function OsIonAlert({ mode, cssClass, ...rest }: OsIonAlertProps) {
    const resolvedMode = isPlatform('android') ? 'md' : mode
    const resolvedCssClass = [ALERT_BUTTONS_NORMAL_CLASS, cssClass].filter(Boolean).join(' ')

    return (
        <IonAlert
            {...rest}
            mode={resolvedMode}
            cssClass={resolvedCssClass || undefined}
        />
    )
}

export default OsIonAlert
