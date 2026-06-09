import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { IonReactRouter } from '@ionic/react-router'
import { Provider } from 'react-redux'
import { setupIonicReact } from '@ionic/react'
import App from './app'
import { store } from './rtk/store'
import './styling/ionic-base.css'
import './styling/ionic-theme.css'
import './styling/index.css'
import './styling/custom-styles.css'

setupIonicReact({
    mode: 'ios',
})

createRoot(document.getElementById('root')!).render(
    <StrictMode>
        <Provider store={store}>
            <IonReactRouter>
                <App />
            </IonReactRouter>
        </Provider>
    </StrictMode>,
)
