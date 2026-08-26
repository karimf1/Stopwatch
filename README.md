# stopwatch

A 0.1-second-resolution stopwatch in Verilog-2001, driving six seven-segment
displays directly, with a five-deep lap stack you can page back through on
switches while the clock keeps running.

Five modules, 348 lines, no vendor IP and no SystemVerilog. Targets a 50 MHz
board with six HEX displays and at least seven switch inputs — an Intel DE-series
board is the obvious fit.

```
   +---+     +---+---+     +---+---+     +---+
   | H |  :  | M | M |  :  | S | S |  .  | T |     6 x active-low 7-segment
   +---+     +---+---+     +---+---+     +---+
    0-9       0-5 0-9       0-5 0-9       0-9
   hours       minutes       seconds     tenths
```

Display range is `0:00:00.0` to `9:59:59.9`, then it wraps to zero. There is no
physical colon or decimal point — those are drawn above only to show the reading.

## Controls

| input | type | effect |
|---|---|---|
| `reset` | active-high, async | clears the running time **and all five stored laps** |
| `sw_start` | level | high = counting, low = paused. Not a toggle — the count runs while it is held high |
| `sw_capture` | edge | on each 0→1 transition, pushes the current time onto the lap stack |
| `sw0 .. sw4` | level | show stored lap 1..5 instead of the live time. Priority: `sw0` wins over `sw1`, and so on |

Outputs are six independent 7-bit segment buses, one per digit — no display
multiplexing, so the board needs six real seven-segment units:

| output | digit | width |
|---|---|---|
| `hrs_display` | hours, 0-9 | `[6:0]` |
| `mins_tens_display` / `mins_ones_display` | minutes, 00-59 | `[6:0]` each |
| `secs_tens_display` / `secs_ones_display` | seconds, 00-59 | `[6:0]` each |
| `ms_display` | tenths, 0-9 | `[6:0]` |

With no `swN` asserted, the display shows live running time. Asserting one
freezes the display on a stored lap **without stopping the counter** — the timer
keeps advancing behind the switch, and dropping the switch snaps the display back
to the current time. That separation of "what is being counted" from "what is
being shown" is the design's one genuinely interesting idea, and it is the reason
the lap stack lives in its own module rather than inside the counter.

## Block diagram

```
                    +--------------------+
                    | clock_dividermain  |  23-bit counter + toggle FF
                    | / 5,000,000        |  50 MHz -> 10.000 Hz, 50% duty
                    +--------------------+
                              | clk_10hz
                              v
                    +--------------------+
                    | time_counter_dec   | <-- sw_start (enable)
                    | 10 / 60 / 60 / 10  |
                    +--------------------+
                              |
                              |  live time: hrs mins secs ms
              +---------------+-------------------+
              |                                   |
              v                                   |
     +--------------------+                       |
     | storage_values     | <-- sw_capture        |
     | 20 ms debounce     |                       |
     | rising-edge pulse  |                       |
     | 5-deep lap stack   |                       |
     +--------------------+                       |
              |                                   |
              |  5 stored laps                    |
              +---------------+-------------------+
                              |
                              v
                    +--------------------------+
     sw0..sw4 ----> | display_stored           |
                    | 6-way priority mux       |
                    | /10 and %10 digit split  |
                    +--------------------------+
                              |
                              |  6 x 4-bit BCD
                              v
                    +--------------------------+
                    | bcd_display  x 6         |
                    | case ROM, active low     |
                    +--------------------------+
                              |
                              v
                     HEX5 HEX4 ... HEX0

     clock domains:  clk_10hz drives time_counter_dec only.
                     Everything else runs on the 50 MHz clk.
```

## How it works

### clock_dividermain — 50 MHz to 10 Hz

A 23-bit counter and a toggle flip-flop. The counter runs `0 .. 2_499_999`, so
`clk_10hz` inverts every 2,500,000 input cycles and its full period is 5,000,000
cycles. At 50 MHz that is exactly 10.000 Hz with a 50% duty cycle — one tick per
tenth of a second, which is the timebase everything else is built on.

The 50 MHz figure is *implicit in that constant*, not a parameter. Feeding this
design a 100 MHz clock silently makes the stopwatch run at half speed.

### time_counter_dec — cascaded mod-N counters

Four counters chained so each rolls the next over, clocked by `clk_10hz`:

```
ms 0..9  --carry-->  secs 0..59  --carry-->  mins 0..59  --carry-->  hrs 0..9
(tenths)                                                                    |
                                                              wraps to 0 <--+
```

`enable` gates the whole chain. When it is low every register holds — there is no
`else` clause, so pause is implemented as the absence of an assignment rather
than a feedback mux, which synthesizes to the flip-flop's own clock enable.

Note that `ms` counts **tenths of a second**, not milliseconds. The name is the
one piece of the interface that lies about what it does.

### storage_values — debounce, edge detect, lap stack

Three things in one module, all clocked by the fast 50 MHz `clk`.

**The debouncer is an integrator, not a timer.** It only counts while the raw
input disagrees with the currently accepted value, and any bounce back to that
value resets the count to zero:

```
sw_capture == sw_stable  ->  db_count <= 0
sw_capture != sw_stable  ->  db_count <= db_count + 1
db_count == 999_999      ->  sw_stable <= sw_capture,  db_count <= 0
```

So the input has to hold its new state *continuously* for 1,000,000 cycles — 20 ms
at 50 MHz — before it is believed. That is the right structure: a plain "wait
20 ms then sample" timer can be fooled by a bounce train that happens to be
settled at the moment of sampling.

**The edge detector** is one delay register plus an AND:

```verilog
sw_stable_prev <= sw_stable;
assign capture_pulse = (sw_stable && !sw_stable_prev);
```

One `clk`-wide pulse on press. Releasing does nothing, and holding the button
down does not repeat — one press, one lap.

**The lap stack is a shift register**, five entries deep and 20 bits wide per
entry (4+6+6+4), so 100 flip-flops in all. On `capture_pulse` everything shifts
down one slot and the live time lands in slot 0:

```
                       lap0      lap1      lap2      lap3      lap4
  press #1  @ 3.7  ->    3.7        -         -         -         -
  press #2  @ 9.1  ->    9.1       3.7        -         -         -
  press #3  @ 12.4 ->   12.4       9.1       3.7        -         -
  press #6  @ 31.0 ->   31.0      27.2      22.8      18.5      15.3
                                                                  ^
                                                     lap #1 has fallen off the end
```

The stack keeps the five *most recent* laps and silently discards older ones.
Because all five shifts are non-blocking assignments in one `always` block, they
happen simultaneously off the same edge — this is the standard idiom, and writing
it with blocking assignments would collapse the whole stack to one value.

### display_stored — priority mux and digit split

A combinational `if / else if` chain selects one of six sources (five laps, or
the live time as the fall-through), which synthesizes to a priority mux. Then the
two-digit fields are split for display:

```verilog
wire [3:0] mins_tens = mins_out / 10;
wire [3:0] mins_ones = mins_out % 10;
```

Division by a constant is synthesizable — the tool turns it into a shift-and-add,
not a real divider — but it is still arithmetic that does not need to exist. See
[Improvements](#improvements).

### bcd_display — active-low segment decoder

A `case` statement over 4 bits, which infers a small combinational ROM. The
encoding is active-low with bit order `{g, f, e, d, c, b, a}`:

| value | `seg[6:0]` | lit segments |
|---|---|---|
| 0 | `1000000` | a b c d e f |
| 1 | `1111001` | b c |
| 8 | `0000000` | all |
| default | `1111111` | blank |

Active-low means these are common-anode displays, which is what the HEX outputs
on Intel DE boards expect. The `default` branch blanks the digit — inputs above 9
cannot occur given the counter ranges, but the branch is there so the case is
full and no latch is inferred.

## Methods used

Named plainly, since this is what the project is a demonstration of:

| technique | where |
|---|---|
| Clock division by counter + toggle FF | `clock_dividermain` |
| Cascaded mod-N counters with roll-over carry | `time_counter_dec` |
| Clock-enable gating for pause (no feedback mux) | `time_counter_dec` |
| Integrating switch debouncer | `storage_values` |
| Rising-edge detection via delay register | `storage_values` |
| Shift-register history buffer (FIFO-like stack) | `storage_values` |
| Priority multiplexer from an `if/else if` chain | `display_stored` |
| Combinational ROM via full `case` | `bcd_display` |
| Structural hierarchy — five modules, one top-level integrator | `stopwatch_draft` |
| Asynchronous active-high reset throughout | all sequential modules |
| Blocking `=` in `always @(*)`, non-blocking `<=` in clocked blocks | throughout |

## Numbers

| quantity | value | derivation |
|---|---|---|
| assumed input clock | 50 MHz | implied by the divider constant |
| tick rate | 10.000 Hz | 50 MHz / 5,000,000 |
| resolution | 100 ms | one tick |
| full-scale range | 9:59:59.9 | then wraps to 0:00:00.0 |
| debounce window | 20 ms | 1,000,000 cycles @ 50 MHz |
| capture pulse width | 20 ns | one `clk` cycle |
| lap stack | 5 x 20 bits | 100 flip-flops |
| display digits | 6 | H MM SS T |

## Known limitations

Named rather than hidden. These are properties of the design as written, not
speculation.

- **Nothing works in simulation until `reset` is pulsed.** `clk_10hz`,
  `db_count` and `sw_stable` have no reset-independent initial value, so they
  start as `X`. `clk_10hz <= ~clk_10hz` on an `X` stays `X` forever, and
  `db_count + 1` on an `X` never reaches the compare value. On a real FPGA the
  power-up state saves this; a testbench must assert reset first.
- **`clk_10hz` is a fabric-generated clock, not a clock-enable.** It comes off a
  logic flip-flop, not a global clock buffer, so it picks up routing skew and
  needs an explicit derived-clock constraint for timing analysis. This is the
  single biggest structural criticism of the design.
- **The lap capture crosses a clock domain unsynchronized.** `time_counter_dec`
  runs on `clk_10hz`; `storage_values` samples its 20-bit output on the 50 MHz
  `clk`. If `capture_pulse` lands inside the setup/hold window of a `clk_10hz`
  edge, some bits can be captured before the tick and others after — a stored lap
  of `1:59.9` becoming `2:59.9`. The odds are roughly one 20 ns window per 100 ms
  tick, so about 2 in 10 million per capture: rare enough to never show up in
  testing, real enough to be wrong.
- **No reset synchronizer.** Reset is asserted asynchronously and released
  asynchronously, so different flip-flops can leave reset on different cycles.
- **`sw_start`, `sw_capture` and `sw0..sw4` go straight into logic.** No two-flop
  synchronizer on any asynchronous input. The debouncer masks most of the risk on
  `sw_capture`, and `sw0..sw4` are purely combinational so the worst case is a
  flickering digit, but `sw_start` is sampled by a flip-flop and can go
  metastable.
- **A held `sw_capture` across reset release fires a spurious lap.** Reset forces
  `sw_stable` to 0; if the button is already down, the debouncer times out 20 ms
  later and captures `0:00:00.0`.
- **`reset` is the only way to clear laps.** There is no separate lap-clear, so
  clearing history necessarily throws away the running time too.
- **Start/stop is a level, not a toggle.** `sw_start` must be a slide switch. Wire
  a momentary push-button to it and the stopwatch only runs while your finger is
  on it.
- **Hours is a single digit.** The counter wraps at 10 hours with no carry-out and
  no overflow flag, so a wrap is indistinguishable from a fresh start.
- **`display_stored` has an unused `clk` port.** It is entirely combinational.
  Lint will flag it.
- **Multiple `swN` switches on at once is not an error.** Priority silently picks
  the lowest-numbered one; there is no indication which lap you are looking at.
- **No leading-zero blanking** and no decimal point control — `0:00:03.7` shows a
  literal leading `0:00`.
- **No testbench.** None of the above is verified by anything but inspection.

## Improvements

Roughly in order of how much they are worth doing.

**1. Replace the divided clock with a clock-enable strobe.** Have
`clock_dividermain` emit a one-cycle `tick_10hz` pulse instead of a 10 Hz square
wave, and clock `time_counter_dec` on the 50 MHz `clk` with `tick_10hz` as its
enable. This is a small edit that fixes three problems at once: the whole design
becomes single-clock, the clock-domain-crossing bug on lap capture disappears
entirely because the counter and the lap stack now share a clock, and timing
analysis stops needing a derived-clock constraint. If only one thing on this list
gets done, it should be this one.

**2. Write a testbench.** Icarus Verilog is free and the design is small enough
to verify exhaustively. The cases worth checking: roll-over at 9.9→10.0,
59.9→1:00.0 and 9:59:59.9→0:00:00.0; pause holding the count with no drift;
capture during a roll-over; a sixth capture pushing the oldest lap off the end;
`swN` priority; reset from mid-count. Speed up simulation by parameterizing the
divider (see 4) so a tick costs tens of cycles rather than five million.

**3. Count in BCD and delete the arithmetic.** Store seconds and minutes as two
mod-10 / mod-6 digits instead of one 0–59 value. The `/ 10` and `% 10` in
`display_stored` vanish, the digits feed `bcd_display` directly, and the carry
chain gets simpler rather than more complex. This is the standard way these are
built.

**4. Parameterize the constants.** `2_499_999` and `999_999` should be
`localparam DIV = CLK_HZ / 20 - 1` and `localparam DB = CLK_HZ / 50 - 1`, derived
from a `parameter CLK_HZ = 50_000_000`. The design then ports to a 100 MHz board
by changing one number, and a testbench can override it to something small.

**5. Add a synchronizer on every asynchronous input**, and an async-assert /
sync-deassert reset synchronizer. Both are three-line modules and both are things
a reviewer will look for.

**6. Pack the port lists into vectors.** `sw0..sw4` becomes `input [4:0] sw`, and
the twenty `*_prevN` wires become four flat buses (`[19:0] hrs_laps`, and so on)
sliced with `hrs_laps[4*i +: 4]`. The `display_stored` mux collapses from a
30-line `if/else if` chain to a `case` over a priority-encoded index, and the
top-level instantiation loses about forty lines of port connections. Verilog-2001
cannot pass unpacked arrays through ports; flat vectors are the portable way, or
move to SystemVerilog and use real arrays.

**7. Make start/stop a proper toggle.** Debounce `sw_start` with the same
debouncer already written for `sw_capture`, edge-detect it, and flip a `running`
register on each press. Then it works with a push-button, which is what a
stopwatch actually wants. Factoring the debouncer out of `storage_values` into
its own reusable module is the enabling step.

**8. Add a separate lap-clear**, and a second-digit for hours with an overflow
flag so a wrap is visible.

**9. Show which lap is being displayed.** With `sw0..sw4` collapsed to a bus,
the index is already computed — putting it on a spare LED or blanking a digit to
mark "this is history, not live" removes the ambiguity of looking at a frozen
display.

**10. Board plumbing.** A pin-assignment file, a `.qsf`/constraints file, and a
top-level wrapper naming the real board signals (`MAX10_CLK1_50`, `KEY[0]`,
`SW[9:0]`, `HEX0..HEX5`) so the project builds without manual pin entry.

## Repo layout

```
stopwatch/
  rtl/    stopwatch_draft.v    all five modules
  README.md
```

The five modules currently share one file. Splitting them one-per-file — as
`clock_divider.v`, `time_counter.v`, `lap_store.v`, `display_mux.v`,
`seg_decode.v` — is worth doing alongside improvement 6, since that is the edit
that touches every port list anyway.
