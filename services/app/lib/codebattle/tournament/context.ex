defmodule Codebattle.Tournament.Context do
  alias Codebattle.Tournament

  import Ecto.Query

  @states_from_restore ["upcoming", "waiting_participants"]

  def get(id) do
    case Tournament.Server.get_tournament(id) do
      nil -> get_from_db(id)
      tournament -> {:ok, tournament}
    end
  end

  def get!(id) do
    case Tournament.Server.get_tournament(id) do
      nil -> get_from_db!(id)
      tournament -> tournament
    end
  end

  def get_from_db!(id) do
    tournament = Codebattle.Repo.get!(Tournament, id)
    add_module(tournament)
  end

  def get_from_db(id) do
    q =
      from(
        t in Tournament,
        where: t.id == ^id,
        preload: :creator
      )

    case Codebattle.Repo.one(q) do
      nil -> {:error, :not_found}
      t -> {:ok, add_module(t)}
    end
  end

  def list_live_and_finished() do
    get_live_tournaments() ++ get_db_tournaments(["finished"])
  end

  def get_db_tournaments(states) do
    from(
      t in Tournament,
      order_by: [desc: t.id],
      where: t.state in ^states,
      limit: 10,
      preload: :creator
    )
    |> Codebattle.Repo.all()
  end

  def get_live_tournaments do
    Tournament.GlobalSupervisor
    |> Supervisor.which_children()
    |> Enum.map(fn {id, _, _, _} -> id end)
    |> Enum.map(fn id -> Tournament.Server.get_tournament(id) end)
    |> Enum.filter(&Function.identity/1)
    |> Enum.filter(fn tournament ->
      tournament.state in ["upcoming", "waiting_participants", "active"]
    end)
  end

  def get_live_tournaments_count do
    get_live_tournaments() |> Enum.count()
  end

  def validate(params) do
    %Tournament{}
    |> Tournament.changeset(params)
    |> Map.put(:action, :insert)
  end

  def create(params) do
    starts_at = NaiveDateTime.from_iso8601!(params["starts_at"] <> ":00")
    match_timeout_seconds = params["match_timeout_seconds"] || "180"

    state =
      case params["is_upcoming"] do
        "true" -> "upcoming"
        _ -> "waiting_participants"
      end

    meta =
      case params["type"] do
        "team" ->
          team_1_name = Utils.presence(params["team_1_name"]) || "Backend"
          team_2_name = Utils.presence(params["team_2_name"]) || "Frontend"

          %{
            teams: [
              %{id: 0, title: team_1_name},
              %{id: 1, title: team_2_name}
            ]
          }

        _ ->
          %{}
      end

    result =
      %Tournament{}
      |> Tournament.changeset(
        Map.merge(params, %{
          "alive_count" => get_live_tournaments_count(),
          "match_timeout_seconds" => match_timeout_seconds,
          "starts_at" => starts_at,
          "state" => state,
          "step" => 0,
          "meta" => meta,
          "data" => %{}
        })
      )
      |> Codebattle.Repo.insert()

    case result do
      {:ok, tournament} ->
        {:ok, _pid} =
          tournament
          |> add_module
          |> mark_as_live
          |> Tournament.GlobalSupervisor.start_tournament()

        {:ok, tournament}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def get_tournament_for_restore() do
    @states_from_restore
    |> get_db_tournaments()
    |> Enum.map(fn tournament ->
      tournament
      |> add_module
      |> mark_as_live
    end)
  end

  defp get_module(%{type: "team"}), do: Tournament.Team
  defp get_module(%{"type" => "team"}), do: Tournament.Team
  defp get_module(_), do: Tournament.Individual

  defp add_module(tournament), do: Map.put(tournament, :module, get_module(tournament))

  defp mark_as_live(tournament), do: Map.put(tournament, :is_live, true)
end
