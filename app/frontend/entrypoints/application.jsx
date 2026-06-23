import { createInertiaApp } from "@inertiajs/react"
import { createRoot } from "react-dom/client"
import "../styles/application.css"

createInertiaApp({
  resolve: (name) => {
    const pages = import.meta.glob("../pages/**/*.jsx", { eager: true })
    const page = pages[`../pages/${name}.jsx`]

    if (!page) {
      throw new Error(`Missing Inertia page: ${name}`)
    }

    return page.default
  },
  setup({ el, App, props }) {
    createRoot(el).render(<App {...props} />)
  },
})
