# frozen_string_literal: true

module Net
  class HTTP
    alias orig_request request unless method_defined?(:orig_request)
    alias orig_connect connect unless method_defined?(:orig_connect)

    def request(req, body = nil, &block)
      url = "http://#{@address}:#{@port}#{req.path}"

      request_error = nil
      bm = Benchmark.realtime do
        begin
          @response = orig_request(req, body, &block)
        rescue Exception => e
          request_error = e
        end
      end
      body_stream  = req.body_stream
      request_body = if body_stream
                       body_stream.to_s # read and rewind for RestClient::Payload::Base
                       body_stream.rewind if body_stream.respond_to?(:rewind) # RestClient::Payload::Base has no method rewind
                       body_stream.read
                     elsif req.body.nil? || req.body.empty?
                       body
                     else
                       req.body
                     end

      if request_error
        if HttpLog.url_approved?(url)
          HttpLog.call(
            method: req.method,
            url: url,
            request_body: request_body,
            request_headers: req.each_header.collect,
            response_headers: {error: request_error.inspect},
            benchmark: bm,
            mask_body: HttpLog.masked_body_url?(url)
          )
        end
        raise request_error
      end

      if HttpLog.url_approved?(url) && started?
        HttpLog.call(
          method: req.method,
          url: url,
          request_body: request_body,
          request_headers: req.each_header.collect,
          response_code: @response.code,
          response_body: @response.body,
          response_headers: @response.each_header.collect,
          benchmark: bm,
          encoding: @response['Content-Encoding'],
          content_type: @response['Content-Type'],
          mask_body: HttpLog.masked_body_url?(url)
        )
      end

      @response
    end

    def connect
      url = "http://#{@address}:#{@port}"
      HttpLog.log_connection(@address, @port) if !started? && HttpLog.url_approved?(url)

      connection_error = nil
      bm = Benchmark.realtime do
        begin
          orig_connect
        rescue Exception => e
          connection_error = e
        end
      end

      if connection_error
        if HttpLog.url_approved?(url)
          HttpLog.call(
            url: url,
            response_headers: {error: connection_error.inspect},
            benchmark: bm
          )
        end
        raise connection_error
      end
    end
  end
end
