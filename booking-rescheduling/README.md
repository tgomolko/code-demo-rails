# Booking Rescheduling

## Problem

A support agent can confirm a new booking time after the customer and assigned
vendor agree in chat. The operation must remain safe if two requests arrive at
the same time and must not leave the booking, audit history, or scheduled jobs
in a partially updated state.

## Design

`ConfirmBookingTimeChange` owns the transaction and locks both the booking and
the latest pending time-change request. The workflow then:

1. validates the booking state, vendor, proposed time, service hours, and
   schedule availability;
2. supersedes an existing pending request;
3. reuses the application's established rescheduling persistence path;
4. creates an accepted audit record;
5. reschedules related jobs and enqueues notifications.

If persistence fails, the transaction restores the previous request state and
booking time.

## Notable details

- The overlap predicate uses half-open time ranges, allowing adjacent bookings
  while rejecting real overlaps.
- Typed error codes keep the API contract independent of human-readable copy.
- Time parsing is normalized into the booking's local time zone.
- The spec covers success, rollback, malformed input, service hours, schedule
  conflicts, audit evidence, and notification scheduling.

## Files

```text
app/interactors/confirm_booking_time_change.rb
app/interactors/confirm_booking_time_change/
  create_audit_request.rb
  guards.rb
  notify.rb
  persist_booking.rb
  schedule_jobs.rb
  supersede_pending_request.rb
spec/interactors/confirm_booking_time_change_spec.rb
```

## Omitted dependencies

The sample references domain objects and services supplied by the host
application, including `Booking`, `BookingTimeChangeRequest`,
`RescheduleBooking::PersistBooking`, Sidekiq notifiers, and
`ApplicationOrganizer`.
