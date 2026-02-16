defmodule LucaGymapp.SeasonPassesTest do
  use LucaGymapp.DataCase, async: true

  alias LucaGymapp.Accounts
  alias LucaGymapp.SeasonPasses
  alias LucaGymapp.Repo
  alias LucaGymapp.SeasonPasses.SeasonPass

  test "cannot buy two active cross passes" do
    user = create_user()

    assert {:ok, _pass} = SeasonPasses.purchase_season_pass(user, "cross_1_alkalmas_jegy")

    assert {:error, :active_pass_exists} =
             SeasonPasses.purchase_season_pass(user, "cross_10_alkalmas_berlet")
  end

  test "cannot buy two active personal passes" do
    user = create_user()

    assert {:ok, _pass} = SeasonPasses.purchase_season_pass(user, "10_alkalmas_berlet")

    assert {:error, :active_pass_exists} =
             SeasonPasses.purchase_season_pass(user, "1_alkalmas_jegy")
  end

  test "cannot buy the same personal pass type when one is already active" do
    user = create_user()

    assert {:ok, _pass} = SeasonPasses.purchase_season_pass(user, "10_alkalmas_berlet")

    assert {:error, :active_pass_exists} =
             SeasonPasses.purchase_season_pass(user, "10_alkalmas_berlet")
  end

  test "cannot buy cross pass when active cross exists with legacy pass_type" do
    user = create_user()

    _legacy_pass =
      create_pass(user, %{
        pass_name: "cross_1_alkalmas_jegy",
        pass_type: "cross_1_alkalmas_jegy",
        occasions: 8,
        purchase_price: 27_000,
        expiry_date: Date.add(Date.utc_today(), 30)
      })

    assert {:error, :active_pass_exists} =
             SeasonPasses.purchase_season_pass(user, "cross_10_alkalmas_berlet")
  end

  test "can buy one cross and one personal pass together" do
    user = create_user()

    assert {:ok, _cross_pass} = SeasonPasses.purchase_season_pass(user, "cross_1_alkalmas_jegy")
    assert {:ok, _personal_pass} = SeasonPasses.purchase_season_pass(user, "10_alkalmas_berlet")
  end

  test "can buy a new personal pass when the old one has 0 occasions" do
    user = create_user()

    assert {:ok, pass} = SeasonPasses.purchase_season_pass(user, "10_alkalmas_berlet")
    pass = update_pass(pass, %{occasions: 0})

    assert pass.occasions == 0
    assert {:ok, _new_pass} = SeasonPasses.purchase_season_pass(user, "1_alkalmas_jegy")
  end

  test "can buy a new personal pass when the old one is expired" do
    user = create_user()

    assert {:ok, pass} = SeasonPasses.purchase_season_pass(user, "10_alkalmas_berlet")
    yesterday = Date.add(Date.utc_today(), -1)
    pass = update_pass(pass, %{expiry_date: yesterday})

    assert pass.expiry_date == yesterday
    assert {:ok, _new_pass} = SeasonPasses.purchase_season_pass(user, "1_alkalmas_jegy")
  end

  test "can buy a new cross pass when the old one has 0 occasions" do
    user = create_user()

    assert {:ok, pass} = SeasonPasses.purchase_season_pass(user, "cross_1_alkalmas_jegy")
    pass = update_pass(pass, %{occasions: 0})

    assert pass.occasions == 0
    assert {:ok, _new_pass} = SeasonPasses.purchase_season_pass(user, "cross_10_alkalmas_berlet")
  end

  test "can buy a new cross pass when the old one is expired" do
    user = create_user()

    assert {:ok, pass} = SeasonPasses.purchase_season_pass(user, "cross_1_alkalmas_jegy")
    yesterday = Date.add(Date.utc_today(), -1)
    pass = update_pass(pass, %{expiry_date: yesterday})

    assert pass.expiry_date == yesterday
    assert {:ok, _new_pass} = SeasonPasses.purchase_season_pass(user, "cross_10_alkalmas_berlet")
  end

  test "once-per-user passes cannot be purchased twice even after expiry" do
    user = create_user()

    assert {:ok, pass} = SeasonPasses.purchase_season_pass(user, "5_alkalmas_kezdo")
    yesterday = Date.add(Date.utc_today(), -1)
    _pass = update_pass(pass, %{expiry_date: yesterday, occasions: 0})

    assert {:error, :once_per_user} =
             SeasonPasses.purchase_season_pass(user, "5_alkalmas_kezdo")
  end

  test "display_name returns accented Hungarian labels" do
    assert SeasonPasses.display_name("10_alkalmas_berlet") == "10 alkalmas bérlet"
    assert SeasonPasses.display_name("cross_8_alkalmas_berlet") == "Cross 8 alkalmas bérlet"
    assert SeasonPasses.display_name("1_honapos_etrend") == "1 hónapos étrend"
    assert SeasonPasses.display_name("egyedi_berlet") == "Egyedi bérlet"
  end

  defp create_user do
    email = "test-user-#{System.unique_integer([:positive])}@example.com"
    {:ok, user} = Accounts.create_user(%{email: email, name: "Test User"})
    user
  end

  defp update_pass(%SeasonPass{} = pass, attrs) do
    pass
    |> Ecto.Changeset.change(attrs)
    |> Repo.update!()
  end

  defp create_pass(user, attrs) do
    defaults = %{
      pass_id: Ecto.UUID.generate(),
      pass_name: "10_alkalmas_berlet",
      pass_type: "personal",
      payment_method: "cash",
      occasions: 10,
      purchase_timestamp: DateTime.utc_now() |> DateTime.truncate(:second),
      purchase_price: 45_000,
      expiry_date: Date.add(Date.utc_today(), 30),
      user_id: user.id
    }

    %SeasonPass{}
    |> Ecto.Changeset.change(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end
end
