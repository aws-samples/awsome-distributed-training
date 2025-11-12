# Migration Guide: Custom Builds → NGC-Based

## Overview

Migrate from custom multi-stage builds to NGC-based lightweight approach.

### Before (Custom Builds)
```bash
# Multi-stage: nixl-aligned → dynamo-base → dynamo-vllm
./build_vllm.sh
# Time: ~45 minutes
# Size: 32.4 GB
```

### After (NGC-Based)
```bash
cd ngc-builds/vllm
./build-vllm.sh runtime
# Time: ~5 minutes
# Size: 17 GB
```

## Step-by-Step Migration

### 1. Review Current Setup

Check your current images:
```bash
docker images | grep dynamo
```

Expected output:
```
dynamo-vllm         slim    ...   32.4GB
dynamo-trtllm       slim    ...   40.7GB
nixl-aligned        latest  ...   14.2GB
dynamo-base         latest  ...   22.8GB
```

### 2. Build NGC Versions

Build new NGC-based images:
```bash
cd ngc-builds

# Build vLLM
cd vllm && ./build-vllm.sh runtime

# Build TensorRT-LLM
cd ../trtllm && ./build-trtllm.sh runtime

# Or build everything
cd ../scripts && ./build-all.sh runtime
```

### 3. Update Deployments

#### Before (Custom Image)
```yaml
image: 058264135704.dkr.ecr.us-east-2.amazonaws.com/dynamo-vllm:slim
```

#### After (NGC-Based)
```yaml
image: dynamo-vllm-ngc:runtime
```

### 4. Test New Images

Test standalone:
```bash
kubectl apply -f ngc-builds/configs/vllm-standalone.yaml
kubectl logs dynamo-vllm-ngc --tail=50
```

Test disaggregated:
```bash
kubectl apply -f ngc-builds/configs/vllm-disagg.yaml
kubectl get pods -n dynamo-cloud
```

### 5. Verify Functionality

All features work identically:
- ✅ Model loading
- ✅ Inference API
- ✅ Disaggregated serving
- ✅ NIXL/UCX networking
- ✅ ETCD coordination

### 6. Update CI/CD

#### Before
```yaml
# .github/workflows/build.yml
- name: Build dynamo-vllm
  run: ./build_vllm.sh
  timeout: 60  # 60 minutes
```

#### After
```yaml
# .github/workflows/build.yml
- name: Build dynamo-vllm-ngc
  run: cd ngc-builds/vllm && ./build-vllm.sh runtime
  timeout: 10  # 10 minutes
```

### 7. Update Registry

Push to your registry:
```bash
# Tag for your registry
docker tag dynamo-vllm-ngc:runtime your-registry/dynamo-vllm:ngc

# Push
docker push your-registry/dynamo-vllm:ngc
```

### 8. Cleanup Old Images (Optional)

After verifying everything works:
```bash
# Remove old custom builds
docker rmi dynamo-vllm:slim
docker rmi dynamo-base:latest
docker rmi nixl-aligned:latest

# This frees up ~60GB
```

## Key Differences

### Image Tags
| Custom | NGC-Based |
|--------|-----------|
| `dynamo-vllm:slim` | `dynamo-vllm-ngc:runtime` |
| `dynamo-trtllm:slim` | `dynamo-trtllm-ngc:runtime` |

### Build Commands
| Custom | NGC-Based |
|--------|-----------|
| `./build_vllm.sh` | `cd ngc-builds/vllm && ./build-vllm.sh runtime` |
| `./build_trtllm.sh` | `cd ngc-builds/trtllm && ./build-trtllm.sh runtime` |
| `./build-all-slim.sh` | `cd ngc-builds/scripts && ./build-all.sh runtime` |

### Virtual Environment
| Custom | NGC-Based |
|--------|-----------|
| `/opt/venv` | `/opt/dynamo/venv` |

Update your scripts:
```bash
# Before
source /opt/venv/bin/activate

# After
source /opt/dynamo/venv/bin/activate
```

## Rollback Plan

If you need to rollback:

1. **Keep old images** during migration period
2. **Update deployments** back to old image tags
3. **No data loss** - models/configs unchanged

```bash
# Rollback deployment
kubectl set image deployment/my-deployment \
  container=058264135704.dkr.ecr.us-east-2.amazonaws.com/dynamo-vllm:slim
```

## Benefits Summary

| Aspect | Custom | NGC | Improvement |
|--------|--------|-----|-------------|
| Build Time | 45 min | 5 min | **9x faster** |
| Image Size | 32 GB | 17 GB | **47% smaller** |
| Maintenance | High | Low | Easier |
| Updates | Manual | NGC | Automatic |
| Validation | Custom | NVIDIA | Official |

## Troubleshooting

### Issue: Model not loading
**Solution:** Check venv activation
```bash
source /opt/dynamo/venv/bin/activate  # Not /opt/venv
```

### Issue: Import errors
**Solution:** All packages pre-installed in NGC
```bash
# No need to pip install, everything included
```

### Issue: Different UCX/NIXL versions
**Solution:** NGC uses validated versions
- UCX: 1.19.0 (same)
- NIXL: 0.7.0 (same)
- No incompatibilities

## Support

- **NGC Images:** https://catalog.ngc.nvidia.com/orgs/nvidia/teams/ai-dynamo
- **Issues:** File in this repo
- **Docs:** See ngc-builds/docs/
