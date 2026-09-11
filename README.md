# 🖥️ SPIRE Admin Console (Web & Desktop)

SPIRE Admin Console is a secure administrative platform for managing [SPIRE](https://github.com/spiffe/spire) (SPIFFE Runtime Environment) deployments. Available as a cross-platform desktop application or a remote web-based console, it provides centralized control and visibility over SPIRE Servers, SPIRE Agents, workload identities, trust authorities, and federation relationships across distributed environments.

The console enables administrators to configure registration entries, monitor agent attestation, inspect issued X.509-SVIDs and JWT-SVIDs, manage trust bundles, and establish workload federation between multiple SPIFFE trust domains. It also provides operational dashboards for server health, connected agents, active workloads, certificate rotation, federation status, and audit events.

By integrating strong authentication (mTLS, SPIFFE identities, or enterprise identity providers) with role-based authorization, the SPIRE Admin Console offers a secure and user-friendly control plane for operating large-scale zero-trust identity infrastructure.

---

## 📚 Documentation

- 🏛️ **[Architecture & Design Document](docs/design_document.md)**: Deep dive into the platform architecture, SPIFFE/Workload API integration, mTLS communication, multi-domain federation mechanics, and subsystem designs.
- 🧪 **[Test Setup & Execution Guide](docs/test_setup_guide.md)**: In-depth reference for running the multi-domain local SPIRE test environment, CLI options, console connections, and troubleshooting.

---

## 📸 Screenshots

### Web Console Interface
![SPIRE Admin Web Console](images/web_console.png)

### Desktop GUI Application
![SPIRE Admin Desktop GUI](images/desktop_gui.png)

---

## 🏗️ Architectural Overview

The SPIRE Admin Console runs as a **SPIFFE workload**. 
1. It connects to a local SPIRE Agent's Workload API socket (e.g., `agent.sock`).
2. It automatically and dynamically retrieves its own X.509 SVID (mTLS certificate and private key).
3. Using these SPIFFE credentials, it secures TLS connections to the remote SPIRE Servers' administration endpoints.
4. Once authenticated, administrators can execute commands, manage registrations, control agents, and rotate keys remotely.

![SPIRE Admin Architecture](images/architecture.jpg)



### 🔗 Server Federation & Authorization Requirements

To allow the SPIRE Admin Console to remotely administer a SPIRE Server (e.g. `domain-a.test`), two main requirements must be satisfied in the target server's HCL configuration:

1. **SPIFFE ID Authorization (`admin_ids`)**:
   The remote SPIRE Server must explicitly authorize the admin workload's SPIFFE ID (`spiffe://admin.app/spire_admin`) to execute administrative gRPC APIs. This is done by adding the ID to the `admin_ids` array in the `server` block:
   ```hcl
   server {
       # ...
       admin_ids = ["spiffe://admin.app/spire_admin"]
   }
   ```

2. **Trust Federation (`federation`)**:
   The remote SPIRE Server must trust the root authority of the Admin Console's trust domain (`admin.app`) to establish mutual TLS (mTLS). This is configured in the server's `federation` block, defining how it retrieves the trust bundle for `admin.app` (typically over HTTPS):
   ```hcl
   server {
       # ...
       federation {
           federates_with "admin.app" {
               bundle_endpoint_url = "https://127.0.0.1:8445"
               bundle_endpoint_profile "https_spiffe" {
                   endpoint_spiffe_id = "spiffe://admin.app/spire/server"
               }
           }
       }
   }
   ```
   *(Refer to [docs/test_setup_guide.md](docs/test_setup_guide.md) and [test/spire_test_setup.sh](test/spire_test_setup.sh) for the complete multi-domain federation bootstrapping details).*

---

## ✨ Features

Both interfaces share a unified, professional user experience styled with responsive custom CSS themes (`Purple`, `Green`, `Blue`, `Gray`).

### Shared Features (Web & Desktop)
- **Live Server Status Monitoring**: Real-time health checks (`Online`, `Connecting`, `Offline`) indicated by colored status badges and absolute timezone-adjusted timestamps.
- **SPIRE Agent Management**:
  - List all connected agents and view detailed properties (SPIFFE ID, attestation type, expiration, serial number, agent version).
  - Evict (delete) agents.
  - Ban agents.
  - Purge expired agents automatically in bulk.
- **Registration Entries**:
  - Segmented tab panels to organize registration entries for **Workloads**, **Agents**, and **Downstream Servers**.
  - Complete CRUD capability: Create new registrations, view full properties, update fields (DNS names, Hint, TTL, Federates With, downstream/admin status), and delete entries.
- **Federated Trust Bundles**:
  - View trust domain lists and sequence numbers.
  - Display lists of trusted X.509 and JWT authorities.
  - Set/Update federated bundles manually via PEM-encoded certificates.
  - Delete federated trust bundles.
- **Federation Relationships**:
  - List and add dynamic federation relationships with foreign trust domains.
  - Modify bundle endpoint addresses.
  - Refresh federation bundles from remote endpoints immediately.
  - Terminate federation relationships.
- **Local Authority Management**:
  - Monitor local signing keys (Active, Prepared, and Old authority states).
  - Prepare/Generate new authority keys (Rotate).
  - Activate prepared signing keys.
  - Taint and revoke old authorities.
- **Upstream Authority Management**:
  - Taint and revoke upstream X.509 authority trust using the Upstream Subject Key ID (SKID) in hex format.
- **System Logs Console**: Inline scrolling logs console capturing internal application event logs.

### Desktop GUI Specific Features
- **Offline configurations**: Save connected server profiles locally in HCL format, or load existing configurations from file.

### Web Console Specific Features
- **User Manager (Admin only)**: Provision user accounts and define roles (Operators or Administrators) from a secure interface.
- **Interactive SPA**: Clean, responsive, and dynamic single-page application experience.
- **Inactivity Timer**: Automatic session logout after 30 minutes of inactivity.

---

## 🔨 Building & Installation

### 1. Building on NixOS

This repository includes a [Nix Flake](flake.nix) providing a fully configured development shell with Go, GCC, SPIRE, OpenSSL, and all required Fyne OpenGL/X11 graphics libraries.

#### Enter the Nix Development Shell
```bash
nix develop
```

#### Build Commands in NixOS
Once inside the development shell, you can use the predefined shell aliases or standard `go build`:
```bash
# Build Desktop GUI
build-desktop-app
# Or:
go build -o spire-admin-desktop ./apps/spire-admin-desktop

# Build Web Console
build-web-app
# Or:
go build -o spire-admin-web ./apps/spire-admin-web
```

---

### 2. Building on Ubuntu / Debian

#### Package Requirements (APT)
To build both the Desktop GUI (which requires CGO and OpenGL/X11 headers for the Fyne toolkit) and the Web Console on Ubuntu (20.04/22.04/24.04 LTS), install the following prerequisites:

```bash
sudo apt-get update && sudo apt-get install -y \
  golang-go \
  gcc \
  pkg-config \
  libgl1-mesa-dev \
  libglu1-mesa-dev \
  libglvnd-dev \
  xorg-dev \
  libx11-dev \
  libxcursor-dev \
  libxrandr-dev \
  libxinerama-dev \
  libxi-dev \
  libxxf86vm-dev \
  libglfw3-dev \
  libfreetype6-dev \
  libdbus-1-dev \
  openssl
```

> **Note**: If your distribution provides an older Go version, install Go 1.20+ from [golang.org](https://go.dev/dl/). Ensure [SPIRE](https://github.com/spiffe/spire/releases) (`spire-server` and `spire-agent`) is installed and available in your `PATH`.

#### Build Commands on Ubuntu
```bash
# Clone the repository
git clone https://github.com/gngram/spire-admin.git
cd spire-admin

# Download Go dependencies
go mod download

# Build Desktop GUI binary
go build -o spire-admin-desktop ./apps/spire-admin-desktop

# Build Web Console binary
go build -o spire-admin-web ./apps/spire-admin-web
```

---

## 🛠️ Getting Started & Local Testing

You can spin up a local SPIRE testing environment simulating an administrative domain and federated test domains to test the SPIRE Admin Console.

### 1. Start the Local SPIRE Testing Environment
The repository contains a script under [`test/spire_test_setup.sh`](test/spire_test_setup.sh) that sets up:
- **Admin Server** (`admin.app` at `127.0.0.1:8081`) and Agent.
- **Federated Server A** (`domain-a.test` at `127.0.0.1:8082`) and Agent.
- **Federated Server B** (`domain-b.test` at `127.0.0.1:8083`) and Agent.

Run the script providing a temporary directory for configuration and database files:
```bash
./test/spire_test_setup.sh /tmp/spire-data
```

*(See [docs/test_setup_guide.md](docs/test_setup_guide.md) for full CLI options including `--domain-a-server-port`, `--domain-b-server-port`, `--admin-server-port`, and `-c/--clean`).*

Keep this terminal running. It will output a summary showing the socket paths and ports once initialization is complete.

---

## 💻 Running the Desktop GUI

Run the desktop application pointing to the admin agent socket created by the test setup:
```bash
./spire-admin-desktop -socket /tmp/spire-data/spire-admin/agent.sock
```
*Note: Make sure your system environment supports OpenGL for GUI rendering (Fyne framework).*

---

## 🌐 Running the Web Console

### 1. Generate SSL Certificates for HTTPS
Generate local HTTPS development certificates:
```bash
cd apps/spire-admin-web
./generate_certs.sh /tmp
cd ../..
```
This produces `cert.pem` and `key.pem` files under `/tmp/spire-certs/`.

### 2. Launch the Web Server
Run the web server by specifying the agent socket, SSL keys, and target port:
```bash
./spire-admin-web \
  -socket /tmp/spire-data/spire-admin/agent.sock \
  -cert /tmp/spire-certs/cert.pem \
  -key /tmp/spire-certs/key.pem \
  -port 8443
```

### 3. Log In as Administrator
Open your browser and navigate to `https://localhost:8443`.

#### 🔐 Default Credentials & Env Variables
By default, the server provisions a default administrator account:
- **Username**: `admin`
- **Password**: `admin123`

You can override these credentials before starting the web server by setting the `ADMIN_USERNAME` and `ADMIN_PASSWORD` environment variables:
```bash
export ADMIN_USERNAME="my_custom_admin"
export ADMIN_PASSWORD="my_secure_password"
./spire-admin-web \
  -socket /tmp/spire-data/spire-admin/agent.sock \
  -cert /tmp/spire-certs/cert.pem \
  -key /tmp/spire-certs/key.pem \
  -port 8443
```

#### 🛡️ HTTPS CA Certificate & Trust Setup
When connecting to the web server over HTTPS:
1. The web server expects the `-cert` and `-key` parameters to serve TLS traffic.
2. If self-signed certificates were generated (via `./generate_certs.sh`), browsers will display a connection warning. To establish a fully secure HTTPS connection, import the generated root CA certificate (`/tmp/spire-certs/rootCA.pem`) into your browser/system trust store, or use certificates issued by a trusted Certificate Authority.

Once logged in:
- Click the **User Manager** tab at the bottom left to create additional operator or administrator accounts.
- Under the **Servers** tab, add `Server 1`, `Domain A`, and `Domain B` using addresses `127.0.0.1` and ports `8081`, `8082`, `8083`.
