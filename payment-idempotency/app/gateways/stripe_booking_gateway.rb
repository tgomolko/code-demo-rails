require 'bigdecimal'

class StripeBookingGateway
  CURRENCY = 'usd'.freeze
  DESCRIPTION = 'Service booking charge'.freeze

  def initialize(stripe_customer:, charge_client: Stripe::Charge)
    @stripe_customer = stripe_customer
    @charge_client = charge_client
  end

  def charge(booking, idempotent: true)
    params = charge_params(booking)
    return @charge_client.create(params) unless idempotent

    @charge_client.create(
      params,
      idempotency_key: idempotency_key_for(booking)
    )
  end

  private

  def charge_params(booking)
    {
      amount: cents(booking.amount_to_charge),
      currency: CURRENCY,
      customer: @stripe_customer.id,
      description: DESCRIPTION,
      metadata: { booking_id: booking.id },
      source: booking.card_id
    }
  end

  def idempotency_key_for(booking)
    # Retrying the same booking, amount, and card represents the same charge.
    # A changed amount or card is a distinct, intentional payment attempt.
    [
      'booking-charge',
      booking.id,
      cents(booking.amount_to_charge),
      booking.card_id
    ].join('-')
  end

  def cents(amount)
    (BigDecimal(amount.to_s) * 100).to_i
  end
end
