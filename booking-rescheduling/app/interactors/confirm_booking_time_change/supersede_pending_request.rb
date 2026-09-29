class ConfirmBookingTimeChange::SupersedePendingRequest
  include Interactor

  def call
    return if context.pending_request.blank?

    context.pending_request.cancel!
    context.pending_request.update!(responded_at: Time.current, response_channel: 'chat')
  end
end
