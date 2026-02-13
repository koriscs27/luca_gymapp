defmodule LucaGymappWeb.PageControllerTest do
  use LucaGymappWeb.ConnCase

  alias LucaGymapp.Accounts.User
  alias LucaGymapp.Repo
  alias LucaGymapp.SeasonPasses
  alias LucaGymapp.SeasonPasses.SeasonPass

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Luca Gym"
  end

  test "berletek purchase buttons are inactive for guests", %{conn: conn} do
    conn = get(conn, ~p"/berletek")
    html = html_response(conn, 200)
    doc = LazyHTML.from_document(html)

    SeasonPasses.list_type_definitions()
    |> Enum.each(fn pass ->
      button_id = "purchase-button-#{pass.key}"
      button = LazyHTML.query_by_id(doc, button_id)

      assert LazyHTML.tag(button) == ["button"]
      assert LazyHTML.attribute(button, "disabled") == [""]
    end)
  end

  test "berletek hides recent passes when only expired passes exist", %{conn: conn} do
    user =
      %User{
        email: "expired-pass@example.com",
        password_hash: "hash",
        email_confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }
      |> Repo.insert!()

    insert_pass(user.id, %{
      pass_name: "10_alkalmas_berlet",
      pass_type: "personal",
      occasions: 5,
      expiry_date: Date.add(Date.utc_today(), -1)
    })

    conn = conn |> init_test_session(%{user_id: user.id}) |> get(~p"/berletek")
    html = html_response(conn, 200)
    doc = LazyHTML.from_document(html)

    headings =
      doc
      |> LazyHTML.query("h2")
      |> Enum.map(&LazyHTML.text/1)

    refute Enum.any?(headings, &String.contains?(&1, "Legutóbbi bérletek"))
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
    doc = LazyHTML.from_document(html)

    recent_titles =
      doc
      |> LazyHTML.query("section.bg-neutral-950 .grid p.mt-2")
      |> Enum.map(fn node -> node |> LazyHTML.text() |> String.trim() end)

    assert "Personal valid older" in recent_titles
    assert "Other valid latest" in recent_titles
    refute "Personal invalid newest" in recent_titles
    refute String.contains?(LazyHTML.text(doc), "Nincs még bérlet ebben a kategóriában.")
  end

  test "purchase shows specific error when user already has active pass in category", %{
    conn: conn
  } do
    user =
      %User{
        email: "active-pass@example.com",
        password_hash: "hash",
        email_confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }
      |> Repo.insert!()

    insert_pass(user.id, %{
      pass_name: "10_alkalmas_berlet",
      pass_type: "personal",
      occasions: 5,
      expiry_date: Date.add(Date.utc_today(), 30)
    })

    conn =
      conn
      |> init_test_session(%{user_id: user.id})
      |> post(~p"/berletek/purchase", %{
        "pass_name" => "1_alkalmas_jegy",
        "payment_method" => "barion"
      })

    assert redirected_to(conn) == ~p"/berletek"

    assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
             "Már van aktív bérleted ebben a kategóriában."
  end

  defp insert_pass(user_id, attrs) do
    %SeasonPass{}
    |> SeasonPass.changeset(
      Map.merge(
        %{
          pass_id: Ecto.UUID.generate(),
          pass_name: "default_pass",
          pass_type: "personal",
          payment_method: "cash",
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
