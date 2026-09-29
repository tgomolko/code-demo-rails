class ConfirmBookingTimeChange::PersistBooking
  include Interactor

  def call
    context.previous_date_due = context.booking.date_due

    result = RescheduleBooking::PersistBooking.call(
      booking: context.booking,
      date_due: context.new_date_due,
      selected_vendor_ids: context.booking.selected_vendor_ids,
      admin: context.admin
    )

    context.fail!(message: result.message, error_code: result.error_code) if result.failure?
  end
end
