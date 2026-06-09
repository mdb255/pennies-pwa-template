import { IonApp } from '@ionic/react'
import Router from './modules/router/router.tsx'
import PWABadge from './PWABadge.tsx'
import AuthInitializer from './components/auth-initializer/auth-initializer'

function App() {
    return (
        <IonApp>
            <AuthInitializer>
                <Router />
            </AuthInitializer>
            <PWABadge />
        </IonApp>
    )
}

export default App
