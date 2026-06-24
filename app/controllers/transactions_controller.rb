class TransactionsController < ApplicationController
  PER_PAGE = 50

  def index
    scope = Transaction.order(id: :desc)
    scope = scope.where("id < ?", params[:cursor]) if params[:cursor].present?
    transactions = scope.limit(PER_PAGE).to_a

    render inertia: "Transactions", props: {
      transactions: transactions.map { |t| transaction_json(t) },
      next_cursor: transactions.size == PER_PAGE ? transactions.last.id : nil
    }
  end

  private

  def transaction_json(t)
    {
      id: t.id, date: t.date.to_s, description: t.description, merchant: t.merchant,
      category: t.category, bank_name: t.bank_name, cardname: t.cardname, amount: t.amount.to_f
    }
  end
end
