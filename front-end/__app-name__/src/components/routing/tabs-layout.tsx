import { Route, Redirect, useLocation, useHistory } from 'react-router-dom'
import { useDispatch } from 'react-redux'
import {
    IonRouterOutlet,
    IonTabs,
    IonTabBar,
    IonTabButton,
    IonIcon,
    IonLabel,
    IonMenu,
    IonContent,
    IonList,
    IonItem,
    IonHeader,
    IonToolbar,
} from '@ionic/react'
import { home, homeOutline, checkboxOutline, checkbox, power } from 'ionicons/icons'
import WelcomeScreen from '../welcome-screen/welcome-screen'
import TodosScreen from '../todos-screen/todos-screen'
import { RouteTransition } from './route-transition'
import { clearAuth } from '../../rtk/auth/auth-slice'
import { authApi } from '../../rtk/auth-api'
import { APP_MENU_ID } from './app-menu-id'

const TABS_CONTENT_ID = 'tabs-content'

function TabsLayout() {
    const location = useLocation()
    const history = useHistory()
    const dispatch = useDispatch()
    const [logoutTrigger] = authApi.useLogoutMutation()

    const handleLogout = async () => {
        try {
            await logoutTrigger().unwrap()
        } catch {
            // proceed to clear auth regardless
        } finally {
            dispatch(clearAuth())
            history.push('/login')
        }
    }

    return (
        <>
            <IonMenu
                contentId={TABS_CONTENT_ID}
                menuId={APP_MENU_ID}
                type="overlay"
                side="start"
            >
                <IonHeader>
                    <IonToolbar />
                </IonHeader>
                <IonContent>
                    <IonList lines="none" className="py-2">
                        <IonItem button onClick={handleLogout} detail={false}>
                            <IonIcon
                                icon={power}
                                slot="start"
                                className="text-[20px] shrink-0 me-3 w-5 h-5"
                            />
                            <IonLabel>Log Out</IonLabel>
                        </IonItem>
                    </IonList>
                </IonContent>
            </IonMenu>
            <IonTabs>
                <IonRouterOutlet id={TABS_CONTENT_ID}>
                    <Redirect exact path="/" to="/todos" />
                    <Route
                        exact
                        path="/todos"
                        render={() => (
                            <RouteTransition routeKey="/todos">
                                <TodosScreen />
                            </RouteTransition>
                        )}
                    />
                    <Route
                        exact
                        path="/welcome"
                        render={() => (
                            <RouteTransition routeKey="/welcome">
                                <WelcomeScreen />
                            </RouteTransition>
                        )}
                    />
                </IonRouterOutlet>
                <IonTabBar slot="bottom">
                    <IonTabButton tab="todos" href="/todos">
                        <IonIcon icon={location.pathname === '/todos' ? checkbox : checkboxOutline} />
                        <IonLabel>Todos</IonLabel>
                    </IonTabButton>
                    <IonTabButton tab="home" href="/welcome">
                        <IonIcon icon={location.pathname === '/welcome' ? home : homeOutline} />
                        <IonLabel>Home</IonLabel>
                    </IonTabButton>
                </IonTabBar>
            </IonTabs>
        </>
    )
}

export default TabsLayout
