# PodcastMcp (WIP)
* Everything is currently a WIP in progress and is subject to change at my whims.
** Overview: **
The aim of this project is to generate AI Show Notes, and allow for a user to utilize a Transcript Search Engine for listeners/researchers.
* Name is also a WIP.


## Dictation of Components
** TODO: ... **


## Intended Tech Stack
* Web App/API: Elixir (Phoenix)
* Metadata & User data: PostgreSQL
* File/Transcript Storage: MinIO (Object Storage)
* Search Index: OpenSearch
* Job Queue: RabbitMQ
* Media Processor: FFmpeg
* Transcriber: TBD (A lot of progress in the arena atm; currently leaning towards latest NVIDIA model.)
* NLP Tasks: MCP with Gemini or Anthropic & Search APIs (Initially)
* Background Workers: Elixir


## Bucket
**Bucket Name:** podcast-episodes


**Custom Access Policy**
```
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "AWS": [
                    "*"
                ]
            },
            "Action": [
                "s3:GetObject"
            ],
            "Resource": [
                "arn:aws:s3:::podcast-episodes/*"
            ]
        }
    ]
}
```




## Docket Composer

* Start Via:  docker compose up -d
* Must have respective volumes
    * ~/docker_volumes/postgres_data_compose
    * ~/docker_volumes/minio_data_compose
**File is: ** ~/dev-services/docker-compose.yml
```
services:
  postgres:
    image: postgres:16
    container_name: postgres-dev-compose
    restart: unless-stopped
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
      POSTGRES_DB: podcast_mcp_dev
    ports:
      - "5432:5432"
    volumes:
      - ~/docker_volumes/postgres_data_compose:/var/lib/postgresql/data # Use a separate volume path if you ran the standalone docker run before
    networks:
      - dev-network

  minio:
    image: quay.io/minio/minio
    container_name: minio-dev-compose
    restart: unless-stopped
    environment:
      MINIO_ROOT_USER: minioadmin   # CHANGE THIS
      MINIO_ROOT_PASSWORD: minioadmin  # CHANGE THIS TO A STRONG PASSWORD
    ports:
      - "9000:9000" # API port
      - "9002:9002" # Console port (using 9002 to avoid conflict if you have another MinIO on 9001)
    volumes:
      - ~/docker_volumes/minio_data_compose:/data # Use a separate volume path
    command: server /data --console-address ":9002"
    networks:
      - dev-network

volumes: # Define named volumes (optional, but good practice for clarity if not using host paths directly)
  postgres_data_compose: # This refers to the host path ~/docker_volumes/postgres_data_compose
    driver_opts:
      type: none
      device: ~/docker_volumes/postgres_data_compose # Make sure this directory exists
      o: bind
  minio_data_compose: # This refers to the host path ~/docker_volumes/minio_data_compose
    driver_opts:
      type: none
      device: ~/docker_volumes/minio_data_compose # Make sure this directory exists
      o: bind

networks:
  dev-network:
    driver: bridge

```

## Phoenix Information
To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://hexdocs.pm/phoenix/overview.html
* Docs: https://hexdocs.pm/phoenix
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix
