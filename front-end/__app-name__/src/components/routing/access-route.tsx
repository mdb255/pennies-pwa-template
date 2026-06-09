import { Route, Redirect } from 'react-router-dom'
import { useSelector } from 'react-redux'
import { IonSpinner } from '@ionic/react'
import { RootState } from '../../rtk/store'
import { ReactElement, ReactNode } from 'react'

type AccessMode = 'authenticated' | 'anonymous'

type AccessRouteConfig = {
    path?: string
    exact?: boolean
    element?: ReactNode
    children?: ReactNode
    access?: AccessMode
}

// Factory function that returns a guarded <Route> element
export function accessRoute({ access = 'authenticated', element, children, ...rest }: AccessRouteConfig): ReactElement {
    function Guarded(): ReactElement {
        const { isAuthenticated, isInitialized } = useSelector((state: RootState) => state.auth)
        const content = element ?? children

        if (!isInitialized) {
            return (
                <div className="flex justify-center items-center min-h-screen">
                    <IonSpinner name="crescent" />
                </div>
            ) as ReactElement
        }

        if (access === 'authenticated' && !isAuthenticated) {
            return <Redirect to="/login" /> as ReactElement
        }
        if (access === 'anonymous' && isAuthenticated) {
            return <Redirect to="/welcome" /> as ReactElement
        }
        return <>{content}</> as ReactElement
    }

    return <Route {...rest} render={() => <Guarded />} />
}

export type { AccessRouteConfig, AccessMode }
