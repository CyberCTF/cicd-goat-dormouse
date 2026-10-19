import pytest

from dormouse import Dormouse, teatime


def test_nudge_wakes_and_records():
    d = Dormouse()
    assert d.asleep is True
    assert d.nudge("twinkle") == "twinkle"
    assert d.asleep is False
    assert d.mutters == ["twinkle"]
    d.doze()
    assert d.asleep is True


def test_teatime():
    assert teatime(3) == "room for 3 at the table"
    assert teatime(0) == "no room! no room!"
    with pytest.raises(ValueError):
        teatime(-1)
