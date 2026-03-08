defmodule LucaGymapp.Payments.SzamlazzClient do
  @moduledoc false
  @behaviour LucaGymapp.Payments.BillingClient

  alias LucaGymapp.Accounts.User
  alias LucaGymapp.Payments.Payment
  alias LucaGymapp.SeasonPasses
  require Logger

  @default_base_url "https://www.szamlazz.hu/szamla/"
  @default_timeout_ms 15_000
  @default_vat_key "AAM"

  @impl true
  def send_invoice(%Payment{} = payment, %User{} = user, opts \\ []) do
    config = config()
    xml_result = safe_invoice_xml(payment, user, opts)

    case xml_result do
      {:ok, xml} ->
        case Req.post(config.base_url,
               form_multipart: [
                 {"action-xmlagentxmlfile",
                  {xml, filename: "invoice.xml", content_type: "text/xml"}}
               ],
               receive_timeout: config.timeout_ms,
               retry: false
             ) do
          {:ok, %{status: 200} = response} ->
            parse_success_or_error(response)

          {:ok, %{status: status, body: body}} ->
            Logger.error(
              "szamlazz_http_error payment_id=#{payment.payment_id} payment_request_id=#{payment.payment_request_id} status=#{status} body=#{inspect(body)}"
            )

            {:error, {:http_error, status, to_string(body)}}

          {:error, reason} ->
            Logger.error(
              "szamlazz_http_no_response payment_id=#{payment.payment_id} payment_request_id=#{payment.payment_request_id} reason=#{inspect(reason)}"
            )

            {:error, {:no_response, reason}}
        end

      {:error, _} = error ->
        error
    end
  end

  @doc false
  def invoice_xml(%Payment{} = payment, %User{} = user, opts \\ []) do
    config = config()
    item_name = Keyword.fetch!(opts, :item_name)
    build_xml(payment, user, item_name, config)
  end

  defp build_xml(payment, user, item_name, config) do
    today = Date.utc_today() |> Date.to_iso8601()
    amount = payment.amount_huf
    payment_method = invoice_payment_method(payment.payment_method)
    test_mode = if config.test_mode, do: "true", else: "false"
    invoice_external_id = payment.payment_id || payment.payment_request_id

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
    <xmlszamla xmlns="http://www.szamlazz.hu/xmlszamla" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://www.szamlazz.hu/xmlszamla https://www.szamlazz.hu/szamla/docs/xsds/agent/xmlszamla.xsd">
      <beallitasok>
        <szamlaagentkulcs>#{xml_escape(config.agent_key)}</szamlaagentkulcs>
        <eszamla>true</eszamla>
        <szamlaLetoltes>false</szamlaLetoltes>
        <valaszVerzio>2</valaszVerzio>
        <szamlaKulsoAzon>#{xml_escape(invoice_external_id)}</szamlaKulsoAzon>
      </beallitasok>
      <fejlec>
        <keltDatum>#{today}</keltDatum>
        <teljesitesDatum>#{today}</teljesitesDatum>
        <fizetesiHataridoDatum>#{today}</fizetesiHataridoDatum>
        <fizmod>#{xml_escape(payment_method)}</fizmod>
        <penznem>HUF</penznem>
        <szamlaNyelve>hu</szamlaNyelve>
        <rendelesSzam>#{xml_escape(invoice_external_id)}</rendelesSzam>
      </fejlec>
      <elado />
      <vevo>
        <nev>#{xml_escape(normalize(user.name))}</nev>
        #{company_xml}
        <irsz>#{xml_escape(normalize(user.billing_zip) || "")}</irsz>
        <telepules>#{xml_escape(normalize(user.billing_city) || "")}</telepules>
        <cim>#{xml_escape(normalize(user.billing_address) || "")}</cim>
        <email>#{xml_escape(user.email)}</email>
        <sendEmail>true</sendEmail>
      </vevo>
      <tetelek>
        <tetel>
          <megnevezes>#{xml_escape(item_name)}</megnevezes>
          <mennyiseg>1</mennyiseg>
          <mennyisegiEgyseg>db</mennyisegiEgyseg>
          <nettoEgysegar>#{amount}</nettoEgysegar>
          <afakulcs>#{@default_vat_key}</afakulcs>
          <nettoErtek>#{amount}</nettoErtek>
          <afaErtek>0</afaErtek>
          <bruttoErtek>#{amount}</bruttoErtek>
        </tetel>
      </tetelek>
      <tesztszamla>#{test_mode}</tesztszamla>
    </xmlszamla>
    """
  end

  defp parse_success_or_error(%{headers: headers, body: body}) do
    try do
      invoice_number =
        header_value(headers, "szlahu_szamlaszam") ||
          header_value(headers, "szlahu_invoice_number")

      error_message =
        header_value(headers, "szlahu_error") ||
          header_value(headers, "szlahu_error_message") ||
          body_error(body)

      cond do
        is_binary(error_message) and String.trim(error_message) != "" ->
          Logger.error(
            "szamlazz_api_error error_message=#{inspect(error_message)} headers=#{inspect(headers)} body=#{inspect(body)}"
          )

          {:error, {:api_error, error_message}}

        true ->
          {:ok,
           %{
             invoice_number: invoice_number,
             headers: headers_to_plain_map(headers),
             body: normalize_body(body)
           }}
      end
    rescue
      exception ->
        Logger.error(
          "szamlazz_parse_error exception=#{inspect(exception)} headers=#{inspect(headers)} body=#{inspect(body)} stacktrace=#{Exception.format_stacktrace(__STACKTRACE__)}"
        )

        {:error, {:parse_error, inspect(exception)}}
    end
  end

  defp parse_success_or_error(response) do
    Logger.error("szamlazz_parse_unexpected_response response=#{inspect(response)}")
    {:error, {:parse_error, "unexpected_response"}}
  end

  defp safe_invoice_xml(%Payment{} = payment, %User{} = user, opts) do
    try do
      {:ok, invoice_xml(payment, user, opts)}
    rescue
      exception ->
        Logger.error(
          "szamlazz_xml_generation_error payment_id=#{payment.payment_id} payment_request_id=#{payment.payment_request_id} user_id=#{user.id} exception=#{inspect(exception)} opts=#{inspect(opts)} stacktrace=#{Exception.format_stacktrace(__STACKTRACE__)}"
        )

        {:error, {:xml_generation_error, inspect(exception)}}
    end
  end

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
      timeout_ms: Keyword.get(cfg, :timeout_ms, @default_timeout_ms)
    }
  end

  defp invoice_payment_method("cash"), do: "Készpénz"
  defp invoice_payment_method("barion"), do: "Bankkártya"
  defp invoice_payment_method("bankcard"), do: "Bankkártya"
  defp invoice_payment_method("bank_card"), do: "Bankkártya"
  defp invoice_payment_method(_), do: "Bankkártya"

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
