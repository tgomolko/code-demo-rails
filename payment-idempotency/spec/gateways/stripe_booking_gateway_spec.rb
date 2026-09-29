require 'rails_helper'

RSpec.describe StripeBookingGateway do
  subject(:gateway) do
    described_class.new(
      stripe_customer: stripe_customer,
      charge_client: charge_client
    )
  end

  let(:stripe_customer) { instance_double('Stripe::Customer', id: 'cus_123') }
  let(:charge_client) { class_double('Stripe::Charge', create: nil) }
  let(:booking) do
    instance_double(
      'Booking',
      id: 42,
      amount_to_charge: BigDecimal('23.21'),
      card_id: 'card_123'
    )
  end

  it 'uses a stable idempotency key for the same logical charge' do
    gateway.charge(booking)

    expect(charge_client).to have_received(:create).with(
      hash_including(
        amount: 2321,
        currency: 'usd',
        customer: 'cus_123',
        source: 'card_123'
      ),
      idempotency_key: 'booking-charge-42-2321-card_123'
    )
  end

  it 'allows an explicit collection retry to create a fresh Stripe request' do
    gateway.charge(booking, idempotent: false)

    expect(charge_client).to have_received(:create).with(
      hash_including(amount: 2321, metadata: { booking_id: 42 })
    )
  end
end
