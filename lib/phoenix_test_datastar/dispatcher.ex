defmodule PhoenixTestDatastar.Dispatcher do
  @moduledoc """
  HTTP dispatcher for Datastar requests.

  Builds HTTP requests with appropriate headers and body, dispatches them
  through the Phoenix endpoint, parses SSE responses, and applies events
  to update session state (signals + DOM).
  """

  import Phoenix.ConnTest, only: [dispatch: 5, recycle: 1]

  alias PhoenixTestDatastar.SSE
  alias PhoenixTest.EndpointHelpers
  alias PhoenixTestDatastar.Actions
  alias PhoenixTestDatastar.DOM
  alias PhoenixTestDatastar.Session
  alias PhoenixTestDatastar.Signals

  @doc """
  Dispatches an action and returns the updated session.

  Takes a parsed action (from `Actions.parse_one/1`) and dispatches it
  through the endpoint, then processes the SSE response.
  """
  @spec dispatch_action(%Session{}, Actions.action()) :: %Session{}
  def dispatch_action(%Session{} = session, %{method: method, url: url} = action) do
    {path, body, conn} = build_request(session, method, url, action)

    result_conn = dispatch(conn, endpoint(session), method, path, body)

    process_response(session, result_conn)
  end

  @doc """
  Dispatches a standard form submission (non-Datastar).
  """
  @spec dispatch_form(%Session{}, String.t(), String.t(), map() | String.t()) :: %Session{}
  def dispatch_form(%Session{} = session, method, action_url, payload) do
    conn =
      session.conn
      |> recycle_conn(session)

    result_conn = dispatch(conn, endpoint(session), method, action_url, payload)

    process_response(session, result_conn)
  end

  @doc """
  Follows a redirect, returning the updated session.
  """
  @spec follow_redirect(%Session{}, String.t()) :: %Session{}
  def follow_redirect(%Session{} = session, path) do
    conn =
      session.conn
      |> recycle_conn(session)

    result_conn = dispatch(conn, endpoint(session), :get, path, nil)

    process_response(session, result_conn)
  end

  # Build request conn, path, and body based on HTTP method
  defp build_request(session, method, url, _action) when method in [:get] do
    # GET: signals go as ?datastar=<json> query param
    query = Signals.to_get_query(session.signals)

    path =
      if query != "" and query != "datastar=%7B%7D" do
        url <> "?" <> query
      else
        url
      end

    conn =
      session.conn
      |> recycle_conn(session)
      |> Plug.Conn.put_req_header("datastar-request", "true")

    {path, nil, conn}
  end

  defp build_request(session, method, url, _action)
       when method in [:post, :put, :patch, :delete] do
    body = Signals.to_post_body(session.signals)

    conn =
      session.conn
      |> recycle_conn(session)
      |> Plug.Conn.put_req_header("content-type", "application/json")
      |> Plug.Conn.put_req_header("datastar-request", "true")
      |> maybe_put_csrf_header(session.csrf_token)

    {url, body, conn}
  end

  # Process the response based on content type and status
  defp process_response(session, %{status: status} = conn)
       when status in [301, 302, 303, 307, 308] do
    path = Phoenix.ConnTest.redirected_to(conn, status)
    follow_redirect(%{session | conn: conn}, path)
  end

  defp process_response(session, conn) do
    content_type = get_content_type(conn)

    cond do
      String.contains?(content_type, "text/event-stream") ->
        # SSE response — parse and apply events
        events = SSE.parse(conn.resp_body || "")
        session = %{session | conn: conn}
        apply_events(session, events)

      true ->
        # Regular HTML response
        raw_html = conn.resp_body || ""
        signals = Signals.extract_from_html(raw_html)
        csrf = Map.get(signals, "_csrfToken", session.csrf_token)
        current_path = build_current_path(conn)

        %{
          session
          | conn: conn,
            raw_html: raw_html,
            current_path: current_path,
            signals: signals,
            csrf_token: csrf
        }
    end
  end

  @doc """
  Applies a list of SSE events to the session, updating signals and DOM.
  """
  @spec apply_events(%Session{}, [SSE.event()]) :: %Session{}
  def apply_events(session, events) do
    Enum.reduce(events, session, fn event, acc ->
      apply_event(acc, event)
    end)
  end

  # Apply a patch_signals event
  defp apply_event(session, %{
         type: :patch_signals,
         signals: new_signals,
         only_if_missing: only_if_missing
       }) do
    signals = Signals.apply_patch(session.signals, new_signals, only_if_missing: only_if_missing)
    csrf = Map.get(signals, "_csrfToken", session.csrf_token)
    %{session | signals: signals, csrf_token: csrf}
  end

  # Apply a patch_elements event
  defp apply_event(session, %{type: :patch_elements, elements: elements} = event)
       when is_binary(elements) do
    cond do
      script_redirect?(elements) ->
        url = extract_redirect_url(elements)
        follow_redirect(session, url)

      script_console?(elements) ->
        # Console.log — no-op in tests
        session

      true ->
        # Normal DOM patch — don't re-extract signals here.
        # Signals come from SSE patch_signals events, not from the DOM.
        # Re-extracting would overwrite SSE signals with original HTML values.
        raw_html = DOM.apply_patch(session.raw_html, event)
        %{session | raw_html: raw_html}
    end
  end

  defp apply_event(session, %{type: :patch_elements, elements: nil}) do
    session
  end

  # Detect redirect scripts: window.location.href="..." or window.location='...'
  defp script_redirect?(html) do
    String.contains?(html, "window.location.href") or
      html =~ ~r/window\.location\s*=\s*['"]/
  end

  defp extract_redirect_url(html) do
    # Match window.location.href= or window.location= with single or double quotes
    case Regex.run(~r/window\.location(?:\.href)?\s*=\s*(?:"([^"]+)"|'([^']+)')/, html) do
      [_, url, ""] ->
        url

      [_, "", url] ->
        url

      [_, url] ->
        url

      _ ->
        "/"
    end
  end

  # Detect console scripts
  defp script_console?(html) do
    html =~ ~r/<script[^>]*>.*console\./s and not script_redirect?(html)
  end

  # Helper to get content type from response
  defp get_content_type(conn) do
    case Plug.Conn.get_resp_header(conn, "content-type") do
      [ct | _] -> ct
      [] -> ""
    end
  end

  defp maybe_put_csrf_header(conn, nil), do: conn

  defp maybe_put_csrf_header(conn, token) do
    Plug.Conn.put_req_header(conn, "x-csrf-token", token)
  end

  defp recycle_conn(conn, _session) do
    conn
    |> recycle()
  end

  defp endpoint(session) do
    EndpointHelpers.endpoint_from!(session.conn)
  end

  defp build_current_path(conn) do
    case conn.query_string do
      "" -> conn.request_path
      qs -> conn.request_path <> "?" <> qs
    end
  end
end
