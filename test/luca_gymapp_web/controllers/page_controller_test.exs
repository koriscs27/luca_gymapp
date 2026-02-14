defmodule LucaGymappWeb.PageControllerTest do
  use LucaGymappWeb.ConnCase
  import Swoosh.TestAssertions

  alias LucaGymapp.Accounts.User
  alias LucaGymapp.Bookings.CalendarSlot
  alias LucaGymapp.Bookings.CrossBooking
  alias LucaGymapp.Bookings.PersonalBooking
  alias LucaGymapp.Repo
  alias LucaGymapp.SeasonPasses
  alias LucaGymapp.SeasonPasses.SeasonPass

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Luca Gym"
  end

  test "GET /rolam", %{conn: conn} do
    conn = get(conn, ~p"/rolam")
    html = html_response(conn, 200)

    assert html =~ "Luca - edző, mentor, motivátor."
    assert html =~ "rolam-video-1"
    assert html =~ "rolam-video-2"
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

    refute Enum.any?(headings, &String.contains?(&1, "LegutĂ„â€šÄąâ€šbbi bĂ„â€šĂ‚Â©rletek"))
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

    refute String.contains?(
             LazyHTML.text(doc),
             "Nincs mĂ„â€šĂ‚Â©g bĂ„â€šĂ‚Â©rlet ebben a kategĂ„â€šÄąâ€šriĂ„â€šĂ‹â€ˇban."
           )
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

  test "personal booking too close shows preparation-time message", %{conn: conn} do
    user =
      %User{
        email: "personal-too-close@example.com",
        password_hash: "hash",
        email_confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }
      |> Repo.insert!()

    insert_pass(user.id, %{pass_name: "personal_close", pass_type: "personal", occasions: 1})

    start_time =
      DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.add(2 * 60 * 60, :second)

    end_time = DateTime.add(start_time, 60 * 60, :second)
    insert_calendar_slot("personal", start_time, end_time)

    conn =
      conn
      |> init_test_session(%{user_id: user.id})
      |> post(~p"/foglalas/personal", %{
        "start_time" => DateTime.to_iso8601(start_time),
        "end_time" => DateTime.to_iso8601(end_time)
      })

    assert redirected_to(conn) == ~p"/foglalas?type=personal&view=week"

    assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
             "A személyi edzést legalább 6 óráva az edzés kezdete előtt kell lefoglalni."
  end

  test "booking without valid pass shows a specific message", %{conn: conn} do
    user =
      %User{
        email: "no-valid-pass@example.com",
        password_hash: "hash",
        email_confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }
      |> Repo.insert!()

    start_time =
      DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.add(8 * 60 * 60, :second)

    end_time = DateTime.add(start_time, 60 * 60, :second)
    insert_calendar_slot("personal", start_time, end_time)

    conn =
      conn
      |> init_test_session(%{user_id: user.id})
      |> post(~p"/foglalas/personal", %{
        "start_time" => DateTime.to_iso8601(start_time),
        "end_time" => DateTime.to_iso8601(end_time)
      })

    assert redirected_to(conn) == ~p"/foglalas?type=personal&view=week"

    assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
             "Ehhez a foglaláshoz nincs érvényes bérleted."
  end

  test "booking page lists all active passes in selected category", %{conn: conn} do
    user =
      %User{
        email: "multi-pass-booking@example.com",
        password_hash: "hash",
        email_confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }
      |> Repo.insert!()

    insert_pass(user.id, %{
      pass_name: "alpha_pass",
      pass_type: "personal",
      occasions: 1,
      purchase_timestamp: DateTime.add(DateTime.utc_now() |> DateTime.truncate(:second), -1, :day)
    })

    insert_pass(user.id, %{
      pass_name: "beta_pass",
      pass_type: "personal",
      occasions: 2,
      purchase_timestamp: DateTime.utc_now() |> DateTime.truncate(:second)
    })

    conn =
      conn |> init_test_session(%{user_id: user.id}) |> get(~p"/foglalas?type=personal&week=0")

    html = html_response(conn, 200)

    assert html =~ "Alpha pass"
    assert html =~ "Beta pass"
  end

  test "users cannot navigate to previous week and week offset is clamped at current week", %{
    conn: conn
  } do
    user =
      %User{
        email: "week-clamp-user@example.com",
        password_hash: "hash",
        email_confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }
      |> Repo.insert!()

    conn =
      conn
      |> init_test_session(%{user_id: user.id})
      |> get(~p"/foglalas?type=personal&week=-1")

    html = html_response(conn, 200)

    assert html =~ "Előző hét"
    assert html =~ "cursor-not-allowed"
    refute html =~ ~s(href="/foglalas?type=personal&amp;week=-1")
  end

  test "admins can still navigate to previous week from current week", %{conn: conn} do
    admin =
      %User{
        email: "week-clamp-admin@example.com",
        password_hash: "hash",
        admin: true,
        email_confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }
      |> Repo.insert!()

    conn =
      conn
      |> init_test_session(%{user_id: admin.id})
      |> get(~p"/foglalas?type=personal&week=0")

    html = html_response(conn, 200)

    assert html =~ ~s(href="/foglalas?type=personal&amp;week=-1")
  end

  test "booking a past cross slot shows a specific message", %{conn: conn} do
    user =
      %User{
        email: "past-cross@example.com",
        password_hash: "hash",
        email_confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }
      |> Repo.insert!()

    insert_pass(user.id, %{pass_name: "cross_past", pass_type: "cross", occasions: 1})

    start_time =
      DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.add(-2 * 60 * 60, :second)

    end_time = DateTime.add(start_time, 60 * 60, :second)
    insert_calendar_slot("cross", start_time, end_time)

    conn =
      conn
      |> init_test_session(%{user_id: user.id})
      |> post(~p"/foglalas/cross", %{
        "start_time" => DateTime.to_iso8601(start_time),
        "end_time" => DateTime.to_iso8601(end_time)
      })

    assert redirected_to(conn) == ~p"/foglalas?type=cross&view=week"

    assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
             "Erre az időpontra már nem lehet foglalni, mert elmúlt."
  end

  test "cross slot shows full for non-booked user when capacity reached", %{conn: conn} do
    user =
      %User{
        email: "cross-viewer@example.com",
        password_hash: "hash",
        email_confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }
      |> Repo.insert!()

    {start_time, end_time, week_offset} = future_slot_and_week()
    insert_calendar_slot("cross", start_time, end_time)

    user_a =
      %User{
        email: "cross-full-a@example.com",
        password_hash: "hash",
        email_confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }
      |> Repo.insert!()

    user_b =
      %User{
        email: "cross-full-b@example.com",
        password_hash: "hash",
        email_confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }
      |> Repo.insert!()

    pass_a =
      insert_pass(user_a.id, %{pass_name: "cross_test_a", pass_type: "cross", occasions: 1})

    pass_b =
      insert_pass(user_b.id, %{pass_name: "cross_test_b", pass_type: "cross", occasions: 1})

    insert_cross_booking(user_a.id, pass_a.pass_id, start_time, end_time)
    insert_cross_booking(user_b.id, pass_b.pass_id, start_time, end_time)

    conn =
      conn
      |> init_test_session(%{user_id: user.id})
      |> get(~p"/foglalas?type=cross&week=#{week_offset}")

    html = html_response(conn, 200)

    assert html =~ "MEGTELT"
    refute html =~ "Igen, foglalok"
  end

  test "personal slot shows occupied for non-booked user", %{conn: conn} do
    viewer =
      %User{
        email: "personal-viewer@example.com",
        password_hash: "hash",
        email_confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }
      |> Repo.insert!()

    booked_user =
      %User{
        email: "personal-booked@example.com",
        password_hash: "hash",
        email_confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }
      |> Repo.insert!()

    monday = Date.beginning_of_week(Date.utc_today(), :monday)
    start_time = DateTime.new!(monday, ~T[10:00:00], "Etc/UTC")
    end_time = DateTime.new!(monday, ~T[11:00:00], "Etc/UTC")
    insert_calendar_slot("personal", start_time, end_time)

    pass =
      insert_pass(booked_user.id, %{
        pass_name: "personal_booked",
        pass_type: "personal",
        occasions: 1
      })

    insert_personal_booking(booked_user.id, pass.pass_id, start_time, end_time)

    conn =
      conn |> init_test_session(%{user_id: viewer.id}) |> get(~p"/foglalas?type=personal&week=0")

    html = html_response(conn, 200)

    refute html =~ "falseFoglalt"
    refute html =~ "Igen, foglalok"
  end

  test "cross slot shows booked for user even when capacity reached", %{conn: conn} do
    {start_time, end_time, week_offset} = future_slot_and_week()
    insert_calendar_slot("cross", start_time, end_time)

    user_a =
      %User{
        email: "cross-booked-a@example.com",
        password_hash: "hash",
        email_confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }
      |> Repo.insert!()

    user_b =
      %User{
        email: "cross-booked-b@example.com",
        password_hash: "hash",
        email_confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }
      |> Repo.insert!()

    pass_a =
      insert_pass(user_a.id, %{pass_name: "cross_booked_a", pass_type: "cross", occasions: 1})

    pass_b =
      insert_pass(user_b.id, %{pass_name: "cross_booked_b", pass_type: "cross", occasions: 1})

    insert_cross_booking(user_a.id, pass_a.pass_id, start_time, end_time)
    insert_cross_booking(user_b.id, pass_b.pass_id, start_time, end_time)

    conn =
      conn
      |> init_test_session(%{user_id: user_a.id})
      |> get(~p"/foglalas?type=cross&week=#{week_offset}")

    html = html_response(conn, 200)

    assert html =~ "Foglalva"
    assert html =~ "Lemond"
  end

  test "admin can cancel personal booking and user receives email", %{conn: conn} do
    admin =
      %User{
        email: "admin-personal-cancel@example.com",
        password_hash: "hash",
        admin: true,
        email_confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }
      |> Repo.insert!()

    booked_user =
      %User{
        email: "booked-personal@example.com",
        password_hash: "hash",
        name: "Booked Personal",
        email_confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }
      |> Repo.insert!()

    monday = Date.beginning_of_week(Date.utc_today(), :monday)
    start_time = DateTime.new!(monday, ~T[10:00:00], "Etc/UTC")
    end_time = DateTime.new!(monday, ~T[11:00:00], "Etc/UTC")

    pass =
      insert_pass(booked_user.id, %{
        pass_name: "admin_cancel_personal",
        pass_type: "personal",
        occasions: 0
      })

    booking =
      %PersonalBooking{}
      |> PersonalBooking.changeset(%{
        user_name: "Booked Personal",
        start_time: start_time,
        end_time: end_time,
        booking_timestamp: DateTime.utc_now() |> DateTime.truncate(:second),
        status: "booked",
        pass_id: pass.pass_id
      })
      |> Ecto.Changeset.put_change(:user_id, booked_user.id)
      |> Repo.insert!()

    conn =
      conn
      |> init_test_session(%{user_id: admin.id})
      |> post(~p"/foglalas/admin/booking/delete", %{
        "admin_booking_delete" => %{
          "type" => "personal",
          "booking_id" => Integer.to_string(booking.id),
          "week" => "0"
        }
      })

    assert redirected_to(conn) == ~p"/admin/foglalas?week=0"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) == "A foglalas torolve lett."

    cancelled = Repo.get!(PersonalBooking, booking.id)
    assert cancelled.status == "cancelled"

    reloaded_pass = Repo.get_by!(SeasonPass, pass_id: pass.pass_id)
    assert reloaded_pass.occasions == 1

    assert_email_sent(to: {booked_user.name, booked_user.email})
  end

  test "admin can cancel cross booking and user receives email", %{conn: conn} do
    admin =
      %User{
        email: "admin-cross-cancel@example.com",
        password_hash: "hash",
        admin: true,
        email_confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }
      |> Repo.insert!()

    booked_user =
      %User{
        email: "booked-cross@example.com",
        password_hash: "hash",
        name: "Booked Cross",
        email_confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }
      |> Repo.insert!()

    monday = Date.beginning_of_week(Date.utc_today(), :monday)
    start_time = DateTime.new!(monday, ~T[17:00:00], "Etc/UTC")
    end_time = DateTime.new!(monday, ~T[18:00:00], "Etc/UTC")

    pass =
      insert_pass(booked_user.id, %{
        pass_name: "admin_cancel_cross",
        pass_type: "cross",
        occasions: 0
      })

    booking = insert_cross_booking(booked_user.id, pass.pass_id, start_time, end_time)

    conn =
      conn
      |> init_test_session(%{user_id: admin.id})
      |> post(~p"/foglalas/admin/booking/delete", %{
        "admin_booking_delete" => %{
          "type" => "cross",
          "booking_id" => Integer.to_string(booking.id),
          "week" => "0"
        }
      })

    assert redirected_to(conn) == ~p"/admin/foglalas?week=0"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) == "A foglalas torolve lett."

    cancelled = Repo.get!(CrossBooking, booking.id)
    assert cancelled.status == "cancelled"

    reloaded_pass = Repo.get_by!(SeasonPass, pass_id: pass.pass_id)
    assert reloaded_pass.occasions == 1

    assert_email_sent(to: {booked_user.name, booked_user.email})
  end

  test "admin purchase shows specific error when target user already has active pass", %{
    conn: conn
  } do
    admin =
      %User{
        email: "admin-pass-error@example.com",
        password_hash: "hash",
        admin: true,
        email_confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }
      |> Repo.insert!()

    target_user =
      %User{
        email: "target-pass-error@example.com",
        password_hash: "hash",
        email_confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }
      |> Repo.insert!()

    insert_pass(target_user.id, %{
      pass_name: "10_alkalmas_berlet",
      pass_type: "personal",
      occasions: 3,
      expiry_date: Date.add(Date.utc_today(), 30)
    })

    conn =
      conn
      |> init_test_session(%{user_id: admin.id})
      |> post(~p"/berletek/admin/purchase", %{
        "admin_purchase" => %{
          "user_id" => Integer.to_string(target_user.id),
          "pass_name" => "1_alkalmas_jegy"
        }
      })

    assert redirected_to(conn) == ~p"/berletek"

    assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
             "A kiválasztott felhasználónak már van aktív bérlete ebben a kategóriában."
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

  defp insert_calendar_slot(slot_type, %DateTime{} = start_time, %DateTime{} = end_time) do
    %CalendarSlot{}
    |> CalendarSlot.changeset(%{
      slot_type: slot_type,
      start_time: start_time,
      end_time: end_time
    })
    |> Repo.insert!()
  end

  defp insert_cross_booking(user_id, pass_id, %DateTime{} = start_time, %DateTime{} = end_time) do
    %CrossBooking{}
    |> CrossBooking.changeset(%{
      user_name: "Cross User",
      start_time: start_time,
      end_time: end_time,
      booking_timestamp: DateTime.utc_now() |> DateTime.truncate(:second),
      status: "booked",
      pass_id: pass_id
    })
    |> Ecto.Changeset.put_change(:user_id, user_id)
    |> Repo.insert!()
  end

  defp insert_personal_booking(user_id, pass_id, %DateTime{} = start_time, %DateTime{} = end_time) do
    %LucaGymapp.Bookings.PersonalBooking{}
    |> LucaGymapp.Bookings.PersonalBooking.changeset(%{
      user_name: "Personal User",
      start_time: start_time,
      end_time: end_time,
      booking_timestamp: DateTime.utc_now() |> DateTime.truncate(:second),
      status: "booked",
      pass_id: pass_id
    })
    |> Ecto.Changeset.put_change(:user_id, user_id)
    |> Repo.insert!()
  end

  defp future_slot_and_week do
    start_time =
      DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.add(2 * 60 * 60, :second)

    end_time = DateTime.add(start_time, 60 * 60, :second)
    week_offset = Date.diff(DateTime.to_date(start_time), Date.utc_today()) |> div(7)

    {start_time, end_time, week_offset}
  end
end
