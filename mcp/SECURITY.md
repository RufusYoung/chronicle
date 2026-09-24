# Private MCP Security Boundary

This is a single-owner, read-only project discussion service, not a general file server.

- All MCP methods, including initialization and discovery of tools, require a resource-bound OAuth bearer token. Public endpoints contain only service identity, authorization metadata and login UI.
- OAuth authorization-code flow uses PKCE S256, exact registered ChatGPT callbacks, issuer identification on success/error, one-use 60-second codes, CSRF cookies and Origin checks. Access tokens last one hour; refresh tokens rotate and last 30 days. Revocation removes a token family.
- A random 192-bit owner password is stored outside Git with Windows ACL protection. The server receives only its salted scrypt hash. Token secrets are stored as SHA-256 digests. OAuth client secrets, if requested by DCR, remain in the private server store.
- Client registration is restricted to official ChatGPT callback shapes, rate-limited and capped at 100 clients. Registration is not authorization: an untrusted registrant still needs the owner password. Rate limits and quotas bound basic abuse but cannot prevent all denial of service; the owner can restart or disable the container.
- The source snapshot is generated from Git blobs, not by recursively reading the working directory. Symlinks, executable blobs, private directories, binaries, saves, untracked files and oversize files are excluded. Each document has a verified hash. No runtime tool can open a local path or invoke a shell.
- Secret-pattern scanning is a guardrail, not a proof that a document contains no sensitive prose. Review committed documents before publishing. This service intentionally transfers selected repository content to the existing private server and returns requested portions to ChatGPT.
- Search is literal and bounded, not a user-supplied regular expression. Fetch is allowlist-only and bounded. Tool schemas limit input sizes. The container has CPU/memory/PID limits, no host ports, no source mount, no Docker socket and no privileged capabilities.
- Logs do not deliberately contain file contents, passwords or tool arguments. Do not enable request-body/access-token logging at the reverse proxy. The shared reverse proxy must exclude these paths from unrelated site policies.
- Source text can contain prompt injection. MCP instructions mark it as untrusted evidence. Read-only tools reduce the impact but cannot guarantee a model interprets documents correctly.
- The game backend and native saves are not exposed. There is no claim that this service can play the game, synchronize edits bidirectionally or observe the live world.

Authentication/router design follows the owner's existing Vibe Deck private MCP pattern, narrowed to one read-only scope and a committed snapshot. No Vibe Deck credentials, pairing keys, control tools or live bridge are shared. Dependencies are locked separately; use the official npm audit endpoint. Unit/integration tests cover protocol security and snapshot isolation; public checks validate the deployed instance without treating that as ChatGPT account linkage.
