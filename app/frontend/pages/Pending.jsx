import { useState } from "react"
import { router } from "@inertiajs/react"
import Layout from "../components/Layout"

export default function Pending({ transactions, next_cursor }) {
  const [rows, setRows] = useState(transactions)
  const [cursor, setCursor] = useState(next_cursor)
  const [loading, setLoading] = useState(false)

  const classify = (id, status) => {
    router.patch(`/transactions/${id}`, { status }, {
      preserveScroll: true,
      onSuccess: () => setRows((prev) => prev.filter((t) => t.id !== id)),
    })
  }

  const loadMore = () => {
    setLoading(true)
    router.get("/pending", { cursor }, {
      preserveState: true,
      preserveScroll: true,
      only: ["transactions", "next_cursor"],
      onSuccess: (page) => {
        setRows((prev) => [...prev, ...page.props.transactions])
        setCursor(page.props.next_cursor)
        setLoading(false)
      },
    })
  }

  const Actions = ({ t }) => (
    <span className="flex gap-2">
      <button onClick={() => classify(t.id, "posted")}
        className="rounded bg-green-600 px-2 py-1 text-xs text-white">Posted</button>
      <button onClick={() => classify(t.id, "canceled")}
        className="rounded bg-red-600 px-2 py-1 text-xs text-white">Canceled</button>
    </span>
  )

  return (
    <Layout>
      <div className="mx-auto max-w-5xl px-4 py-6 sm:p-6 space-y-4">
        <h1 className="text-xl sm:text-2xl font-bold">Pending</h1>

        {rows.length === 0 && <p className="text-gray-500">Nothing pending.</p>}

        {/* Mobile: stacked cards */}
        <ul className="space-y-3 sm:hidden">
          {rows.map((t) => (
            <li key={t.id} className="rounded border p-3 space-y-2">
              <div className="flex justify-between gap-2">
                <span className="font-medium truncate">{t.merchant || t.description}</span>
                <span className="font-mono shrink-0">{t.amount.toFixed(2)}</span>
              </div>
              <div className="text-xs text-gray-500">{t.date} · {t.category}</div>
              <Actions t={t} />
            </li>
          ))}
        </ul>

        {/* Desktop: table */}
        <table className="hidden sm:table w-full text-sm border-collapse">
          <thead>
            <tr className="border-b text-left">
              <th className="py-1 pr-2">Date</th>
              <th className="py-1 pr-2">Description</th>
              <th className="py-1 pr-2">Merchant</th>
              <th className="py-1 pr-2">Category</th>
              <th className="py-1 pr-2 text-right">Amount</th>
              <th className="py-1 pr-2">Classify</th>
            </tr>
          </thead>
          <tbody>
            {rows.map((t) => (
              <tr key={t.id} className="border-b">
                <td className="py-1 pr-2">{t.date}</td>
                <td className="py-1 pr-2">{t.description}</td>
                <td className="py-1 pr-2">{t.merchant}</td>
                <td className="py-1 pr-2">{t.category}</td>
                <td className="py-1 pr-2 text-right font-mono">{t.amount.toFixed(2)}</td>
                <td className="py-1 pr-2"><Actions t={t} /></td>
              </tr>
            ))}
          </tbody>
        </table>

        {cursor && (
          <button onClick={loadMore} disabled={loading}
            className="rounded bg-blue-600 px-4 py-2 text-white disabled:opacity-50">
            {loading ? "Loading..." : "Load more"}
          </button>
        )}
      </div>
    </Layout>
  )
}
