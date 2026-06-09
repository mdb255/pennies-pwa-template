import { Route, Redirect, Switch } from 'react-router-dom'
import { IonRouterOutlet } from '@ionic/react'
import { useSelector } from 'react-redux'
import LoginScreen from '../../components/login-screen/login-screen'
import SignUpScreen from '../../components/sign-up-screen/sign-up-screen'
import TabsLayout from '../../components/routing/tabs-layout'
import { accessRoute } from '../../components/routing/access-route'
import { RootState } from '../../rtk/store'

function Router() {
    const { isAuthenticated } = useSelector((state: RootState) => state.auth)

    return (
        <IonRouterOutlet>
            <Switch>
                <Route
                    exact
                    path="/"
                    render={() =>
                        isAuthenticated ? (
                            <Redirect to="/todos" />
                        ) : (
                            <Redirect to="/login" />
                        )
                    }
                />
                {accessRoute({ path: '/login', exact: true, access: 'anonymous', element: <LoginScreen /> })}
                {accessRoute({ path: '/sign-up', exact: true, access: 'anonymous', element: <SignUpScreen /> })}
                <Route path="/" render={() => <TabsLayout />} />
            </Switch>
        </IonRouterOutlet>
    )
}

export default Router
