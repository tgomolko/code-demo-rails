class ConfirmBookingTimeChange::Guards
  include Interactor

  MINIMUM_NOTICE = 30.minutes

  def call
    guard_booking_state
    guard_vendor
    guard_time
    guard_service_hours
    guard_schedule_conflict
  end

  private

  def guard_booking_state
    return if context.booking.status.in?(%w[assigned vendor_on_his_way])

    context.fail!(
      message: 'This booking can no longer be moved.',
      error_code: 'booking_not_movable'
    )
  end

  def guard_vendor
    return if context.booking.vendor_id.present? && context.booking.vendor_id.to_s == context.vendor_id.to_s

    context.fail!(
      message: 'The assigned vendor does not match.',
      error_code: 'vendor_mismatch'
    )
  end

  def guard_time
    if context.new_date_due.blank?
      context.fail!(message: 'The requested time is invalid.', error_code: 'invalid_time')
      return
    end

    return if context.new_date_due >= Time.current + MINIMUM_NOTICE

    context.fail!(
      message: 'The requested time must be at least 30 minutes away.',
      error_code: 'too_soon'
    )
  end

  def guard_service_hours
    proposed_time = context.new_date_due.in_time_zone(context.booking.zone)
    start_of_day = proposed_time.beginning_of_day
    return if proposed_time.between?(
      start_of_day + schedule_start_hour.hours,
      start_of_day + schedule_end_hour.hours
    )

    context.fail!(
      message: 'The requested time is outside service hours.',
      error_code: 'outside_service_hours'
    )
  end

  def schedule_start_hour
    area_schedule_setting&.schedule_time_begin || ApplicationParameter.get!('schedule_time_begin_24_format')
  end

  def schedule_end_hour
    area_schedule_setting&.schedule_time_end || ApplicationParameter.get!('schedule_time_end_24_format')
  end

  def area_schedule_setting
    @area_schedule_setting ||= context.booking.area_schedule_setting
  end

  def guard_schedule_conflict
    return unless overlaps_vendor_booking?

    context.fail!(
      message: 'The requested time conflicts with another booking on the vendor schedule.',
      error_code: 'schedule_conflict'
    )
  end

  def overlaps_vendor_booking?
    end_at = context.new_date_due + context.booking.max_duration.minutes

    Booking
      .where(vendor_id: context.booking.vendor_id)
      .where.not(id: context.booking.id)
      .where.not(status: %w[done cancelled])
      .exists?(
        [
          "date_due < :end_at AND (date_due + (max_duration * interval '1 minute')) > :start_at",
          { end_at: end_at, start_at: context.new_date_due }
        ]
      )
  end
end
