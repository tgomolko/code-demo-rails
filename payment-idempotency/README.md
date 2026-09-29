# Payment Idempotency

## Problem

Repeated completion requests must not charge the same booking more than once.
At the same time, a declined-payment recovery initiated later must create a new
payment attempt rather than reuse the original completion request.

## Design

Normal booking charges send Stripe an idempotency key derived from the booking,
amount, and card. Retries of the same logical request therefore resolve to the
same Stripe operation, while a changed amount or card remains a distinct charge.

Collection retries deliberately disable that key and instead acquire a row lock
on `DeclinedPayment`. This serializes concurrent recovery attempts. An expected
Interactor failure is re-raised only after the transaction commits because the
existing business flow intentionally preserves some writes after a failed
collection.

## Files

```text
app/gateways/stripe_booking_gateway.rb
app/interactors/retry_declined_payment.rb
spec/gateways/stripe_booking_gateway_spec.rb
spec/interactors/retry_declined_payment_spec.rb
```

## Review focus

- `StripeBookingGateway#idempotency_key_for` shows how the business identity of
  a charge is translated into a Stripe idempotency key.
- `RetryDeclinedPayment` shows the database transaction and row lock.
- The specs show payment gateway expectations and the behavior of failed final
  collection attempts.

## Omitted dependencies

The gateway is a focused adaptation of the relevant production behavior rather
than a copy of the application's larger legacy Stripe wrapper. The retry sample
still relies on the host application's booking models, Interactor setup,
Sidekiq configuration, and RSpec factories.
