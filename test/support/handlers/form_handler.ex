defmodule PhoenixTestDatastar.TestHandlers.FormHandler do
  @moduledoc false

  def handle_event(conn, "submit", signals) do
    name = signals["name"] || ""
    email = signals["email"] || ""
    color = signals["color"] || ""
    agree = signals["agree"]
    role = signals["role"] || ""

    result_html = """
    <div id="result">
      <p id="result-name">Name: #{name}</p>
      <p id="result-email">Email: #{email}</p>
      <p id="result-color">Color: #{color}</p>
      <p id="result-agree">Agree: #{agree}</p>
      <p id="result-role">Role: #{role}</p>
    </div>
    """

    conn
    |> Dstar.start()
    |> Dstar.patch_elements(result_html, selector: "#result")
  end
end
