"""Stand-in for pygame on the box: MaAI uses it only to play a wav file
aloud (MaaiInput.Wav), which the turn service never does."""


class _Mixer:
    def init(self, *args, **kwargs):
        raise RuntimeError("no sound output on the box")


mixer = _Mixer()
