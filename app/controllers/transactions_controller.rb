class TransactionsController < ApplicationController
  PER_PAGE = 50
  CLASSIFIABLE = %w[posted canceled].freeze

  def index
    render inertia: "Transactions", props: page_props(Transaction.all)
  end

  def pending
    render inertia: "Pending", props: page_props(Transaction.pending)
  end

  def update
    transaction = Transaction.find(params[:id])
    status = params[:status].to_s
    return head :unprocessable_content unless CLASSIFIABLE.include?(status)

    transaction.update!(status: status)
    redirect_to "/pending"
  end

  private

  def page_props(base)
    scope = base.order(id: :desc)
    scope = scope.where("id < ?", params[:cursor]) if params[:cursor].present?
    transactions = scope.limit(PER_PAGE).to_a
    {
      transactions: transactions.map { |t| transaction_json(t) },
      next_cursor: transactions.size == PER_PAGE ? transactions.last.id : nil
    }
  end

  def transaction_json(t)
    {
      id: t.id, date: t.date.to_s, description: t.description, merchant: t.merchant,
      category: t.category, bank_name: t.bank_name, cardname: t.cardname,
      amount: t.amount.to_f, status: t.status
    }
  end
end
