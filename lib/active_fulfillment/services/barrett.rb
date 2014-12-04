require 'base64'
require 'openssl'

module ActiveFulfillment
  class BarrettService < Service

    SUCCESS, FAILURE, ERROR = 'Accepted', 'Failure', 'Error'

    OPERATIONS = {
      session: {
        connect: 'Connect',
        disconnect: 'Disconnect'
      },
      outbound: {
        create: 'OutboundOrderAdd',
        delete: 'OutboundOrderDelete',
        update: 'OutboundOrderUpdate',
        tracking: 'OutboundOrderShipmentDetails_Serial'
      },
      inbound: {
        create: 'InboundOrderAdd',
        delete: 'InboundOrderDelete',
        update: 'InboundOrderUpdate'
      }
    }

    def initialize(options = {})
      requires!(options, :custid, :userid, :password)
      super
    end

    def connect
      commit :session, :connect, build_connection_request
    end

    def fulfill(order_id, shipping_address, line_items, options = {})
      requires!(options, :billing_address)
      commit :outbound, :create, build_fulfillment_request(order_id, shipping_address, line_items, options)
    end

    def fetch_tracking_data(order_ids, options = {})
      order_ids.inject(nil) do |previous, o_id|
        response = commit :outbound, :tracking, build_tracking_request(o_id, options)
        return response unless response.success?

        if previous
          response.tracking_numbers.merge!(previous.tracking_numbers)
          response.tracking_companies.merge!(previous.tracking_companies)
          response.tracking_urls.merge!(previous.tracking_urls)
        end

        response
      end
    end

    def valid_credentials?
      @options.has_key?(:sessionId)
    end

    def test_mode?
      true
    end

    private

    def service_path
      test? ? 'wsi2test' : 'wsi2'
    end

    def service_url
      "https://ws.barrettdistribution.com/#{service_path}/SynapseOrderInterface.asmx"
    end

    def xml_namespaces
      {
        'xmlns:soap' => 'http://www.w3.org/2003/05/soap-envelope',
        'xmlns:wsi' => "http://ws.barrettdistribution.com/#{service_path}/"
      }
    end

    def soap_request(request)
      xml = Builder::XmlMarkup.new :indent => 2
      xml.instruct!
      xml.tag! "soap:Envelope", xml_namespaces do
        xml.tag! "soap:Body" do
          yield xml
        end
      end
      xml.target!
    end

    def build_connection_request
      request = "wsi:#{OPERATIONS[:session][:connect]}"
      soap_request(request) do |xml|
        xml.tag! request do
          xml.tag! "wsi:strCustId", @options[:custid]
          xml.tag! "wsi:strUserName", @options[:userid]
          xml.tag! "wsi:strPassword", @options[:password]
          xml.tag! "wsi:strRandomText", SecureRandom.hex(10) # HUH?
        end
      end
    end

    def build_fulfillment_request(order_id, shipping_address, line_items, options)
      request = "wsi:#{OPERATIONS[:outbound][:create]}"
      soap_request(request) do |xml|
        xml.tag! request do
          add_credentials(xml)
          xml.tag! 'wsi:OutboundOrder' do
            xml.tag! "wsi:IN_ORDERTYPE", "O"
            xml.tag! "wsi:IN_FROMFACILITY", "MEM"

            # <option value="3RD">3rd Party to Collect</option>
            # <option value="DT3">Bill Freight &amp; Duties/Taxes 3RD</option>
            # <option value="COL">Collect</option>
            # <option value="PCK">Consignee to Pick Up</option>
            # <option value="UCB">Contract Consignee Billing</option>
            # <option value="CSL">Customer Supplied Labels</option>
            # <option value="DDP">Free Domicile</option>
            # <option value="PPD">Prepaid</option>
            xml.tag! "wsi:IN_SHIPTERMS", "PPD"

            xml.tag! "wsi:IN_REFERENCE", order_id
            xml.tag! "wsi:IN_PO", order_id # TODO

            add_address(xml, "BILLTO", options[:billing_address])
            add_address(xml, "SHIPTO", shipping_address)

            xml.tag! "wsi:IN_CARRIER", "UPS"
            xml.tag! "wsi:IN_DELIVERYSERVICE", "GRND"

            add_items(xml, line_items)
          end
        end
      end
    end

    def build_tracking_request(order_id, options)
      request = "wsi:#{OPERATIONS[:outbound][:tracking]}"
      soap_request(request) do |xml|
        xml.tag! "wsi:OutboundOrderShipmentDetailsRequest" do
          add_credentials(xml)
          xml.tag! "wsi:IN_REFERENCE", order_id
          xml.tag! "wsi:GetBatch"
        end
      end
    end

    def add_credentials(xml)
      xml.tag! 'wsi:strSessionId', @options[:sessionId]
    end

    def add_items(xml, line_items)
      xml.tag! 'wsi:IN_ORDERLINES' do
        Array(line_items).each_with_index do |item, index|
          xml.tag! 'wsi:OutboundOrderLines' do
            xml.tag! 'wsi:IN_ITEMENTERED', item[:sku]
            xml.tag! 'wsi:IN_QTYENTERED', item[:quantity]
            xml.tag! 'wsi:IN_UOMENTERED', 'EA'
            xml.tag! 'wsi:IN_BACKORDER', 'N'
          end
        end
      end
    end

    def add_address(xml, prefix, address)
      xml.tag! "wsi:IN_#{prefix}NAME", address[:name]
      xml.tag! "wsi:IN_#{prefix}ADDR1", address[:address1]
      xml.tag! "wsi:IN_#{prefix}ADDR2", address[:address2] unless address[:address2].blank?
      xml.tag! "wsi:IN_#{prefix}CITY", address[:city]
      xml.tag! "wsi:IN_#{prefix}STATE", address[:state]
      xml.tag! "wsi:IN_#{prefix}POSTALCODE", address[:zip]
      xml.tag! "wsi:IN_#{prefix}COUNTRYCODE", address[:country]
      xml.tag! "wsi:IN_#{prefix}PHONE", address[:phone] unless address[:phone].blank?
      xml.tag! "wsi:IN_#{prefix}EMAIL", address[:email] unless address[:email].blank?
      xml.tag! "wsi:IN_#{prefix}CONTACT", address[:name] #TODO
    end

    def commit(service, op, body)
      action = "http://ws.barrettdistribution.com/#{service_path}/#{OPERATIONS[service][op]}/"
      data = ssl_post(service_url, body, 'Content-Type' => "application/soap+xml; charset=utf-8; action=#{action}")
      response = parse_response(service, op, data)
      Response.new(success?(response), message_from(response), response, test: test?)
    rescue ActiveUtils::ResponseError => e
      puts e
      # handle_error(e)
    end

    def handle_error(e)
      response = parse_error(e.response)
      if response.fetch(:faultstring, "") =~ /Reason: requested order not found./
        Response.new(true, nil, {:status => SUCCESS, :tracking_numbers => {}, :tracking_companies => {}, :tracking_urls => {}})
      else
        Response.new(false, message_from(response), response)
      end
    end

    def success?(response)
      response[:response_status] == SUCCESS
    end

    def message_from(response)
      response[:response_status]
    end

    def parse_response(service, op, xml)
      begin
        document = REXML::Document.new(xml)
      rescue REXML::ParseException
        return {response_status: FAILURE}
      end

      case service
      when :session
        case op
        when :connect
          parse_connection_response(document)
        end
      when :outbound
        case op
        when :tracking
          parse_tracking_response(document)
        else
          parse_fulfillment_response(op, document)
        end
      when :inventory
        parse_inventory_response(document)
      else
        raise ArgumentError, "Unknown service #{service}"
      end
    end

    def parse_connection_response(document)
      response = {}
      node = REXML::XPath.first(document, "//ConnectResult")
      # TODO Robust error checking
      if node.text.length == 32
        @options[:sessionId] = node.text
        response[:response_status]  = SUCCESS
      else
        response[:response_status]  = FAILURE
      end
      response
    end

    def parse_fulfillment_response(op, document)
      response = {}
      action   = OPERATIONS[:outbound][op]
      node     = REXML::XPath.first(document, "//OutboundOrderActionResponse/ActionResponse")

      response[:response_status] = (node && node.text) == "OK" ?  SUCCESS : FAILURE
      response
    end

    def parse_tracking_response(document)
      response = {}
      response[:tracking_numbers] = {}
      response[:tracking_companies] = {}
      response[:tracking_urls] = {}

      track_node = REXML::XPath.first(document, '//TrackingNumber')
      if track_node
        id_node = REXML::XPath.first(document, '//Reference') # Or OrderID?
        response[:tracking_numbers][id_node.text] = [track_node.text]
      end

      company_node = REXML::XPath.first(document, '//carrier')
      if company_node
        id_node = REXML::XPath.first(document, '//Reference') # Or OrderID?
        response[:tracking_companies][id_node.text] = [company_node.text]
      end

      response[:date_shipped] = REXML::XPath.first(document, '//dateshipped').text
      response[:freight_cost] = REXML::XPath.first(document, '//freightcost').text

      response[:response_status] = SUCCESS
      response
    end

    def parse_error(http_response)
    #   response = {}
    #   response[:http_code] = http_response.code
    #   response[:http_message] = http_response.message
    #
    #   document = REXML::Document.new(http_response.body)
    #
    #   node     = REXML::XPath.first(document, "//env:Fault")
    #
    #   failed_node = node.find_first_recursive {|sib| sib.name == "Fault" }
    #   faultcode_node = node.find_first_recursive {|sib| sib.name == "faultcode" }
    #   faultstring_node = node.find_first_recursive {|sib| sib.name == "faultstring" }
    #
    #   response[:response_status]  = FAILURE
    #   response[:faultcode]        = faultcode_node ? faultcode_node.text : ""
    #   response[:faultstring]      = faultstring_node ? faultstring_node.text : ""
    #   response[:response_comment] = "#{response[:faultcode]} #{response[:faultstring]}"
    #   response
    # rescue REXML::ParseException => e
    #   response[:http_body]        = http_response.body
    #   response[:response_status]  = FAILURE
    #   response[:response_comment] = "#{response[:http_code]}: #{response[:http_message]}"
    #   response
    end
  end
end
