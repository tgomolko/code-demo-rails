class RetryDeclinedPayment
  include ApplicationOrganizer

  # A collection retry needs a fresh Stripe attempt, so serialize it in the
  # database instead of reusing the original completion idempotency key.
  around do |interactor|
    interactor_failure = nil

    DeclinedPayment.transaction do
      DeclinedPayment.lock.where(id: context.declined_payment_id).load

      begin
        interactor.call
      rescue Interactor::Failure => error
        # A failed collection still completes the booking and schedules the
        # vendor payment. Preserve those writes, matching the existing flow.
        interactor_failure = error
      end
    end

    raise interactor_failure if interactor_failure
  end

  def REQUIRED_PARAMS
    [:declined_payment_id, :remind_customer]
  end

  before do
    context.remind_customer = !context.silent_attempt if context.silent_attempt.present?
    context.declined_payment = DeclinedPayment.find(context.declined_payment_id)
    context.booking = context.declined_payment.booking
    context.user = context.booking.user
    context.last_customer_notification = false
  end

  after do
    unless context.declined_payment.reload.solved?
      context.fail!(
        message: "The attempt to recover the declined payment didn't work.",
        error_code: "did_not_recover"
      )
    end
  end

  organize [
    RetryDeclinedPayment::Guards,
    RetryDeclinedPayment::Retry,
    RetryDeclinedPayment::RemindCustomer,
    RetryDeclinedPayment::HandleLastFailingAttempt,
  ]
end
