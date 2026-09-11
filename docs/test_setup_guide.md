# 🧪 SPIRE Multi-Domain Test Environment Guide

This guide describes how to run and use the local multi-domain SPIRE testing environment provided in [`test/spire_test_setup.sh`](file:///home/gangaram/playground/spire-admin/test/spire_test_setup.sh).

---

## 1. Overview of the Test Environment

The test environment simulates a complete multi-domain SPIRE deployment on `localhost` with three distinct SPIFFE trust domains:

1. **Admin Domain (`admin.app`)**:
   - **SPIRE Server**: Listens on gRPC port `8081`, bundle endpoint `8445`.
   - **SPIRE Agent**: Attested via join token, connects over socket `spire-admin/agent.sock`.
   - **Admin Workload**: Registered with SPIFFE ID `spiffe://admin.app/spire_admin` for the current user's UID (`unix:uid:<uid>`). It has administrative privileges (`-admin`) and is authorized to federate with `domain-a.test` and `domain-b.test`.

2. **Federated Domain A (`domain-a.test`)**:
   - **SPIRE Server**: Listens on gRPC port `8082`, bundle endpoint `8446`.
   - **SPIRE Agent**: Connects over socket `spire-test-servers/test-agent-a.sock`.
   - **Workload**: `spiffe://domain-a.test/workload-a`.
   - **Admin Authorization**: Configured with `admin_ids = ["spiffe://admin.app/spire_admin"]`.

3. **Federated Domain B (`domain-b.test`)**:
   - **SPIRE Server**: Listens on gRPC port `8083`, bundle endpoint `8447`.
   - **SPIRE Agent**: Connects over socket `spire-test-servers/test-agent-b.sock`.
   - **Workload**: `spiffe://domain-b.test/workload-b`.
   - **Admin Authorization**: Configured with `admin_ids = ["spiffe://admin.app/spire_admin"]`.

---

## 2. Prerequisites

Ensure the following dependencies are installed and available in your system `PATH`:
- **`spire-server`** (v1.8.0+)
- **`spire-agent`** (v1.8.0+)
- **`openssl`**
- **`bash`** (v4.0+)

---

## 3. Command Line Options Reference

The test script [`test/spire_test_setup.sh`](file:///home/gangaram/playground/spire-admin/test/spire_test_setup.sh) supports both positional arguments and named flags:

| Option | Default | Description |
| :--- | :--- | :--- |
| `DATA_DIRECTORY` / `-d`, `--data-dir <path>` | *(Required)* | Base directory for runtime configs, databases, logs, and sockets |
| `--admin-server-port <port>` | `8081` | gRPC listening port for the Admin SPIRE Server |
| `--admin-bundle-port <port>` | `8445` | HTTPS federation bundle endpoint for Admin Server |
| `--domain-a-server-port <port>` | `8082` | gRPC listening port for Server A (`domain-a.test`) |
| `--domain-b-server-port <port>` | `8083` | gRPC listening port for Server B (`domain-b.test`) |
| `--domain-a-bundle-port <port>` | `8446` | HTTPS federation bundle endpoint for Server A |
| `--domain-b-bundle-port <port>` | `8447` | HTTPS federation bundle endpoint for Server B |
| `-c`, `--clean` | `false` | Terminate running SPIRE processes, remove data directories, and exit |
| `-h`, `--help` | — | Display usage instructions and exit |

---

## 4. Running the Test Environment

### 4.1 Basic Start (Default Ports)
Run the script providing a target directory (e.g. `/tmp/spire-data`):
```bash
./test/spire_test_setup.sh /tmp/spire-data
```
Or using the `--data-dir` flag:
```bash
./test/spire_test_setup.sh --data-dir /tmp/spire-data
```

### 4.2 Customizing Ports
You can override any of the gRPC or bundle endpoint ports:
```bash
./test/spire_test_setup.sh /tmp/spire-data \
  --admin-server-port 9081 \
  --domain-a-server-port 9082 \
  --domain-b-server-port 9083 \
  --domain-a-bundle-port 9446 \
  --domain-b-bundle-port 9447
```

### 4.3 Output Summary
Upon successful startup, the script prints an operational summary:
```text
=======================================================================
✅ SPIRE environment is up and running!

  Admin (admin.app)
    gRPC:            127.0.0.1:8081
    Bundle endpoint: https://127.0.0.1:8445  (https_web)
    Workload:        spiffe://admin.app/spire_admin
    Logs:            /tmp/spire-data/spire-admin/admin-server.log
                     /tmp/spire-data/spire-admin/admin-agent.log

  Server A (domain-a.test)
    gRPC:            127.0.0.1:8082
    Bundle endpoint: https://127.0.0.1:8446  (https_web)
    Workload:        spiffe://domain-a.test/workload-a
    Logs:            /tmp/spire-data/spire-test-servers/test-server-a.log
                     /tmp/spire-data/spire-test-servers/test-agent-a.log

  Server B (domain-b.test)
    gRPC:            127.0.0.1:8083
    Bundle endpoint: https://127.0.0.1:8447  (https_web)
    Workload:        spiffe://domain-b.test/workload-b
    Logs:            /tmp/spire-data/spire-test-servers/test-server-b.log
                     /tmp/spire-data/spire-test-servers/test-agent-b.log
=======================================================================
```

---

## 5. Connecting Admin Consoles to the Test Environment

Keep the terminal running the test script open. In separate terminals:

### 5.1 Connecting the Desktop GUI
```bash
# 1. Build desktop binary
go build -o spire-admin-desktop ./apps/spire-admin-desktop

# 2. Run pointing to the Admin Agent socket
./spire-admin-desktop -socket /tmp/spire-data/spire-admin/agent.sock
```

### 5.2 Connecting the Web Console
```bash
# 1. Generate local development TLS certificates
cd apps/spire-admin-web
./generate_certs.sh /tmp
cd ../..

# 2. Build and launch web server
go build -o spire-admin-web ./apps/spire-admin-web
./spire-admin-web \
  -socket /tmp/spire-data/spire-admin/agent.sock \
  -cert /tmp/spire-certs/cert.pem \
  -key /tmp/spire-certs/key.pem \
  -port 8443
```
Open your browser at `https://localhost:8443` (Default login: `admin` / `admin123`).

### 5.3 Adding Test Servers in the Console UI
Under the **Servers** tab, register the servers:
- **Admin Server**: Address `127.0.0.1`, Port `8081`
- **Domain A Server**: Address `127.0.0.1`, Port `8082`
- **Domain B Server**: Address `127.0.0.1`, Port `8083`

---

## 6. Cleanup & Troubleshooting

### Stopping the Test Environment
- Press `Ctrl+C` in the terminal where `spire_test_setup.sh` is running. The process trap will automatically shut down all child SPIRE processes.
- To wipe test data and terminate any lingering background processes:
  ```bash
  ./test/spire_test_setup.sh --data-dir /tmp/spire-data --clean
  ```

### Common Issues
1. **`spire-server: command not found`**: Ensure SPIRE binaries are installed and in your `PATH`.
2. **`Port collision detected`**: Ensure every server and bundle endpoint uses a unique port.
3. **`Parent socket not found`**: Verify that `spire_test_setup.sh` is running and that the path matches `<data_dir>/spire-admin/agent.sock`.
4. **`Address already in use`**: Run `./test/spire_test_setup.sh -d /tmp/spire-data --clean` to kill lingering instances before restarting.
