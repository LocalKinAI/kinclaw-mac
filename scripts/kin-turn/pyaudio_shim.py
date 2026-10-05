"""Stand-in for PyAudio on the box: the turn service feeds MaAI audio it
receives over the network (MaaiInput.Chunk) and never opens a microphone,
so only the names MaAI reads at import time need to exist."""
paFloat32 = 1
paInt16 = 8


class PyAudio:
    def __init__(self, *args, **kwargs):
        raise RuntimeError("no microphone on the box: feed audio through MaaiInput.Chunk")
