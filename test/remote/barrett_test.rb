require 'test_helper'

class RemoteBarrettTest < Minitest::Test
  include ActiveFulfillment::Test::Fixtures

  def setup
    ActiveFulfillment::Base.mode = :test

    @service = ActiveFulfillment::BarrettService.new( fixtures(:barrett) )
    @service.connect

    @options = {
      shipping_method: 'Standard',
      order_date: Time.now.utc.yesterday,
      comment: "Delayed due to tornados"
    }

    @address = {
      name: 'Johnny Chase',
      address1: '100 Information Super Highway',
      address2: 'Suite 66',
      city: 'Beverly Hills',
      state: 'CA',
      country: 'US',
      zip: '90210',
      email: 'chase@example.com',
      phone: '123-456-789'
    }

    @line_items = [
      {
        sku: 'SETTLERS8',
        quantity: 1
      }
    ]
  end

  def test_successful_order_submission
    @options[:billing_address] = @address
    response = @service.fulfill(Time.now.to_i, @address, @line_items, @options)
    assert response.success?
    assert response.test?
  end

  def test_order_multiple_line_items
    @line_items.push({
      sku: 'CARCASSONNE',
      quantity: 2
    })
    @line_items.push({
      sku: 'CITADELS',
      quantity: 3
    })
    @options[:billing_address] = @address
    response = @service.fulfill(Time.now.to_i, @address, @line_items, @options)
    assert response.success?
    assert response.test?
  end

  def test_fetch_tracking_data
    response = @service.fetch_tracking_data(['123456D']) # an actual order
    assert response.success?
    assert_equal ['1Z4430900000013'], response.tracking_numbers['123456D']
    assert_equal ['UPS'], response.tracking_companies['123456D']
  end

  def test_valid_credentials
    assert @service.valid_credentials?
  end

  def test_invalid_credentials
    service = ActiveFulfillment::BarrettService.new(
      custid: 12345,
      userid: 67890,
      password: "test"
    )
    assert !service.valid_credentials?
  end

end
