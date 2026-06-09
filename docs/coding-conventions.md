# Coding Conventions

## Frontend
- All components go under src/components
- Each component has its own folder to accommodate unit tests
- Components are named using dash case (e.g. slideshow-admin.tsx)
- Ionic 8 is used for UI components (IonButton, IonInput, IonModal, etc.)
- Styling is done with Tailwind CSS utility classes (theme bridge to Ionic CSS variables)
- Use className with Tailwind utilities (e.g. className="bg-primary text-white p-4") for layout and colors
