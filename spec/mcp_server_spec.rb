# typed: false
# frozen_string_literal: true

require "spec_helper"
require "json"
require "stringio"

RSpec.describe Tickrb::McpServer do
  let(:server) { described_class.new }
  let(:mock_client) { double("Client") }

  before do
    allow(Tickrb::Client).to receive(:new).and_return(mock_client)
    allow(mock_client).to receive(:is_a?).with(Tickrb::Client).and_return(true)
  end

  describe "#initialize" do
    it "initializes with empty tools and resources" do
      expect(server.instance_variable_get(:@tools)).to be_a(Hash)
      expect(server.instance_variable_get(:@resources)).to be_a(Hash)
    end

    it "registers default tools" do
      tools = server.instance_variable_get(:@tools)
      expect(tools).to have_key("ping")
      expect(tools).to have_key("list_tasks")
      expect(tools).to have_key("create_task")
      expect(tools).to have_key("complete_task")
      expect(tools).to have_key("delete_task")
      expect(tools).to have_key("list_projects")
    end
  end

  describe "#handle_request" do
    let(:request_id) { "test-id-123" }

    context "initialize request" do
      let(:request) do
        {
          "method" => "initialize",
          "params" => {},
          "id" => request_id
        }
      end

      it "returns initialization response" do
        response = server.send(:handle_request, request)

        expect(response).to include(
          jsonrpc: "2.0",
          id: request_id,
          result: hash_including(
            protocolVersion: "2024-11-05",
            capabilities: hash_including(tools: {}, resources: {}),
            serverInfo: hash_including(
              name: "tickrb-mcp-server",
              version: "0.1.0"
            )
          )
        )
      end
    end

    context "tools/list request" do
      let(:request) do
        {
          "method" => "tools/list",
          "id" => request_id
        }
      end

      it "returns list of available tools" do
        response = server.send(:handle_request, request)

        expect(response).to include(
          jsonrpc: "2.0",
          id: request_id,
          result: hash_including(
            tools: array_including(
              hash_including(name: "ping", description: "Simple ping tool to test server connectivity"),
              hash_including(name: "list_tasks", description: "Get all tasks from TickTick"),
              hash_including(name: "create_task", description: "Create a new task in TickTick")
            )
          )
        )
      end
    end

    context "tools/call request" do
      let(:request) do
        {
          "method" => "tools/call",
          "params" => {
            "name" => tool_name,
            "arguments" => arguments
          },
          "id" => request_id
        }
      end

      context "ping tool" do
        let(:tool_name) { "ping" }
        let(:arguments) { {"message" => "test message"} }

        it "calls ping tool and returns response" do
          response = server.send(:handle_request, request)

          expect(response[:jsonrpc]).to eq("2.0")
          expect(response[:id]).to eq(request_id)
          expect(response[:result][:content][0][:type]).to eq("text")

          content = JSON.parse(response[:result][:content][0][:text])
          expect(content["message"]).to eq("Pong! test message")
        end
      end

      context "list_tasks tool" do
        let(:tool_name) { "list_tasks" }
        let(:arguments) { {} }
        let(:mock_tasks) do
          [
            {"id" => "task1", "title" => "Test Task", "projectId" => "project1", "status" => 0},
            {"id" => "task2", "title" => "Another Task", "projectId" => "project1", "status" => 1}
          ]
        end

        before do
          allow(mock_client).to receive(:get_tasks).and_return(mock_tasks)
        end

        it "calls list_tasks tool and returns formatted response" do
          response = server.send(:handle_request, request)

          expect(response[:jsonrpc]).to eq("2.0")
          expect(response[:id]).to eq(request_id)
          expect(response[:result][:content][0][:type]).to eq("text")

          content = JSON.parse(response[:result][:content][0][:text])
          expect(content["success"]).to be true
          expect(content["count"]).to eq(2)
          expect(content["tasks"][0]["id"]).to eq("task1")
          expect(content["tasks"][0]["title"]).to eq("Test Task")
          expect(content["tasks"][0]["status"]).to eq(0) # Expecting the actual status from mock data
        end

        context "when client raises error" do
          before do
            allow(mock_client).to receive(:get_tasks).and_raise(Tickrb::Error, "API Error")
          end

          it "returns error response" do
            response = server.send(:handle_request, request)

            expected_content = {
              success: false,
              error: "API Error",
              tasks: [],
              count: 0
            }

            expect(response).to include(
              jsonrpc: "2.0",
              id: request_id,
              result: hash_including(
                content: [
                  hash_including(
                    type: "text",
                    text: expected_content.to_json
                  )
                ]
              )
            )
          end
        end
      end

      context "create_task tool" do
        let(:tool_name) { "create_task" }
        let(:arguments) { {"title" => "New Task", "content" => "Task description"} }
        let(:created_task) { {"id" => "new_task_id", "title" => "New Task", "content" => "Task description"} }

        before do
          allow(mock_client).to receive(:create_task).and_return(created_task)
        end

        it "calls create_task tool" do
          response = server.send(:handle_request, request)

          expect(mock_client).to have_received(:create_task).with(
            title: "New Task",
            content: "Task description",
            project_id: nil
          )

          expected_content = {
            success: true,
            task: {
              id: "new_task_id",
              title: "New Task",
              content: "Task description",
              project_id: nil
            }
          }

          expect(response).to include(
            jsonrpc: "2.0",
            id: request_id,
            result: hash_including(
              content: [
                hash_including(
                  type: "text",
                  text: expected_content.to_json
                )
              ]
            )
          )
        end
      end

      context "complete_task tool" do
        let(:tool_name) { "complete_task" }
        let(:arguments) { {"task_id" => "task123", "project_id" => "project123"} }

        before do
          allow(mock_client).to receive(:complete_task).and_return({})
        end

        it "calls complete_task tool" do
          response = server.send(:handle_request, request)

          expect(mock_client).to have_received(:complete_task).with("task123", "project123")

          expected_content = {
            success: true,
            message: "Task marked as completed",
            task_id: "task123"
          }

          expect(response).to include(
            jsonrpc: "2.0",
            id: request_id,
            result: hash_including(
              content: [
                hash_including(
                  type: "text",
                  text: expected_content.to_json
                )
              ]
            )
          )
        end
      end

      context "delete_task tool" do
        let(:tool_name) { "delete_task" }
        let(:arguments) { {"task_id" => "task123", "project_id" => "project123"} }

        before do
          allow(mock_client).to receive(:delete_task).and_return({})
        end

        it "calls delete_task tool" do
          response = server.send(:handle_request, request)

          expect(mock_client).to have_received(:delete_task).with("task123", "project123")

          expected_content = {
            success: true,
            message: "Task deleted successfully",
            task_id: "task123"
          }

          expect(response).to include(
            jsonrpc: "2.0",
            id: request_id,
            result: hash_including(
              content: [
                hash_including(
                  type: "text",
                  text: expected_content.to_json
                )
              ]
            )
          )
        end
      end

      context "list_projects tool" do
        let(:tool_name) { "list_projects" }
        let(:arguments) { {} }
        let(:mock_projects) { [{"id" => "project1", "name" => "Test Project"}] }

        before do
          allow(mock_client).to receive(:get_projects).and_return(mock_projects)
        end

        it "calls list_projects tool" do
          response = server.send(:handle_request, request)

          expected_content = {
            success: true,
            projects: [
              {
                id: "project1",
                name: "Test Project"
              }
            ],
            count: 1
          }

          expect(response).to include(
            jsonrpc: "2.0",
            id: request_id,
            result: hash_including(
              content: [
                hash_including(
                  type: "text",
                  text: expected_content.to_json
                )
              ]
            )
          )
        end
      end

      context "non-existent tool" do
        let(:tool_name) { "non_existent_tool" }
        let(:arguments) { {} }

        it "returns tool not found error" do
          response = server.send(:handle_request, request)

          expect(response).to include(
            jsonrpc: "2.0",
            id: request_id,
            error: hash_including(
              code: -32602,
              message: "Tool not found: non_existent_tool"
            )
          )
        end
      end
    end

    context "resources/list request" do
      let(:request) do
        {
          "method" => "resources/list",
          "id" => request_id
        }
      end

      it "returns empty resources list" do
        response = server.send(:handle_request, request)

        expect(response).to include(
          jsonrpc: "2.0",
          id: request_id,
          result: hash_including(
            resources: []
          )
        )
      end
    end

    context "unknown method" do
      let(:request) do
        {
          "method" => "unknown_method",
          "id" => request_id
        }
      end

      it "returns method not found error" do
        response = server.send(:handle_request, request)

        expect(response).to include(
          jsonrpc: "2.0",
          id: request_id,
          error: hash_including(
            code: -32601,
            message: "Method not found"
          )
        )
      end
    end
  end

  describe "#get_client" do
    it "creates and memoizes client instance" do
      client1 = server.send(:get_client)
      client2 = server.send(:get_client)

      expect(client1).to be(client2)
      expect(Tickrb::Client).to have_received(:new).once
    end
  end

  describe "#register_tool" do
    let(:tool_name) { "test_tool" }
    let(:tool_description) { "Test tool description" }
    let(:input_schema) { {"type" => "object"} }
    let(:handler) { ->(args) { "test result" } }

    it "registers tool with handler" do
      server.send(:register_tool,
        name: tool_name,
        description: tool_description,
        inputSchema: input_schema,
        &handler)

      tools = server.instance_variable_get(:@tools)
      expect(tools[tool_name]).to include(
        name: tool_name,
        description: tool_description,
        inputSchema: input_schema
      )
      expect(tools[tool_name][:handler]).to be_a(Proc)
    end
  end

  describe "#register_resource" do
    let(:resource_name) { "test_resource" }
    let(:resource_description) { "Test resource description" }
    let(:resource_uri) { "test://resource" }
    let(:mime_type) { "text/plain" }
    let(:handler) { -> { "resource content" } }

    it "registers resource with handler" do
      server.send(:register_resource,
        name: resource_name,
        description: resource_description,
        uri: resource_uri,
        mimeType: mime_type,
        &handler)

      resources = server.instance_variable_get(:@resources)
      expect(resources[resource_name]).to include(
        name: resource_name,
        description: resource_description,
        uri: resource_uri,
        mimeType: mime_type
      )
      expect(resources[resource_name][:handler]).to be_a(Proc)
    end
  end

  describe ".start" do
    it "creates new instance and starts server" do
      mock_server = double("McpServer")
      allow(described_class).to receive(:new).and_return(mock_server)
      allow(mock_server).to receive(:start)

      described_class.start

      expect(described_class).to have_received(:new)
      expect(mock_server).to have_received(:start)
    end
  end
end
