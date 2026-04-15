# For testing on docker
    1. Create docker containers
    docker compose up -d
    2. Pull and run model on the server with ollama
    docker exec -it ollama-server ollama run gpt-oss:20b
    3. Set up attacker-server to receive data (attacker_server directory)
    docker compose up -d
    4. Copy go file into victim environment
    docker cp main.go promptlock-victim:/home/victim/main.go
    5. Compile and run the binary in victim environment
    docker exec -it promptlock-victim bash
    go mod init main.go
    go mod tidy
    go mod build -o promptlock_sim main.go
    ./promptlock_sim

# Generating update binary for linux
go build -o update main.go

# Generating update.exe binary for windows
GOOS=windows GOARCH=amd64 go build -o update.exe main.go

# Testing on aws cloud
refer to /attacker_server/attacker_notes.txt and /victim_files/setup.txt

After setting up attacker side terraform, upload update(linux) and update.exe(windows) binary to the S3 bucket under /updates directory.

Attack flow:
1. Enter SSM session using AWS keys
2. Download and execute update/update.exe from S3 (cloudfront)
3. Check attacker's C2 server (ec2 instance) under received_files for exfiltrated files.