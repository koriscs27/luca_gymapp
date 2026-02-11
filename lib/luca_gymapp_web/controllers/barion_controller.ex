defmodule LucaGymappWeb.BarionController do
  use LucaGymappWeb, :controller

  alias LucaGymapp.Payments
  require Logger

  def return(conn, %{"paymentId" => payment_id}) do
    Logger.warning("barion_return payload=#{inspect(conn.query_params)}")

    if dev_env?() do
      payment_error(conn)
    else
      case Payments.handle_return(payment_id) do
        {:ok, "paid"} ->
          conn
          |> put_flash(:info, "Sikeres fizetés. A bérleted aktiválva lett.")
          |> redirect(to: ~p"/berletek")

        {:ok, status} when status in ["pending", "authorized"] ->
          conn
          |> put_flash(:info, "A fizetés feldolgozás alatt. Kérjük, térj vissza később.")
          |> redirect(to: ~p"/berletek")

        {:ok, _status} ->
          payment_error(conn)

        {:error, _reason} ->
          payment_error(conn)
      end
    end
  end

  def return(conn, _params) do
    Logger.warning("barion_return payload=#{inspect(conn.query_params)}")
    payment_error(conn)
  end

  def callback(conn, params) do
    Logger.warning("barion_callback payload=#{inspect(params)}")
    payment_id = Map.get(params, "PaymentId") || Map.get(params, "paymentId")

    if is_binary(payment_id) do
      _ = Payments.handle_callback(payment_id)
    end

    send_resp(conn, 200, "OK")
  end

  def check(conn, %{"payment_id" => payment_id}) do
    current_user_id = get_session(conn, :user_id)

    if current_user_id do
      case Payments.sync_payment_status_for_user(current_user_id, payment_id) do
        {:ok, %LucaGymapp.Payments.Payment{status: "paid"}} ->
          conn
          |> put_flash(:info, "Sikeres fizetés. A bérleted aktiválva lett.")
          |> redirect(to: ~p"/berletek")

        {:ok, %LucaGymapp.Payments.Payment{status: status}}
        when status in ["pending", "authorized"] ->
          conn
          |> put_flash(:info, "A fizetés még feldolgozás alatt van. Próbáld meg később.")
          |> redirect(to: ~p"/berletek")

        {:ok, _payment} ->
          conn
          |> put_flash(:error, "A fizetés nem sikerült. Próbáld újra.")
          |> redirect(to: ~p"/berletek")

        {:error, :payment_not_found} ->
          conn
          |> put_flash(:error, "Nem található ilyen fizetés.")
          |> redirect(to: ~p"/berletek")

        {:error, _reason} ->
          conn
          |> put_flash(:error, "Nem sikerült lekérdezni a fizetés státuszát.")
          |> redirect(to: ~p"/berletek")
      end
    else
      conn
      |> put_flash(:error, "Jelentkezz be a fizetés ellenőrzéséhez.")
      |> redirect(to: ~p"/berletek")
    end
  end

  def check(conn, _params) do
    conn
    |> put_flash(:error, "Nem sikerült lekérdezni a fizetés státuszát.")
    |> redirect(to: ~p"/berletek")
  end

  defp payment_error(conn) do
    conn
    |> put_flash(:error, "A fizetés nem sikerült. Próbáld újra.")
    |> redirect(to: ~p"/berletek")
  end

  defp dev_env?, do: Application.get_env(:luca_gymapp, :env) == "dev"
end
