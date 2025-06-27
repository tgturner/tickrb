#!/usr/bin/env ruby
# Direct API testing script

require_relative "lib/tickrb"

def test_token_loading
  puts "=== Testing Token Loading ==="

  token_file = File.expand_path("~/.config/tickrb/token.json")
  puts "Token file path: #{token_file}"
  puts "Token file exists: #{File.exist?(token_file)}"

  if File.exist?(token_file)
    puts "Token file contents:"
    puts File.read(token_file)
    puts

    begin
      data = JSON.parse(File.read(token_file))
      expires_at = Time.parse(data["expires_at"]).utc
      now = Time.now.utc
      puts "Token expires at: #{expires_at}"
      puts "Current time: #{now}"
      puts "Token expired: #{now > expires_at}"
      puts "Token value: #{data["access_token"][0..20]}..." if data["access_token"]
    rescue => e
      puts "Error parsing token file: #{e.message}"
    end
  else
    puts "No token file found. Need to authenticate first."
  end
  puts
end

def test_client_creation
  puts "=== Testing Client Creation ==="

  begin
    client = Tickrb::Client.new
    puts "✅ Client created successfully"
    client
  rescue => e
    puts "❌ Client creation failed: #{e.message}"
    nil
  end
end

def test_api_calls(client)
  return unless client

  puts "=== Testing API Calls ==="

  # Test get_tasks
  puts "\n1. Testing get_tasks..."
  begin
    tasks = client.get_tasks
    puts "✅ get_tasks successful"
    puts "   Number of tasks: #{tasks.length}"
    if tasks.any?
      puts "   First task: #{tasks.first["title"]}"
    else
      puts "   No tasks found"
    end
  rescue => e
    puts "❌ get_tasks failed: #{e.message}"
  end

  # Test get_projects
  puts "\n2. Testing get_projects..."
  begin
    projects = client.get_projects
    puts "✅ get_projects successful"
    puts "   Number of projects: #{projects.length}"
    if projects.any?
      puts "   First project: #{projects.first["name"]}"
    else
      puts "   No projects found"
    end
  rescue => e
    puts "❌ get_projects failed: #{e.message}"
  end
end

def main
  puts "TickRb Direct API Test"
  puts "=" * 30

  test_token_loading
  client = test_client_creation
  test_api_calls(client)

  puts "\n" + "=" * 30
  puts "Test completed!"
end

if __FILE__ == $0
  main
end
