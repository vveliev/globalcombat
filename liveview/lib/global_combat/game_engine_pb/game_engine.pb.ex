defmodule GlobalCombat.GrpcHost.Command do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "GlobalCombat.GrpcHost.Command",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :None, 0
  field :Transfer, 1
  field :Attack, 2
end

defmodule GlobalCombat.GrpcHost.MapName do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "GlobalCombat.GrpcHost.MapName",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :Original, 0
  field :Elements, 1
end

defmodule GlobalCombat.GrpcHost.Area do
  @moduledoc false

  use Protobuf,
    full_name: "GlobalCombat.GrpcHost.Area",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :Number, 1, type: :int32
  field :Owner, 2, type: GlobalCombat.GrpcHost.Player
  field :Armies, 3, type: :int32
  field :AssignedArmies, 4, type: :int32
  field :Command, 5, type: GlobalCombat.GrpcHost.Command, enum: true
  field :Target, 6, type: GlobalCombat.GrpcHost.Area
  field :Amount, 7, type: :int32
end

defmodule GlobalCombat.GrpcHost.Game do
  @moduledoc false

  use Protobuf,
    full_name: "GlobalCombat.GrpcHost.Game",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :Id, 1, type: :int32
  field :GameName, 2, type: :string
  field :MapName, 3, type: GlobalCombat.GrpcHost.MapName, enum: true
  field :TurnLength, 4, type: :int32
  field :MaxPlayers, 5, type: :int32
  field :IsFogged, 6, type: :bool
  field :IsNonRandom, 7, type: :bool
  field :ReverseAttackOrder, 8, type: :bool
  field :MinimumArmies, 9, type: :int32
  field :Turn, 10, type: :int32
  field :PreviousTurnTime, 11, type: Bcl.DateTime
  field :LastTurnTime, 12, type: Bcl.DateTime
  field :Started, 13, type: :bool
  field :StartTime, 14, type: Bcl.DateTime
  field :Ended, 15, type: :bool
  field :EndTime, 16, type: Bcl.DateTime
  field :Areas, 17, repeated: true, type: GlobalCombat.GrpcHost.Area
  field :Players, 18, repeated: true, type: GlobalCombat.GrpcHost.Player
  field :IsPrivate, 20, type: :bool
  field :IsTraining, 21, type: :bool
  field :Invites, 22, repeated: true, type: GlobalCombat.GrpcHost.Invite
  field :TourneyId, 23, type: :int32
end

defmodule GlobalCombat.GrpcHost.Invite do
  @moduledoc false

  use Protobuf,
    full_name: "GlobalCombat.GrpcHost.Invite",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :AccountId, 1, type: :int32
  field :Name, 2, type: :string
end

defmodule GlobalCombat.GrpcHost.NewGameRequest do
  @moduledoc false

  use Protobuf,
    full_name: "GlobalCombat.GrpcHost.NewGameRequest",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :MapName, 1, type: GlobalCombat.GrpcHost.MapName, enum: true
  field :PlayerNames, 2, repeated: true, type: :string
end

defmodule GlobalCombat.GrpcHost.NewGameResponse do
  @moduledoc false

  use Protobuf,
    full_name: "GlobalCombat.GrpcHost.NewGameResponse",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :Game, 1, type: GlobalCombat.GrpcHost.Game
end

defmodule GlobalCombat.GrpcHost.Order do
  @moduledoc false

  use Protobuf,
    full_name: "GlobalCombat.GrpcHost.Order",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :SourceAreaNumber, 1, type: :int32
  field :TargetAreaNumber, 2, type: :int32
  field :Amount, 3, type: :int32
  field :Command, 4, type: GlobalCombat.GrpcHost.Command, enum: true
end

defmodule GlobalCombat.GrpcHost.Player do
  @moduledoc false

  use Protobuf,
    full_name: "GlobalCombat.GrpcHost.Player",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :AccountId, 1, type: :int32
  field :Number, 2, type: :int32
  field :Name, 3, type: :string
  field :Done, 4, type: :bool
  field :Areas, 6, type: :int32
  field :Armies, 7, type: :int32
  field :UnassignedArmies, 8, type: :int32
  field :Place, 9, type: :int32
  field :Score, 10, type: :double
  field :ScoreExpected, 11, type: :double
  field :Rating, 12, type: :int32
  field :RatingChange, 13, type: :int32
end

defmodule GlobalCombat.GrpcHost.ResolveTurnRequest do
  @moduledoc false

  use Protobuf,
    full_name: "GlobalCombat.GrpcHost.ResolveTurnRequest",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :Game, 1, type: GlobalCombat.GrpcHost.Game
  field :Orders, 2, repeated: true, type: GlobalCombat.GrpcHost.Order
end

defmodule GlobalCombat.GrpcHost.ResolveTurnResponse do
  @moduledoc false

  use Protobuf,
    full_name: "GlobalCombat.GrpcHost.ResolveTurnResponse",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :Game, 1, type: GlobalCombat.GrpcHost.Game
  field :TurnSummary, 2, type: :string
end

defmodule GlobalCombat.GrpcHost.GameEngine.Service do
  @moduledoc false

  use GRPC.Service, name: "GlobalCombat.GrpcHost.GameEngine", protoc_gen_elixir_version: "0.17.0"

  rpc(:NewGame, GlobalCombat.GrpcHost.NewGameRequest, GlobalCombat.GrpcHost.NewGameResponse)

  rpc(
    :ResolveTurn,
    GlobalCombat.GrpcHost.ResolveTurnRequest,
    GlobalCombat.GrpcHost.ResolveTurnResponse
  )
end

defmodule GlobalCombat.GrpcHost.GameEngine.Stub do
  @moduledoc false

  use GRPC.Stub, service: GlobalCombat.GrpcHost.GameEngine.Service
end
