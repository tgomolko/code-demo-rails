# Rails Engineering Samples

This repository contains two focused code samples extracted and adapted from a
production Ruby on Rails application. They are presented as reviewable slices
of a larger system rather than as a standalone application.

The surrounding domain models, application framework, factories, and service
integrations are intentionally omitted. Product-specific names and integration
details have been generalized.

## Samples

### [Booking rescheduling](booking-rescheduling/README.md)

A transactional workflow for confirming a booking time change through a
support channel. It demonstrates:

- orchestration of a multi-step domain operation;
- PostgreSQL-backed row locking and rollback behavior;
- validation of booking state, service hours, and schedule conflicts;
- reuse of an existing persistence path;
- audit records, background jobs, and notifications;
- behavior-focused RSpec coverage.

### [Payment idempotency](payment-idempotency/README.md)

A defensive payment flow designed to prevent duplicate Stripe charges while
still allowing deliberate collection retries. It demonstrates:

- Stripe idempotency keys based on business identity;
- serialization of concurrent retries with a database lock;
- careful transaction boundaries around expected failures;
- tests for gateway arguments and background-job behavior.

## What to review first

Start with:

1. `booking-rescheduling/app/interactors/confirm_booking_time_change.rb`
2. `booking-rescheduling/app/interactors/confirm_booking_time_change/guards.rb`
3. `booking-rescheduling/spec/interactors/confirm_booking_time_change_spec.rb`
4. `payment-idempotency/app/gateways/stripe_booking_gateway.rb`
5. `payment-idempotency/app/interactors/retry_declined_payment.rb`
