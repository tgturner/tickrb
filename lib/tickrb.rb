# typed: true
# frozen_string_literal: true

require "dotenv/load"
require "sorbet-runtime"

require_relative "tickrb/version"
require_relative "tickrb/auth"
require_relative "tickrb/token_store"
require_relative "tickrb/client"
require_relative "tickrb/mcp_server"

module Tickrb
  extend T::Sig

  class Error < StandardError; end

  class << self
    def mcp_server(options = {})
      auth(options)

      McpServer.start
    end

    def auth(options = {})
      existing_token = TokenStore.load_token

      unless existing_token
        Auth.run(
          client_id: options[:client_id],
          client_secret: options[:client_secret],
          redirect_uri: options[:redirect_uri]
        )
      end
    end
  end
end
