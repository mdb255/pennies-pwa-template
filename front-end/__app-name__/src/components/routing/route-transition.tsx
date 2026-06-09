import { ReactNode, useEffect, useRef } from 'react'
import { useLocation } from 'react-router-dom'

interface RouteTransitionProps {
    children: ReactNode
    /**
     * Stable key for this route (e.g. path). Use in tabs so multiple mounted
     * routes don't all use current pathname and collide.
     */
    routeKey?: string
}

/**
 * Wrapper component that applies fade transition on route changes
 */
export function RouteTransition({ children, routeKey }: RouteTransitionProps) {
    const location = useLocation()
    const key = routeKey ?? location.pathname
    const isTab = routeKey !== undefined
    const isActive = isTab && location.pathname === routeKey
    const animRef = useRef<HTMLDivElement>(null)
    const hasAnimatedOnce = useRef(false)

    useEffect(() => {
        if (!isTab || !isActive) return
        const el = animRef.current
        if (!el) return
        if (!hasAnimatedOnce.current) {
            hasAnimatedOnce.current = true
            return
        }
        el.classList.remove('route-transition-enter')
        const raf = requestAnimationFrame(() => {
            el.classList.add('route-transition-enter')
        })
        return () => cancelAnimationFrame(raf)
    }, [isTab, isActive])

    if (isTab) {
        return (
            <div key={key}>
                <div
                    ref={animRef}
                    className={isActive ? 'route-transition-enter' : ''}
                >
                    {children}
                </div>
            </div>
        )
    }

    return (
        <div key={key} className="route-transition">
            {children}
        </div>
    )
}
