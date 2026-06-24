class DashboardStats
  def initialize(scope = Transaction.all)
    @spend = scope.where("amount < 0").posted
  end

  def to_h
    {
      top_categories: top_categories,
      top_merchants: top_merchants,
      largest_purchases: largest_purchases,
      category_timeseries: category_timeseries
    }
  end

  private

  def total_spend
    @total_spend ||= @spend.sum("ABS(amount)").to_f
  end

  def top_categories
    @spend.group(:category).sum("ABS(amount)").sort_by { |_, v| -v }.first(5).map do |category, total|
      pct = total_spend.zero? ? 0.0 : (total.to_f / total_spend * 100).round(2)
      { category: category, total: total.to_f, percentage: pct }
    end
  end

  def top_merchants
    @spend.group(:merchant).sum("ABS(amount)").sort_by { |_, v| -v }.first(5).map do |merchant, total|
      { merchant: merchant, total: total.to_f }
    end
  end

  def largest_purchases
    @spend.order(:amount).limit(5).map do |t|
      { date: t.date.to_s, merchant: t.merchant, amount: t.amount.to_f }
    end
  end

  def category_timeseries
    rows = @spend.group(Arel.sql("to_char(date, 'YYYY-MM')"), :category).sum("ABS(amount)")
    months = rows.keys.map(&:first).uniq.sort
    categories = rows.keys.map(&:last).uniq
    series = categories.map do |category|
      data = months.map { |m| (rows[[m, category]] || 0).to_f }
      { category: category, data: data }
    end
    { months: months, series: series }
  end
end
