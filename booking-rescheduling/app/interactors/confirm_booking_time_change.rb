class ConfirmBookingTimeChange
  include ApplicationOrganizer

  around do |interactor|
    Booking.transaction do
      context.pending_request = context.booking.booking_time_change_requests
                                       .pending
                                       .lock
                                       .order(created_at: :desc)
                                       .first
      context.booking.lock!
      interactor.call
    end
  end

  def REQUIRED_PARAMS
    [:booking, :admin]
  end

  before do
    context.new_date_due = parse_new_date_due
  end

  organize [
    ConfirmBookingTimeChange::Guards,
    ConfirmBookingTimeChange::SupersedePendingRequest,
    ConfirmBookingTimeChange::PersistBooking,
    ConfirmBookingTimeChange::CreateAuditRequest,
    ConfirmBookingTimeChange::ScheduleJobs,
    ConfirmBookingTimeChange::Notify
  ]

  private

  def parse_new_date_due
    value = context.new_date_due
    parsed =
      if value.is_a?(Time) || value.is_a?(ActiveSupport::TimeWithZone)
        value
      else
        Time.iso8601(value.to_s)
      end

    parsed.in_time_zone(context.booking.zone)
  rescue ArgumentError, TypeError
    nil
  end
end
