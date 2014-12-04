require 'test_helper'

class BarrettTest < Minitest::Test
  include ActiveFulfillment::Test::Fixtures

  def setup
    ActiveFulfillment::Base.mode = :test

    @service = ActiveFulfillment::BarrettService.new(
      custid: 12345,
      userid: 67890,
      password: "test"
    )


    @address = {
      name: 'Fred Brooks',
      address1: '1234 Penny Lane',
      city: 'Jonsetown',
      state: 'NC',
      country: 'US',
      zip: '23456',
      email:    'buyer@jadedpallet.com'
    }


     @options = {
       shipping_method: 'UPS Ground',
       billing_address: @address
     }

    @line_items = [
      {
        sku: '9999',
        quantity: 25
      }
    ]
  end

  def test_missing_login
    assert_raises(ArgumentError) do
      ActiveFulfillment::BarrettService.new(password: 'test')
    end
  end

  def test_missing_password
    assert_raises(ArgumentError) do
      ActiveFulfillment::BarrettService.new(login: 'cody')
    end
  end

  def test_missing_credentials
    assert_raises(ArgumentError) do
      ActiveFulfillment::BarrettService.new(password: 'test')
    end
  end

  def test_credentials_present
    assert ActiveFulfillment::BarrettService.new(
      custid: 12345,
      userid: 67890,
      password: "test"
    )
  end

  def test_successful_fulfillment
    @service.expects(:ssl_post).returns(successful_fulfillment_response)

    @options[:billing_address] = @address
    response = @service.fulfill('123456', @address, @line_items, @options)
    assert response.success?
    assert response.test?
    assert_equal ActiveFulfillment::BarrettService::SUCCESS, response.message
  end

  def test_failed_fulfillment
    @service.expects(:ssl_post).returns(failed_fulfillment_response)

    response = @service.fulfill('123456', @address, @line_items, @options)
    assert !response.success?
    assert response.test?
    assert_equal ActiveFulfillment::BarrettService::FAILURE, response.message
  end

  def test_tracking_numbers
    @service.expects(:ssl_post).returns(xml_fixture('barrett/tracking_response'))

    response = @service.fetch_tracking_numbers(['123456D'])
    assert response.success?
    assert_equal ActiveFulfillment::BarrettService::SUCCESS, response.message
    assert_equal ['1Z4430900000013'], response.tracking_numbers['123456D']
    assert_nil response.tracking_numbers['XY4567']
  end

  def test_tracking_data
    @service.expects(:ssl_post).returns(xml_fixture('barrett/tracking_response'))

    response = @service.fetch_tracking_data(['123456D'])

    assert response.success?
    assert_equal ActiveFulfillment::BarrettService::SUCCESS, response.message
    assert_equal ['1Z4430900000013'], response.tracking_numbers['123456D']
    assert_equal ['UPS'], response.tracking_companies['123456D']
    assert_equal({}, response.tracking_urls)
  end

  def test_garbage_response
    @service.expects(:ssl_post).returns(garbage_response)

    @options[:billing_address] = @address
    response = @service.fulfill('123456', @address, @line_items, @options)
    assert !response.success?
    assert response.test?
    assert_equal ActiveFulfillment::BarrettService::FAILURE, response.message
  end

  def test_valid_credentials
    @service.expects(:ssl_post).returns(successful_connection_response)
    @service.connect
    assert @service.valid_credentials?
  end

  def test_invalid_credentials
    @service.expects(:ssl_post).returns(invalid_connection_response)
    @service.connect
    assert !@service.valid_credentials?
  end

  private

  def successful_connection_response
    '<?xml version="1.0" encoding="utf-8"?><soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema"><soap:Body><ConnectResponse xmlns="http://ws.barrettdistribution.com/wsi2test/"><ConnectResult>abcdefghijklmnopqrstuvwxyz012345</ConnectResult></ConnectResponse></soap:Body></soap:Envelope>'
  end

  def invalid_connection_response
    '<?xml version="1.0" encoding="utf-8"?><soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema"><soap:Body><ConnectResponse xmlns="http://ws.barrettdistribution.com/wsi2test/"><ConnectResult>ENC_CATCH_ERROR</ConnectResult></ConnectResponse></soap:Body></soap:Envelope>'
  end

  def successful_fulfillment_response
    '<?xml version="1.0" encoding="utf-8"?><soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema"><soap:Body><OutboundOrderActionResponse xmlns="http://ws.barrettdistribution.com/wsi2test/"><ActionResponse>OK</ActionResponse></OutboundOrderActionResponse></soap:Body></soap:Envelope>'
  end

  def failed_fulfillment_response
    '<?xml version="1.0" encoding="utf-8"?><soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema"><soap:Body><OutboundOrderActionResponse xmlns="http://ws.barrettdistribution.com/wsi2test/" /></soap:Body></soap:Envelope>'
  end

  def garbage_response
    '<font face="Arial" size=2>/XML/shippingTest.asp</font><font face="Arial" size=2>, line 39</font>'
  end

  def duplicate_response
    '<?xml version="1.0" encoding="utf-8"?><soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema"><soap:Body><OutboundOrderActionResponse xmlns="http://ws.barrettdistribution.com/wsi2test/"><ActionResponse>DUPLICATE ORDER</ActionResponse></OutboundOrderActionResponse></soap:Body></soap:Envelope>'
  end
end
