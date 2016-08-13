module HTTP
  class WebMockPerform
    def initialize(request, &perform)
      @request = request
      @perform = perform
      @request_signature = nil
    end

    def exec
      replay || perform || halt
    end

    def request_signature
      unless @request_signature
        @request_signature = @request.webmock_signature
        register_request(@request_signature)
      end

      @request_signature
    end

    protected

    def response_for_request(signature)
      ::WebMock::StubRegistry.instance.response_for_request(signature)
    end

    def register_request(signature)
      ::WebMock::RequestRegistry.instance.requested_signatures.put(signature)
    end

    def replay
      webmock_response = response_for_request request_signature

      return unless webmock_response

      webmock_response.on_timeout { raise_timeout_error }
      webmock_response.raise_error_if_any

      invoke_callbacks(webmock_response, real_request: false)
      ::HTTP::Response.from_webmock webmock_response, request_signature
    end

    def raise_timeout_error
      raise Errno::ETIMEDOUT if HTTP::VERSION < "1.0.0"
      raise HTTP::ConnectionError, "connection error: #{Errno::ETIMEDOUT.new}"
    end

    def perform
      return unless ::WebMock.net_connect_allowed?(request_signature.uri)
      response = @perform.call
      invoke_callbacks(response.to_webmock, real_request: true)
      response
    end

    def halt
      raise ::WebMock::NetConnectNotAllowedError.new request_signature
    end

    def invoke_callbacks(webmock_response, options = {})
      ::WebMock::CallbackRegistry.invoke_callbacks(
        options.merge({ lib: :http_rb }),
        request_signature,
        webmock_response
      )
    end
  end
end
