"""A Conv3d done as a sum of Conv2d over the kernel's depth — the same numbers, but on
Apple's GPU 2D convolution is fast and a 7x7x7 3D one is not (543 ms of Ditto's 583 ms
warp, 2026-10-02). Swaps every such Conv3d in a module."""
import torch, torch.nn as nn, torch.nn.functional as F

class Conv3dAs2d(nn.Module):
    def __init__(self, conv: nn.Conv3d):
        super().__init__()
        assert conv.groups == 1 and conv.dilation == (1, 1, 1) and conv.stride == (1, 1, 1)
        self.kd = conv.kernel_size[0]
        self.pd, self.ph, self.pw = conv.padding
        self.weight = conv.weight          # (out, in, kd, kh, kw)
        self.bias = conv.bias

    def forward(self, x):                  # (n, c, d, h, w)
        n, c, d, h, w = x.shape
        if self.pd:
            x = F.pad(x, (0, 0, 0, 0, self.pd, self.pd))
        out = None
        for k in range(self.kd):
            s = x[:, :, k:k + d]                                   # (n, c, d, h, w)
            s = s.permute(0, 2, 1, 3, 4).reshape(n * d, c, h, w)   # depth into the batch
            y = F.conv2d(s, self.weight[:, :, k], None, padding=(self.ph, self.pw))
            out = y if out is None else out + y
        out = out.reshape(n, d, -1, h, w).permute(0, 2, 1, 3, 4)
        if self.bias is not None:
            out = out + self.bias.view(1, -1, 1, 1, 1)
        return out.contiguous()

def swap(module, min_kernel=5):
    for name, child in module.named_children():
        if isinstance(child, nn.Conv3d) and child.kernel_size[0] >= min_kernel and child.groups == 1 \
                and child.stride == (1, 1, 1) and child.dilation == (1, 1, 1):
            setattr(module, name, Conv3dAs2d(child))
        else:
            swap(child, min_kernel)
    return module
