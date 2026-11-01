# Sofle ZMK config

ZMK firmware for a Sofle on two nice!nano v2 controllers. Every push builds
the firmware with GitHub Actions (`build.yaml` lists the targets):

| File | What it is |
| --- | --- |
| `sofle_left-nice_nano_v2-zmk.uf2` | Left half. This is the central half: it connects to the computer over USB/Bluetooth. |
| `sofle_right-nice_nano_v2-zmk.uf2` | Right half. It talks only to the left half. |
| `settings_reset-nice_nano_v2-zmk.uf2` | Wipes stored settings and Bluetooth pairings. |

## Getting the firmware

1. Push to GitHub, then open **Actions** → the latest *Build ZMK firmware* run.
2. Under **Artifacts**, download `firmware`. It lands in Downloads as `firmware.zip`.

`flash.ps1` picks up the newest `firmware*.zip` from Downloads and unpacks it
into `firmware/`, so you don't need to unzip anything yourself.

## Flashing

Double-click `flash.cmd`, or run it from a terminal with the half you want:

```powershell
.\flash.cmd left
```

Then plug in a controller and put it in bootloader mode. A brand-new nice!nano
starts in bootloader mode by itself. Otherwise, short **RST** to the **GND** pin
next to it twice quickly. The script finds the `NICENANO` drive, copies the firmware onto it and
checks that the controller rebooted. It then waits for the next controller, so
you can flash several in a row. Press Ctrl+C to stop.

## Testing a controller before soldering

The right-half firmware does nothing on its own over USB, so test **both**
controllers with the **left** firmware.

1. Run `.\flash.cmd left` and flash the controller.
2. **USB:** Windows plays the connect sound and a *Sofle* keyboard appears in
   Device Manager → Keyboards.
3. **Bluetooth:** *Sofle* shows up when you scan for devices on your phone.
4. **Pins:** open Notepad and bridge a row pin to a column pin with tweezers or
   a wire. The pin labels (`024`, `002`, ...) are printed on the board. The rows
   are the bottom 5 pins on one edge and the columns are the bottom 6 on the
   other edge (the edge with RST):

   | Row \ Column | D19 `002` | D18 `115` | D15 `113` | D14 `111` | D16 `010` | D10 `009` |
   | --- | --- | --- | --- | --- | --- | --- |
   | **D5** `024` | `` ` `` | 1 | 2 | 3 | 4 | 5 |
   | **D6** `100` | Esc | q | w | e | r | t |
   | **D7** `011` | Tab | a | s | d | f | g |
   | **D8** `104` | Shift | z | x | c | v | b |
   | **D9** `106` | Win | Alt | Ctrl | (Symbols layer) | Enter | Mute |

   Two sweeps cover all 11 matrix pins:
   - Hold one leg on **D7** and step through the columns. Notepad should show
     Tab, then `asdfg`.
   - Hold one leg on **D16** and step through the rows. Notepad should show
     `4rfv`, then Enter.

   You might get a repeated letter from the tweezers bouncing. That's normal.

If a controller passes all of this, it is fine to solder.

## After soldering

1. Flash `settings_reset` onto **both** halves. This clears any pairing left
   over from testing.
2. Flash `left` onto the left half and `right` onto the right half.
3. Turn both halves on (or reset them together) so they pair with each other.
   Then pair the left half with your computer as *Sofle*.
