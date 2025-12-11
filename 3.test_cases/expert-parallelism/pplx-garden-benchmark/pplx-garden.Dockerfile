FROM pplx-garden-dev:latest

COPY pplx-garden /app
RUN cd /app \
    && export TORCH_CMAKE_PREFIX_PATH=$(python3 -c "import torch; print(torch.utils.cmake_prefix_path)") \
    && python3 -m build --wheel \
    && python3 -m pip install /app/dist/*.whl

WORKDIR /app
