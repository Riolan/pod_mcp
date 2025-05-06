defmodule PodcastMcp.Repo do
  use Ecto.Repo,
    otp_app: :podcast_mcp,
    adapter: Ecto.Adapters.Postgres
end
