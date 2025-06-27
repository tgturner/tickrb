# typed: true
# frozen_string_literal: true

require "net/http"
require "uri"
require "json"
require "sorbet-runtime"

module Tickrb
  class Client
    extend T::Sig

    BASE_URL = "https://api.ticktick.com/open/v1"

    sig { params(token: T.nilable(String)).void }
    def initialize(token: nil)
      @token = token || TokenStore.load_token
      raise Error, "No authentication token available. Please run authentication first." unless @token
      @projects_cache = T.let(nil, T.nilable(T::Array[T::Hash[String, T.untyped]]))
      @tasks_cache = T.let(nil, T.nilable(T::Array[T::Hash[String, T.untyped]]))
      @cache_timestamp = T.let(nil, T.nilable(Time))
    end

    sig { returns(T::Array[T::Hash[String, T.untyped]]) }
    def get_tasks
      return @tasks_cache if cache_valid? && @tasks_cache

      all_tasks = []
      projects = get_projects

      projects.each do |project|
        project_tasks = get_tasks_for_project(project["id"])
        project_tasks.each { |task| task["projectId"] = project["id"] }
        all_tasks.concat(project_tasks)
      end

      @tasks_cache = all_tasks
      @cache_timestamp = Time.now.utc
      all_tasks
    end

    sig { params(project_id: String).returns(T::Array[T::Hash[String, T.untyped]]) }
    def get_tasks_for_project(project_id)
      response = make_request("GET", "/project/#{project_id}/data")
      if response.is_a?(Hash) && response["tasks"]
        response["tasks"]
      else
        []
      end
    end

    sig { params(title: String, content: T.nilable(String), project_id: T.nilable(String)).returns(T::Hash[String, T.untyped]) }
    def create_task(title:, content: nil, project_id: nil)
      task_data = {
        title: title,
        content: content,
        projectId: project_id
      }.compact

      result = T.cast(make_request("POST", "/task", task_data), T::Hash[String, T.untyped])
      invalidate_cache
      result
    end

    sig { params(task_id: String, project_id: String).returns(T::Hash[String, T.untyped]) }
    def complete_task(task_id, project_id)
      result = T.cast(make_request("POST", "/project/#{project_id}/task/#{task_id}/complete"), T::Hash[String, T.untyped])
      invalidate_cache
      result
    end

    sig { params(task_id: String, project_id: String).returns(T::Hash[String, T.untyped]) }
    def delete_task(task_id, project_id)
      result = T.cast(make_request("DELETE", "/project/#{project_id}/task/#{task_id}"), T::Hash[String, T.untyped])
      invalidate_cache
      result
    end

    sig { returns(T::Array[T::Hash[String, T.untyped]]) }
    def get_projects
      return @projects_cache if cache_valid? && @projects_cache

      response = make_request("GET", "/project")
      @projects_cache = response.is_a?(Array) ? response : []
      @cache_timestamp = Time.now.utc
      @projects_cache
    end

    private

    attr_reader :token

    sig { returns(T::Boolean) }
    def cache_valid?
      return false unless @cache_timestamp
      Time.now.utc - @cache_timestamp < 100
    end

    sig { void }
    def invalidate_cache
      @projects_cache = nil
      @tasks_cache = nil
      @cache_timestamp = nil
    end

    sig { params(method: String, endpoint: String, data: T.nilable(T::Hash[String, T.untyped])).returns(T.any(T::Hash[String, T.untyped], T::Array[T::Hash[String, T.untyped]])) }
    def make_request(method, endpoint, data = nil)
      uri = URI("#{BASE_URL}#{endpoint}")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true

      case method.upcase
      when "GET"
        request = Net::HTTP::Get.new(uri)
      when "POST"
        request = Net::HTTP::Post.new(uri)
        if data
          request.body = data.to_json
          request["Content-Type"] = "application/json"
        end
      when "DELETE"
        request = Net::HTTP::Delete.new(uri)
      else
        raise Error, "Unsupported HTTP method: #{method}"
      end

      request["Authorization"] = "Bearer #{token}"
      request["User-Agent"] = "TickRb/1.0.0"

      response = http.request(request)

      case response.code.to_i
      when 200..299
        response.body.empty? ? {} : JSON.parse(response.body)
      when 401
        raise Error, "Authentication failed. Token may be expired."
      when 404
        raise Error, "Resource not found"
      else
        raise Error, "API request failed: #{response.code} #{response.message}"
      end
    end
  end
end
