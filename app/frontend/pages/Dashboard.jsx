import { Chart as ChartJS, ArcElement, BarElement, CategoryScale, LinearScale, Tooltip, Legend } from "chart.js"
import { Pie, Bar } from "react-chartjs-2"
import Layout from "../components/Layout"

ChartJS.register(ArcElement, BarElement, CategoryScale, LinearScale, Tooltip, Legend)

const COLORS = ["#2563eb", "#16a34a", "#dc2626", "#d97706", "#7c3aed", "#0891b2"]

export default function Dashboard({ top_categories, top_merchants, largest_purchases, category_timeseries }) {
  const pieData = {
    labels: top_categories.map((c) => `${c.category} (${c.percentage}%)`),
    datasets: [{ data: top_categories.map((c) => c.total), backgroundColor: COLORS }],
  }
  const merchantData = {
    labels: top_merchants.map((m) => m.merchant),
    datasets: [{ label: "Spend", data: top_merchants.map((m) => m.total), backgroundColor: COLORS[0] }],
  }
  const tsData = {
    labels: category_timeseries.months,
    datasets: category_timeseries.series.map((s, i) => ({
      label: s.category, data: s.data, backgroundColor: COLORS[i % COLORS.length],
    })),
  }
  const base = { responsive: true, maintainAspectRatio: false }
  const stacked = { ...base, scales: { x: { stacked: true }, y: { stacked: true } } }

  return (
    <Layout>
    <div className="mx-auto max-w-5xl px-4 py-6 sm:p-6 space-y-8 sm:space-y-10">
      <h1 className="text-xl sm:text-2xl font-bold">Spending Overview</h1>

      <section>
        <h2 className="mb-2 font-semibold">Top Categories</h2>
        <div className="relative w-full h-72 sm:h-96"><Pie data={pieData} options={base} /></div>
      </section>

      <section>
        <h2 className="mb-2 font-semibold">Top Merchants</h2>
        <div className="relative w-full h-72 sm:h-96"><Bar data={merchantData} options={base} /></div>
      </section>

      <section>
        <h2 className="mb-2 font-semibold">Largest Purchases</h2>
        <ul className="divide-y">
          {largest_purchases.map((p, i) => (
            <li key={i} className="flex justify-between gap-2 py-1 text-sm sm:text-base">
              <span className="truncate">{p.date} — {p.merchant}</span>
              <span className="font-mono shrink-0">{Math.abs(p.amount).toFixed(2)}</span>
            </li>
          ))}
        </ul>
      </section>

      <section>
        <h2 className="mb-2 font-semibold">Spend by Category Over Time</h2>
        <div className="relative w-full h-80 sm:h-96"><Bar data={tsData} options={stacked} /></div>
      </section>
    </div>
    </Layout>
  )
}
