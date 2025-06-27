# typed: false
# frozen_string_literal: true

require "spec_helper"
require "webrick"
require "net/http"

RSpec.describe Tickrb::Auth do
  let(:client_id) { "test_client_id" }
  let(:client_secret) { "test_client_secret" }
  let(:redirect_uri) { "http://localhost:8080/callback" }
  let(:mock_token_store) { double("TokenStore") }

  subject(:auth) do
    described_class.new(
      client_id: client_id,
      client_secret: client_secret,
      redirect_uri: redirect_uri,
      token_store: mock_token_store
    )
  end

  describe "#initialize" do
    it "uses provided credentials" do
      expect(auth.send(:client_id)).to eq(client_id)
      expect(auth.send(:client_secret)).to eq(client_secret)
      expect(auth.send(:redirect_uri)).to eq(redirect_uri)
    end

    context "when using environment variables" do
      before do
        allow(ENV).to receive(:[]).with("CLIENT_ID").and_return("env_client_id")
        allow(ENV).to receive(:[]).with("CLIENT_SECRET").and_return("env_client_secret")
        allow(ENV).to receive(:[]).with("REDIRECT_URI").and_return("env_redirect_uri")
      end

      subject(:auth_with_env) { described_class.new(token_store: mock_token_store) }

      it "falls back to environment variables" do
        expect(auth_with_env.send(:client_id)).to eq("env_client_id")
        expect(auth_with_env.send(:client_secret)).to eq("env_client_secret")
        expect(auth_with_env.send(:redirect_uri)).to eq("env_redirect_uri")
      end
    end
  end

  describe "#exchange_code_for_token" do
    let(:auth_code) { "test_auth_code" }
    let(:mock_response) do
      double("Response", body: {
        "access_token" => "test_token",
        "expires_in" => 3600,
        "other_field" => "ignored"
      }.to_json)
    end
    let(:mock_http) { double("HTTP") }
    let(:mock_request) { double("Request") }

    before do
      allow(URI).to receive(:new).with("https://ticktick.com/oauth/token").and_return(double(host: "ticktick.com", port: 443))
      allow(Net::HTTP).to receive(:new).and_return(mock_http)
      allow(mock_http).to receive(:use_ssl=)
      allow(Net::HTTP::Post).to receive(:new).and_return(mock_request)
      allow(mock_request).to receive(:body=)
      allow(mock_request).to receive(:[]=)
      allow(mock_http).to receive(:request).and_return(mock_response)
    end

    it "exchanges authorization code for access token" do
      result = auth.send(:exchange_code_for_token, auth_code)

      expect(result).to eq({
        "access_token" => "test_token",
        "expires_in" => 3600
      })
    end

    it "makes correct HTTP request" do
      auth.send(:exchange_code_for_token, auth_code)

      expect(mock_http).to have_received(:use_ssl=).with(true)
      expect(mock_request).to have_received(:body=).with(
        URI.encode_www_form({
          grant_type: "authorization_code",
          code: auth_code,
          redirect_uri: redirect_uri,
          scope: "tasks:write tasks:read"
        })
      )
      expect(mock_request).to have_received(:[]=).with("Content-Type", "application/x-www-form-urlencoded")
      expect(mock_request).to have_received(:[]=).with("Authorization", /^Basic/)
      expect(mock_request).to have_received(:[]=).with("User-Agent", "curl/8.7.1")
    end
  end

  describe "#scope" do
    it "returns correct OAuth scope" do
      expect(auth.send(:scope)).to eq("tasks:write tasks:read")
    end
  end

  describe "#basic_auth" do
    it "returns base64 encoded client credentials" do
      expected = Base64.encode64("#{client_id}:#{client_secret}")
      expect(auth.send(:basic_auth)).to eq(expected)
    end
  end

  describe "#build_auth_url_params" do
    let(:params) do
      {
        client_id: client_id,
        scope: "tasks:write tasks:read",
        redirect_uri: redirect_uri,
        response_type: "code"
      }
    end

    it "builds URL encoded parameter string" do
      result = auth.send(:build_auth_url_params, params)
      expect(result).to include("client_id=#{client_id}")
      expect(result).to include("scope=tasks%3Awrite+tasks%3Aread")
      expect(result).to include("redirect_uri=http%3A%2F%2Flocalhost%3A8080%2Fcallback")
      expect(result).to include("response_type=code")
    end
  end

  describe ".run" do
    it "creates new instance and runs OAuth flow" do
      mock_auth = double("Auth")
      allow(described_class).to receive(:new).and_return(mock_auth)
      allow(mock_auth).to receive(:run_oauth_flow)

      described_class.run

      expect(described_class).to have_received(:new).with(
        client_id: nil,
        client_secret: nil,
        redirect_uri: nil
      )
      expect(mock_auth).to have_received(:run_oauth_flow)
    end

    it "passes credentials to new instance" do
      mock_auth = double("Auth")
      allow(described_class).to receive(:new).and_return(mock_auth)
      allow(mock_auth).to receive(:run_oauth_flow)

      described_class.run(
        client_id: "test_id",
        client_secret: "test_secret",
        redirect_uri: "test_uri"
      )

      expect(described_class).to have_received(:new).with(
        client_id: "test_id",
        client_secret: "test_secret",
        redirect_uri: "test_uri"
      )
      expect(mock_auth).to have_received(:run_oauth_flow)
    end
  end
end
