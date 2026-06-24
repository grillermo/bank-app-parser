import { Link } from "@inertiajs/react"

export default function Layout({ children }) {
  return (
    <div>
      <header className="border-b px-4 sm:px-6 py-4 flex gap-4 sm:gap-6">
        <Link href="/" className="font-semibold hover:underline">Dashboard</Link>
        <Link href="/transactions" className="font-semibold hover:underline">Transactions</Link>
      </header>
      {children}
    </div>
  )
}
