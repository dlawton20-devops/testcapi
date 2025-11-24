# Simple Solution for macOS + Kind + Metal3

## The Core Problem

1. **sushy-tools** (on macOS host) needs to fetch boot ISOs from Ironic
2. **Ironic** (in Kubernetes) generates boot ISO URLs
3. **The URL must be reachable from the macOS host**

## Why MetalLB Doesn't Work

- MetalLB on macOS with Kind doesn't work because Docker networking blocks it
- LoadBalancer IPs aren't accessible from the host

## The Simple Solution

**Use NodePort + Host IP + Port Forwarding (if needed)**

### Step 1: Ensure Service is NodePort

```bash
kubectl patch svc metal3-metal3-ironic -n metal3-system -p '{"spec":{"type":"NodePort"}}'
```

### Step 2: Get NodePort Number

```bash
NODE_PORT=$(kubectl get svc metal3-metal3-ironic -n metal3-system -o jsonpath='{.spec.ports[?(@.port==6385)].nodePort}')
echo "NodePort: $NODE_PORT"
```

### Step 3: Test if NodePort is Accessible

On macOS with Kind, NodePort might not be directly accessible. Test:
```bash
curl http://192.168.1.242:$NODE_PORT/v1
```

If it works → Use `http://192.168.1.242:$NODE_PORT` in Ironic ConfigMap
If it doesn't → Use port forwarding to localhost, then socat to host IP

### Step 4: Configure Ironic

```bash
# If NodePort is directly accessible:
kubectl patch configmap ironic -n metal3-system --type merge -p "{\"data\":{\"IRONIC_EXTERNAL_HTTP_URL\":\"http://192.168.1.242:$NODE_PORT\"}}"

# If NodePort needs port forwarding:
# 1. Port forward: kubectl port-forward -n metal3-system svc/metal3-metal3-ironic 6385:6385 &
# 2. Socat: socat TCP-LISTEN:6385,fork,reuseaddr TCP:localhost:6385 &
# 3. Use: http://192.168.1.242:6385
```

## Alternative: Use the Service ClusterIP with Port Forwarding

If NodePort doesn't work, use ClusterIP + reliable port forwarding:

1. **Keep service as ClusterIP or NodePort**
2. **Set up persistent port forwarding:**
   ```bash
   # Create a script that keeps port forwarding alive
   while true; do
     kubectl port-forward -n metal3-system svc/metal3-metal3-ironic 6385:6385
     sleep 1
   done
   ```
3. **Use socat to expose on host IP:**
   ```bash
   socat TCP-LISTEN:6385,fork,reuseaddr TCP:localhost:6385
   ```
4. **Configure Ironic:**
   ```bash
   kubectl patch configmap ironic -n metal3-system --type merge -p '{"data":{"IRONIC_EXTERNAL_HTTP_URL":"http://192.168.1.242:6385"}}'
   ```

## What We Know Works

- Port forwarding DOES work (we've tested it)
- The issue is keeping it running reliably
- sushy-tools CAN reach Ironic when port forwarding is active

## Recommended Approach

**Use a system service (launchd on macOS) to keep port forwarding running:**

1. Create a launchd plist to keep port forwarding alive
2. Use socat to expose on host IP
3. Configure Ironic to use host IP
4. This is more reliable than manual port forwarding

