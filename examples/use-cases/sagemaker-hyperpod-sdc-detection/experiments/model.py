"""Llama-style decoder with optional manual tensor parallelism (Megatron-style), all-gather-KV
context parallelism, and top-1 MoE MLPs with expert parallelism. Plain PyTorch only."""
import math

import torch
import torch.distributed as dist
import torch.distributed.nn.functional as dnf
import torch.nn as nn
import torch.nn.functional as F


class _CopyToTP(torch.autograd.Function):
    """Identity forward, all-reduce over the TP group in backward (Megatron 'f')."""

    @staticmethod
    def forward(ctx, x, group):
        ctx.group = group
        return x

    @staticmethod
    def backward(ctx, g):
        g = g.contiguous().clone()
        dist.all_reduce(g, group=ctx.group)
        return g, None


class _ReduceFromTP(torch.autograd.Function):
    """All-reduce over the TP group in forward, identity backward (Megatron 'g')."""

    @staticmethod
    def forward(ctx, x, group):
        x = x.contiguous().clone()
        dist.all_reduce(x, group=group)
        return x

    @staticmethod
    def backward(ctx, g):
        return g, None


class RMSNorm(nn.Module):
    def __init__(self, d, eps=1e-5):
        super().__init__()
        self.weight = nn.Parameter(torch.ones(d))
        self.eps = eps

    def forward(self, x):
        xf = x.float()
        return (xf * torch.rsqrt(xf.pow(2).mean(-1, keepdim=True) + self.eps) * self.weight).to(x.dtype)


def rope_cache(S, hd, device):
    inv = 1.0 / (10000 ** (torch.arange(0, hd, 2, device=device, dtype=torch.float32) / hd))
    t = torch.arange(S, device=device, dtype=torch.float32)
    f = torch.outer(t, inv)
    return torch.cos(f), torch.sin(f)


def apply_rope(x, cos, sin):
    # x [B, h, S, hd]; cos/sin [S, hd/2]
    x1, x2 = x[..., 0::2], x[..., 1::2]
    c, s = cos.to(x.dtype), sin.to(x.dtype)
    o1 = x1 * c - x2 * s
    o2 = x1 * s + x2 * c
    return torch.stack([o1, o2], -1).flatten(-2)


class Attn(nn.Module):
    def __init__(self, D, H, tp=1, tp_group=None, cp_group=None):
        super().__init__()
        self.tp, self.tp_group, self.cp_group = tp, tp_group, cp_group
        self.hl, self.hd = H // tp, D // H
        w = self.hl * self.hd
        self.q = nn.Linear(D, w, bias=False)
        self.k = nn.Linear(D, w, bias=False)
        self.v = nn.Linear(D, w, bias=False)
        self.o = nn.Linear(w, D, bias=False)

    def forward(self, x, rope, pos0):
        if self.tp > 1:
            x = _CopyToTP.apply(x, self.tp_group)
        B, S, _ = x.shape
        q = self.q(x).view(B, S, self.hl, self.hd).transpose(1, 2)
        k = self.k(x).view(B, S, self.hl, self.hd).transpose(1, 2)
        v = self.v(x).view(B, S, self.hl, self.hd).transpose(1, 2)
        cos, sin = rope
        q = apply_rope(q, cos[pos0:pos0 + S], sin[pos0:pos0 + S])
        k = apply_rope(k, cos[pos0:pos0 + S], sin[pos0:pos0 + S])
        if self.cp_group is not None:
            k = torch.cat(dnf.all_gather(k.contiguous(), group=self.cp_group), dim=2)
            v = torch.cat(dnf.all_gather(v.contiguous(), group=self.cp_group), dim=2)
            qpos = torch.arange(pos0, pos0 + S, device=x.device)
            kpos = torch.arange(k.shape[2], device=x.device)
            mask = kpos[None, :] <= qpos[:, None]
            y = F.scaled_dot_product_attention(q, k, v, attn_mask=mask)
        else:
            y = F.scaled_dot_product_attention(q, k, v, is_causal=True)
        y = self.o(y.transpose(1, 2).reshape(B, S, self.hl * self.hd))
        if self.tp > 1:
            y = _ReduceFromTP.apply(y, self.tp_group)
        return y


class MLP(nn.Module):
    def __init__(self, D, F_, tp=1, tp_group=None):
        super().__init__()
        self.tp, self.tp_group = tp, tp_group
        self.gate = nn.Linear(D, F_ // tp, bias=False)
        self.up = nn.Linear(D, F_ // tp, bias=False)
        self.down = nn.Linear(F_ // tp, D, bias=False)

    def forward(self, x):
        if self.tp > 1:
            x = _CopyToTP.apply(x, self.tp_group)
        y = self.down(F.silu(self.gate(x)) * self.up(x))
        if self.tp > 1:
            y = _ReduceFromTP.apply(y, self.tp_group)
        return y


class Expert(nn.Module):
    def __init__(self, D, F_):
        super().__init__()
        self.gate = nn.Linear(D, F_, bias=False)
        self.up = nn.Linear(D, F_, bias=False)
        self.down = nn.Linear(F_, D, bias=False)

    def forward(self, x):
        return self.down(F.silu(self.gate(x)) * self.up(x))


class MoE(nn.Module):
    """Top-1 MoE, one expert per GPU of the EP group (= node). Fixed capacity per
    (source rank, expert) so all_to_all uses equal splits."""

    def __init__(self, D, F_, ep_group, ep_size, cap_factor=1.25):
        super().__init__()
        self.E, self.ep_group, self.cap = ep_size, ep_group, cap_factor
        self.router = nn.Linear(D, self.E, bias=False)
        self.expert = Expert(D, F_)
        self.last_drop = 0.0

    def forward(self, x):
        B, S, D = x.shape
        t = x.reshape(B * S, D)
        T, E = t.shape[0], self.E
        C = int(math.ceil(self.cap * T / E))
        prob = torch.softmax(self.router(t).float(), -1)
        top = prob.argmax(-1)
        gate = prob.gather(1, top[:, None]).squeeze(1)
        onehot = F.one_hot(top, E)
        # Switch-Transformer load-balancing loss: E * sum_e(fraction routed to e * mean prob of e)
        self.aux = E * (onehot.float().mean(0) * prob.mean(0)).sum()
        pos = (torch.cumsum(onehot, 0) - 1).gather(1, top[:, None]).squeeze(1)
        keep = pos < C
        self.last_drop = float(1.0 - keep.float().mean())
        idx = (top * C + pos)[keep]
        send = t.new_zeros(E * C, D).index_copy(0, idx, t[keep])
        recv = torch.empty_like(send)
        recv = dnf.all_to_all_single(recv, send, group=self.ep_group)     # [E sources * C, D]
        y = self.expert(recv)
        back = torch.empty_like(y)
        back = dnf.all_to_all_single(back, y, group=self.ep_group)        # [E experts * C, D]
        out = t.new_zeros(T, D).index_copy(0, keep.nonzero().squeeze(1),
                                           (back[idx] * gate[keep, None].to(back.dtype)).to(t.dtype))
        return out.view(B, S, D)


class Block(nn.Module):
    def __init__(self, c, tp=1, tp_group=None, cp_group=None, moe=None):
        super().__init__()
        self.n1 = RMSNorm(c["D"])
        self.attn = Attn(c["D"], c["H"], tp, tp_group, cp_group)
        self.n2 = RMSNorm(c["D"])
        if moe is not None:
            self.mlp = MoE(c["D"], c["FFN"] // 2, moe["group"], moe["size"])
        else:
            self.mlp = MLP(c["D"], c["FFN"], tp, tp_group)

    def forward(self, x, rope, pos0):
        x = x + self.attn(self.n1(x), rope, pos0)
        return x + self.mlp(self.n2(x))


class Llama(nn.Module):
    def __init__(self, c, tp=1, tp_group=None, cp_group=None, moe=None, layers=None,
                 has_emb=True, has_head=True):
        super().__init__()
        self.c = c
        L = c["L"] if layers is None else layers
        self.emb = nn.Embedding(c["V"], c["D"]) if has_emb else None
        self.blocks = nn.ModuleList([Block(c, tp, tp_group, cp_group, moe) for _ in range(L)])
        self.norm = RMSNorm(c["D"]) if has_head else None
        self.head = nn.Linear(c["D"], c["V"], bias=False) if has_head else None
        cos, sin = rope_cache(c["S"], c["D"] // c["H"], "cuda")
        self.register_buffer("cos", cos, persistent=False)
        self.register_buffer("sin", sin, persistent=False)

    def run_blocks(self, h, pos0=0):
        for b in self.blocks:
            h = b(h, (self.cos, self.sin), pos0)
        return h

    def forward(self, x, pos0=0):
        h = self.emb(x) if self.emb is not None else x
        h = self.run_blocks(h, pos0)
        if self.head is None:
            return h
        return self.head(self.norm(h))


@torch.no_grad()
def init_full(model, c, seed=1234):
    """Deterministic init of an unsharded model (same on every rank)."""
    g = torch.Generator(device="cuda")
    g.manual_seed(seed)
    std = 0.02
    for name, p in model.named_parameters():
        if p.dim() == 1:
            p.fill_(1.0)
        elif name.endswith(("attn.o.weight", "mlp.down.weight", "expert.down.weight")):
            p.normal_(0.0, std / math.sqrt(2 * c["L"]), generator=g)
        else:
            p.normal_(0.0, std, generator=g)
