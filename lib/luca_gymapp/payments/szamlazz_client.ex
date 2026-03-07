defmodule LucaGymapp.Payments.SzamlazzClient do
  @moduledoc false
  @behaviour LucaGymapp.Payments.BillingClient

  alias LucaGymapp.Accounts.User
  alias LucaGymapp.Payments.Payment
  alias LucaGymapp.SeasonPasses

  @default_base_url "https://www.szamlazz.hu/szamla/"

  @impl true
  def send_invoice(%Payment{} = payment, %User{} = user, opts \\ []) do
    config = config()
    xml = build_xml(payment, user, opts, config)

    case Req.post(config.base_url,
           form_multipart: [
             {"action-xmlagentxmlfile", {xml, filename: "invoice.xml", content_type: "text/xml"}}
           ],
           receive_timeout: config.timeout_ms,
           retry: false
         ) do
      {:ok, %{status: 200} = response} ->
        parse_success_or_error(response)

      {:ok, %{status: status, body: body}} ->
        {:error, {:http_error, status, to_string(body)}}

      {:error, reason} ->
        {:error, {:no_response, reason}}
    end
  end

  defp build_xml(payment, user, opts, config) do
    item_name = Keyword.fetch!(opts, :item_name)
    today = Date.utc_today() |> Date.to_iso8601()
    amount = payment.amount_huf
    country = normalize_country(user.billing_country)
    send_email = if config.send_email, do: "true", else: "false"
    eszamla = if config.eszamla, do: "true", else: "false"
    test_mode = if config.test_mode, do: "true", else: "false"

    company_xml =
      case normalize(user.billing_company_name) do
        nil ->
          ""

        company_name ->
          """
            <cegnev>#{xml_escape(company_name)}</cegnev>
            <adoszam>#{xml_escape(normalize(user.billing_tax_number) || "")}</adoszam>
          """
      end

    """
    <?xml version="1.0" encoding="UTF-8"?>
    <xmlszamlaagent>
      <beallitasok>
        <szamlaagentkulcs>#{xml_escape(config.agent_key)}</szamlaagentkulcs>
        <eszamla>#{eszamla}</eszamla>
        <szamlaLetoltes>false</szamlaLetoltes>
        <valaszVerzio>2</valaszVerzio>
      </beallitasok>
      <fejlec>
        <keltDatum>#{today}</keltDatum>
        <teljesitesDatum>#{today}</teljesitesDatum>
        <fizetesiHataridoDatum>#{today}</fizetesiHataridoDatum>
        <fizmod>#{xml_escape(config.payment_method)}</fizmod>
        <penznem>HUF</penznem>
        <szamlaNyelve>hu</szamlaNyelve>
        <rendelesSzam>#{xml_escape(payment.payment_id || payment.payment_request_id)}</rendelesSzam>
        <szamlaKulsoAzon>#{xml_escape(payment.payment_id || payment.payment_request_id)}</szamlaKulsoAzon>
      </fejlec>
      <elado />
      <vevo>
        <nev>#{xml_escape(normalize(user.name) || user.email)}</nev>
        #{company_xml}
        <orszag>#{xml_escape(country)}</orszag>
        <irsz>#{xml_escape(normalize(user.billing_zip) || "")}</irsz>
        <telepules>#{xml_escape(normalize(user.billing_city) || "")}</telepules>
        <cim>#{xml_escape(normalize(user.billing_address) || "")}</cim>
        <email>#{xml_escape(user.email)}</email>
        <sendEmail>#{send_email}</sendEmail>
      </vevo>
      <tetelek>
        <tetel>
          <megnevezes>#{xml_escape(item_name)}</megnevezes>
          <mennyiseg>1</mennyiseg>
          <mennyisegiEgyseg>db</mennyisegiEgyseg>
          <nettoEgysegar>#{amount}</nettoEgysegar>
          <afakulcs>#{xml_escape(config.vat_key)}</afakulcs>
          <nettoErtek>#{amount}</nettoErtek>
          <afaErtek>0</afaErtek>
          <bruttoErtek>#{amount}</bruttoErtek>
        </tetel>
      </tetelek>
      <tesztszamla>#{test_mode}</tesztszamla>
    </xmlszamlaagent>
    """
  end

  defp parse_success_or_error(%{headers: headers, body: body}) do
    invoice_number =
      header_value(headers, "szlahu_szamlaszam") ||
        header_value(headers, "szlahu_invoice_number")

    error_message =
      header_value(headers, "szlahu_error") ||
        header_value(headers, "szlahu_error_message") ||
        body_error(body)

    cond do
      is_binary(error_message) and String.trim(error_message) != "" ->
        {:error, {:api_error, error_message}}

      true ->
        {:ok,
         %{
           invoice_number: invoice_number,
           headers: headers_to_plain_map(headers),
           body: normalize_body(body)
         }}
    end
  end

  defp parse_success_or_error(response), do: {:ok, %{body: inspect(response)}}

  defp body_error(body) when is_binary(body) do
    if String.contains?(String.downcase(body), "hiba"), do: body, else: nil
  end

  defp body_error(_), do: nil

  defp normalize_body(body) when is_binary(body), do: body
  defp normalize_body(body), do: inspect(body)

  defp headers_to_plain_map(headers) when is_map(headers) do
    headers
    |> Enum.into(%{}, fn {k, v} -> {String.downcase(to_string(k)), header_scalar(v)} end)
  end

  defp headers_to_plain_map(_), do: %{}

  defp header_value(headers, key) do
    headers
    |> headers_to_plain_map()
    |> Map.get(String.downcase(key))
    |> normalize()
  end

  defp header_scalar([first | _]), do: to_string(first)
  defp header_scalar(value), do: to_string(value)

  defp config do
    cfg = Application.get_env(:luca_gymapp, :szamlazz, [])

    %{
      base_url: Keyword.get(cfg, :base_url, @default_base_url),
      agent_key: Keyword.get(cfg, :agent_key),
      test_mode: Keyword.get(cfg, :test_mode, false),
      vat_key: Keyword.get(cfg, :vat_key, "AAM"),
      send_email: Keyword.get(cfg, :send_email, true),
      eszamla: Keyword.get(cfg, :eszamla, true),
      payment_method: Keyword.get(cfg, :payment_method, "Bankkartya"),
      timeout_ms: Keyword.get(cfg, :timeout_ms, 15_000)
    }
  end

  def invoice_item_name(%Payment{} = payment) do
    display_name = SeasonPasses.display_name(payment.pass_name)
    type_def = Enum.find(SeasonPasses.list_type_definitions(), &(&1.type == payment.pass_name))
    occasions = if type_def, do: type_def.occasions, else: nil

    cond do
      String.contains?(payment.pass_name || "", "cross") ->
        "Cross berlet - #{occasion_suffix(occasions)}"

      true ->
        "Szemelyi edzes berlet - #{occasion_suffix(occasions)} (#{display_name})"
    end
  end

  defp occasion_suffix(occasions) when is_integer(occasions) and occasions > 0,
    do: "#{occasions} alkalom"

  defp occasion_suffix(_), do: "egyszeri vasarlas"

  defp normalize_country(value) do
    case normalize(value) do
      nil -> "HU"
      country -> country
    end
  end

  defp normalize(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize(_), do: nil

  defp xml_escape(nil), do: ""

  defp xml_escape(value) do
    value
    |> to_string()
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&apos;")
  end
end
