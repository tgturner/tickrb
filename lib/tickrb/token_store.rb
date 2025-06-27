# typed: true
# frozen_string_literal: true

require "json"

module Tickrb
  class TokenStore
    def self.store_token(token_info)
      # TODO: make this respect some standard?
      config_dir = File.expand_path("~/.config/tickrb")
      Dir.mkdir(config_dir) unless Dir.exist?(config_dir)

      File.write(File.join(config_dir, "token.json"), {
        access_token: token_info["access_token"],
        expires_at: Time.now.utc + (token_info["expires_in"] - 60)
      }.to_json)
    end

    def self.load_token
      token_file = File.expand_path("~/.config/tickrb/token.json")
      return nil unless File.exist?(token_file)

      data = JSON.parse(File.read(token_file))
      return nil if Time.now.utc > Time.parse(data["expires_at"]).utc

      data["access_token"]
    end
  end
end
