defmodule Bcl.TimeSpan.TimeSpanScale do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "bcl.TimeSpan.TimeSpanScale",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :DAYS, 0
  field :HOURS, 1
  field :MINUTES, 2
  field :SECONDS, 3
  field :MILLISECONDS, 4
  field :TICKS, 5
  field :MINMAX, 15
end

defmodule Bcl.DateTime.TimeSpanScale do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "bcl.DateTime.TimeSpanScale",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :DAYS, 0
  field :HOURS, 1
  field :MINUTES, 2
  field :SECONDS, 3
  field :MILLISECONDS, 4
  field :TICKS, 5
  field :MINMAX, 15
end

defmodule Bcl.DateTime.DateTimeKind do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "bcl.DateTime.DateTimeKind",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :UNSPECIFIED, 0
  field :UTC, 1
  field :LOCAL, 2
end

defmodule Bcl.TimeSpan do
  @moduledoc false

  use Protobuf, full_name: "bcl.TimeSpan", protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  field :value, 1, type: :sint64
  field :scale, 2, type: Bcl.TimeSpan.TimeSpanScale, enum: true
end

defmodule Bcl.DateTime do
  @moduledoc false

  use Protobuf, full_name: "bcl.DateTime", protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  field :value, 1, type: :sint64
  field :scale, 2, type: Bcl.DateTime.TimeSpanScale, enum: true
  field :kind, 3, type: Bcl.DateTime.DateTimeKind, enum: true
end

defmodule Bcl.NetObjectProxy do
  @moduledoc false

  use Protobuf,
    full_name: "bcl.NetObjectProxy",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field :existingObjectKey, 1, type: :int32
  field :newObjectKey, 2, type: :int32
  field :existingTypeKey, 3, type: :int32
  field :newTypeKey, 4, type: :int32
  field :typeName, 8, type: :string
  field :payload, 10, type: :bytes
end

defmodule Bcl.Guid do
  @moduledoc false

  use Protobuf, full_name: "bcl.Guid", protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  field :lo, 1, type: :fixed64
  field :hi, 2, type: :fixed64
end

defmodule Bcl.Decimal do
  @moduledoc false

  use Protobuf, full_name: "bcl.Decimal", protoc_gen_elixir_version: "0.17.0", syntax: :proto3

  field :lo, 1, type: :uint64
  field :hi, 2, type: :uint32
  field :signScale, 3, type: :uint32
end
