# twin-kit
twin-kit is a deterministic visual twin for a local Kubernetes release-pipeline sandbox. A stdlib-only Python server polls real cluster state — minikube profile health, rollout phases, a gRPC mock, the git branch under test, and an endpoint-allowlist safety check — and a single offline HTML page renders it as a live topology (scripted walkthroughs)
