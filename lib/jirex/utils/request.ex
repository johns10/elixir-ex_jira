require Logger

defmodule Jirex.Request do
  @moduledoc """
  Provides the base request function and helper functions for GET and POST.
  All request functions return either {:ok, {status, data}} or {:error, reason}
  """

  @type request_response :: {:ok, any} | {:error, any}

  @spec jira_account() :: String.t
  defp jira_account(), do: Application.get_env(:jirex, :account)
  @spec jira_username() :: String.t
  defp jira_username(), do: Application.get_env(:jirex, :username)
  @spec jira_password() :: String.t
  defp jira_password(), do: Application.get_env(:jirex, :password)
  @spec jira_timeout() :: String.t
  defp jira_timeout(), do: Application.get_env(:jirex, :timeout) || 30_000
  @spec jira_client() :: atom
  defp jira_client(), do: Application.get_env(:jirex, :http_client) || HTTPotion

  @doc """
  Sends a GET request to the specified resource_path with the specified query_params.
  Sends multiple requests if more resources are available.

  ## Examples

      iex> Request.get_all("/some/items", "items", "a=b&c=d")
      {:ok, [%{"id" => "1002"},%{"id" => "1003"}]}

      iex> Request.get_all("/some/failure", "items", "a=b&c=d")
      {:error, "aliens"}

  """
  @spec get_all(String.t, String.t, String.t) :: request_response
  def get_all(resource_path, resource, query_params) do
    request("GET", resource_path, query_params, "")
    |> get_more([], resource_path, resource, query_params)
  end

  @doc """
  Sends a GET request to the specified resource_path with the specified query_params.
  Expects a single return item.

      iex> Request.get_one("/one/widget", "c=d&e=f")
      {:ok, %{"id" => "1006"}}

  """
  @spec get_one(String.t, String.t) :: request_response
  def get_one(resource_path, query_params) do
    request("GET", resource_path, query_params, "")
  end

  @spec get_more(request_response, [...], String.t, String.t, String.t) :: request_response
  defp get_more({:error, reason}, _, _, _, _), do: {:error, reason}
  defp get_more({:ok, %{"total" => total} = response}, prev_items, resource_path, resource, query_params) do
    items = response[resource]
    case length(prev_items) + length(items) do
      x when x >= total ->
        {:ok, prev_items ++ items}
      _ ->
        request("GET", resource_path, "startAt=#{length(prev_items) + length(items)}&#{query_params}&maxResults=300", "")
        |> get_more(prev_items ++ items, resource_path, resource, query_params)
    end
  end

  @doc """
  Sends a POST request to the specified resource_path with the specified
  query_params (as a string in the form "key1=val1&key2=val2") and the
  specified payload.
  """
  @spec post(String.t, String.t, String.t) :: request_response
  def post(resource_path, query_params, payload) do
    request("POST", resource_path, query_params, payload)
  end


  @doc """
  Sends a request using the specified method to the specified resource_path
  with the specified query_params (as a string in the form "key1=val1&key2=val2")
  and the specified payload.

  ## Examples

      iex> Jirex.Request.request("GET", "/some/item", "a=b&c=d", "")
      {:ok, %{"id" => "1001"}}

      iex> Jirex.Request.request("GET", "/httpotion/failure", "a=b&c=d", "")
      {:error, "some error"}

  """
  @spec request(String.t, String.t, String.t, String.t) :: request_response
  def request(method, resource_path, query_params, payload) do
    url = "https://#{jira_account()}/rest/api/latest#{resource_path}?#{query_params}"
    auth = get_auth()
    Logger.debug("Jirex.Request: Sending #{method} to #{url} using #{jira_client()}")
    case httpotion_request(jira_client(), method, url, payload, [timeout: jira_timeout(), headers: ["Content-Type": "application/json", "Authorization": auth]]) do
      %HTTPotion.ErrorResponse{message: message} ->
        {:error, message}
      %HTTPotion.Response{status_code: 404} ->
        {:error, "404 - Not Found"}
      %HTTPotion.Response{body: body, headers: %{hdrs: %{"content-type" => "application/json;charset=UTF-8"}}} ->
        Poison.decode(body)
      %HTTPotion.Response{headers: %{hdrs: %{"content-type" => content_type}}} ->
        {:error, "Invalid content-type returned: #{content_type}"}
    end
  end

  def get_auth() do
    auth = "#{jira_username()}:#{jira_password()}" |> Base.encode64
    "Basic #{auth}"
  end

  @spec httpotion_request(atom, String.t, String.t, String.t, list) :: %HTTPotion.ErrorResponse{} | %HTTPotion.Response{}
  defp httpotion_request(client, "GET", url, _payload, opts), do: client.get(url, opts)
  defp httpotion_request(client, "POST", url, payload, opts), do: client.post(url, [body: payload] ++ opts)
end