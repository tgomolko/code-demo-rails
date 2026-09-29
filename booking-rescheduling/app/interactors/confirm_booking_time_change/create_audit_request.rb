class ConfirmBookingTimeChange::CreateAuditRequest
  include Interactor

  def call
    now = Time.current
    context.request = BookingTimeChangeRequest.create!(
      booking: context.booking,
      vendor_id: context.vendor_id,
      proposed_date_due: context.new_date_due,
      requested_at: now,
      expires_at: now,
      responded_at: now,
      response_channel: 'chat',
      source: 'chat_confirmed',
      evidence: context.evidence,
      status: 'accepted'
    )
  end
end
