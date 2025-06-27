# typed: false
# frozen_string_literal: true

require "spec_helper"
require "net/http"

RSpec.describe Tickrb::Client do
  let(:token) { "test_access_token" }
  let(:mock_token_store) { double("TokenStore") }

  before do
    allow(Tickrb::TokenStore).to receive(:load_token).and_return(token)
  end

  subject(:client) { described_class.new(token: token) }

  describe "#initialize" do
    context "with token provided" do
      it "uses provided token" do
        expect(client.send(:token)).to eq(token)
      end
    end

    context "without token provided" do
      it "loads token from TokenStore" do
        client = described_class.new
        expect(client.send(:token)).to eq(token)
      end
    end

    context "when no token available" do
      before do
        allow(Tickrb::TokenStore).to receive(:load_token).and_return(nil)
      end

      it "raises error" do
        expect { described_class.new }.to raise_error(Tickrb::Error, /No authentication token available/)
      end
    end
  end

  describe "#get_tasks" do
    let(:projects) { [{"id" => "project1", "name" => "Test Project"}] }
    let(:project_tasks) { [{"id" => "task1", "title" => "Test Task"}] }

    before do
      allow(client).to receive(:get_projects).and_return(projects)
      allow(client).to receive(:get_tasks_for_project).with("project1").and_return(project_tasks)
    end

    it "fetches tasks from all projects" do
      tasks = client.get_tasks

      expect(tasks).to eq([{"id" => "task1", "title" => "Test Task", "projectId" => "project1"}])
    end

    context "when cache is valid" do
      before do
        client.instance_variable_set(:@tasks_cache, [{"cached" => "task"}])
        client.instance_variable_set(:@cache_timestamp, Time.now.utc)
      end

      it "returns cached tasks" do
        tasks = client.get_tasks
        expect(tasks).to eq([{"cached" => "task"}])
      end
    end
  end

  describe "#get_tasks_for_project" do
    let(:project_id) { "test_project_id" }
    let(:response) { {"tasks" => [{"id" => "task1", "title" => "Test Task"}]} }

    before do
      allow(client).to receive(:make_request).with("GET", "/project/#{project_id}/data").and_return(response)
    end

    it "fetches tasks for specific project" do
      tasks = client.get_tasks_for_project(project_id)
      expect(tasks).to eq([{"id" => "task1", "title" => "Test Task"}])
    end

    context "when response has no tasks" do
      let(:response) { {} }

      it "returns empty array" do
        tasks = client.get_tasks_for_project(project_id)
        expect(tasks).to eq([])
      end
    end
  end

  describe "#create_task" do
    let(:title) { "New Task" }
    let(:content) { "Task description" }
    let(:project_id) { "project123" }
    let(:response) { {"id" => "new_task_id", "title" => title} }

    before do
      allow(client).to receive(:make_request).and_return(response)
      allow(client).to receive(:invalidate_cache)
    end

    it "creates task with all parameters" do
      result = client.create_task(title: title, content: content, project_id: project_id)

      expect(client).to have_received(:make_request).with("POST", "/task", {
        title: title,
        content: content,
        projectId: project_id
      })
      expect(result).to eq(response)
      expect(client).to have_received(:invalidate_cache)
    end

    it "creates task with minimal parameters" do
      client.create_task(title: title)

      expect(client).to have_received(:make_request).with("POST", "/task", {
        title: title
      })
    end
  end

  describe "#complete_task" do
    let(:task_id) { "task123" }
    let(:project_id) { "project123" }
    let(:response) { {"success" => true} }

    before do
      allow(client).to receive(:make_request).and_return(response)
      allow(client).to receive(:invalidate_cache)
    end

    it "completes task" do
      result = client.complete_task(task_id, project_id)

      expect(client).to have_received(:make_request).with("POST", "/project/#{project_id}/task/#{task_id}/complete")
      expect(result).to eq(response)
      expect(client).to have_received(:invalidate_cache)
    end
  end

  describe "#delete_task" do
    let(:task_id) { "task123" }
    let(:project_id) { "project123" }
    let(:response) { {"success" => true} }

    before do
      allow(client).to receive(:make_request).and_return(response)
      allow(client).to receive(:invalidate_cache)
    end

    it "deletes task" do
      result = client.delete_task(task_id, project_id)

      expect(client).to have_received(:make_request).with("DELETE", "/project/#{project_id}/task/#{task_id}")
      expect(result).to eq(response)
      expect(client).to have_received(:invalidate_cache)
    end
  end

  describe "#get_projects" do
    let(:response) { [{"id" => "project1", "name" => "Test Project"}] }

    before do
      allow(client).to receive(:make_request).with("GET", "/project").and_return(response)
    end

    it "fetches projects" do
      projects = client.get_projects
      expect(projects).to eq(response)
    end

    context "when cache is valid" do
      before do
        client.instance_variable_set(:@projects_cache, [{"cached" => "project"}])
        client.instance_variable_set(:@cache_timestamp, Time.now.utc)
      end

      it "returns cached projects" do
        projects = client.get_projects
        expect(projects).to eq([{"cached" => "project"}])
      end
    end
  end

  describe "#make_request" do
    let(:mock_http) { double("HTTP") }
    let(:mock_request) { double("Request") }
    let(:mock_response) { double("Response", code: "200", body: '{"success": true}') }

    before do
      allow(URI).to receive(:new).and_return(double(host: "api.ticktick.com", port: 443))
      allow(Net::HTTP).to receive(:new).and_return(mock_http)
      allow(mock_http).to receive(:use_ssl=)
      allow(mock_http).to receive(:request).and_return(mock_response)
    end

    context "GET request" do
      before do
        allow(Net::HTTP::Get).to receive(:new).and_return(mock_request)
        allow(mock_request).to receive(:[]=)
      end

      it "makes GET request with proper headers" do
        client.send(:make_request, "GET", "/test")

        expect(mock_request).to have_received(:[]=).with("Authorization", "Bearer #{token}")
        expect(mock_request).to have_received(:[]=).with("User-Agent", "TickRb/1.0.0")
      end
    end

    context "POST request with data" do
      let(:data) { {"key" => "value"} }

      before do
        allow(Net::HTTP::Post).to receive(:new).and_return(mock_request)
        allow(mock_request).to receive(:[]=)
        allow(mock_request).to receive(:body=)
      end

      it "makes POST request with JSON body" do
        client.send(:make_request, "POST", "/test", data)

        expect(mock_request).to have_received(:body=).with(data.to_json)
        expect(mock_request).to have_received(:[]=).with("Content-Type", "application/json")
      end
    end

    context "error responses" do
      context "401 Unauthorized" do
        let(:mock_response) { double("Response", code: "401") }

        it "raises authentication error" do
          allow(Net::HTTP::Get).to receive(:new).and_return(mock_request)
          allow(mock_request).to receive(:[]=)

          expect { client.send(:make_request, "GET", "/test") }
            .to raise_error(Tickrb::Error, /Authentication failed/)
        end
      end

      context "404 Not Found" do
        let(:mock_response) { double("Response", code: "404") }

        it "raises not found error" do
          allow(Net::HTTP::Get).to receive(:new).and_return(mock_request)
          allow(mock_request).to receive(:[]=)

          expect { client.send(:make_request, "GET", "/test") }
            .to raise_error(Tickrb::Error, /Resource not found/)
        end
      end

      context "500 Server Error" do
        let(:mock_response) { double("Response", code: "500", message: "Internal Server Error") }

        it "raises API error" do
          allow(Net::HTTP::Get).to receive(:new).and_return(mock_request)
          allow(mock_request).to receive(:[]=)

          expect { client.send(:make_request, "GET", "/test") }
            .to raise_error(Tickrb::Error, /API request failed: 500/)
        end
      end
    end

    context "unsupported HTTP method" do
      it "raises error for unsupported method" do
        expect { client.send(:make_request, "PATCH", "/test") }
          .to raise_error(Tickrb::Error, /Unsupported HTTP method: PATCH/)
      end
    end
  end

  describe "caching" do
    describe "#cache_valid?" do
      context "when no cache timestamp" do
        it "returns false" do
          expect(client.send(:cache_valid?)).to be false
        end
      end

      context "when cache is fresh" do
        before do
          client.instance_variable_set(:@cache_timestamp, Time.now.utc - 50)
        end

        it "returns true" do
          expect(client.send(:cache_valid?)).to be true
        end
      end

      context "when cache is expired" do
        before do
          client.instance_variable_set(:@cache_timestamp, Time.now.utc - 400)
        end

        it "returns false" do
          expect(client.send(:cache_valid?)).to be false
        end
      end
    end

    describe "#invalidate_cache" do
      before do
        client.instance_variable_set(:@projects_cache, ["cached"])
        client.instance_variable_set(:@tasks_cache, ["cached"])
        client.instance_variable_set(:@cache_timestamp, Time.now.utc)
      end

      it "clears all cache variables" do
        client.send(:invalidate_cache)

        expect(client.instance_variable_get(:@projects_cache)).to be_nil
        expect(client.instance_variable_get(:@tasks_cache)).to be_nil
        expect(client.instance_variable_get(:@cache_timestamp)).to be_nil
      end
    end
  end
end
