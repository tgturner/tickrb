# typed: true
# frozen_string_literal: true

require "json"
require "sorbet-runtime"

require_relative "client"
require_relative "version"

module Tickrb
  class Error < StandardError; end

  class McpServer
    extend T::Sig

    JSONRPC = "2.0"
    PROTOCOL_VERSION = "2024-11-05"
    SERVER_INFO = {
      name: "tickrb-mcp-server",
      version: VERSION
    }

    class << self
      def start
        new.start
      end
    end

    sig { void }
    def initialize
      @tools = {}
      @resources = {}
      @client = nil

      register_default_tools
      register_ticktick_tools
    end

    sig { void }
    def start
      loop do
        input = $stdin.gets
        break if input.nil?

        begin
          request = JSON.parse(input.strip)
          response = handle_request(request)
          puts response.to_json if response
          $stdout.flush
        rescue JSON::ParserError => e
          error_response = {
            jsonrpc: JSONRPC,
            error: {
              code: -32700,
              message: "Parse error",
              data: e.message
            },
            id: nil
          }
          puts error_response.to_json
        rescue => e
          error_response = {
            jsonrpc: JSONRPC,
            error: {
              code: -32603,
              message: "Internal error",
              data: e.message
            },
            id: request&.dig("id")
          }
          puts error_response.to_json
        end
      end
    end

    private

    sig { params(request: T::Hash[String, T.untyped]).returns(T.nilable(T::Hash[String, T.untyped])) }
    def handle_request(request)
      method = request["method"]
      params = request["params"] || {}
      id = request["id"]

      case method
      when "initialize"
        handle_initialize(params, id)
      when "tools/list"
        handle_list_tools(id)
      when "tools/call"
        handle_call_tool(params, id)
      when "resources/list"
        handle_list_resources(id)
      when "resources/read"
        handle_read_resource(params, id)
      else
        {
          jsonrpc: JSONRPC,
          error: {
            code: -32601,
            message: "Method not found"
          },
          id: id
        }
      end
    end

    sig { params(params: T::Hash[String, T.untyped], id: T.untyped).returns(T::Hash[String, T.untyped]) }
    def handle_initialize(params, id)
      {
        jsonrpc: JSONRPC,
        result: {
          protocolVersion: PROTOCOL_VERSION, # rubocop:disable Naming/VariableName
          capabilities: {
            tools: {},
            resources: {}
          },
          serverInfo: SERVER_INFO # rubocop:disable Naming/VariableName
        },
        id: id
      }
    end

    sig { params(id: T.untyped).returns(T::Hash[String, T.untyped]) }
    def handle_list_tools(id)
      {
        jsonrpc: JSONRPC,
        result: {
          tools: @tools.values
        },
        id: id
      }
    end

    sig { params(params: T::Hash[String, T.untyped], id: T.untyped).returns(T::Hash[String, T.untyped]) }
    def handle_call_tool(params, id)
      tool_name = params["name"]
      arguments = params["arguments"] || {}

      unless @tools.key?(tool_name)
        return {
          jsonrpc: JSONRPC,
          error: {
            code: -32602,
            message: "Tool not found: #{tool_name}"
          },
          id: id
        }
      end

      tool = @tools[tool_name]
      result = tool[:handler].call(arguments)

      # Handle structured responses vs string responses
      content = if result.is_a?(Hash)
        [
          {
            type: "text",
            text: result.to_json
          }
        ]
      else
        [
          {
            type: "text",
            text: result
          }
        ]
      end

      {
        jsonrpc: "2.0",
        result: {
          content: content
        },
        id: id
      }
    end

    sig { params(id: T.untyped).returns(T::Hash[String, T.untyped]) }
    def handle_list_resources(id)
      {
        jsonrpc: JSONRPC,
        result: {
          resources: @resources.values
        },
        id: id
      }
    end

    sig { params(params: T::Hash[String, T.untyped], id: T.untyped).returns(T::Hash[String, T.untyped]) }
    def handle_read_resource(params, id)
      uri = params["uri"]

      resource = @resources.values.find { |r| r[:uri] == uri }
      unless resource
        return {
          jsonrpc: JSONRPC,
          error: {
            code: -32602,
            message: "Resource not found: #{uri}"
          },
          id: id
        }
      end

      content = resource[:handler].call
      {
        jsonrpc: JSONRPC,
        result: {
          contents: [
            {
              uri: uri,
              mimeType: resource[:mimeType] || "text/plain", # rubocop:disable Naming/VariableName
              text: content
            }
          ]
        },
        id: id
      }
    end

    sig { void }
    def register_default_tools
      register_tool(
        name: "ping",
        description: "Simple ping tool to test server connectivity",
        inputSchema: { # rubocop:disable Naming/VariableName
          type: "object",
          properties: {
            message: {
              type: "string",
              description: "Message to echo back"
            }
          }
        }
      ) do |args|
        {
          message: "Pong! #{args["message"] || "Hello from TickRb MCP Server"}"
        }
      end
    end

    sig { void }
    def register_ticktick_tools
      register_tool(
        name: "list_tasks",
        description: "Get all tasks from TickTick",
        inputSchema: { # rubocop:disable Naming/VariableName
          type: "object",
          properties: {}
        }
      ) do |args|
        client = get_client
        tasks = client.get_tasks
        {
          success: true,
          tasks: tasks.map do |task|
            {
              id: task["id"],
              title: task["title"],
              project_id: task["projectId"],
              due_date: task["dueDate"],
              description: task["desc"],
              status: task["status"] || "open"
            }
          end,
          count: tasks.length
        }
      rescue => e
        {
          success: false,
          error: e.message,
          tasks: [],
          count: 0
        }
      end

      register_tool(
        name: "create_task",
        description: "Create a new task in TickTick",
        inputSchema: { # rubocop:disable Naming/VariableName
          type: "object",
          properties: {
            title: {
              type: "string",
              description: "Task title"
            },
            content: {
              type: "string",
              description: "Task description/content"
            },
            project_id: {
              type: "string",
              description: "Project ID to add task to"
            }
          },
          required: ["title"]
        }
      ) do |args|
        client = get_client
        task = client.create_task(
          title: args["title"],
          content: args["content"],
          project_id: args["project_id"]
        )
        {
          success: true,
          task: {
            id: task["id"],
            title: task["title"],
            content: task["content"],
            project_id: task["projectId"]
          }
        }
      rescue => e
        {
          success: false,
          error: e.message,
          task: nil
        }
      end

      register_tool(
        name: "complete_task",
        description: "Mark a task as completed in TickTick",
        inputSchema: { # rubocop:disable Naming/VariableName
          type: "object",
          properties: {
            task_id: {
              type: "string",
              description: "ID of the task to complete"
            },
            project_id: {
              type: "string",
              description: "ID of the project containing the task"
            }
          },
          required: ["task_id", "project_id"]
        }
      ) do |args|
        client = get_client
        client.complete_task(args["task_id"], args["project_id"])
        {
          success: true,
          message: "Task marked as completed",
          task_id: args["task_id"]
        }
      rescue => e
        {
          success: false,
          error: e.message,
          task_id: args["task_id"]
        }
      end

      register_tool(
        name: "delete_task",
        description: "Delete a task in TickTick",
        inputSchema: { # rubocop:disable Naming/VariableName
          type: "object",
          properties: {
            task_id: {
              type: "string",
              description: "ID of the task to delete"
            },
            project_id: {
              type: "string",
              description: "ID of the project containing the task"
            }
          },
          required: ["task_id", "project_id"]
        }
      ) do |args|
        client = get_client
        client.delete_task(args["task_id"], args["project_id"])
        {
          success: true,
          message: "Task deleted successfully",
          task_id: args["task_id"]
        }
      rescue => e
        {
          success: false,
          error: e.message,
          task_id: args["task_id"]
        }
      end

      register_tool(
        name: "list_projects",
        description: "Get all projects from TickTick",
        inputSchema: { # rubocop:disable Naming/VariableName
          type: "object",
          properties: {}
        }
      ) do |args|
        client = get_client
        projects = client.get_projects
        {
          success: true,
          projects: projects.map do |project|
            {
              id: project["id"],
              name: project["name"]
            }
          end,
          count: projects.length
        }
      rescue => e
        {
          success: false,
          error: e.message,
          projects: [],
          count: 0
        }
      end
    end

    sig { returns(Client) }
    def get_client
      @client ||= Client.new
    end

    sig { params(name: String, description: String, inputSchema: T::Hash[String, T.untyped], block: T.proc.params(args: T::Hash[String, T.untyped]).returns(T::Hash[T.untyped, T.untyped])).void }
    def register_tool(name:, description:, inputSchema:, &block) # rubocop:disable Naming/VariableName
      @tools[name] = {
        name: name,
        description: description,
        inputSchema: inputSchema, # rubocop:disable Naming/VariableName
        handler: block
      }
    end

    sig { params(name: String, description: String, uri: String, mimeType: T.nilable(String), block: T.proc.returns(String)).void }
    def register_resource(name:, description:, uri:, mimeType: nil, &block) # rubocop:disable Naming/VariableName
      @resources[name] = {
        name: name,
        description: description,
        uri: uri,
        mimeType: mimeType, # rubocop:disable Naming/VariableName
        handler: block
      }
    end
  end
end
