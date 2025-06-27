# typed: false
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Tickrb do
  it "has a version number" do
    expect(Tickrb::VERSION).not_to be nil
  end

  describe ".mcp_server" do
    it "calls auth and starts MCP server" do
      allow(Tickrb).to receive(:auth)
      allow(Tickrb::McpServer).to receive(:start)

      Tickrb.mcp_server

      expect(Tickrb).to have_received(:auth).with({})
      expect(Tickrb::McpServer).to have_received(:start)
    end

    it "passes options to auth" do
      allow(Tickrb).to receive(:auth)
      allow(Tickrb::McpServer).to receive(:start)

      options = {
        client_id: "test_id",
        client_secret: "test_secret",
        redirect_uri: "test_uri"
      }

      Tickrb.mcp_server(options)

      expect(Tickrb).to have_received(:auth).with(options)
      expect(Tickrb::McpServer).to have_received(:start)
    end
  end

  describe ".auth" do
    context "when token exists" do
      before do
        allow(Tickrb::TokenStore).to receive(:load_token).and_return("existing_token")
      end

      it "does not run authentication" do
        allow(Tickrb::Auth).to receive(:run)

        Tickrb.auth

        expect(Tickrb::Auth).not_to have_received(:run)
      end
    end

    context "when no token exists" do
      before do
        allow(Tickrb::TokenStore).to receive(:load_token).and_return(nil)
      end

      it "runs authentication with default options" do
        allow(Tickrb::Auth).to receive(:run)

        Tickrb.auth

        expect(Tickrb::Auth).to have_received(:run).with(
          client_id: nil,
          client_secret: nil,
          redirect_uri: nil
        )
      end

      it "runs authentication with provided options" do
        allow(Tickrb::Auth).to receive(:run)

        options = {
          client_id: "test_id",
          client_secret: "test_secret",
          redirect_uri: "test_uri"
        }

        Tickrb.auth(options)

        expect(Tickrb::Auth).to have_received(:run).with(
          client_id: "test_id",
          client_secret: "test_secret",
          redirect_uri: "test_uri"
        )
      end
    end
  end
end
