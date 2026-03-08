defmodule LucaGymappWeb.PageControllerTest do
  use LucaGymappWeb.ConnCase
  import Swoosh.TestAssertions

  alias LucaGymapp.Accounts.User
  alias LucaGymapp.Bookings
  alias LucaGymapp.Bookings.AdminDraftStore
  alias LucaGymapp.Bookings.CalendarSlot
  alias LucaGymapp.Bookings.CrossBooking
  alias LucaGymapp.Bookings.PersonalBooking
  alias LucaGymapp.Repo
  alias LucaGymapp.SeasonPasses
  alias LucaGymapp.SeasonPasses.SeasonPass

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    html = html_response(conn, 200)

    assert html =~ "PL logo"
    assert html =~ "home-video-personal"
  end

  test "GET / renders Barion Pixel base code when pixel id is configured", %{conn: conn} do
    previous_value = Application.get_env(:luca_gymapp, :barion_pixel_id)
    pixel_id = "BP-TEST-PIXEL-ID"

    on_exit(fn ->
      Application.put_env(:luca_gymapp, :barion_pixel_id, previous_value)
    end)

    Application.put_env(:luca_gymapp, :barion_pixel_id, pixel_id)

    conn = get(conn, ~p"/")
    html = html_response(conn, 200)

    assert html =~ "https://pixel.barion.com/bp.js"
    assert html =~ ~s(window["barion_pixel_id"] = "#{pixel_id}")
    assert html =~ "bp(\"init\", \"addBarionPixelId\", window[\"barion_pixel_id\"]);"

    encoded_pixel_id = URI.encode_www_form(pixel_id)

    assert html =~ "https://pixel.barion.com/a.gif?ba_pixel_id=#{encoded_pixel_id}"
    assert html =~ "ev=contentView"
    assert html =~ "noscript=1"
  end

  test "GET / does not render Barion Pixel code when pixel id is missing", %{conn: conn} do
    previous_value = Application.get_env(:luca_gymapp, :barion_pixel_id)

    on_exit(fn ->
      Application.put_env(:luca_gymapp, :barion_pixel_id, previous_value)
    end)

    Application.delete_env(:luca_gymapp, :barion_pixel_id)

    conn = get(conn, ~p"/")
    html = html_response(conn, 200)

    refute html =~ "https://pixel.barion.com/bp.js"
    refute html =~ "https://pixel.barion.com/a.gif?"
    refute html =~ "bp(\"init\", \"addBarionPixelId\""
  end

  test "GET /rolam", %{conn: conn} do
    conn = get(conn, ~p"/rolam")
    html = html_response(conn, 200)

    assert html =~ "Pankotai Luca vagyok"
    assert html =~ "rolam-video-1"
  end

  test "GET /aszf supports return_to and renders back link", %{conn: conn} do
    conn = get(conn, ~p"/aszf?return_to=%2Fprofile")
    html = html_response(conn, 200)

    assert html =~ ~s(id="aszf-back-button")
    assert html =~ ~s(href="/profile")
  end

  test "GET /adatkezelesi-tajekoztato supports return_to and renders back link", %{conn: conn} do
    conn = get(conn, ~p"/adatkezelesi-tajekoztato?return_to=%2Fprofile")
    html = html_response(conn, 200)

    assert html =~ ~s(id="adatkezelesi-back-button")
    assert html =~ ~s(href="/profile")
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

    refute Enum.any?(
             headings,
             &String.contains?(&1, "Legutobbi berletek")
           )
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
             "Nincs meg berlet ebben a kategoriaban."
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
        "payment_method" => "barion",
        "accept_aszf" => "true"
      })

    assert redirected_to(conn) == ~p"/berletek"

    assert Phoenix.Flash.get(conn.assigns.flash, :error)
  end

  test "purchase requires billing profile data before starting payment", %{conn: conn} do
    user =
      %User{
        email: "missing-billing@example.com",
        password_hash: "hash",
        email_confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second),
        name: nil,
        billing_country: nil,
        billing_zip: nil,
        billing_city: nil,
        billing_address: nil
      }
      |> Repo.insert!()

    conn =
      conn
      |> init_test_session(%{user_id: user.id})
      |> post(~p"/berletek/purchase", %{
        "pass_name" => "10_alkalmas_berlet",
        "accept_aszf" => "true"
      })

    assert redirected_to(conn) == ~p"/berletek"

    assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
             "A vásárláshoz töltsd ki a nevedet és a számlázási adatokat a profil oldalon."
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

    assert Phoenix.Flash.get(conn.assigns.flash, :error)
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

    assert Phoenix.Flash.get(conn.assigns.flash, :error)
  end

  test "personal booking keeps selected week after successful booking", %{conn: conn} do
    user =
      %User{
        email: "personal-week-keep@example.com",
        password_hash: "hash",
        email_confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }
      |> Repo.insert!()

    insert_pass(user.id, %{pass_name: "personal_week_keep", pass_type: "personal", occasions: 1})

    slot_date = Date.add(Date.utc_today(), 14)
    start_time = DateTime.new!(slot_date, ~T[10:00:00], "Etc/UTC")
    end_time = DateTime.add(start_time, 60 * 60, :second)
    insert_calendar_slot("personal", start_time, end_time)

    conn =
      conn
      |> init_test_session(%{user_id: user.id})
      |> post(~p"/foglalas/personal", %{
        "start_time" => DateTime.to_iso8601(start_time),
        "end_time" => DateTime.to_iso8601(end_time),
        "week" => "2"
      })

    assert redirected_to(conn) == ~p"/foglalas?type=personal&view=week&week=2"
  end

  test "cross booking keeps selected week after successful booking", %{conn: conn} do
    user =
      %User{
        email: "cross-week-keep@example.com",
        password_hash: "hash",
        email_confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }
      |> Repo.insert!()

    insert_pass(user.id, %{pass_name: "cross_week_keep", pass_type: "cross", occasions: 1})

    slot_date = Date.add(Date.utc_today(), 14)
    start_time = DateTime.new!(slot_date, ~T[18:00:00], "Etc/UTC")
    end_time = DateTime.add(start_time, 60 * 60, :second)
    insert_calendar_slot("cross", start_time, end_time)

    conn =
      conn
      |> init_test_session(%{user_id: user.id})
      |> post(~p"/foglalas/cross", %{
        "start_time" => DateTime.to_iso8601(start_time),
        "end_time" => DateTime.to_iso8601(end_time),
        "week" => "2"
      })

    assert redirected_to(conn) == ~p"/foglalas?type=cross&view=week&week=2"
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

  test "admin can delete draft slot before upload and stays on selected week", %{conn: conn} do
    admin =
      %User{
        email: "draft-delete-admin@example.com",
        password_hash: "hash",
        admin: true,
        email_confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }
      |> Repo.insert!()

    monday = Date.beginning_of_week(Date.utc_today(), :monday) |> Date.add(14)
    start_time = DateTime.new!(monday, ~T[10:00:00], "Etc/UTC")
    end_time = DateTime.new!(monday, ~T[11:00:00], "Etc/UTC")

    draft_slot = %CalendarSlot{slot_type: "personal", start_time: start_time, end_time: end_time}
    :ok = AdminDraftStore.add_slot(admin.id, :personal, draft_slot)
    draft_key = AdminDraftStore.slot_key(draft_slot)

    conn =
      conn
      |> init_test_session(%{user_id: admin.id})
      |> post(~p"/foglalas/admin/slot/delete", %{
        "admin_delete" => %{
          "type" => "personal",
          "slot_key" => draft_key,
          "draft_key" => draft_key,
          "week" => "2"
        }
      })

    assert redirected_to(conn) == ~p"/foglalas?type=personal&view=week&week=2"
    draft = Bookings.AdminDraftStore.list(admin.id, :personal)
    assert draft.adds == %{}
  end

  test "admin upload keeps selected week and persists draft slots", %{conn: conn} do
    admin =
      %User{
        email: "upload-week-admin@example.com",
        password_hash: "hash",
        admin: true,
        email_confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }
      |> Repo.insert!()

    monday = Date.beginning_of_week(Date.utc_today(), :monday) |> Date.add(14)
    start_time = DateTime.new!(monday, ~T[09:00:00], "Etc/UTC")
    end_time = DateTime.new!(monday, ~T[10:00:00], "Etc/UTC")

    draft_slot = %CalendarSlot{slot_type: "personal", start_time: start_time, end_time: end_time}
    :ok = AdminDraftStore.add_slot(admin.id, :personal, draft_slot)

    conn =
      conn
      |> init_test_session(%{user_id: admin.id})
      |> post(~p"/foglalas/admin/upload", %{
        "admin_upload" => %{
          "type" => "personal",
          "week" => "2"
        }
      })

    assert redirected_to(conn) == ~p"/admin/foglalas?week=2"

    assert Repo.get_by(CalendarSlot,
             slot_type: "personal",
             start_time: start_time,
             end_time: end_time
           )
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

    assert Phoenix.Flash.get(conn.assigns.flash, :error)
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

  test "admin foglalasok lists booked slots before open slots within a day", %{conn: conn} do
    admin =
      %User{
        email: "admin-day-order@example.com",
        password_hash: "hash",
        admin: true,
        email_confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }
      |> Repo.insert!()

    booked_user_a =
      %User{
        email: "booked-a-day-order@example.com",
        password_hash: "hash",
        name: "Booked A",
        email_confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }
      |> Repo.insert!()

    booked_user_b =
      %User{
        email: "booked-b-day-order@example.com",
        password_hash: "hash",
        name: "Booked B",
        email_confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }
      |> Repo.insert!()

    monday = Date.beginning_of_week(Date.utc_today(), :monday)

    start_booked_early = DateTime.new!(monday, ~T[09:00:00], "Etc/UTC")
    end_booked_early = DateTime.new!(monday, ~T[10:00:00], "Etc/UTC")
    start_open = DateTime.new!(monday, ~T[10:00:00], "Etc/UTC")
    end_open = DateTime.new!(monday, ~T[11:00:00], "Etc/UTC")
    start_booked_late = DateTime.new!(monday, ~T[11:00:00], "Etc/UTC")
    end_booked_late = DateTime.new!(monday, ~T[12:00:00], "Etc/UTC")

    insert_calendar_slot("personal", start_booked_early, end_booked_early)
    insert_calendar_slot("personal", start_open, end_open)
    insert_calendar_slot("personal", start_booked_late, end_booked_late)

    pass_a =
      insert_pass(booked_user_a.id, %{
        pass_name: "order_personal_a",
        pass_type: "personal",
        occasions: 1
      })

    pass_b =
      insert_pass(booked_user_b.id, %{
        pass_name: "order_personal_b",
        pass_type: "personal",
        occasions: 1
      })

    insert_personal_booking(
      booked_user_a.id,
      pass_a.pass_id,
      start_booked_early,
      end_booked_early
    )

    insert_personal_booking(booked_user_b.id, pass_b.pass_id, start_booked_late, end_booked_late)

    conn =
      conn
      |> init_test_session(%{user_id: admin.id})
      |> get(~p"/admin/foglalas?week=0")

    html = html_response(conn, 200)

    assert {early_idx, _} = :binary.match(html, "09:00 - 10:00")
    assert {late_idx, _} = :binary.match(html, "11:00 - 12:00")
    assert {open_idx, _} = :binary.match(html, "10:00 - 11:00")
    assert early_idx < late_idx
    assert late_idx < open_idx
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

    assert Phoenix.Flash.get(conn.assigns.flash, :error)
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
