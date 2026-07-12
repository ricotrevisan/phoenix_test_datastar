defmodule PhoenixTestDatastar.TestHandlers.PageController do
  @moduledoc false
  use Phoenix.Controller, formats: [:html]

  plug(:put_layout, false)

  def authenticate_stream(conn, _params) do
    _csrf_token = Plug.CSRFProtection.get_csrf_token()

    conn
    |> Plug.Conn.put_session(:user_id, "test-user")
    |> html("authenticated")
  end

  def counter(conn, _params) do
    html(conn, """
    <!DOCTYPE html>
    <html>
    <head><title>Counter</title></head>
    <body>
      <div id="app"
        data-signals:count="0"
        data-signals:_csrf-token="'test-csrf-token'"
        data-signals:_dstar-module="'phoenix_test_datastar-test_handlers-counter_handler'">

        <h1>Counter</h1>
        <span id="count">0</span>

        <button id="increment-btn"
          data-on:click="#{Dstar.post(PhoenixTestDatastar.TestHandlers.CounterHandler, "increment")}">
          Increment
        </button>

        <button id="decrement-btn"
          data-on:click="#{Dstar.post(PhoenixTestDatastar.TestHandlers.CounterHandler, "decrement")}">
          Decrement
        </button>

        <button id="increment-by-5-btn"
          data-on:click="#{Dstar.post(PhoenixTestDatastar.TestHandlers.CounterHandler, "increment_by")}">
          Add 5
        </button>
      </div>
    </body>
    </html>
    """)
  end

  def form(conn, _params) do
    html(conn, """
    <!DOCTYPE html>
    <html>
    <head><title>Form</title></head>
    <body>
      <div id="app"
        data-signals:name="''"
        data-signals:email="''"
        data-signals:color="'red'"
        data-signals:agree="false"
        data-signals:role="'user'"
        data-signals:_csrf-token="'test-csrf-token'">

        <h1>User Form</h1>

        <form id="user-form"
          data-on:submit="#{Dstar.post(PhoenixTestDatastar.TestHandlers.FormHandler, "submit")}">

          <label for="name-input">Name</label>
          <input id="name-input" type="text" name="name" data-bind:name />

          <label for="email-input">Email</label>
          <input id="email-input" type="email" name="email" data-bind="email" />

          <label for="color-select">Favorite Color</label>
          <select id="color-select" name="color" data-bind="color">
            <option value="red">Red</option>
            <option value="green">Green</option>
            <option value="blue">Blue</option>
          </select>

          <label for="agree-check">I agree</label>
          <input id="agree-check" type="checkbox" name="agree" value="true" data-bind="agree" />
          <input type="hidden" name="agree" value="false" />

          <fieldset>
            <legend>Role</legend>
            <label for="role-user">User</label>
            <input id="role-user" type="radio" name="role" value="user" data-bind="role" checked />
            <label for="role-admin">Admin</label>
            <input id="role-admin" type="radio" name="role" value="admin" data-bind="role" />
          </fieldset>

          <button type="submit">Submit</button>
        </form>

        <div id="result"></div>
      </div>
    </body>
    </html>
    """)
  end

  def standard_form(conn, _params) do
    html(conn, """
    <!DOCTYPE html>
    <html>
    <head><title>Standard Form</title></head>
    <body>
      <h1>Standard Form</h1>
      <form id="login-form" action="/redirected" method="get">
        <label for="username-input">Username</label>
        <input id="username-input" type="text" name="username" />

        <label for="password-input">Password</label>
        <input id="password-input" type="password" name="password" />

        <button type="submit"
          data-attr:disabled="$_generating"
          data-indicator="_generating">Login</button>
      </form>
    </body>
    </html>
    """)
  end

  def links(conn, _params) do
    html(conn, """
    <!DOCTYPE html>
    <html>
    <head><title>Links Page</title></head>
    <body>
      <div data-signals:_csrf-token="'test-csrf-token'">
        <h1>Links</h1>

        <a href="/counter">Go to Counter</a>

        <a id="ds-link"
          href="#"
          data-on:click="#{Dstar.post(PhoenixTestDatastar.TestHandlers.RedirectHandler, "go_counter")}">
          Datastar Navigate
        </a>

        <a href="/redirected"
           data-method="post"
           data-to="/redirected"
           data-csrf="test-csrf">
          Data Method Link
        </a>
      </div>
    </body>
    </html>
    """)
  end

  def redirected(conn, _params) do
    html(conn, """
    <!DOCTYPE html>
    <html>
    <head><title>Redirected</title></head>
    <body>
      <h1>You were redirected!</h1>
      <p id="message">Welcome to the redirected page.</p>
    </body>
    </html>
    """)
  end

  def multi_action(conn, _params) do
    html(conn, """
    <!DOCTYPE html>
    <html>
    <head><title>Multi Action</title></head>
    <body>
      <div id="app"
        data-signals:count="0"
        data-signals:status="'idle'"
        data-signals:_csrf-token="'test-csrf-token'">

        <span id="count">0</span>
        <span id="status">idle</span>

        <button id="multi-btn"
          data-on:click="#{Dstar.post(PhoenixTestDatastar.TestHandlers.MultiHandler, "update")}">
          Update Both
        </button>
      </div>
    </body>
    </html>
    """)
  end

  def data_init(conn, _params) do
    html(conn, """
    <!DOCTYPE html>
    <html>
    <head><title>Data Init</title></head>
    <body>
      <div id="app"
        data-signals:count="0"
        data-signals:_csrf-token="'test-csrf-token'"
        data-init="#{Dstar.get(PhoenixTestDatastar.TestHandlers.InitHandler, "load")}">

        <span id="count">0</span>
      </div>
    </body>
    </html>
    """)
  end

  def stream(conn, _params) do
    html(conn, """
    <!DOCTYPE html>
    <html>
    <head><title>Stream</title></head>
    <body>
      <div id="app"
        data-signals:count="0"
        data-signals:status="'disconnected'"
        data-signals:_csrf-token="'test-csrf-token'">

        <span id="count">0</span>
        <span id="status">disconnected</span>
      </div>
    </body>
    </html>
    """)
  end

  # Page using dstar >= 0.1.0-alpha.2 page-local helper output:
  # Dstar.Page.Helpers.event("wire_check")
  def wire(conn, _params) do
    html(conn, """
    <!DOCTYPE html>
    <html>
    <head><title>Wire</title></head>
    <body>
      <div id="app"
        data-signals:wired="false"
        data-signals:_csrf-token="'test-csrf-token'">

        <span id="wired">false</span>

        <button id="wire-btn"
          data-on:click="@post(location.pathname.replace(/\\/+$/, '') + '/_event/wire_check')">
          Wire Check
        </button>
      </div>
    </body>
    </html>
    """)
  end

  def wire_event(conn, _params) do
    conn
    |> Dstar.start()
    |> Dstar.patch_signals(%{wired: true})
    |> Dstar.patch_elements(~s(<span id="wired">true</span>), selector: "#wired")
  end

  # Page using dstar >= 0.1.0-alpha.2 page-local helper output:
  # Dstar.Page.Helpers.connect()
  def connect_page(conn, _params) do
    html(conn, """
    <!DOCTYPE html>
    <html>
    <head><title>Connect</title></head>
    <body>
      <div id="app"
        data-signals:status="'disconnected'"
        data-signals:_csrf-token="'test-csrf-token'"
        data-init="@post(location.pathname, {retryMaxCount: Infinity})">

        <span id="status">disconnected</span>
      </div>
    </body>
    </html>
    """)
  end

  def connect_stream(conn, _params) do
    conn
    |> Dstar.start()
    |> Dstar.patch_signals(%{status: "connected"})
    |> Dstar.patch_elements(~s(<span id="status">connected</span>), selector: "#status")
  end

  def nested_signals(conn, _params) do
    html(conn, """
    <!DOCTYPE html>
    <html>
    <head><title>Nested Signals</title></head>
    <body>
      <div id="app"
        data-signals="{user: {name: 'Alice', age: 30}, settings: {theme: 'dark'}}">
        <span id="user-name">Alice</span>
      </div>
    </body>
    </html>
    """)
  end
end
