# motion3d — the prototypes behind the Motion tab's 3D cameras

The app does all of this itself now (`MotionPose3D.swift`, `MotionStage.swift`,
`MotionStudio.produce3D`). These are the three scripts it was worked out with,
kept because they run by hand, one step at a time, which the app does not.

    pose3d.swift   Vision's 3D body pose for N frames of a video: the joints in the
                   pelvis's frame, and the camera matrix                       -> pose3d.json
    world.py       the repairs: bad frames un-mirrored, un-swapped or dropped;
                   the pelvis put where Vision says it is, depth averaged; the
                   old camera's tilt undone; planted feet as a gentle correction -> motion3d.json
    stage.py       Blender, headless: a blockout set, a capsule mannequin keyed
                   on every frame, a camera path, depth of every frame (near is
                   white) and the first frame plainly lit
    preview.py     the same scene plainly lit, every fourth frame, small — to look
                   at a tracked movement before spending five minutes filming it

    swiftc -O pose3d.swift -o pose3d
    ./pose3d reference.mp4 30 97 24 pose3d.json          # start second, frames, fps
    python3 world.py pose3d.json motion3d.json
    B=~/.kinclaw/blender/Blender.app/Contents/MacOS/Blender
    $B -b -P preview.py -- motion3d.json view static open
    $B -b -P stage.py -- motion3d.json out orbit park

`world.py` and `MotionPose3D.world` agree to the last digit on the two clips
they were checked on (a standing form, and Brush Knee with its step and turn).
`stage.py` is embedded word for word in `MotionStage.swift` (`script`): change
one, change the other.

Then: the image editor re-renders `out/blockout-first.png` as a photograph with
her in it ("do not move anything"), and the video model is given that still and
the depth frames as its control video.
