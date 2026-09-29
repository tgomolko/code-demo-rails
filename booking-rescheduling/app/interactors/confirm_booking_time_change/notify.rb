class ConfirmBookingTimeChange::Notify
  include Interactor

  def call
    UserSmsNotifier.perform_async('booking_time_change_accepted', context.request.id)
    VendorSmsNotifier.perform_async('booking_time_change_accepted', context.request.id)
  end
end
