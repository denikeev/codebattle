defmodule Codebattle.CodeCheck.Ruby.IntegrationTest do
  use Codebattle.IntegrationCase

  alias CodebattleWeb.GameChannel
  alias Codebattle.Game
  alias CodebattleWeb.UserSocket

  setup do
    user1 = insert(:user)
    user2 = insert(:user)
    task = insert(:task)
    socket1 = socket(UserSocket, "user_id", %{user_id: user1.id, current_user: user1})
    socket2 = socket(UserSocket, "user_id", %{user_id: user2.id, current_user: user2})
    game_params = %{state: "playing", players: [user1, user2], task: task}

    {:ok, %{game_params: game_params, socket1: socket1, socket2: socket2}}
  end

  @tag :code_check
  test "failure code, game playing", %{
    game_params: game_params,
    socket1: socket1,
    socket2: socket2
  } do
    {:ok, game} = Game.Context.create_game(game_params)
    game_topic = "game:" <> to_string(game.id)

    {:ok, _response, socket1} = subscribe_and_join(socket1, GameChannel, game_topic)
    {:ok, _response, _socket2} = subscribe_and_join(socket2, GameChannel, game_topic)
    Mix.Shell.Process.flush()

    Phoenix.ChannelTest.push(socket1, "check_result", %{
      lang_slug: "ruby",
      editor_text: "def solution(x,y); x - y; end"
    })

    assert_code_check()

    assert_receive %Phoenix.Socket.Broadcast{
      payload: %{check_result: check_result}
    }

    assert %Codebattle.CodeCheck.CheckResultV2{status: "failure", success_count: 0} = check_result

    game = Game.Context.get_game!(game.id)

    assert game.state == "playing"
  end

  @tag :code_check
  test "error code, game playing", %{game_params: game_params, socket1: socket1, socket2: socket2} do
    {:ok, game} = Game.Context.create_game(game_params)
    game_topic = "game:" <> to_string(game.id)

    {:ok, _response, socket1} = subscribe_and_join(socket1, GameChannel, game_topic)
    {:ok, _response, _socket2} = subscribe_and_join(socket2, GameChannel, game_topic)
    Mix.Shell.Process.flush()

    Phoenix.ChannelTest.push(socket1, "check_result", %{editor_text: "sdf", lang_slug: "ruby"})

    assert_code_check()

    assert_receive %Phoenix.Socket.Broadcast{
      payload: %{check_result: check_result}
    }

    assert %Codebattle.CodeCheck.CheckResultV2{status: "error", success_count: 0} = check_result

    game = Game.Context.get_game!(game.id)

    assert game.state == "playing"
  end

  @tag :code_check
  test "good code, player won", %{
    game_params: game_params,
    socket1: socket1,
    socket2: socket2
  } do
    {:ok, game} = Game.Context.create_game(game_params)
    game_topic = "game:" <> to_string(game.id)

    {:ok, _response, socket1} = subscribe_and_join(socket1, GameChannel, game_topic)
    {:ok, _response, _socket2} = subscribe_and_join(socket2, GameChannel, game_topic)
    Mix.Shell.Process.flush()

    Phoenix.ChannelTest.push(socket1, "editor:data", %{
      "editor_text" => "test",
      "lang_slug" => "js"
    })

    Phoenix.ChannelTest.push(socket1, "check_result", %{
      "editor_text" => "def solution(x,y); x + y; end",
      "lang_slug" => "ruby"
    })

    assert_code_check()

    assert_receive %Phoenix.Socket.Broadcast{
      payload: %{status: "game_over"}
    }

    game = Game.Context.get_game!(game.id)
    assert game.state == "game_over"
  end

  @tag :code_check
  test "test all data cases", %{
    game_params: game_params,
    socket1: socket1,
    socket2: socket2
  } do
    task = insert(:task_with_all_data_types)
    {:ok, game} = Game.Context.create_game(%{game_params | task: task})
    game_topic = "game:" <> to_string(game.id)

    {:ok, _response, socket1} = subscribe_and_join(socket1, GameChannel, game_topic)
    {:ok, _response, _socket2} = subscribe_and_join(socket2, GameChannel, game_topic)
    Mix.Shell.Process.flush()

    Phoenix.ChannelTest.push(socket1, "editor:data", %{editor_text: "test", lang_slug: "js"})

    Phoenix.ChannelTest.push(socket1, "check_result", %{
      editor_text: "def solution(a,b,c,d,e,f,g); ['asdf']; end",
      lang_slug: "ruby"
    })

    assert_code_check()

    assert_receive %Phoenix.Socket.Broadcast{payload: %{status: "game_over"}}

    game = Game.Context.get_game!(game.id)
    assert game.state == "game_over"
  end
end
