# lib/podcast_mcp/rabbit_mq/consumer.ex
defmodule PodcastMcp.RabbitMQ.Consumer do
  use GenServer
  require Logger
  alias AMQP.{Connection, Channel, Queue, Basic, Exchange}

  alias PodcastMcp.Podcasts
  alias PodcastMcp.Podcasts.Episode
  alias ExAws.S3 # For downloading audio and uploading transcript
  alias MIME     # For content type when uploading transcript

  # Finch is started in application.ex as PodcastMcp.Finch

  # Client (GenServer) API
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  # GenServer Callbacks
  @impl true
  def init(_opts) do
    Logger.info("[RabbitMQ Consumer] Starting...")
    rabbitmq_config = Application.get_env(:podcast_mcp, :rabbit_mq, [])
    rabbitmq_url = Keyword.get(rabbitmq_config, :url, "amqp://guest:guest@localhost:5672")
    exchange_name = Keyword.get(rabbitmq_config, :exchange_name, "podcast_processing_exchange")
    queue_name = Keyword.get(rabbitmq_config, :transcription_queue_name, "transcription_tasks_queue")
    routing_key = Keyword.get(rabbitmq_config, :transcription_routing_key, "episode.transcribe")

    state = %{
      conn: nil,
      chan: nil,
      consumer_tag: nil,
      rabbitmq_url: rabbitmq_url,
      exchange_name: exchange_name,
      queue_name: queue_name,
      routing_key: routing_key
    }
    send(self(), :connect_and_consume)
    {:ok, state}
  end

  @impl true
  def handle_info(:connect_and_consume, state) do
    if state.chan, do: Channel.close(state.chan) |> ignore_error()
    if state.conn, do: Connection.close(state.conn) |> ignore_error()

    case connect_and_setup_consumer(state.rabbitmq_url, state.exchange_name, state.queue_name, state.routing_key) do
      {:ok, new_conn, new_chan, new_consumer_tag} ->
        Logger.info("[RabbitMQ Consumer] Connected and consuming from queue '#{state.queue_name}'.")
        new_state = %{state | conn: new_conn, chan: new_chan, consumer_tag: new_consumer_tag}
        {:noreply, new_state}
      {:error, reason} ->
        Logger.error("[RabbitMQ Consumer] Failed to connect/setup: #{inspect(reason)}. Retrying in 10s.")
        Process.send_after(self(), :connect_and_consume, 10_000)
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
      process_message(message_data) # Main processing logic
      Basic.ack(state.chan, delivery_tag)
      Logger.info("[RabbitMQ Consumer] ACKed message with delivery_tag: #{delivery_tag}")
    rescue
      e in Jason.DecodeError ->
        Logger.error("[RabbitMQ Consumer] Failed to decode JSON: #{inspect(e)}. Payload: #{inspect(payload)}")
        Basic.reject(state.chan, delivery_tag, requeue: false)
        Logger.error("[RabbitMQ Consumer] REJECTED (no requeue) unparseable message: #{delivery_tag}")
      e ->
        Logger.error("[RabbitMQ Consumer] Error processing message: #{inspect(e)}. Stacktrace: #{inspect(__STACKTRACE__)} Payload: #{inspect(payload)}")
        Basic.nack(state.chan, delivery_tag, requeue: false) # Consider your requeue strategy
        Logger.error("[RabbitMQ Consumer] NACKed (no requeue) message: #{delivery_tag} due to processing error.")
    end
    {:noreply, state}
  end

  @impl true
  def handle_info({:basic_cancel, %{consumer_tag: consumer_tag}}, state) do
    Logger.warn("[RabbitMQ Consumer] Consumer with tag #{consumer_tag} was cancelled by server. Attempting to reconnect.")
    send(self(), :connect_and_consume)
    {:noreply, %{state | chan: nil, consumer_tag: nil, conn: state.conn}}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("[RabbitMQ Consumer] Terminating. Reason: #{inspect(reason)}")
    if state.chan, do: Channel.close(state.chan) |> ignore_error()
    if state.conn, do: Connection.close(state.conn) |> ignore_error()
    :ok
  end

  # --- Message Processing Logic ---
  defp process_message(%{"episode_id" => episode_id, "task_type" => "transcription"}) do
    Logger.info("[Worker] Processing transcription task for episode_id: #{episode_id}")

    case Podcasts.get_episode(episode_id) do
      nil ->
        Logger.error("[Worker] Episode with ID #{episode_id} not found. Cannot process transcription.")
      %Episode{} = episode ->
        Logger.info("[Worker] Found episode: #{episode.title}. Original audio URL: #{episode.original_audio_url}")
        case Podcasts.update_episode(episode, %{processing_status: "transcribing"}) do
          {:ok, episode_transcribing_state} ->
            Logger.info("[Worker] Episode ID #{episode.id} status updated to 'transcribing'.")
            transcribe_audio_and_update_db(episode_transcribing_state) # Actual workflow
          {:error, changeset} ->
            Logger.error("[Worker] Failed to update episode ID #{episode.id} status to 'transcribing': #{inspect(changeset.errors)}")
        end
    end
  end
  defp process_message(unknown_message) do
    Logger.warn("[Worker] Received unknown message format for processing: #{inspect(unknown_message)}")
  end

  # --- Audio Transcription Workflow ---
  defp transcribe_audio_and_update_db(%Episode{} = episode) do
    temp_audio_extension = Path.extname(episode.original_audio_url || ".tmp")
    temp_audio_filename = "podcast_mcp_audio_#{episode.id}_#{Ecto.UUID.generate()}#{temp_audio_extension}"
    temp_audio_path = Path.join(System.tmp_dir!(), temp_audio_filename)

    try do
      with {:ok, _downloaded_path} <- download_from_minio(episode.original_audio_url, temp_audio_path),
           {:ok, whisper_response_json} <- call_whisper_service(temp_audio_path),
           {:ok, transcript_text} <- extract_transcript_from_response(whisper_response_json),
           {:ok, transcript_minio_url} <- save_transcript_to_minio(transcript_text, episode),
           {:ok, _final_episode_state} <- update_episode_after_transcription(episode, transcript_minio_url, "transcribed")
      do
        Logger.info("[Worker] Successfully transcribed and processed episode ID: #{episode.id}. Transcript at: #{transcript_minio_url}")
      else
        {:error, :minio_download_failed, reason} ->
          Logger.error("[Worker] Failed to download audio from MinIO for episode #{episode.id}: #{inspect(reason)}")
          update_episode_after_transcription(episode, nil, "transcription_failed_download")
        {:error, :whisper_call_failed, reason} ->
          Logger.error("[Worker] Whisper service call failed for episode #{episode.id}: #{inspect(reason)}")
          update_episode_after_transcription(episode, nil, "transcription_failed_whisper")
        {:error, :transcript_extraction_failed, raw_response} ->
          Logger.error("[Worker] Failed to extract transcript text from Whisper response for episode #{episode.id}. Response: #{inspect(raw_response)}")
          update_episode_after_transcription(episode, nil, "transcription_failed_parsing")
        {:error, :minio_transcript_upload_failed, reason} ->
          Logger.error("[Worker] Failed to upload transcript to MinIO for episode #{episode.id}: #{inspect(reason)}")
          update_episode_after_transcription(episode, nil, "transcription_failed_transcript_upload")
        {:error, :db_update_failed, changeset_errors} ->
          Logger.error("[Worker] Failed to update episode after transcription for episode #{episode.id}: #{inspect(changeset_errors)}")
        _other_error_tuple ->
          Logger.error("[Worker] An unknown error occurred during transcription workflow for episode #{episode.id}: #{inspect(_other_error_tuple)}")
          update_episode_after_transcription(episode, nil, "transcription_failed_unknown")
      end
    after
      Logger.debug("[Worker] Cleaning up temporary audio file (if exists): #{temp_audio_path}")
      if File.exists?(temp_audio_path), do: File.rm(temp_audio_path)
    end
  end

defp download_from_minio(minio_url, local_path) when is_binary(minio_url) and is_binary(local_path) do
  Logger.info("[Worker] Downloading audio from #{minio_url} to #{local_path}...")
  try do
    uri = URI.parse(minio_url)
    path_parts = String.split(uri.path, "/", trim: true)

    case path_parts do
      [bucket | object_key_parts] when bucket != "" ->
        object_key = Enum.join(object_key_parts, "/")
        Logger.info("[Worker] Parsed for MinIO download - Bucket: '#{bucket}', Key: '#{object_key}'")

        # Correct approach - get the object and write the response to a file
        operation = ExAws.S3.get_object(bucket, object_key)
        case ExAws.request(operation) do
          {:ok, %{body: body, status_code: 200}} ->
            File.write!(local_path, body)
            Logger.info("[Worker] Successfully downloaded audio to #{local_path}")
            {:ok, local_path}
          {:ok, %{status_code: status_code}} ->
            Logger.error("[Worker] S3 get_object returned status code: #{status_code}")
            {:error, :minio_download_failed, {:s3_error, status_code}}
          {:error, reason} ->
            Logger.error("[Worker] ExAws request failed: #{inspect(reason)}")
            {:error, :minio_download_failed, reason}
        end
      _ ->
        Logger.error("[Worker] Could not parse bucket and key from MinIO URL: #{minio_url}. Path parts: #{inspect(path_parts)}")
        {:error, :minio_download_failed, :url_parse_error}
    end
  rescue
    e -> # Catch unexpected errors
      Logger.error("[Worker] Unexpected error during MinIO download or URL parsing for '#{minio_url}': #{inspect(e)}")
      {:error, :minio_download_failed, {:unexpected_error, e}}
  end
end
defp download_from_minio(nil, _local_path), do: {:error, :minio_download_failed, :nil_minio_url}
defp download_from_minio(_minio_url, nil), do: {:error, :minio_download_failed, :nil_local_path}

defp call_whisper_service(audio_file_path) do
  whisper_config = Application.get_env(:podcast_mcp, :whisper_service, [])
  base_url = Keyword.fetch!(whisper_config, :base_url)
  transcribe_path = Keyword.get(whisper_config, :transcribe_path, "/asr")
  full_url = base_url <> transcribe_path
  request_timeout = Keyword.get(whisper_config, :request_timeout, 300_000)

  Logger.info("[Worker] Calling Whisper service at #{full_url} with audio file: #{audio_file_path}")

  # Check if file exists
  unless File.exists?(audio_file_path) do
    Logger.error("[Worker] Audio file does not exist at path: #{audio_file_path}")
    {:error, :whisper_call_failed, :audio_file_not_found}
  else
    # Read file content
    Logger.info("[Worker] Reading file content from: #{audio_file_path}")
    case File.read(audio_file_path) do
      {:ok, file_content} ->
        # Determine file name from path for the multipart form
        file_name = Path.basename(audio_file_path)
        content_type = MIME.from_path(audio_file_path)

        # Create multipart form data
        boundary = "------------------------#{:crypto.strong_rand_bytes(12) |> Base.encode16(case: :lower)}"
        headers = [
          {"content-type", "multipart/form-data; boundary=#{boundary}"},
        ]

        # Build form data manually
        body = ""
        |> append_multipart_field(boundary, "task", "transcribe")
        |> append_multipart_field(boundary, "output", "json")
        |> append_multipart_file(boundary, "audio_file", file_name, content_type, file_content)
        |> append_multipart_close(boundary)

        # Make the request
        Logger.info("[Worker] Sending POST request to Whisper: #{full_url}")

        # Use Finch.build with properly formatted multipart data
        case Finch.build(:post, full_url, headers, body)
             |> Finch.request(PodcastMcp.Finch,
                  receive_timeout: request_timeout,
                  pool_timeout: request_timeout) do
          {:ok, %Finch.Response{status: 200, body: resp_body} = response} ->
            # DEBUG: Log the response headers
            Logger.info("[Worker] Whisper response headers: #{inspect(response.headers)}")

            # DEBUG: Log the first part of the response body
            sample_length = min(byte_size(resp_body), 1000)
            sample_body = String.slice(resp_body, 0, sample_length)
            Logger.info("[Worker] Whisper response first #{sample_length} bytes: #{inspect(sample_body)}")

            # DEBUG: Try to determine the content type
            content_type_header = Enum.find_value(response.headers, fn {k, v} ->
              if String.downcase(k) == "content-type", do: v, else: nil
            end)
            Logger.info("[Worker] Content-Type from response: #{inspect(content_type_header)}")

            # For proper debugging, just return the raw body to be handled upstream
            {:ok, %{"debug_raw_response" => resp_body}}

          {:ok, %Finch.Response{status: status, body: resp_body}} ->
            Logger.error("[Worker] Whisper service returned non-200 status: #{status}. Body (first 500 chars): #{String.slice(resp_body, 0, 500)}")
            {:error, :whisper_call_failed, {:http_error, status, resp_body}}
          {:error, reason} ->
            Logger.error("[Worker] Finch request to Whisper service failed: #{inspect(reason)}")
            {:error, :whisper_call_failed, reason}
        end
      {:error, reason} ->
        Logger.error("[Worker] Failed to read audio file: #{inspect(reason)}")
        {:error, :whisper_call_failed, {:file_read_error, reason}}
    end
  end
end

# Modified extract function to handle our debug response
defp extract_transcript_from_response(%{"debug_raw_response" => raw_response}) when is_binary(raw_response) do
  # Check if the response looks like JSON
  case Jason.decode(raw_response) do
    {:ok, json_data} ->
      Logger.info("[Worker] Successfully parsed raw response as JSON: #{inspect(json_data)}")
      case Map.get(json_data, "text") do
        nil ->
          Logger.error("[Worker] JSON response doesn't contain 'text' field: #{inspect(json_data)}")
          {:error, :transcript_extraction_failed, :missing_text_field_in_json}
        text when is_binary(text) ->
          {:ok, text}
        other ->
          Logger.error("[Worker] 'text' field in JSON is not a string: #{inspect(other)}")
          {:error, :transcript_extraction_failed, :invalid_text_field_type}
      end
    {:error, jason_error} ->
      # If not JSON, treat the raw response as the transcript text
      Logger.info("[Worker] Raw response is not JSON (#{inspect(jason_error)}). Treating entire response as transcript text.")
      # Do a basic check to see if it looks like a transcript (printable text)
      if String.printable?(raw_response) do
        clean_text = String.trim(raw_response)
        Logger.info("[Worker] Extracted plain text transcript: #{String.slice(clean_text, 0, 100)}...")
        {:ok, clean_text}
      else
        Logger.error("[Worker] Raw response is not printable text")
        {:error, :transcript_extraction_failed, :response_not_printable_text}
      end
  end
end

# Keep the original function for backward compatibility
defp extract_transcript_from_response(whisper_json_response) when is_map(whisper_json_response) do
  case Map.get(whisper_json_response, "text") do
    nil ->
      Logger.error("[Worker] 'text' field not found or nil in Whisper JSON response: #{inspect(whisper_json_response)}")
      {:error, :transcript_extraction_failed, :missing_text_field}
    transcript_text when is_binary(transcript_text) ->
      {:ok, transcript_text}
    _other ->
      Logger.error("[Worker] 'text' field in Whisper JSON response was not a string: #{inspect(Map.get(whisper_json_response, "text"))}")
      {:error, :transcript_extraction_failed, :invalid_text_field_type}
  end
end
defp extract_transcript_from_response(bad_response) do
  Logger.error("[Worker] Whisper response was not a map: #{inspect(bad_response)}")
  {:error, :transcript_extraction_failed, :response_not_a_map}
end

# New helper function to process the Whisper response
defp process_whisper_response(resp_body) do
  # Try to decode as JSON first
  case Jason.decode(resp_body) do
    {:ok, decoded_json} ->
      Logger.debug("[Worker] Whisper response successfully parsed as JSON: #{inspect(decoded_json)}")
      {:ok, decoded_json}
    {:error, %Jason.DecodeError{} = decode_error} ->
      # If not valid JSON, log the error details
      Logger.warning("[Worker] JSON decode error: #{inspect(decode_error)}. Treating response as plain text.")

      # Log a sample of the response for debugging
      sample = String.slice(resp_body, 0, 200)
      Logger.debug("[Worker] Response sample: #{inspect(sample)}")

      # Check if response looks like valid plain text (not binary garbage)
      if String.printable?(resp_body) do
        # Create a simple map structure to mimic the expected JSON format with text field
        clean_text = String.trim(resp_body)
        Logger.info("[Worker] Created JSON-compatible structure with #{String.length(clean_text)} characters of text")
        {:ok, %{"text" => clean_text}}
      else
        # If response is not even printable text, there's a deeper issue
        Logger.error("[Worker] Response is neither JSON nor printable text. Response may be corrupt.")
        {:error, :whisper_call_failed, :invalid_response_format}
      end
  end
end

# Helper functions for multipart form data
defp append_multipart_field(acc, boundary, name, value) do
  acc <> """
  --#{boundary}\r
  Content-Disposition: form-data; name="#{name}"\r
  \r
  #{value}\r
  """
end

defp append_multipart_file(acc, boundary, name, filename, content_type, content) do
  acc <> """
  --#{boundary}\r
  Content-Disposition: form-data; name="#{name}"; filename="#{filename}"\r
  Content-Type: #{content_type}\r
  \r
  """ <> content <> "\r\n"
end

defp append_multipart_close(acc, boundary) do
  acc <> "--#{boundary}--\r\n"
end
defp extract_transcript_from_response(whisper_json_response) when is_map(whisper_json_response) do
  case Map.get(whisper_json_response, "text") do
    nil ->
      Logger.error("[Worker] 'text' field not found or nil in Whisper JSON response: #{inspect(whisper_json_response)}")
      {:error, :transcript_extraction_failed, :missing_text_field}
    transcript_text when is_binary(transcript_text) ->
      # Clean up any extra whitespace
      clean_transcript = String.trim(transcript_text)
      Logger.info("[Worker] Successfully extracted transcript text (#{String.length(clean_transcript)} characters)")
      {:ok, clean_transcript}
    _other ->
      Logger.error("[Worker] 'text' field in Whisper JSON response was not a string: #{inspect(Map.get(whisper_json_response, "text"))}")
      {:error, :transcript_extraction_failed, :invalid_text_field_type}
  end
end
defp extract_transcript_from_response(bad_response) do
  Logger.error("[Worker] Whisper response was not a map: #{inspect(bad_response)}")
  {:error, :transcript_extraction_failed, :response_not_a_map}
end

  defp save_transcript_to_minio(transcript_text, %Episode{} = episode) do
    bucket = System.get_env("MINIO_BUCKET") || "podcast-episodes"
    transcript_object_key = "transcripts/#{episode.user_id}/#{episode.id}/transcript_#{Ecto.UUID.generate()}.txt"
    Logger.info("[Worker] Uploading transcript to MinIO. Bucket: #{bucket}, Key: #{transcript_object_key}")

    case ExAws.S3.put_object(bucket, transcript_object_key, transcript_text, content_type: "text/plain", acl: :private) |> ExAws.request() do
      {:ok, %{status_code: 200}} ->
        minio_scheme = System.get_env("MINIO_SCHEME") || "http"
        minio_host = System.get_env("MINIO_HOST") || "localhost"
        minio_port = System.get_env("MINIO_PORT") || "9000"
        transcript_minio_url = "#{minio_scheme}://#{minio_host}:#{minio_port}/#{bucket}/#{transcript_object_key}"
        Logger.info("[Worker] Successfully uploaded transcript to: #{transcript_minio_url}")
        {:ok, transcript_minio_url}
      {:error, reason} ->
        Logger.error("[Worker] Failed to upload transcript to MinIO: #{inspect(reason)}")
        {:error, :minio_transcript_upload_failed, reason}
    end
  end

  defp update_episode_after_transcription(%Episode{} = episode, transcript_url, status) do
    attrs = %{processing_status: status}
    attrs = if transcript_url, do: Map.put(attrs, :transcript_url, transcript_url), else: attrs

    case Podcasts.update_episode(episode, attrs) do
      {:ok, updated_episode} ->
        Logger.info("[Worker] Episode ID #{episode.id} final status updated to '#{status}'. Transcript URL (if any): #{updated_episode.transcript_url}")
        {:ok, updated_episode}
      {:error, changeset} ->
        Logger.error("[Worker] Failed to update episode ID #{episode.id} with final status '#{status}': #{inspect(changeset.errors)}")
        {:error, :db_update_failed, changeset.errors}
    end
  end

  defp connect_and_setup_consumer(rabbitmq_url, exchange_name, queue_name, routing_key) do
    with {:ok, conn} <- Connection.open(rabbitmq_url),
         {:ok, chan} <- Channel.open(conn) do
      :ok = Exchange.declare(chan, exchange_name, :direct, durable: true, auto_delete: false)
      {:ok, %{queue: _q_name}} = Queue.declare(chan, queue_name, durable: true, auto_delete: false)
      :ok = Queue.bind(chan, queue_name, exchange_name, routing_key: routing_key)
      {:ok, consumer_tag} = Basic.consume(chan, queue_name, self(), no_ack: false)
      {:ok, conn, chan, consumer_tag} # Return conn as well
    else
      {:error, reason} = error_tuple ->
        Logger.error("[RabbitMQ Consumer] Error in connection/setup pipeline: #{inspect(reason)}")
        error_tuple
    end
  end

  defp ignore_error({:error, _reason}), do: :ok
  defp ignore_error(:ok), do: :ok
end
