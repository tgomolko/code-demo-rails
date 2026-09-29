require 'rails_helper'

RSpec.describe ConfirmBookingTimeChange do
  let(:admin) { create(:admin) }
  let(:vendor) { create(:vendor) }
  let(:base_date_due) do
    due = vendor.time_zone.now.beginning_of_day + 10.hours + 3.days
    due += 1.day if due < Time.current + 30.minutes
    due
  end
  let(:booking) { create(:booking, vendor: vendor, status: 'assigned', date_due: base_date_due) }
  let(:new_date_due) { base_date_due + 1.day }
  let(:evidence) do
    {
      source: 'booking_chat',
      message_id: 'message-123',
      excerpt: 'Tomorrow works for me',
      agreed_at: Time.current.iso8601
    }
  end

  before do
    allow(BookingCommon::ScheduleReminders).to receive(:call)
    allow(BookingCommon::ScheduleOnMyWayMissingAlert).to receive(:call)
    allow(BookingCommon::ComputeMinutesNotice).to receive(:call)
    allow(UserSmsNotifier).to receive(:perform_async)
    allow(VendorSmsNotifier).to receive(:perform_async)
  end

  def call_interactor(overrides = {})
    described_class.call(
      {
        booking: booking,
        vendor_id: vendor.id,
        new_date_due: new_date_due.iso8601,
        evidence: evidence,
        admin: admin
      }.merge(overrides)
    )
  end

  it 'moves the booking, keeps the vendor, and creates an accepted audit request' do
    previous_date_due = booking.date_due

    result = call_interactor

    expect(result).to be_success
    expect(result.previous_date_due).to eq(previous_date_due)
    expect(booking.reload.date_due.to_i).to eq(new_date_due.to_i)
    expect(booking.vendor).to eq(vendor)
    expect(result.request).to have_attributes(
      status: 'accepted',
      source: 'chat_confirmed',
      response_channel: 'chat',
      vendor_id: vendor.id,
      evidence: evidence.stringify_keys
    )
  end

  it 'allows confirmation when the original booking time is less than 30 minutes away or past' do
    booking.update!(date_due: 10.minutes.ago)

    result = call_interactor

    expect(result).to be_success
    expect(booking.reload.date_due.to_i).to eq(new_date_due.to_i)
  end

  it 'allows a chat-agreed time outside the 15-minute grid' do
    chat_agreed_time = new_date_due + 40.minutes

    result = call_interactor(new_date_due: chat_agreed_time.iso8601)

    expect(result).to be_success
    expect(booking.reload.date_due.to_i).to eq(chat_agreed_time.to_i)
  end

  it 'supersedes a pending request before creating the chat-confirmed audit request', :aggregate_fauilures do
    pending = create(:booking_time_change_request, booking: booking, vendor: vendor)

    result = call_interactor

    expect(result).to be_success
    expect(pending.reload).to be_cancelled
    expect(pending.response_channel).to eq('chat')
    expect(booking.booking_time_change_requests.count).to eq(2)
  end

  it 'resyncs pricing through the existing reschedule persistence path' do
    expect(RescheduleBooking::PersistBooking).to receive(:call).with(
      hash_including(
        booking: booking,
        date_due: kind_of(ActiveSupport::TimeWithZone),
        selected_vendor_ids: booking.selected_vendor_ids,
        admin: admin
      )
    ).and_call_original

    expect(call_interactor).to be_success
  end

  it 'rolls back the superseded request when persistence fails' do
    pending = create(:booking_time_change_request, booking: booking, vendor: vendor)
    original_date_due = booking.date_due
    failure = double(
      'failure',
      failure?: true,
      message: 'Could not update booking',
      error_code: 'failed_to_update_date_due'
    )
    allow(RescheduleBooking::PersistBooking).to receive(:call).and_return(failure)

    result = call_interactor

    expect(result).to be_failure
    expect(pending.reload).to be_pending
    expect(booking.reload.date_due).to eq(original_date_due)
    expect(booking.booking_time_change_requests.count).to eq(1)
  end

  it 'schedules the accepted-path jobs and notifies both sides' do
    result = call_interactor

    expect(BookingCommon::ScheduleReminders).to have_received(:call).with(booking: booking, notify_customer: true)
    expect(BookingCommon::ScheduleOnMyWayMissingAlert).to have_received(:call).with(booking: booking)
    expect(BookingCommon::ComputeMinutesNotice).to have_received(:call).with(booking: booking)
    expect(UserSmsNotifier).to have_received(:perform_async).with('booking_time_change_accepted', result.request.id)
    expect(VendorSmsNotifier).to have_received(:perform_async).with('booking_time_change_accepted', result.request.id)
  end

  it 'returns booking_not_movable for an unsupported status' do
    booking.update!(status: 'done')

    result = call_interactor

    expect(result).to be_failure
    expect(result.error_code).to eq('booking_not_movable')
  end

  it 'returns vendor_mismatch when the assigned vendor differs' do
    result = call_interactor(vendor_id: create(:vendor).id)

    expect(result).to be_failure
    expect(result.error_code).to eq('vendor_mismatch')
  end

  it 'returns invalid_time for a malformed time' do
    result = call_interactor(new_date_due: 'tomorrow sometime')

    expect(result).to be_failure
    expect(result.error_code).to eq('invalid_time')
  end

  it 'returns too_soon when the new time is less than 30 minutes away' do
    result = call_interactor(new_date_due: 20.minutes.from_now.iso8601)

    expect(result).to be_failure
    expect(result.error_code).to eq('too_soon')
  end

  it 'returns outside_service_hours when the new time is outside the service window' do
    result = call_interactor(new_date_due: new_date_due.in_time_zone(booking.zone).beginning_of_day.iso8601)

    expect(result).to be_failure
    expect(result.error_code).to eq('outside_service_hours')
  end

  it 'returns schedule_conflict when the vendor has an overlapping job' do
    create(
      :booking,
      vendor: vendor,
      status: 'assigned',
      date_due: new_date_due + 15.minutes,
      max_duration: 90
    )

    result = call_interactor

    expect(result).to be_failure
    expect(result.error_code).to eq('schedule_conflict')
  end
end
