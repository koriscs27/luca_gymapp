defmodule LucaGymappWeb.PageControllerTest do
  use LucaGymappWeb.ConnCase

  alias LucaGymapp.Accounts.User
  alias LucaGymapp.Repo
  alias LucaGymapp.SeasonPasses.SeasonPass

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Luca Gym"
  end

  test "berletek purchase buttons are inactive for guests", %{conn: conn} do
    conn = get(conn, ~p"/berletek")
    html = html_response(conn, 200)

    assert html =~ "Bejelentkezés szükséges"
    assert html =~ ~s(type="button")
    assert html =~ ~s(disabled)
  end

  test "berletek shows only latest valid pass per category and no empty-state text", %{conn: conn} do
    user =
      %User{
        email: "passes@example.com",
        password_hash: "hash",
        email_confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }
      |> Repo.insert!()

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    insert_pass(user.id, %{
      pass_name: "personal_valid_older",
      pass_type: "personal",
      occasions: 3,
      purchase_timestamp: DateTime.add(now, -3, :day),
      expiry_date: Date.add(Date.utc_today(), 10)
    })

    insert_pass(user.id, %{
      pass_name: "personal_invalid_newest",
      pass_type: "personal",
      occasions: 0,
      purchase_timestamp: DateTime.add(now, -1, :day),
      expiry_date: Date.add(Date.utc_today(), 10)
    })

    insert_pass(user.id, %{
      pass_name: "other_valid_latest",
      pass_type: "other",
      occasions: 0,
      purchase_timestamp: now,
      expiry_date: Date.add(Date.utc_today(), 20)
    })

    conn = conn |> init_test_session(%{user_id: user.id}) |> get(~p"/berletek")
    html = html_response(conn, 200)

    assert html =~ "Legutóbbi bérletek"
    assert html =~ "Personal valid older"
    assert html =~ "Other valid latest"
    refute html =~ "Personal invalid newest"
    refute html =~ "Nincs még bérlet ebben a kategóriában."
  end

  defp insert_pass(user_id, attrs) do
    %SeasonPass{}
    |> SeasonPass.changeset(
      Map.merge(
        %{
          pass_id: Ecto.UUID.generate(),
          pass_name: "default_pass",
          pass_type: "personal",
          occasions: 1,
          purchase_timestamp: DateTime.utc_now() |> DateTime.truncate(:second),
          purchase_price: 10_000,
          expiry_date: Date.add(Date.utc_today(), 30),
          user_id: user_id
        },
        attrs
      )
    )
    |> Repo.insert!()
  end
end
