require 'rails_helper'

describe RetryDeclinedPayment do
  let(:user) { create(:user, :with_cards) }
  let(:booking) { create(:booking, status: 'support_needed', user: user, vendor: create(:vendor)) }
  let(:declined_payment) { create(:declined_payment, booking: booking) }

  it "performs the necessary steps" do
    expect(RetryDeclinedPayment.organized).to eq [
      RetryDeclinedPayment::Guards,
      RetryDeclinedPayment::Retry,
      RetryDeclinedPayment::RemindCustomer,
      RetryDeclinedPayment::HandleLastFailingAttempt,
    ]
  end

  it 'recreates the next occurrence if the booking is a plan' do
    user = create(:user)
    create(:plan, user: user, upcoming_booking: (booking = create(:booking, status: 'support_needed', user: user)))
    declined_payment = create(:declined_payment, booking: booking)

    expect {
      RetryDeclinedPayment.call({ declined_payment_id: declined_payment.id, remind_customer: true })
    }.to change {
      user.reload.bookings.count
    }.by(1)

    expect(booking.reload.declined_payment.solved?).to eq true
  end

  it 'fails if supplied card is declined' do
    StripeMock.prepare_card_error(:card_declined)

    result = RetryDeclinedPayment.call(declined_payment_id: declined_payment.id, remind_customer: false, preferred_card: user.cards[0][:id])

    expect(result.success?).to eq false
  end

  it 'works even if there is one card declined' do
    StripeMock.prepare_card_error(:card_declined)

    result = RetryDeclinedPayment.call(declined_payment_id: declined_payment.id, remind_customer: false)

    expect(result.success?).to eq true
  end

  context 'when running the last attempt' do
    it 'schedules a job to mark the declined payment as lost after a failed final collection' do
      allow(Stripe::Charge).to receive(:create).and_raise(Stripe::CardError.new('declined', {}, code: 'card_declined'))
      Timecop.freeze do
        create(:declined_payment, customer_notifications_count: 6, id: 42_000, booking: create(:booking, status: 'support_needed'))

        result = RetryDeclinedPayment.call(declined_payment_id: 42_000, remind_customer: true)

        expect(result.success?).to eq false

        expect(MarkDeclinedPaymentAsLostWorker).to have_enqueued_sidekiq_job(42_000, Admin.system_user.id).in(72.hours)
      end
    end
  end

  context 'when not running the last attempt' do
    it 'does not schedule a job to mark the declined payment as lost' do
      Timecop.freeze do
        create(:declined_payment, customer_notifications_count: 5, id: 42_000, booking: create(:booking, status: 'support_needed'))

        result = RetryDeclinedPayment.call(declined_payment_id: 42_000, remind_customer: true)

        expect(result.success?).to eq true
        expect(MarkDeclinedPaymentAsLostWorker).not_to have_enqueued_sidekiq_job(42_000, Admin.system_user.id).in(72.hours)
      end
    end
  end
end
