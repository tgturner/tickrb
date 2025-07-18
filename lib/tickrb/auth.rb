# typed: true
# frozen_string_literal: true

require "webrick"
require "net/http"
require "uri"
require "base64"
require "json"

require_relative "token_store"

AUTH_URL = "https://ticktick.com/oauth/authorize?"

module Tickrb
  class Auth
    class << self
      def run(client_id: nil, client_secret: nil, redirect_uri: nil)
        auth_client = new(
          client_id: client_id,
          client_secret: client_secret,
          redirect_uri: redirect_uri
        )
        auth_client.run_oauth_flow
      end
    end

    def initialize(client_id: nil, client_secret: nil, redirect_uri: nil, token_store: nil)
      @client_id = if client_id.nil? || client_id.empty?
        ENV["CLIENT_ID"]
      else
        client_id
      end

      @client_secret = if client_secret.nil? || client_secret.empty?
        ENV["CLIENT_SECRET"]
      else
        client_secret
      end

      @redirect_uri = if redirect_uri.nil? || redirect_uri.empty?
        ENV["REDIRECT_URI"]
      else
        redirect_uri
      end

      @token_store = token_store || TokenStore
    end

    def run_oauth_flow
      # Start local server to receive callback
      server = WEBrick::HTTPServer.new(Port: 8080, Logger: WEBrick::Log.new(File::NULL))

      # TODO: Generate a random state parameter for CSRF protection
      auth_params = {
        client_id: client_id,
        scope: scope,
        redirect_uri: redirect_uri,
        response_type: "code"
      }

      auth_url_params = build_auth_url_params(auth_params)
      auth_url = AUTH_URL + auth_url_params

      system("open \"#{auth_url}\"") # macOS, use 'xdg-open' on Linux

      # Handle callback
      server.mount_proc "/callback", ->(req, res) do
        code = req.query["code"]
        # Exchange code for token
        token_info = exchange_code_for_token(code)
        token_store.store_token(token_info)

        res.body = "Authentication successful! You can close this window."
        server.shutdown
      end

      server.start
    end

    private

    attr_reader :client_id, :client_secret, :redirect_uri, :token_store

    def exchange_code_for_token(code)
      uri = URI("https://ticktick.com/oauth/token")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true

      request = Net::HTTP::Post.new(uri)
      token_data = {
        grant_type: "authorization_code",
        code: code,
        redirect_uri: redirect_uri,
        scope: scope
      }

      request.body = URI.encode_www_form(token_data)

      request["Content-Type"] = "application/x-www-form-urlencoded"
      request["Authorization"] = "Basic #{basic_auth}".delete("\n")
      request["User-Agent"] = "curl/8.7.1"
      request["Accept-Encoding"] = nil

      response = http.request(request)

      JSON.parse(response.body).slice("access_token", "expires_in")
    end

    def scope
      "tasks:write tasks:read"
    end

    def basic_auth
      Base64.encode64("#{client_id}:#{client_secret}")
    end

    def build_auth_url_params(params)
      URI.encode_www_form(params)
    end
  end
end
