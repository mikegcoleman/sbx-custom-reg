# sbx-custom-reg

Run Docker Sandboxes (`sbx`) agents from **your own container registry**, with extra tools
baked in, and without any developer machine pulling from Docker Hub.

This repository builds one kit, **Claude Code with `kubectl` and Helm**, publishes it to
your registry, and configures `sbx` to use it. After setup, a developer runs a single command:

```console
$ sbx run --name demo registry.example.com/sbx/sbx-kit-claude-k8s:1.0.0 .
```

It uses [kits v3](https://docs.docker.com/ai/sandboxes/customize/), which needs **sbx 0.45 or later**.

## How it works

A v3 kit is an ordinary container image. This repository builds two kits and imports three
images they depend on, all under one path in your registry:

| Image in your registry | What it is |
|---|---|
| `sbx-kit-claude` | Docker's published Claude Code kit, copied in |
| `sbx-kit-k8s-tools` | A small kit that adds `kubectl` and Helm (built here) |
| `sbx-kit-claude-k8s` | A [kit set](https://docs.docker.com/ai/sandboxes/customize/author/kit-sets/) that combines the two. **This is what developers run.** |
| `sandbox-kit` | The kit build frontend, copied in |
| `debian` | The base image the tools kit builds from, copied in |

Only the import step touches Docker Hub, and you can replace it with your registry's own
proxying. Building and running use your registry only.

## Prerequisites

- A container registry that supports OCI images, and an account with push access for the
  person publishing the kits. Developers need pull access.
- `docker` with `buildx`. The scripts log in to your registry for you.
- Docker already trusts your registry's TLS certificate.
- `regctl` for the one-time import ([install](https://github.com/regclient/regclient); on macOS,
  `brew install regclient`). Not needed if your registry already proxies Docker Hub.
- `sbx` 0.45 or later on each developer machine.

## Step 1. Configure

Copy the example file and fill it in:

```console
$ cp .env.example .env
```

| Variable | Required | Meaning |
|---|---|---|
| `REGISTRY` | yes | Registry host, with a port if needed. No `https://`. |
| `REGISTRY_NAMESPACE` | yes | Repository path the images live under, lowercase, no leading or trailing slash. With Artifactory's repository-path access method, start with the Docker repository key, such as `docker-local/sbx`. |
| `REGISTRY_USERNAME` | yes | Registry user. |
| `REGISTRY_PASSWORD` | yes | Registry password or access token. |
| `REGISTRY_CA_FILE` | no | PEM file for your private CA. Only needed if builds fail with an `x509` error (see [Troubleshooting](#troubleshooting)). |
| `CLAUDE_KIT_VERSION` | no | Docker's Claude kit version to import. Default `2.1.267`. |
| `KUBECTL_VERSION`, `HELM_VERSION` | no | Tool versions. Match `KUBECTL_VERSION` to your cluster; kubectl supports one minor version of skew. |
| `K8S_TOOLS_KIT_VERSION`, `CLAUDE_K8S_KIT_VERSION` | no | Tags for the kits built here. Default `1.0.0`. |

You can skip the file and export the same variables in your shell instead. If a variable is set
in both places, the exported one wins. `.env` is git-ignored, so credentials stay out of the repository.

## Step 2. Import Docker's images into your registry

Run this once, from a machine that is allowed to reach Docker Hub:

```console
$ scripts/import.sh
```

It copies `docker/sbx-kit-claude`, `docker/sandbox-kit` and `library/debian` into
`$REGISTRY/$REGISTRY_NAMESPACE/`. If your registry already proxies Docker Hub, make the same
three images available at those paths instead and skip this step.

## Step 3. Build and publish the kits

```console
$ scripts/publish.sh
```

The script fills in your registry settings, builds the tools kit and the combined kit for
`linux/amd64` and `linux/arm64`, and pushes both. The registry host appears inside the kit
descriptors, so the scripts generate them into `.build/` (git-ignored) from the templates in `kits/`.

## Step 4. Configure `sbx` on a developer machine

```console
$ scripts/client-setup.sh
```

This runs two commands:

```console
$ sbx settings set kit.allowedSources '["registry.example.com/sbx/"]'
$ sbx secret set --registry registry.example.com --username "$REGISTRY_USERNAME" --password-stdin
```

`kit.allowedSources` replaces the whole allowlist. The default is `["docker.io/"]`, so after this
command developers can install kits only from your registry. The second command stores the
registry credential for `sbx` to use when pulling.

To configure many machines, the same allowlist can be set in a file instead of with the CLI. See
[Managing settings and approvals centrally](#managing-settings-and-approvals-centrally).

## Step 5. Run it

```console
$ sbx run --name demo registry.example.com/sbx/sbx-kit-claude-k8s:1.0.0 .
```

On the first run, `sbx` shows a **credential approval** prompt, because the kit declares an
Anthropic credential. Choose "Approve all". To avoid asking every developer, see
[Managing settings and approvals centrally](#managing-settings-and-approvals-centrally).

Inside the sandbox, confirm the tools are present:

```console
$ kubectl version --client
$ helm version
```

For `kubectl` to reach a cluster, the sandbox's network policy must allow the cluster's API
server, for example `sbx policy allow network <api-server-host>:6443`, and the user must provide a
kubeconfig.

## Managing settings and approvals centrally

Steps 4 and 5 configure one machine by hand. For many machines, two files hold the same
information, and your MDM or configuration-management tool can deploy them. This repository
doesn't ship either file: you create the content once and distribute it your way. Neither file
is locked, so users can still edit them.

### Allowed kit sources: `settings.json`

`sbx settings set` stores its overrides in a JSON file that maps setting names to values. To set
the allowed kit sources by file, add the key:

```json
{
  "kit.allowedSources": ["registry.example.com/sbx/"]
}
```

- **Merge, don't overwrite.** The file also holds the user's other settings.
- **Location on macOS:** `~/Library/Application Support/com.docker.sandboxes/sandboxes/settings.json`.
  Docker doesn't document this location, so confirm it for your `sbx` version and operating system.
- **The list replaces the default.** The default is `["docker.io/"]`. Include every prefix you want
  to allow, with a trailing slash.
- **Check what `sbx` sees:** `sbx settings get kit.allowedSources`. If a change doesn't show up, run
  `sbx daemon restart`.

### Credential approvals: `credentials.yaml`

A kit that uses a credential needs the user's approval before `sbx` will send it anywhere. That
approval is recorded in `~/.config/sbx/credentials.yaml` (`%APPDATA%\sbx\credentials.yaml` on
Windows), and it is what the first-run prompt writes when a user chooses "Approve all". The file
holds no secrets. It only lists which credential mechanisms a service may use, and for which domains.

An example for the Claude kit used here:

```yaml
bindings:
  anthropic:
    apiKey:
      domains:
        - api.anthropic.com
        - claude.ai
        - console.anthropic.com
        - mcp-proxy.anthropic.com
    oauth:
      domains:
        - platform.claude.com
```

Don't copy this verbatim. The domains have to match what the kit declares, and they can change
between kit versions. The reliable way to produce the file is to run the kit once on a reference
machine, approve it, and copy the entries `sbx` wrote for this kit. If a kit asks for domains the
file doesn't cover, `sbx` asks again. See Docker's
[credentials documentation](https://docs.docker.com/ai/sandboxes/configuration/credentials/).

### What stays per user

- **The registry pull credential** from Step 4 lives in `sbx`'s credential store, not in a file, so
  each user provides it, for example with `sbx secret set --registry`.
- **The Anthropic credential itself.** Approval allows the kit to use a credential; it doesn't supply
  one. Each user still stores a key or signs in.

## Network requirements

These scripts remove Docker Hub from the image and kit path. `sbx` itself still signs users in
and reports telemetry. Docker's [FAQ](https://docs.docker.com/ai/sandboxes/faq/) lists the hosts
`sbx` uses on local sandboxes, including `login.docker.com`, `hub.docker.com` and `api.docker.com`.
Confirm which of those your environment can allow.

## Customizing

- **Different tools.** Edit `kits/k8s-tools/`. The Dockerfile downloads and checks each binary; add
  more the same way. Docker's [tool mixin guide](https://docs.docker.com/ai/sandboxes/customize/author/tool-mixins/)
  covers the format.
- **Different agent.** Docker publishes v3 kits for other agents. Import the one you want in
  `scripts/import.sh`, and reference it from `kits/claude-k8s/` and the scripts.
- **New versions.** Change the version variables in `.env` and run Steps 2 and 3 again. Use a new
  tag so developers' `sbx` doesn't reuse an older build.

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `docker login` fails with `certificate signed by unknown authority` | Docker doesn't trust your registry's certificate. Install the CA the way your organization installs Docker trust. |
| `docker buildx build` fails with `x509: certificate signed by unknown authority` | The build runs in its own container with its own trust store. Set `REGISTRY_CA_FILE` in `.env`, run `docker buildx rm sbx-kit-builder`, and publish again. |
| `sbx run` fails with `401 Unauthorized: pull failed for image` | `sbx` has no registry credential. Run `scripts/client-setup.sh`, or `sbx secret set --registry <host>`. Kit lookup can succeed from your Docker login even when the image pull has no credential. |
| `sbx run` refuses the kit reference | The registry isn't in `kit.allowedSources`. Run `sbx settings get kit.allowedSources`. The entry needs a trailing slash and must cover the full path. |
| The approval prompt appears for every developer | Expected on first run. Pre-approve by deploying `credentials.yaml`, as described under [Managing settings and approvals centrally](#managing-settings-and-approvals-centrally). |
| `sbx run` is rejected because the kit "combines 2 context files" | A kit set can carry only one block of agent guidance. Don't add `agent-context` capabilities to the tools kit. |
| Build fails downloading `kubectl` or Helm | The build container needs `dl.k8s.io` and `get.helm.sh`. Allow them, or mirror the binaries and change the URLs in `kits/k8s-tools/k8s-tools.dockerfile.tmpl`. |

## License

Apache License 2.0. See [LICENSE](LICENSE).
