# lib/podcast_mcp/rabbit_mq/publisher.ex
defmodule PodcastMcp.RabbitMQ.Publisher do
  @moduledoc """
  Handles publishing messages to RabbitMQ.
  """
  require Logger
  alias AMQP.{Connection, Channel, Exchange, Basic}

  # Fetches RabbitMQ configuration
  defp config, do: Application.get_env(:podcast_mcp, :rabbit_mq, [])

  @doc """
  Publishes a message to the configured RabbitMQ exchange.
  The message should be a JSON-encoded string.
  """
  def publish(message_payload, routing_key) do
    exchange_name = Keyword.get(config(), :exchange_name, "podcast_processing_exchange")
    rabbitmq_url = Keyword.get(config(), :url, "amqp://guest:guest@localhost:5672")

    case Connection.open(rabbitmq_url) do
      {:ok, conn} ->
        # Open a channel
        case Channel.open(conn) do
          {:ok, chan} ->
            # Declare the exchange (type: :direct is common for routing key based delivery)
            # durable: true means the exchange will survive server restarts
            # auto_delete: false means it won't be deleted when no longer in use
            Exchange.declare(chan, exchange_name, :direct, durable: true, auto_delete: false)

            # Publish the message
            # The message is published as a binary (JSON string)
            # persistent: true makes the message durable if the queue is also durable
            case Basic.publish(chan, exchange_name, routing_key, Jason.encode!(message_payload), persistent: true) do
              :ok ->
                Logger.info("Successfully published message to RabbitMQ. Routing key: #{routing_key}, Payload: #{inspect(message_payload)}")
                # Close the channel and connection
                Channel.close(chan)
                Connection.close(conn)
                {:ok, :message_published}
              {:error, reason_publish} ->
                Logger.error("Failed to publish message to RabbitMQ: #{inspect(reason_publish)}")
                Channel.close(chan)
                Connection.close(conn)
                {:error, {:publish_failed, reason_publish}}
            end
          {:error, reason_channel} ->
            Logger.error("Failed to open RabbitMQ channel: #{inspect(reason_channel)}")
            Connection.close(conn) # Ensure connection is closed if channel fails
            {:error, {:channel_open_failed, reason_channel}}
        end
      {:error, reason_conn} ->
        Logger.error("Failed to connect to RabbitMQ: #{inspect(reason_conn)}")
        {:error, {:connection_failed, reason_conn}}
    end
  end

  @doc """
  Publishes a job to transcribe an episode.
  """
  def enqueue_transcription_job(episode_id) do
    payload = %{episode_id: episode_id, task_type: "transcription"}
    routing_key = Keyword.get(config(), :transcription_routing_key, "episode.transcribe")
    publish(payload, routing_key)
  end
end
