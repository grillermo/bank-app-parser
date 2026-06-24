# Transaction Status: debit/credit + cancelable transactions

**Date:** 2026-06-23
**Status:** Approved design

## Problem

The app assumed every transaction is a charge. That is no longer true:

- A transaction can be money **spent** (debit, `amount < 0`) or money **received** (credit, `amount > 0`).
- A transaction can be **canceled** (reversed / voided / refunded).
- A transaction can be **pending** (not yet cleared) before it is **posted**.

The dashboard cares only about spending: posted debits.

## Decisions

- **Direction** stays encoded by the amount sign (negative = spent, positive = received). No direction column.
- **Status** is a new enum column: `pending`, `posted`, `canceled`.
- Ambiguous / unreadable status from OCR defaults to `pending`.
- A new `/pending` view lets the user classify pending transactions as posted or canceled.

## 1. Schema + model

Migration:

```ruby
add_column :transactions, :status, :integer, null: false, default: 0
# backfill existing rows to posted (they were all charges)
execute "UPDATE transactions SET status = 1"
add_index :transactions, :status
```

`default: 0` (`pending`) matches the ambiguous-defaults-to-pending rule for any future direct creates. Existing rows are backfilled to `posted`.

Model (`app/models/transaction.rb`):

```ruby
enum :status, { pending: 0, posted: 1, canceled: 2 }
```

Provides scopes `Transaction.pending`/`.posted`/`.canceled` and predicates `t.pending?` etc.

## 2. OCR extraction + import

`OcrClient::PROMPT` — add a `status` field to the output spec:

- `"status"`: one of `pending`, `posted`, `canceled`.
  - `canceled` if the UI marks the row canceled / reversed / voided / refunded.
  - `posted` if the row is clearly cleared / charged / settled.
  - `pending` if the row is marked processing/pending, OR if status is ambiguous or unreadable (default).

`TransactionImporter`:

- Add `"status"` to `PERMITTED`.
- Coerce any value not in `%w[pending posted canceled]` (including blank) to `"pending"` before passing to `dedup_create!`.

## 3. Deduplication with forward-only status promotion

Dedup key is unchanged: `description`, `bank_name`, `date`, `amount`.

The enum integers are intentionally ordered by finality: `pending(0) < posted(1) < canceled(2)`.

`Transaction.dedup_create!(batch:, attrs:)`:

1. Find existing matching row (same dedup key) within the batch.
2. If found:
   - Compare incoming status int vs existing status int.
   - If `incoming > existing`, `existing.update!(status: incoming)` (forward promotion: pending→posted, pending/posted→canceled).
   - Never regress (e.g. posted→pending is ignored).
   - Return `nil` (not counted as a newly created row).
3. If not found, create as today.

## 4. Dashboard

`DashboardStats#initialize`:

```ruby
@spend = scope.where("amount < 0").posted
```

Excludes credits (sign), pending, and canceled. All aggregations (top categories, top merchants, largest purchases, timeseries) inherit the filter.

## 5. `/pending` classify view

Routes (`config/routes.rb`):

```ruby
get   "/pending",          to: "transactions#pending"
patch "/transactions/:id", to: "transactions#update"
```

`TransactionsController`:

- `pending` — cursor-paginated list of `Transaction.pending` (mirrors `index` paging: `order(id: :desc)`, `id < cursor`, `PER_PAGE`). Renders Inertia page `"Pending"`.
- `update` — set status from params, whitelisted to `%w[posted canceled]` only (reject `pending` and garbage with 422 / no-op). Returns an Inertia redirect back to `/pending`.
- `transaction_json` — add `status`.

Frontend:

- New `app/frontend/pages/Pending.jsx` — same card/table layout as `Transactions.jsx`, plus per-row **Posted** and **Canceled** buttons that call `router.patch("/transactions/" + id, { status })`. On success the row is removed from the local list. Cursor "Load more" as in `Transactions.jsx`.
- `app/frontend/components/Layout.jsx` — add a **Pending** nav link.

## 6. Testing

- **Model:** enum scopes/predicates; `dedup_create!` promotion (pending→posted, →canceled) and no-regression (posted stays posted when incoming pending).
- **Importer:** status passed through; unknown/blank → pending.
- **DashboardStats:** pending and canceled rows excluded from spend; credits still excluded.
- **Controller:** `pending` lists only pending rows with cursor paging; `update` accepts posted/canceled, rejects pending/garbage.
- Update existing specs touching these services/controllers.

## Out of scope

- Editing other transaction fields from the UI.
- Bulk classify actions.
- Re-deriving status of already-posted rows.
