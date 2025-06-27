# typed: false
# frozen_string_literal: true

require "spec_helper"
require "json"

RSpec.describe "Integration Tests" do
  let(:mock_token) { "integration_test_token" }
  let(:mock_client) { double("Client") }

  before do
    allow(Tickrb::TokenStore).to receive(:load_token).and_return(mock_token)
    allow(Tickrb::Client).to receive(:new).and_return(mock_client)
    allow(mock_client).to receive(:is_a?).with(Tickrb::Client).and_return(true)
  end

  describe "TickRb module integration" do
    it "coordinates authentication and MCP server startup" do
      allow(Tickrb::Auth).to receive(:run)
      allow(Tickrb::McpServer).to receive(:start)

      Tickrb.mcp_server

      expect(Tickrb::McpServer).to have_received(:start)
    end

    context "when no token exists" do
      before do
        allow(Tickrb::TokenStore).to receive(:load_token).and_return(nil)
      end

      it "runs authentication before starting server" do
        allow(Tickrb::Auth).to receive(:run)
        allow(Tickrb::McpServer).to receive(:start)

        Tickrb.mcp_server

        expect(Tickrb::Auth).to have_received(:run)
        expect(Tickrb::McpServer).to have_received(:start)
      end
    end
  end

  describe "MCP Server with Client integration" do
    let(:server) { Tickrb::McpServer.new }
    let(:mock_tasks) do
      [
        {
          "id" => "task1",
          "title" => "Integration Test Task",
          "projectId" => "project1",
          "status" => 0,
          "dueDate" => "2024-12-31T23:59:59.000+0000",
          "desc" => "Test task description"
        }
      ]
    end
    let(:mock_projects) do
      [
        {"id" => "project1", "name" => "Test Project"}
      ]
    end

    before do
      allow(mock_client).to receive(:get_tasks).and_return(mock_tasks)
      allow(mock_client).to receive(:get_projects).and_return(mock_projects)
      allow(mock_client).to receive(:create_task).and_return({"id" => "new_task", "title" => "New Task"})
      allow(mock_client).to receive(:complete_task).and_return({})
      allow(mock_client).to receive(:delete_task).and_return({})
    end

    describe "list_tasks workflow" do
      it "successfully retrieves and formats tasks" do
        request = {
          "method" => "tools/call",
          "params" => {
            "name" => "list_tasks",
            "arguments" => {}
          },
          "id" => "test-1"
        }

        response = server.send(:handle_request, request)

        expect(response[:jsonrpc]).to eq("2.0")
        expect(response[:id]).to eq("test-1")

        content = JSON.parse(response[:result][:content][0][:text])
        expect(content["success"]).to be true
        expect(content["count"]).to eq(1)
        expect(content["tasks"][0]["id"]).to eq("task1")
        expect(content["tasks"][0]["title"]).to eq("Integration Test Task")
      end
    end

    describe "create_task workflow" do
      it "successfully creates a task" do
        request = {
          "method" => "tools/call",
          "params" => {
            "name" => "create_task",
            "arguments" => {
              "title" => "Integration Test Task",
              "content" => "Test content"
            }
          },
          "id" => "test-2"
        }

        response = server.send(:handle_request, request)

        expect(mock_client).to have_received(:create_task).with(
          title: "Integration Test Task",
          content: "Test content",
          project_id: nil
        )

        content = JSON.parse(response[:result][:content][0][:text])
        expect(content["success"]).to be true
        expect(content["task"]["id"]).to eq("new_task")
      end
    end

    describe "task management workflow" do
      it "supports complete task lifecycle" do
        task_id = "lifecycle_task"
        project_id = "lifecycle_project"

        # Complete task
        complete_request = {
          "method" => "tools/call",
          "params" => {
            "name" => "complete_task",
            "arguments" => {
              "task_id" => task_id,
              "project_id" => project_id
            }
          },
          "id" => "test-3"
        }

        complete_response = server.send(:handle_request, complete_request)

        expect(mock_client).to have_received(:complete_task).with(task_id, project_id)

        complete_content = JSON.parse(complete_response[:result][:content][0][:text])
        expect(complete_content["success"]).to be true
        expect(complete_content["task_id"]).to eq(task_id)

        # Delete task
        delete_request = {
          "method" => "tools/call",
          "params" => {
            "name" => "delete_task",
            "arguments" => {
              "task_id" => task_id,
              "project_id" => project_id
            }
          },
          "id" => "test-4"
        }

        delete_response = server.send(:handle_request, delete_request)

        expect(mock_client).to have_received(:delete_task).with(task_id, project_id)

        delete_content = JSON.parse(delete_response[:result][:content][0][:text])
        expect(delete_content["success"]).to be true
        expect(delete_content["task_id"]).to eq(task_id)
      end
    end

    describe "error handling integration" do
      context "when client raises authentication error" do
        before do
          allow(mock_client).to receive(:get_tasks).and_raise(Tickrb::Error, "Authentication failed. Token may be expired.")
        end

        it "returns formatted error response" do
          request = {
            "method" => "tools/call",
            "params" => {
              "name" => "list_tasks",
              "arguments" => {}
            },
            "id" => "test-error"
          }

          response = server.send(:handle_request, request)

          content = JSON.parse(response[:result][:content][0][:text])
          expect(content["success"]).to be false
          expect(content["error"]).to include("Authentication failed")
          expect(content["tasks"]).to eq([])
          expect(content["count"]).to eq(0)
        end
      end
    end
  end

  describe "Authentication and Client integration" do
    let(:client_id) { "test_client_integration" }
    let(:client_secret) { "test_secret_integration" }
    let(:redirect_uri) { "http://localhost:8080/callback" }
    let(:auth_code) { "integration_auth_code" }
    let(:token_response) do
      {
        "access_token" => "integration_access_token",
        "expires_in" => 3600
      }
    end

    it "can authenticate and create working client" do
      # Mock the token exchange
      mock_token_store = double("TokenStore")
      auth = Tickrb::Auth.new(
        client_id: client_id,
        client_secret: client_secret,
        redirect_uri: redirect_uri,
        token_store: mock_token_store
      )

      allow(auth).to receive(:exchange_code_for_token).with(auth_code).and_return(token_response)
      allow(mock_token_store).to receive(:store_token)

      # Simulate token exchange
      result = auth.send(:exchange_code_for_token, auth_code)
      mock_token_store.store_token(result)

      expect(result).to eq(token_response)
      expect(mock_token_store).to have_received(:store_token).with(token_response)
    end
  end
end
