# Data & Persistence

Every generated Dala app ships with Ecto and SQLite for structured data persistence.

| | Ecto Repo |
|---|---|
| Backed by | SQLite3 via `ecto_sqlite3` |
| Best for | User records, structured data |
| API | Schemas, queries, migrations |
| Setup | `mix ecto.migrate` |
| Capacity | Millions of rows |

## Ecto — structured data

Every generated app includes [Ecto](https://hexdocs.pm/ecto) and [ecto_sqlite3](https://hexdocs.pm/ecto_sqlite3), giving you the full Ecto experience on-device backed by SQLite. If you have used Ecto with PostgreSQL in Phoenix, the API is identical for day-to-day use.

Your app's Repo is generated at `lib/my_app/repo.ex`. It is started in the generated `on_start/0` and reads `dala_DATA_DIR` (set by the native launcher) to place the database file in the platform's correct persistent storage directory — `getFilesDir()` on Android, `NSDocumentDirectory` on iOS.

### Defining a schema

```elixir
defmodule MyApp.Note do
  use Ecto.Schema
  import Ecto.Changeset

  schema "notes" do
    field :title,   :string
    field :body,    :string
    field :pinned,  :boolean, default: false
    timestamps()
  end

  def changeset(note, attrs) do
    note
    |> cast(attrs, [:title, :body, :pinned])
    |> validate_required([:title])
  end
end
```

### Writing migrations

```bash
mix ecto.gen.migration create_notes
```

```elixir
# priv/repo/migrations/20260422000000_create_notes.exs
defmodule MyApp.Repo.Migrations.CreateNotes do
  use Ecto.Migration

  def change do
    create table(:notes) do
      add :title,  :string,  null: false
      add :body,   :text
      add :pinned, :boolean, default: false
      timestamps()
    end
  end
end
```

```bash
mix ecto.migrate
```

### Querying from a screen

```elixir
import Ecto.Query

def mount(_params, _session, socket) do
  notes = MyApp.Repo.all(from n in MyApp.Note, order_by: [desc: n.inserted_at])
  {:ok, Dala.Socket.assign(socket, :notes, notes)}
end

def handle_event(:pin, _params, socket) do
  note = hd(socket.assigns.notes)
  {:ok, _} = MyApp.Repo.update(MyApp.Note.changeset(note, %{pinned: true}))
  {:noreply, socket}
end
```

### SQLite differences from PostgreSQL

For most queries you will notice nothing different. A few things to be aware of:

- **`pool_size: 1`** — SQLite supports only one writer at a time. The Repo is pre-configured with a single connection; no tuning needed.
- **Limited `ALTER TABLE`** — SQLite cannot drop or rename columns in older versions. Write migrations that add columns or recreate tables instead.
- **No arrays or JSONB indexes** — use `string` fields with `Jason` encode/decode if you need nested data, or normalise into a separate table.
- **UUIDs stored as binary** — use `:binary_id` primary keys as normal; the adapter handles encoding transparently.

For a full reference see the [ecto_sqlite3 documentation](https://hexdocs.pm/ecto_sqlite3) and the [Ecto query API](https://hexdocs.pm/ecto/Ecto.Query.html).

## Running migrations on-device

The generated `on_start/0` starts the Repo but does not auto-run migrations. For most apps, running `mix ecto.migrate` in dev is sufficient — ship a database schema that matches what the app expects. If your app needs to migrate an existing on-device database (e.g. after an app store update), add a migration step before the Repo starts:

```elixir
def on_start do
  Application.ensure_all_started(:ecto_sqlite3)
  {:ok, _} = MyApp.Repo.start_link()
  Ecto.Migrator.with_repo(MyApp.Repo, &Ecto.Migrator.run(&1, :up, all: true))
  Dala.Screen.Screen.start_root(MyApp.HomeScreen)
end
```

For small amounts of app state that should survive restarts, store it in your app's supervision tree or use `:dets` / `:ets` directly.

The migration modules are compiled into your app's `.beam` files and copied to the device by the build scripts, so `Ecto.Migrator` finds them at the correct path via `:code.priv_dir/1`.