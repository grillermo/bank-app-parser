import { useState } from "react"
import { router } from "@inertiajs/react"
import Layout from "../components/Layout"

export default function Transactions({ transactions, next_cursor }) {
  const [rows, setRows] = useState(transactions)
  const [cursor, setCursor] = useState(next_cursor)
  const [loading, setLoading] = useState(false)

  const loadMore = () => {
    setLoading(true)
    router.get("/transactions", { cursor }, {
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

  return (
    <Layout>
      <div className="mx-auto max-w-5xl p-6 space-y-4">
        <h1 className="text-2xl font-bold">Transactions</h1>

        <table className="w-full text-sm border-collapse">
          <thead>
            <tr className="border-b text-left">
              <th className="py-1 pr-2">Date</th>
              <th className="py-1 pr-2">Description</th>
              <th className="py-1 pr-2">Merchant</th>
              <th className="py-1 pr-2">Category</th>
              <th className="py-1 pr-2">Bank</th>
              <th className="py-1 pr-2">Card</th>
              <th className="py-1 pr-2 text-right">Amount</th>
            </tr>
          </thead>
          <tbody>
            {rows.map((t) => (
              <tr key={t.id} className="border-b">
                <td className="py-1 pr-2">{t.date}</td>
                <td className="py-1 pr-2">{t.description}</td>
                <td className="py-1 pr-2">{t.merchant}</td>
                <td className="py-1 pr-2">{t.category}</td>
                <td className="py-1 pr-2">{t.bank_name}</td>
                <td className="py-1 pr-2">{t.cardname}</td>
                <td className="py-1 pr-2 text-right font-mono">{t.amount.toFixed(2)}</td>
              </tr>
            ))}
          </tbody>
        </table>

        {cursor && (
          <button
            onClick={loadMore}
            disabled={loading}
            className="rounded bg-blue-600 px-4 py-2 text-white disabled:opacity-50"
          >
            {loading ? "Loading..." : "Load more"}
          </button>
        )}
      </div>
    </Layout>
  )
}
