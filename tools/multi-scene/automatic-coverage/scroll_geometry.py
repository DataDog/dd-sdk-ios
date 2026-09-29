"""Bind scroll controls while ignoring subpixel floating-point conversion noise."""
import math

FRAME_ABSOLUTE_TOLERANCE = 1e-6  # Points, far smaller than one display pixel.


def check(start, end, target, framework):
    def require(value, message):
        if not value:
            raise ValueError('automatic human input: '+message)

    if framework == 'UIKit':
        identifier = target['identifier']
        require(identifier and identifier != 'nil'
                and start.get('accessibility_id') == end.get('accessibility_id') == identifier,
                'scroll target identifier changed')
    frames = [start['frame_in_window'], target['frame_in_window']]
    for frame in frames:
        require(isinstance(frame, list) and len(frame) == 4
                and all(type(value) in [int, float] and math.isfinite(value) for value in frame)
                and frame[2] > 0 and frame[3] > 0, 'invalid visible frame')
    require(all(math.isclose(a, b, rel_tol=0, abs_tol=FRAME_ABSOLUTE_TOLERANCE)
                for a, b in zip(*frames)), 'gesture belongs to another visible scroll')
