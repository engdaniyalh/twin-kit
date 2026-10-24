export interface MinikubeState {
    profile: string;
    status: "Running" | "Stopped" | "Degraded" | "Unknown" | string;
    cpus?: number;
    memory?: string;
    lastCheck?: string;
}

export interface DeploymentState {
    name: string;
    replicas: number;
    ready: number;
    image?: string;
}

export interface RolloutState {
    phase: "stable" | "canary" | "promote" | "rollback" | string;
    deployments: DeploymentState[];
    progress: number;
}

export interface GrpcState {
    mock: string;
    status: "OK" | "DEGRADED" | "DOWN" | string;
    latencyMs?: number;
}

export interface GitState {
    branch: string;
    commit?: string;
    dirty: boolean;
}

export interface SafetyState {
    allowlist: string[];
    violations: string[];
    blocked?: string[];
}

export interface TwinState {
    minikube?: MinikubeState;
    rollout?: RolloutState;
    grpc?: GrpcState;
    git?: GitState;
    safety?: SafetyState;
}

export interface WalkthroughItem {
    id: string;
    name: string;
    description: string;
}

export interface ServerConfig {
    serverPath: string;
    pythonPath: string;
    port: number;
    minikubeProfile: string;
    autoStart: boolean;
    pollInterval: number;
    walkthroughs: string[];
}
