defmodule PhoenixTestDatastar.Session do
  @moduledoc """
  Session struct for tracking state during Datastar testing.

  Holds the current connection, HTML, signals, and form state needed
  to simulate a Datastar client.
  """

  alias PhoenixTest.ActiveForm

  defstruct [
    :conn,
    :raw_html,
    :current_path,
    :signals,
    :csrf_token,
    active_form: ActiveForm.new(),
    within: :none,
    current_operation: nil,
    visit_opts: [],
    stream_info: nil
  ]
end
