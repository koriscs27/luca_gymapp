defmodule LucaGymapp.Payments.Barion do
  @moduledoc false

  require Logger

  def start_payment(%{
        pos_key: pos_key,
        payee_email: payee_email,
        payment_request_id: payment_request_id,
        pass_name: pass_name,
        amount_huf: amount_huf,
        payer_email: payer_email,
        redirect_url: redirect_url,
        callback_url: callback_url
      }) do
    api_base_url = barion_api_base_url()
    pos_key = String.trim(pos_key)
    payee_email = String.trim(payee_email)

    payload = %{
      "POSKey" => pos_key,
      "PaymentType" => "Immediate",
      "GuestCheckout" => true,
      "FundingSources" => ["All"],
      "PaymentRequestId" => payment_request_id,
      "RedirectUrl" => redirect_url,
      "CallbackUrl" => callback_url,
      "Locale" => "hu-HU",
      "PayerHint" => payer_email,
      "Transactions" => [
        %{
          "POSTransactionId" => Ecto.UUID.generate(),
          "Payee" => payee_email,
          "Total" => amount_huf,
          "Currency" => "HUF",
          "Items" => [
            %{
              "Name" => pass_name,
              "Quantity" => 1,
              "Unit" => "db",
              "UnitPrice" => amount_huf,
              "ItemTotal" => amount_huf
            }
          ]
        }
      ]
    }

    request = Req.new(base_url: api_base_url, headers: [{"x-pos-key", pos_key}])

    case Req.post(request, url: "/v2/Payment/Start", json: payload) do
      {:ok,
       %{status: 200, body: %{"PaymentId" => payment_id, "GatewayUrl" => gateway_url} = body} = response} ->
        if has_errors?(body) do
          request_id = request_id_from_response(response)
          Logger.warning("barion_start_errors request_id=#{request_id || "n/a"} body=#{inspect(body)}")
          {:error, {:barion_error, body}}
        else
          {:ok, %{payment_id: payment_id, gateway_url: gateway_url, raw: body}}
        end

      {:ok, %{status: status, body: body} = response} ->
        request_id = request_id_from_response(response)

        Logger.warning(
          "barion_start_failed status=#{status} request_id=#{request_id || "n/a"} body=#{inspect(body)}"
        )

        {:error, {:barion_http_error, status, body}}

      {:error, error} ->
        Logger.error("barion_start_failed error=#{inspect(error)}")
        {:error, {:barion_request_failed, error}}
    end
  end

  def payment_state(payment_id) when is_binary(payment_id) do
    api_base_url = barion_api_base_url()

    pos_key =
      barion_pos_key()
      |> String.trim()

    request = Req.new(base_url: api_base_url, headers: [{"x-pos-key", pos_key}])

    case Req.get(request, url: "/v4/Payment/#{payment_id}/paymentstate") do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: status, body: body} = response} ->
        request_id = request_id_from_response(response)

        Logger.warning(
          "barion_state_failed status=#{status} request_id=#{request_id || "n/a"} body=#{inspect(body)}"
        )

        {:error, {:barion_http_error, status, body}}

      {:error, error} ->
        Logger.error("barion_state_failed error=#{inspect(error)}")
        {:error, {:barion_request_failed, error}}
    end
  end

  defp barion_api_base_url do
    Application.get_env(:luca_gymapp, :barion, [])
    |> Keyword.fetch!(:api_base_url)
  end

  defp barion_pos_key do
    Application.get_env(:luca_gymapp, :barion, [])
    |> Keyword.fetch!(:pos_key)
  end

  defp has_errors?(%{"Errors" => errors}) when is_list(errors) and length(errors) > 0, do: true
  defp has_errors?(_), do: false

  defp request_id_from_response(%{headers: headers, body: body}) do
    header_id = request_id_from_headers(headers)
    body_id = request_id_from_body(body)
    header_id || body_id
  end

  defp request_id_from_response(%{headers: headers}) do
    request_id_from_headers(headers)
  end

  defp request_id_from_response(%{body: body}) do
    request_id_from_body(body)
  end

  defp request_id_from_response(_), do: nil

  defp request_id_from_headers(headers) when is_map(headers) do
    Map.new(headers, fn {k, v} -> {String.downcase(to_string(k)), v} end)
    |> Enum.find_value(fn
      {"x-request-id", value} -> normalize_header_value(value)
      {"request-id", value} -> normalize_header_value(value)
      {"x-correlation-id", value} -> normalize_header_value(value)
      _ -> nil
    end)
  end

  defp request_id_from_headers(_), do: nil

  defp request_id_from_body(body) when is_map(body) do
    Map.get(body, "RequestId") || Map.get(body, "requestId") || Map.get(body, "RequestID")
  end

  defp request_id_from_body(_), do: nil

  defp normalize_header_value([value | _]), do: to_string(value)
  defp normalize_header_value(value) when is_binary(value), do: value
  defp normalize_header_value(value), do: to_string(value)
end
