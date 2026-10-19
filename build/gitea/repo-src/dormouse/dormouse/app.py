"""A deliberately tiny module so the dormouse repo has something to test in CI."""

from dataclasses import dataclass, field


@dataclass
class Dormouse:
    """A sleepy guest at the tea party. Nudge it and it wakes just long enough to mutter."""

    asleep: bool = True
    mutters: list[str] = field(default_factory=list)

    def nudge(self, word: str) -> str:
        self.asleep = False
        self.mutters.append(word)
        return word

    def doze(self) -> None:
        self.asleep = True


def teatime(guests: int) -> str:
    """Return a seating note for the tea party."""
    if guests < 0:
        raise ValueError("cannot seat a negative number of guests")
    return f"room for {guests} at the table" if guests else "no room! no room!"
