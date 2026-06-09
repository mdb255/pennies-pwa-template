import { useSelector } from 'react-redux'
import { IonPage, IonContent } from '@ionic/react'
import TopNavBar from '../design-system/top-nav-bar'
import { APP_MENU_ID } from '../routing/app-menu-id'
import { RootState } from '../../rtk/store'

function WelcomeScreen() {
    const { email } = useSelector((state: RootState) => state.auth)

    return (
        <IonPage>
            <TopNavBar showBackButton={false} menuId={APP_MENU_ID} title="Home" />
            <IonContent className="ion-padding">
                <div className="flex flex-col items-center justify-center h-full gap-6">
                    <div className="text-center max-w-sm">
                        <h1 className="text-3xl font-semibold mb-2">Welcome</h1>
                        {email && (
                            <p className="text-secondary">{email}</p>
                        )}
                    </div>
                </div>
            </IonContent>
        </IonPage>
    )
}

export default WelcomeScreen
