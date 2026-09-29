class ConfirmBookingTimeChange::ScheduleJobs
  include Interactor

  def call
    BookingCommon::ScheduleReminders.call(booking: context.booking, notify_customer: true)
    BookingCommon::ScheduleOnMyWayMissingAlert.call(booking: context.booking)
    BookingCommon::ComputeMinutesNotice.call(booking: context.booking)
  end
end
