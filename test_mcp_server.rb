#!/usr/bin/env ruby
# Test script for the MCP server

require "json"
require "open3"
require "timeout"

def test_mcp_server
  puts "Testing MCP Server..."

  # Start the server process
  server_cmd = "ruby bin/tickrb-mcp-server"

  Open3.popen3(server_cmd) do |stdin, stdout, stderr, wait_thr|
    # Check for any startup errors
    puts "Checking server startup..."
    sleep 0.1 # Give server a moment to start

    # Check if there are any error messages
    begin
      error_output = stderr.read_nonblock(1000)
      puts "Server errors: #{error_output}" unless error_output.empty?
    rescue IO::WaitReadable
      # No errors, continue
    end

    # Test 1: Initialize
    puts "\n1. Testing initialize..."
    init_request = {
      jsonrpc: "2.0",
      id: 1,
      method: "initialize",
      params: {
        protocolVersion: "2024-11-05",
        capabilities: {},
        clientInfo: {
          name: "test-client",
          version: "1.0.0"
        }
      }
    }

    puts "Sending: #{init_request.to_json}"
    stdin.puts init_request.to_json
    stdin.flush

    # Add timeout to prevent hanging
    response = nil
    begin
      Timeout.timeout(5) do
        response_line = stdout.gets
        puts "Received: #{response_line}"
        response = JSON.parse(response_line)
      end
    rescue Timeout::Error
      puts "❌ Timeout waiting for response"
      break
    end

    if response && response["result"] && response["result"]["protocolVersion"]
      puts "✅ Initialize successful"
      puts "   Protocol version: #{response["result"]["protocolVersion"]}"
      puts "   Server name: #{response["result"]["serverInfo"]["name"]}"
    else
      puts "❌ Initialize failed: #{response}"
    end

    # Test 2: List tools
    puts "\n2. Testing tools/list..."
    list_request = {
      jsonrpc: "2.0",
      id: 2,
      method: "tools/list"
    }

    stdin.puts list_request.to_json
    response = JSON.parse(stdout.gets)

    if response["result"] && response["result"]["tools"]
      puts "✅ Tools list successful"
      puts "   Available tools:"
      response["result"]["tools"].each do |tool|
        puts "   - #{tool["name"]}: #{tool["description"]}"
      end
    else
      puts "❌ Tools list failed: #{response}"
    end

    # Test 3: Call ping tool
    puts "\n3. Testing tools/call (ping)..."
    call_request = {
      jsonrpc: "2.0",
      id: 3,
      method: "tools/call",
      params: {
        name: "ping",
        arguments: {
          message: "test message"
        }
      }
    }

    stdin.puts call_request.to_json
    response = JSON.parse(stdout.gets)

    if response["result"] && response["result"]["content"]
      puts "✅ Ping tool successful"
      puts "   Response: #{response["result"]["content"][0]["text"]}"
    else
      puts "❌ Ping tool failed: #{response}"
    end

    # Test 4: Call list_tasks tool
    puts "\n4. Testing tools/call (list_tasks)..."
    list_tasks_request = {
      jsonrpc: "2.0",
      id: 4,
      method: "tools/call",
      params: {
        name: "list_tasks",
        arguments: {}
      }
    }

    stdin.puts list_tasks_request.to_json
    response_line = stdout.gets
    puts "Raw response: #{response_line}"
    response = JSON.parse(response_line)

    if response["result"] && response["result"]["content"]
      puts "✅ List tasks tool successful"
      puts "   Response: #{response["result"]["content"][0]["text"]}"
    else
      puts "❌ List tasks tool failed: #{response}"
      if response["error"]
        puts "   Error code: #{response["error"]["code"]}"
        puts "   Error message: #{response["error"]["message"]}"
        puts "   Error data: #{response["error"]["data"]}" if response["error"]["data"]
      end
    end

    # Close stdin to signal end of input
    stdin.close

    # Wait for process to finish
    wait_thr.join

    puts "\n✅ MCP Server test completed!"
  end
rescue => e
  puts "❌ Test failed: #{e.message}"
  puts e.backtrace.first(5)
end

if __FILE__ == $0
  test_mcp_server
end
