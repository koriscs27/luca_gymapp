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
       %{status: 200, body: %{"PaymentId" => payment_id, "GatewayUrl" => gateway_url} = body}} ->
        if has_errors?(body) do
          {:error, {:barion_error, body}}
        else
          {:ok, %{payment_id: payment_id, gateway_url: gateway_url, raw: body}}
        end

      {:ok, %{status: status, body: body}} ->
        Logger.warning("barion_start_failed status=#{status} body=#{inspect(body)}")
        {:error, {:barion_http_error, status, body}}

      {:error, error} ->
        Logger.error("barion_start_failed error=#{inspect(error)}")
        {:error, {:barion_request_failed, error}}
    end
  end

  def payment_state(payment_id) when is_binary(payment_id) do
    api_base_url = barion_api_base_url()
    pos_key = barion_pos_key()
    request = Req.new(base_url: api_base_url, headers: [{"x-pos-key", pos_key}])

    case Req.get(request, url: "/v4/Payment/#{payment_id}/paymentstate") do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        Logger.warning("barion_state_failed status=#{status} body=#{inspect(body)}")
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
end
