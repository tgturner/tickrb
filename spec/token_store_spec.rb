# typed: false
# frozen_string_literal: true

require "spec_helper"
require "json"
require "tempfile"

RSpec.describe Tickrb::TokenStore do
  let(:config_dir) { File.expand_path("~/.config/tickrb") }
  let(:token_file) { File.join(config_dir, "token.json") }
  let(:token_info) { {"access_token" => "test_token", "expires_in" => 3600} }

  before do
    # Clean up any existing token file
    FileUtils.rm_f(token_file) if File.exist?(token_file)
  end

  after do
    # Clean up test token file
    FileUtils.rm_f(token_file) if File.exist?(token_file)
  end

  describe ".store_token" do
    it "creates config directory if it doesn't exist" do
      FileUtils.rm_rf(config_dir) if Dir.exist?(config_dir)

      described_class.store_token(token_info)

      expect(Dir.exist?(config_dir)).to be true
    end

    it "stores token with expiration time" do
      freeze_time = Time.now.utc
      allow(Time).to receive(:now).and_return(freeze_time)

      described_class.store_token(token_info)

      expect(File.exist?(token_file)).to be true

      stored_data = JSON.parse(File.read(token_file))
      expect(stored_data["access_token"]).to eq("test_token")

      expected_expires_at = freeze_time + (3600 - 60)
      expect(Time.parse(stored_data["expires_at"])).to be_within(1).of(expected_expires_at)
    end

    it "overwrites existing token file" do
      described_class.store_token(token_info)

      new_token_info = {"access_token" => "new_token", "expires_in" => 7200}
      described_class.store_token(new_token_info)

      stored_data = JSON.parse(File.read(token_file))
      expect(stored_data["access_token"]).to eq("new_token")
    end
  end

  describe ".load_token" do
    context "when token file doesn't exist" do
      it "returns nil" do
        expect(described_class.load_token).to be_nil
      end
    end

    context "when token file exists" do
      context "with valid unexpired token" do
        before do
          Dir.mkdir(config_dir) unless Dir.exist?(config_dir)
          token_data = {
            access_token: "valid_token",
            expires_at: (Time.now.utc + 3600).iso8601
          }
          File.write(token_file, token_data.to_json)
        end

        it "returns the access token" do
          expect(described_class.load_token).to eq("valid_token")
        end
      end

      context "with expired token" do
        before do
          Dir.mkdir(config_dir) unless Dir.exist?(config_dir)
          token_data = {
            access_token: "expired_token",
            expires_at: (Time.now.utc - 3600).iso8601
          }
          File.write(token_file, token_data.to_json)
        end

        it "returns nil" do
          expect(described_class.load_token).to be_nil
        end
      end

      context "with malformed JSON" do
        before do
          Dir.mkdir(config_dir) unless Dir.exist?(config_dir)
          File.write(token_file, "invalid json")
        end

        it "raises JSON parse error" do
          expect { described_class.load_token }.to raise_error(JSON::ParserError)
        end
      end

      context "with token at expiration boundary" do
        before do
          Dir.mkdir(config_dir) unless Dir.exist?(config_dir)
          # Token expires exactly now
          token_data = {
            access_token: "boundary_token",
            expires_at: Time.now.utc.iso8601
          }
          File.write(token_file, token_data.to_json)
        end

        it "returns nil when token is expired" do
          # Sleep to ensure we're past the expiration
          sleep(0.1)
          expect(described_class.load_token).to be_nil
        end
      end
    end
  end

  describe "integration test" do
    it "can store and load token successfully" do
      freeze_time = Time.now.utc
      allow(Time).to receive(:now).and_return(freeze_time)

      # Store token
      described_class.store_token(token_info)

      # Load token
      loaded_token = described_class.load_token

      expect(loaded_token).to eq("test_token")
    end

    it "handles token expiration correctly" do
      freeze_time = Time.now.utc
      allow(Time).to receive(:now).and_return(freeze_time)

      # Store token that expires in 1 second (but we subtract 60 seconds in store_token)
      short_lived_token = {"access_token" => "short_token", "expires_in" => 120}
      described_class.store_token(short_lived_token)

      # Token should be valid immediately
      expect(described_class.load_token).to eq("short_token")

      # Move time forward past expiration
      future_time = freeze_time + 120 # Past the expires_in time
      allow(Time).to receive(:now).and_return(future_time)

      # Token should now be expired
      expect(described_class.load_token).to be_nil
    end
  end
end
