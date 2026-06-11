defimpl PhoenixTest.Driver, for: PhoenixTestDatastar.Session do
  @moduledoc false

  import Phoenix.ConnTest, only: [dispatch: 5]

  alias PhoenixTest.ActiveForm
  alias PhoenixTest.Assertions
  alias PhoenixTest.ConnHandler
  alias PhoenixTest.DataAttributeForm
  alias PhoenixTest.Element.Button
  alias PhoenixTest.Element.Field
  alias PhoenixTest.Element.Form
  alias PhoenixTest.Element.Link
  alias PhoenixTest.Element.Select
  alias PhoenixTest.EndpointHelpers
  alias PhoenixTest.FieldHelpers
  alias PhoenixTest.FormData
  alias PhoenixTest.FormPayload
  alias PhoenixTest.Html
  alias PhoenixTest.Locators
  alias PhoenixTest.OpenBrowser
  alias PhoenixTest.Operation
  alias PhoenixTest.Query
  alias PhoenixTest.SessionHelpers
  alias PhoenixTestDatastar.Actions
  alias PhoenixTestDatastar.Dispatcher
  alias PhoenixTestDatastar.Session
  alias PhoenixTestDatastar.Signals

  # ── visit ──────────────────────────────────────────────────────────────

  def visit(%Session{} = session, path) do
    endpoint = EndpointHelpers.endpoint_from!(session.conn)

    conn =
      session.conn
      |> dispatch(endpoint, :get, path, nil)

    raw_html = conn.resp_body || ""
    signals = Signals.extract_from_html(raw_html)
    csrf = Map.get(signals, "_csrfToken")
    current_path = build_current_path(conn)

    session = %{
      session
      | conn: conn,
        raw_html: raw_html,
        current_path: current_path,
        signals: signals,
        csrf_token: csrf,
        active_form: ActiveForm.new(),
        within: :none,
        current_operation: nil
    }

    # Auto-dispatch data-init actions
    if Keyword.get(session.visit_opts, :init, true) do
      dispatch_init_actions(session)
    else
      session
    end
  end

  # ── render ─────────────────────────────────────────────────────────────

  def render_html(%Session{raw_html: raw_html, within: within}) do
    html = Html.parse_document(raw_html)

    case within do
      :none -> html
      selector when is_binary(selector) -> Html.all(html, selector)
    end
  end

  def render_page_title(session) do
    session
    |> render_html()
    |> Query.find("title")
    |> case do
      {:found, element} -> Html.element_text(element)
      _ -> nil
    end
  end

  def current_path(%Session{current_path: path}), do: path

  # ── click_link ─────────────────────────────────────────────────────────

  def click_link(session, text) do
    click_link(session, "a", text)
  end

  def click_link(session, selector, text) do
    session = set_operation(session, :click_link)
    html = session.current_operation.html
    link = Link.find!(html, selector, text)

    # Check for Datastar action on the link
    case find_datastar_action_on_element(session.raw_html, link.parsed) do
      {:ok, action_expr} ->
        dispatch_datastar_action(session, action_expr)

      :none ->
        if Link.has_data_method?(link) do
          click_with_data_method(session, link)
        else
          # Standard link navigation
          conn = session.conn |> recycle_conn(session)
          PhoenixTest.visit(conn, link.href)
        end
    end
  end

  # ── click_button ───────────────────────────────────────────────────────

  def click_button(session, text) do
    locator = Locators.button(text: text)
    session = set_operation(session, :click_button)
    html = session.current_operation.html

    button =
      html
      |> Query.find_by_role!(locator)
      |> Button.build()

    handle_click_button(session, button)
  end

  def click_button(session, selector, text) do
    session = set_operation(session, :click_button)
    html = session.current_operation.html
    button = Button.find!(html, selector, text)

    handle_click_button(session, button)
  end

  defp handle_click_button(session, button) do
    html = session.current_operation.html

    # Check for Datastar action on the button itself (data-on:click)
    case find_datastar_action_on_element(session.raw_html, button.parsed) do
      {:ok, action_expr} ->
        dispatch_datastar_action(session, action_expr)

      :none ->
        # Check for data-method attribute
        if Button.has_data_method?(button) do
          click_with_data_method(session, button)
        else
          # Check if button belongs to a form
          if Button.belongs_to_form?(button, html) do
            form =
              button
              |> Button.parent_form!(html)
              |> Form.put_button_data(button)

            # Check for Datastar action on the form (data-on:submit)
            case find_datastar_submit_action_on_form(form) do
              {:ok, action_expr} ->
                session = %{session | active_form: ActiveForm.new()}
                dispatch_datastar_action(session, action_expr)

              :none ->
                active_form = session.active_form

                if active_form.selector == form.selector do
                  submit_active_form(session, form)
                else
                  perform_submit(session, form, build_payload(form))
                end
            end
          else
            raise ArgumentError,
                  "Could not find a form for the button. " <>
                    "The button must have a data-on:click attribute or belong to a form."
          end
        end
    end
  end

  # ── fill_in ────────────────────────────────────────────────────────────

  def fill_in(session, label, opts) do
    selectors = ["input:not([type='hidden'])", "textarea"]
    fill_in(session, selectors, label, opts)
  end

  def fill_in(session, input_selector, label, opts) do
    {value, opts} = Keyword.pop!(opts, :with)
    session = set_operation(session, :fill_in)
    html = session.current_operation.html
    field = Field.find_input!(html, input_selector, label, opts)

    # Check for data-bind on this input
    case find_data_bind(session.raw_html, field) do
      {:ok, signal_name} ->
        # Update signal directly
        signals = Map.put(session.signals, signal_name, value)
        %{session | signals: signals}

      :none ->
        # Standard form field tracking
        field = Map.put(field, :value, to_string(value))
        fill_in_field_data(session, field)
    end
  end

  # ── select ─────────────────────────────────────────────────────────────

  def select(session, option, opts) do
    select(session, "select", option, opts)
  end

  def select(session, input_selector, option, opts) do
    {label, opts} = Keyword.pop!(opts, :from)
    session = set_operation(session, :select)
    html = session.current_operation.html
    select_field = Select.find_select_option!(html, input_selector, label, option, opts)

    # Check for data-bind on the select
    case find_data_bind(session.raw_html, select_field) do
      {:ok, signal_name} ->
        value = select_field.value
        # For select, value is a list; take first for single select
        signal_value =
          case value do
            [v] -> v
            values when is_list(values) -> values
            v -> v
          end

        signals = Map.put(session.signals, signal_name, signal_value)
        %{session | signals: signals}

      :none ->
        fill_in_field_data(session, select_field)
    end
  end

  # ── check / uncheck / choose ───────────────────────────────────────────

  def check(session, label, opts) do
    check(session, "input[type='checkbox']", label, opts)
  end

  def check(session, input_selector, label, opts) do
    session = set_operation(session, :check)
    html = session.current_operation.html
    field = Field.find_checkbox!(html, input_selector, label, opts)

    case find_data_bind(session.raw_html, field) do
      {:ok, signal_name} ->
        signals = Map.put(session.signals, signal_name, true)
        %{session | signals: signals}

      :none ->
        fill_in_field_data(session, field)
    end
  end

  def uncheck(session, label, opts) do
    uncheck(session, "input[type='checkbox']", label, opts)
  end

  def uncheck(session, input_selector, label, opts) do
    session = set_operation(session, :uncheck)
    html = session.current_operation.html
    field = Field.find_hidden_uncheckbox!(html, input_selector, label, opts)

    case find_data_bind(session.raw_html, field) do
      {:ok, signal_name} ->
        signals = Map.put(session.signals, signal_name, false)
        %{session | signals: signals}

      :none ->
        fill_in_field_data(session, field)
    end
  end

  def choose(session, label, opts) do
    choose(session, "input[type='radio']", label, opts)
  end

  def choose(session, input_selector, label, opts) do
    session = set_operation(session, :choose)
    html = session.current_operation.html
    field = Field.find_input!(html, input_selector, label, opts)

    case find_data_bind(session.raw_html, field) do
      {:ok, signal_name} ->
        signals = Map.put(session.signals, signal_name, field.value)
        %{session | signals: signals}

      :none ->
        fill_in_field_data(session, field)
    end
  end

  # ── upload ─────────────────────────────────────────────────────────────

  def upload(session, label, path, opts) do
    upload(session, "input[type='file']", label, path, opts)
  end

  def upload(session, input_selector, label, path, opts) do
    session = set_operation(session, :upload)
    html = session.current_operation.html
    field = Field.find_input!(html, input_selector, label, opts)
    form = Field.parent_form!(field, html)

    mime_type = MIME.from_path(path)

    upload_data =
      {field.name,
       %Plug.Upload{content_type: mime_type, filename: Path.basename(path), path: path}}

    Map.update!(session, :active_form, fn active_form ->
      if active_form.selector == form.selector do
        ActiveForm.add_upload(active_form, upload_data)
      else
        [id: form.id, selector: form.selector]
        |> ActiveForm.new()
        |> ActiveForm.add_upload(upload_data)
      end
    end)
  end

  # ── submit ─────────────────────────────────────────────────────────────

  def submit(session) do
    active_form = session.active_form

    unless ActiveForm.active?(active_form) do
      raise ArgumentError,
            "There's no active form. Fill in a form with `fill_in`, `select`, etc."
    end

    selector = active_form.selector
    session = set_operation(session, :submit)
    html = session.current_operation.html

    form =
      html
      |> Form.find!(selector)
      |> then(fn form ->
        Form.put_button_data(form, form.submit_button)
      end)

    # Check for Datastar action on the form
    case find_datastar_submit_action_on_form(form) do
      {:ok, action_expr} ->
        session = %{session | active_form: ActiveForm.new()}
        dispatch_datastar_action(session, action_expr)

      :none ->
        submit_active_form(session, form)
    end
  end

  # ── within ─────────────────────────────────────────────────────────────

  defdelegate within(session, selector, fun), to: SessionHelpers

  # ── assertions ─────────────────────────────────────────────────────────

  defdelegate assert_has(session, selector), to: Assertions
  defdelegate assert_has(session, selector, opts), to: Assertions
  defdelegate refute_has(session, selector), to: Assertions
  defdelegate refute_has(session, selector, opts), to: Assertions
  defdelegate assert_path(session, path), to: Assertions
  defdelegate assert_path(session, path, opts), to: Assertions
  defdelegate refute_path(session, path), to: Assertions
  defdelegate refute_path(session, path, opts), to: Assertions
  defdelegate assert_download(session, file_name), to: Assertions

  # ── open_browser ───────────────────────────────────────────────────────

  def open_browser(session, open_fun \\ &OpenBrowser.open_with_system_cmd/1) do
    path = Path.join([System.tmp_dir!(), "phx-test#{System.unique_integer([:monotonic])}.html"])

    html =
      session.raw_html
      |> Html.parse_document()
      |> Html.postwalk(
        &OpenBrowser.prefix_static_paths(&1, EndpointHelpers.endpoint_from!(session.conn))
      )
      |> Html.raw()

    File.write!(path, html)

    open_fun.(path)

    session
  end

  # ── unwrap ─────────────────────────────────────────────────────────────

  def unwrap(%Session{conn: conn} = session, fun) when is_function(fun, 1) do
    case fun.(conn) do
      %Plug.Conn{status: status} = conn when status in [301, 302, 303, 307, 308] ->
        path = Phoenix.ConnTest.redirected_to(conn, status)
        Dispatcher.follow_redirect(%{session | conn: conn}, path)

      %Plug.Conn{} = conn ->
        %{session | conn: conn, current_path: build_current_path(conn)}

      _other ->
        session
    end
  end

  # ── reload_page ────────────────────────────────────────────────────────

  def reload_page(session) do
    visit(session, current_path(session))
  end

  # ══════════════════════════════════════════════════════════════════════
  # Private helpers
  # ══════════════════════════════════════════════════════════════════════

  # ── Datastar action helpers ────────────────────────────────────────────

  defp dispatch_datastar_action(session, action_expr) do
    {:ok, actions} = Actions.parse(action_expr)
    # Use the first action (most common case)
    action = List.first(actions)
    # Resolve dynamic URLs with current signals and current path
    resolved_url = Actions.resolve_url(action.raw_url, session.signals, session.current_path)
    action = %{action | url: resolved_url}

    session = %{session | active_form: ActiveForm.new()}
    Dispatcher.dispatch_action(session, action)
  end

  defp find_datastar_action_on_element(raw_html, parsed_element) do
    # Look for data-on:click, data-on:submit, data-on:change (with optional __modifiers)
    result = find_datastar_attr_on_element(parsed_element, ["click", "submit", "change"])

    # If not found on the element directly, try to find via raw HTML + selector
    case result do
      nil ->
        # Try finding data-on:click on the element using its selector
        find_action_via_raw_html(raw_html, parsed_element)

      expr ->
        {:ok, expr}
    end
  end

  # Finds a data-on:<event> attribute (with optional __modifiers like __prevent, __debounce)
  defp find_datastar_attr_on_element(parsed_element, event_names) do
    Enum.find_value(event_names, fn event ->
      # Try exact match first, then with __modifiers
      Html.attribute(parsed_element, "data-on:#{event}") ||
        find_datastar_attr_with_modifiers(parsed_element, event)
    end)
  end

  # Checks for data-on:<event>__<modifier> attributes (e.g. data-on:click__prevent)
  defp find_datastar_attr_with_modifiers(parsed_element, event) do
    attrs =
      case parsed_element do
        {_tag, attr_list, _children} -> attr_list
        [{_tag, attr_list, _children}] -> attr_list
        _ -> []
      end

    prefix = "data-on:#{event}__"

    Enum.find_value(attrs, fn
      {attr_name, value} ->
        if String.starts_with?(attr_name, prefix) do
          if value != "", do: value, else: nil
        end

      _ ->
        nil
    end)
  end

  defp find_action_via_raw_html(raw_html, parsed_element) do
    # Build a selector from the element's id if available
    case Html.attribute(parsed_element, "id") do
      nil ->
        :none

      id ->
        selector = "##{id}"
        Actions.find_action(raw_html, selector)
    end
  end

  # Extracts a data-on:submit action from the form's parsed element directly,
  # avoiding CSS selector issues with complex attribute values.
  defp find_datastar_submit_action_on_form(form) do
    form_html = Html.raw(form.parsed)
    {:ok, doc} = Floki.parse_fragment(form_html)

    result =
      Enum.find_value(doc, fn
        {_tag, attrs, _children} ->
          Enum.find_value(attrs, fn
            {attr_name, value} ->
              if (attr_name == "data-on:submit" or
                    String.starts_with?(attr_name, "data-on:submit__")) and value != "" do
                value
              end

            _ ->
              nil
          end)

        _ ->
          nil
      end)

    case result do
      nil -> :none
      expr -> {:ok, expr}
    end
  end

  # ── data-bind helpers ──────────────────────────────────────────────────

  defp find_data_bind(raw_html, field) do
    # Look for data-bind or data-bind:* attribute on the input element
    # We search in raw HTML via Floki since LazyHTML doesn't expose data-bind easily
    case field.id do
      nil -> :none
      id -> find_data_bind_by_id(raw_html, id)
    end
  end

  defp find_data_bind_by_id(raw_html, id) do
    doc = Floki.parse_document!(raw_html)
    elements = Floki.find(doc, "##{id}")

    result =
      Enum.find_value(elements, fn {_tag, attrs, _children} ->
        Enum.find_value(attrs, fn
          {"data-bind", signal_name} when signal_name != "" ->
            signal_name

          {attr_name, signal_name} ->
            if String.starts_with?(attr_name, "data-bind:") do
              # data-bind:value="signalName" or just data-bind:signalName
              signal_name
            else
              nil
            end

          _ ->
            nil
        end)
      end)

    case result do
      nil -> :none
      signal_name -> {:ok, signal_name}
    end
  end

  # ── Form handling helpers (mirrors PhoenixTest.Static) ─────────────────

  defp fill_in_field_data(session, field) do
    Field.validate_name!(field)
    html = session.current_operation.html
    form = Field.parent_form!(field, html)
    field_value = FieldHelpers.next_field_value(session, form, field)

    Map.update!(session, :active_form, fn active_form ->
      active_form
      |> FieldHelpers.active_form_for(form)
      |> ActiveForm.put_form_data(field.name, field_value)
    end)
  end

  defp submit_active_form(session, form) do
    active_form = session.active_form

    session
    |> Map.put(:active_form, ActiveForm.new())
    |> perform_submit(form, build_payload(form, active_form))
  end

  defp perform_submit(session, form, payload) do
    Dispatcher.dispatch_form(session, form.method, form.action, payload)
  end

  defp click_with_data_method(session, el) when is_struct(el, Link) or is_struct(el, Button) do
    form =
      el.parsed
      |> DataAttributeForm.build()
      |> DataAttributeForm.validate!(el.selector, el.text)

    perform_submit(session, form, form.data)
  end

  defp build_payload(form, active_form \\ ActiveForm.new()) do
    form.form_data
    |> FormData.override(active_form.form_data)
    |> FormPayload.new()
    |> FormPayload.add_form_data(active_form.uploads)
  end

  # ── Shared helpers ─────────────────────────────────────────────────────

  defp set_operation(session, name) do
    html = render_html(session)
    Map.put(session, :current_operation, Operation.new(name, html))
  end

  defp recycle_conn(conn, _session) do
    ConnHandler.recycle_all_headers(conn)
  end

  defp build_current_path(conn) do
    case conn.query_string do
      "" -> conn.request_path
      qs -> conn.request_path <> "?" <> qs
    end
  end

  # ── data-init auto-dispatching ─────────────────────────────────────────

  defp dispatch_init_actions(session) do
    init_actions = Actions.find_init_actions(session.raw_html)

    Enum.reduce(init_actions, session, fn {_selector, action_expr}, acc ->
      case Actions.parse(action_expr) do
        {:ok, actions} ->
          Enum.reduce(actions, acc, fn action, inner_acc ->
            resolved_url =
              Actions.resolve_url(action.raw_url, inner_acc.signals, inner_acc.current_path)

            action = %{action | url: resolved_url}
            Dispatcher.dispatch_action(inner_acc, action)
          end)

        {:error, _} ->
          acc
      end
    end)
  end
end
