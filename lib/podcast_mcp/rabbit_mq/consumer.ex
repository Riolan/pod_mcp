# lib/podcast_mcp/rabbit_mq/consumer.ex
defmodule PodcastMcp.RabbitMQ.Consumer do
  use GenServer
  require Logger
  alias AMQP.{Connection, Channel, Queue, Basic, Exchange}

  alias PodcastMcp.Podcasts # Your Ecto context
  alias PodcastMcp.Podcasts.Episode # Your Episode schema

  # Client (GenServer) API
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  # GenServer Callbacks
  @impl true
  def init(_opts) do # opts is passed from start_link
    Logger.info("[RabbitMQ Consumer] Starting...")
    rabbitmq_config = Application.get_env(:podcast_mcp, :rabbit_mq, [])
    rabbitmq_url = Keyword.get(rabbitmq_config, :url, "amqp://guest:guest@localhost:5672")
    exchange_name = Keyword.get(rabbitmq_config, :exchange_name, "podcast_processing_exchange")
    queue_name = Keyword.get(rabbitmq_config, :transcription_queue_name, "transcription_tasks_queue")
    routing_key = Keyword.get(rabbitmq_config, :transcription_routing_key, "episode.transcribe")

    state = %{
      conn: nil, # Will hold the AMQP connection
      chan: nil, # Will hold the AMQP channel
      consumer_tag: nil,
      rabbitmq_url: rabbitmq_url,
      exchange_name: exchange_name,
      queue_name: queue_name,
      routing_key: routing_key
    }
    # Asynchronously attempt to connect and start consuming
    send(self(), :connect_and_consume)
    {:ok, state}
  end

  @impl true
  def handle_info(:connect_and_consume, state) do
    # Attempt to close existing resources before reconnecting, if any
    if state.chan, do: Channel.close(state.chan) |> ignore_error()
    if state.conn, do: Connection.close(state.conn) |> ignore_error()

    case connect_and_setup_consumer(state.rabbitmq_url, state.exchange_name, state.queue_name, state.routing_key) do
      {:ok, new_conn, new_chan, new_consumer_tag} ->
        Logger.info("[RabbitMQ Consumer] Connected and consuming from queue '#{state.queue_name}'.")
        new_state = %{state | conn: new_conn, chan: new_chan, consumer_tag: new_consumer_tag}
        {:noreply, new_state}
      {:error, reason} ->
        Logger.error("[RabbitMQ Consumer] Failed to connect/setup: #{inspect(reason)}. Retrying in 10s.")
        Process.send_after(self(), :connect_and_consume, 10_000) # 10 seconds
        # Keep old state, but ensure conn/chan are nil if connection failed
        {:noreply, %{state | conn: nil, chan: nil, consumer_tag: nil}}
    end
  end

  @impl true
  def handle_info({:basic_deliver, payload, meta}, state) do
    delivery_tag = meta.delivery_tag
    Logger.info(~s([RabbitMQ Consumer] Received message. Delivery Tag: #{delivery_tag}, Payload: "#{payload}"))

    try do
      message_data = Jason.decode!(payload)
      Logger.info("[RabbitMQ Consumer] Decoded message data: #{inspect(message_data)}")

      process_transcription_task(message_data) # Call specific processing function

      # Acknowledge message success
      Basic.ack(state.chan, delivery_tag)
      Logger.info("[RabbitMQ Consumer] ACKed message with delivery_tag: #{delivery_tag}")
    rescue
      e in Jason.DecodeError ->
        Logger.error("[RabbitMQ Consumer] Failed to decode JSON: #{inspect(e)}. Payload: #{inspect(payload)}")
        Basic.reject(state.chan, delivery_tag, requeue: false) # Don't requeue unparseable messages
        Logger.error("[RabbitMQ Consumer] REJECTED (no requeue) unparseable message: #{delivery_tag}")
      e ->
        # Catch any other error during process_transcription_task
        # CORRECTED: Use __STACKTRACE__ to get the stacktrace
        Logger.error("[RabbitMQ Consumer] Error processing message: #{inspect(e)}. Stacktrace: #{inspect(__STACKTRACE__)} Payload: #{inspect(payload)}")
        # Decide on requeue strategy. For now, don't requeue to avoid poison messages.
        Basic.nack(state.chan, delivery_tag, requeue: false)
        Logger.error("[RabbitMQ Consumer] NACKed (no requeue) message: #{delivery_tag} due to processing error.")
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:basic_cancel, %{consumer_tag: consumer_tag}}, state) do
    Logger.warn("[RabbitMQ Consumer] Consumer with tag #{consumer_tag} was cancelled by server. Attempting to reconnect.")
    send(self(), :connect_and_consume) # Attempt to reconnect
    {:noreply, %{state | chan: nil, consumer_tag: nil, conn: state.conn}} # Keep conn for explicit close later if needed
  end

  @impl true
  def handle_info(_msg, state) do
    # Handles {:basic_consume_ok, ...} and other unexpected messages
    # Logger.debug("[RabbitMQ Consumer] Received unhandled message: #{inspect(_msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("[RabbitMQ Consumer] Terminating. Reason: #{inspect(reason)}")
    if state.chan, do: Channel.close(state.chan) |> ignore_error()
    if state.conn, do: Connection.close(state.conn) |> ignore_error()
    :ok
  end

  # --- Message Processing Logic (Mock Transcription) ---
  # You mentioned changing this to use get_episode! and a case statement.
  # If get_episode! is used and it raises Ecto.NoResultsError,
  # it will be caught by the `rescue e ->` block in handle_info/2.
  # If you prefer to handle "not found" explicitly here, use Podcasts.get_episode/1.
    defp process_transcription_task(%{"episode_id" => episode_id, "task_type" => "transcription"}) do
    Logger.info("[Worker] Processing transcription task for episode_id: #{episode_id}")
    case Podcasts.get_episode(episode_id) do
      nil ->
        Logger.error("[Worker] Episode with ID #{episode_id} not found. Cannot process.")
      %Episode{} = episode ->
        Logger.info("[Worker] Found episode: '#{episode.title}'. Original audio: #{episode.original_audio_url}")
        case Podcasts.update_episode(episode, %{processing_status: "transcribing_mock"}) do
          {:ok, episode_state_transcribing} ->
            Logger.info("[Worker] Episode ID #{episode.id} status updated to 'transcribing_mock'.")
            Logger.info("[Worker] Simulating transcription for episode ID: #{episode.id}...")
            Process.sleep(2000) # Simulate work

            # --- MODIFIED: Construct an HTTP(S) URL for the mock transcript ---
            minio_scheme = System.get_env("MINIO_SCHEME") || "http"
            minio_host = System.get_env("MINIO_HOST") || "localhost"
            minio_port = System.get_env("MINIO_PORT") || "9000" # API port
            bucket_name = System.get_env("MINIO_BUCKET") || "podcast-episodes"
            # This mock transcript won't actually exist in MinIO yet, but the URL will be HTTP.
            mock_transcript_object_key = "transcripts/#{episode.id}/mock_transcript_#{Ecto.UUID.generate()}.txt"
            mock_transcript_url = "#{minio_scheme}://#{minio_host}:#{minio_port}/#{bucket_name}/#{mock_transcript_object_key}"
            # --- END MODIFICATION ---

            attrs_after_mock_transcription = %{
              processing_status: "transcribed_mock",
              transcript_url: mock_transcript_url
            }
            case Podcasts.update_episode(episode_state_transcribing, attrs_after_mock_transcription) do
              {:ok, final_episode_state} ->
                Logger.info("[Worker] Mock transcription complete for episode ID: #{final_episode_state.id}. Transcript URL: #{final_episode_state.transcript_url}")
              {:error, changeset} ->
                Logger.error("[Worker] Failed to update episode ID #{episode.id} after mock transcription: #{inspect(changeset.errors)}")
            end
          {:error, changeset} ->
            Logger.error("[Worker] Failed to update episode ID #{episode.id} status to 'transcribing_mock': #{inspect(changeset.errors)}")
        end
    end
  end

  defp process_transcription_task(unknown_message) do
    Logger.warn("[Worker] Received unknown message format for processing: #{inspect(unknown_message)}")
  end

  # --- Helper Functions for RabbitMQ Connection Setup ---
  defp connect_and_setup_consumer(rabbitmq_url, exchange_name, queue_name, routing_key) do
    with {:ok, conn} <- Connection.open(rabbitmq_url),
         {:ok, chan} <- Channel.open(conn) do
      :ok = Exchange.declare(chan, exchange_name, :direct, durable: true, auto_delete: false)
      {:ok, %{queue: _declared_queue_name}} = Queue.declare(chan, queue_name, durable: true, auto_delete: false)
      :ok = Queue.bind(chan, queue_name, exchange_name, routing_key: routing_key)
      {:ok, consumer_tag} = Basic.consume(chan, queue_name, self(), no_ack: false)
      {:ok, conn, chan, consumer_tag}
    else
      {:error, reason} = error_tuple ->
        Logger.error("[RabbitMQ Consumer] Error in connection/setup pipeline: #{inspect(reason)}")
        error_tuple
    end
  end

  defp ignore_error({:error, _reason}), do: :ok
  defp ignore_error(:ok), do: :ok
end
