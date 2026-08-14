# Zul'Aman

Map 568. `RaidZulAmanStrategy` ("zulaman") is applied automatically on
entry.

---

## The hunter is load-bearing

All six ZA "pulling boss" triggers open with:

```cpp
if (bot->getClass() != CLASS_HUNTER)
    return false;
```

**Every scripted pull in the instance is a hunter's Misdirection.** No
hunter, no scripted pulls. Bring `Fehmos` or `Ilyna`.

## The assist-tank swaps are yours

Nalorakk and Halazzi branch on `IsAssistTankOfIndex(bot, 0, true)`, a
bot self-check that requires `IsTank()`. Rule 1's conversion whisper
clears exactly that, so in a normally converted raid **nobody satisfies
it** and both swap mechanics are hand-executed.

If a ZA night ever justifies it, the same per-fight restore that ADR
`0004` prescribes for the Illidari Council would fill the role — but
unlike the Council, ZA has no multiplier suppressing taunts, so a
restored tank here **will** taunt bosses off you. Rule 1 applies in
full. Hand-execute instead.
