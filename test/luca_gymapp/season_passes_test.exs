defmodule LucaGymapp.SeasonPassesTest do
  use LucaGymapp.DataCase, async: true

  alias LucaGymapp.Accounts
  alias LucaGymapp.SeasonPasses
  alias LucaGymapp.Repo
  alias LucaGymapp.SeasonPasses.SeasonPass

  test "cannot buy two active cross passes" do
    user = create_user()

    assert {:ok, _pass} = SeasonPasses.purchase_season_pass(user, "cross_8_alkalmas_berlet")

    assert {:error, :active_pass_exists} =
             SeasonPasses.purchase_season_pass(user, "cross_12_alkalmas_berlet")
  end

  test "cannot buy two active personal passes" do
    user = create_user()

    assert {:ok, _pass} = SeasonPasses.purchase_season_pass(user, "10_alkalmas_berlet")

    assert {:error, :active_pass_exists} =
             SeasonPasses.purchase_season_pass(user, "1_alkalmas_jegy")
  end

  test "can buy one cross and one personal pass together" do
    user = create_user()

    assert {:ok, _cross_pass} = SeasonPasses.purchase_season_pass(user, "cross_8_alkalmas_berlet")
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

    assert {:ok, pass} = SeasonPasses.purchase_season_pass(user, "cross_8_alkalmas_berlet")
    pass = update_pass(pass, %{occasions: 0})

    assert pass.occasions == 0
    assert {:ok, _new_pass} = SeasonPasses.purchase_season_pass(user, "cross_12_alkalmas_berlet")
  end

  test "can buy a new cross pass when the old one is expired" do
    user = create_user()

    assert {:ok, pass} = SeasonPasses.purchase_season_pass(user, "cross_8_alkalmas_berlet")
    yesterday = Date.add(Date.utc_today(), -1)
    pass = update_pass(pass, %{expiry_date: yesterday})

    assert pass.expiry_date == yesterday
    assert {:ok, _new_pass} = SeasonPasses.purchase_season_pass(user, "cross_12_alkalmas_berlet")
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
end
