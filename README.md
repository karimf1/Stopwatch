# stopwatch

A 0.1-second-resolution stopwatch in Verilog-2001, driving six seven-segment
displays directly, with a five-deep lap stack you can page back through while the
clock keeps running.


```
   +---+     +---+---+     +---+---+     +---+
   | H |  .  | M | M |  .  | S | S |  .  | T |     6 x active-low 7-segment
   +---+     +---+---+     +---+---+     +---+
    0-9       0-5 0-9       0-5 0-9       0-9
   hours       minutes       seconds     tenths
```

Range is `0:00:00.0` to `9:59:59.9`, then it wraps and latches a sticky
`overflow` flag so the wrap is visible rather than silent.

## Controls

| input | type | effect |
|---|---|---|
| `reset` | async, active high | clears everything: time, laps, and the run state |
| `btn_start_stop` | momentary | each press toggles between running and stopped |
| `btn_lap` | momentary | each press pushes the current time onto the lap stack |
| `clr` | level | holds time and laps at zero. Does **not** stop the count -- this is "restart", not "stop" |
| `sw_view[i]` | level | show stored lap `i` instead of the live time. Lowest asserted index wins |

Viewing a lap freezes the display **without stopping the counter** -- the timer
keeps advancing behind the switch, and dropping the switch snaps the display back
to the current time. That separation of "what is being counted" from "what is
being shown" is the design's one genuinely interesting idea, and it is why the
lap stack is its own module rather than something bolted into the counter.

A slot that has never been written blanks the display rather than showing a
plausible-looking `0:00:00.0`.

| output | meaning |
|---|---|
| `hrs_display`, `mins_tens_display`, `mins_ones_display`, `secs_tens_display`, `secs_ones_display`, `tenths_display` | one `[6:0]` active-low segment bus per digit |
| `running` | counting |
| `overflow` | sticky: has wrapped past 9:59:59.9 |
| `viewing_lap`, `view_index[2:0]` | a lap is on the display, and which slot it came from |

## Block diagram

Everything below runs on `clk`. There is no second clock.

```
                    reset ---> reset_sync ---> rst   (used synchronously below)

           btn_start_stop ---> debounce ---> rise ---> run toggle FF ---> running
                  btn_lap ---> debounce ---> rise ---> push
                      clr ---> sync2    ---> clr_s
             sw_view[4:0] ---> sync2 x5 ---> sel[4:0]

                                  running
                                     |  restart on the press that starts it
                                     v
                          +----------------------+
                          | tick_gen             |
                          | / 5,000,000          |
                          +----------------------+
                                     | tick   one clk wide, 10 Hz
                                     v
                          +----------------------+
                          | time_counter         | <--- clr_s
                          | 6 BCD digits         |
                          +----------------------+
                                     | live [23:0]
              +----------------------+---------------------+
              |                                            |
              v                                            |
   +----------------------+                                |
   | lap_store            | <--- push, clr_s               |
   | 5 x 24 bits + valid  |                                |
   +----------------------+                                |
              | laps, valid                                |
              +----------------------+---------------------+
                                     |
                                     v
                          +--------------------------+
             sel[4:0] --->| display_mux              |
                          | priority, blank-if-empty |
                          +--------------------------+
                                     | 6 x 4-bit BCD
                                     v
                          +--------------------------+
                          | seg_decode  x 6          |
                          +--------------------------+
                                     |
                                     v
                              HEX5  ...  HEX0
```

## How it works

### tick_gen -- a strobe, not a divided clock

The counter is not clocked by a divided clock. `tick_gen` emits a **one-cycle
enable pulse** every `CLK_HZ / TICK_HZ` cycles, and `time_counter` runs on the
full-rate `clk` with that pulse as its enable.

This is the central change from v1 and it fixes three things at once: the design
becomes single-clock so the lap-capture clock-domain crossing stops existing, no
derived-clock constraint is needed for timing analysis, and every flop stays on
the global clock network instead of hanging off a routed logic output.

`restart` zeroes the divider phase, and the top level pulses it on the press that
*starts* the stopwatch. Without that, the first tenth would represent somewhere
between 0 and 100 ms of real elapsed time, depending on where a free-running
divider happened to be.

### time_counter -- BCD digits, no division

Six 4-bit digits, each already in the form its decoder wants:

```
tenths 0..9 --carry--> secs 0..59 --carry--> mins 0..59 --carry--> hrs 0..9
                                                                       |
                                                         wraps to 0 <--+
```

v1 kept seconds and minutes as 0-59 binary and split them for display with
`/ 10` and `% 10`. Counting in BCD deletes that arithmetic entirely.

The carries are combinational ANDs off the digit-at-max comparisons, so this is
not a ripple counter: every digit updates on the same clock edge, and the chain
is one cycle deep rather than six.

```verilog
wire c_t  = tick & run;
wire c_so = c_t  & t_max;
wire c_st = c_so & so_max;
wire c_mo = c_st & st_max;
wire c_mt = c_mo & mo_max;
wire c_h  = c_mt & mt_max;
wire wrap = c_h  & h_max;
```

Pause is the absence of an assignment rather than a feedback mux, which
synthesizes to the flip-flop's own clock enable. `wrap` latches the sticky
`overflow` output.

### debounce -- synchronize, integrate, detect

One reusable module, instantiated twice, replacing the debouncer v1 had
hand-inlined into its lap store.

The debouncer is an **integrator, not a timer**. The counter only runs while the
raw input disagrees with the currently accepted level, and any bounce back to
that level restarts it from zero, so the input must hold its new state
*continuously* for `DEBOUNCE_MS`. A plain "wait 20 ms then sample" timer can be
fooled by a bounce train that happens to be settled at the sampling instant; this
cannot. `tb_debounce` checks that with 12-cycle bounce trains on both edges.

Two details that are not decoration:

**The input goes through a `sync2` first**, so no asynchronous pin ever reaches a
flop directly.

**Out of reset, `level` loads the synchronized pin rather than 0.** That single
line is what stops a button already held down at reset release from looking like
a fresh press. v1 got this wrong and captured a lap nobody asked for.

### lap_store -- indexed array behind a flat port

Same shift-stack idea as v1, newest in slot 0, oldest falling off the end:

```
                       lap0      lap1      lap2      lap3      lap4
  press #1  @ 3.7  ->    3.7        -         -         -         -
  press #2  @ 9.1  ->    9.1       3.7        -         -         -
  press #3  @ 12.4 ->   12.4       9.1       3.7        -         -
  press #6  @ 31.0 ->   31.0      27.2      22.8      18.5      15.3
                                                                  ^
                                                     lap #1 has fallen off the end
```

Written as an indexed array with a `for` loop instead of twenty hand-written
assignments. Every right-hand side reads the pre-edge value, so all five slots
move simultaneously -- the standard non-blocking idiom, and the reason this
cannot be written with blocking assignments.

Verilog-2001 cannot pass an unpacked array through a port, so the stack is
flattened into one vector and sliced with a constant-width part select
(`laps[i*TW +: TW]`). That is the portable alternative to v1's twenty separate
ports.

A `valid` bitmap tracks which slots hold real captures, so an empty slot can
blank rather than read as `0:00:00.0`.

### display_mux and seg_decode

`display_mux` runs its selection loop **downwards**, so slot 0 is assigned last
and therefore wins -- same priority as v1's `if / else if` chain, but off a bus,
so lap depth costs no source lines.

`seg_decode` keeps v1's active-low encoding, bit order `{g,f,e,d,c,b,a}`, with a
`blank` input added:

| value | `seg[6:0]` | lit segments |
|---|---|---|
| 0 | `1000000` | a b c d e f |
| 1 | `1111001` | b c |
| 8 | `0000000` | all |
| blank / default | `1111111` | none |

`tb_stopwatch_top` decodes these patterns back into digits and checks the reading
end to end, so the display path is verified rather than assumed.

### de10_lite -- board wrapper

Board polarity and pin names are kept out of the core. `KEY[1:0]` are active-low
momentary buttons and get inverted here; `SW[9]` is reset, `SW[8]` is clear,
`SW[4:0]` select laps.

The DE10-Lite HEX ports are 8 bits -- `[6:0]` segments plus `[7]` decimal point
-- so three decimal points are lit permanently as the field separators v1 had no
way to drive:

```
        H . M M . S S . T
        ^       ^     ^
    HEX5[7] HEX3[7] HEX1[7]
```

## Methods used

| technique | where |
|---|---|
| Clock-enable strobe generation (single clock domain) | `tick_gen` |
| Divider phase alignment to an event | `tick_gen`, `stopwatch_top` |
| Cascaded BCD counters with look-ahead carry | `time_counter` |
| Clock-enable gating for pause (no feedback mux) | `time_counter` |
| Async-assert / sync-deassert reset synchronizer | `reset_sync` |
| Two-flop CDC synchronizer on every async input | `sync2` |
| Integrating switch debouncer | `debounce` |
| Rising/falling edge detection via delay register | `debounce` |
| Toggle flip-flop for run state | `stopwatch_top` |
| Shift-register history buffer with a valid bitmap | `lap_store` |
| Array-behind-flat-port for Verilog-2001 array ports | `lap_store` |
| Priority multiplexer from a reverse-order loop | `display_mux` |
| Combinational ROM via full `case` | `seg_decode` |
| Parameterized design with derived timing constants | throughout |
| Board wrapper isolating pin polarity from the core | `de10_lite` |

## Numbers

At the default `CLK_HZ = 50_000_000`:

| quantity | value | derivation |
|---|---|---|
| tick rate | 10.000 Hz | `CLK_HZ / TICK_HZ` = one tick per 5,000,000 cycles |
| resolution | 100 ms | one tick |
| full-scale range | 9:59:59.9 | then wraps, `overflow` latches |
| debounce window | 20 ms | `(CLK_HZ/1000) * 20` = 1,000,000 cycles |
| divider counter | 23 bits | `clog2(5,000,000)` |
| debounce counter | 20 bits | `clog2(1,000,000)` |
| lap stack | 5 x 24 bits | 120 flops plus a 5-bit valid mask |
| display digits | 6 | H MM SS T |
| flip-flops | ~240 | hand count from the source, not a synthesis report |

Every interval is derived from `CLK_HZ`. Porting to a 100 MHz board is one
parameter, and the testbenches drop it to 1,000 or 10,000 so a tick costs
hundreds of cycles instead of five million.

## Verification

589 lines of RTL, 803 lines of testbench. Plain Verilog has no `assert` and no
classes, so the checkers are ordinary tasks and `always` blocks.

| testbench | what it establishes |
|---|---|
| `tb_time_counter` | **360,030 checks.** Walks all 360,000 tenths from `0:00:00.0` to `9:59:59.9` and past the wrap, comparing every value against an independently written model. Also: ticks ignored while paused, one advance per tick and not per clock, value frozen across 200 clocks while paused, resume from the paused value, `clr`, and that `overflow` latches exactly at the wrap and is sticky |
| `tb_debounce` | clean press and release, a glitch shorter than the window ignored, 12-cycle bounce trains on both edges producing exactly one edge each, single-cycle pulse width, and **a button held across reset release producing no edge** |
| `tb_lap_store` | shift order, a sixth push dropping the oldest, all five slots moving together, the `valid` bitmap filling and saturating, hold when `push` is low, `clr`, and `clr` winning over a simultaneous `push` |
| `tb_no_reset` | the whole design powers up defined and counts correctly **with `reset` tied low for the entire simulation** |
| `tb_stopwatch_top` | button semantics end to end: one press starts, a second stops, the value freezes, laps capture while stopped, viewing a lap does not stop the count, the display snaps back on release, an unwritten slot blanks, switch priority, `clr` zeroing time and laps while leaving the stopwatch running, reset stopping it -- plus the segment patterns decoded back into digits, and a measurement that the first tick lands **exactly** one divider period after the start press |

The exhaustive counter walk is the one worth pointing at. Roll-over bugs live at
`9.9 -> 10.0`, `59.9 -> 1:00.0` and `9:59:59.9 -> 0:00:00.0`, and checking all
360,000 values against a model rather than spot-checking three of them means
there is nowhere for an off-by-one to hide.

## The bug the testbench reproduces

`make -C sim bug` builds v1's `storage_values` and v2's `debounce` side by side,
holds the capture button down across reset release, and then does nothing:

```
Capture button held down across reset release.
Nobody presses anything after that.

v1 storage_values : lap slot 0 = 3:25:45.6
v2 debounce       : rise pulses = 0

   v1 stored a lap nobody asked for.  Bug reproduced.
   v2 produced no edge.  Fix confirmed.
```

v1 resets `sw_stable` to 0. If the button is physically down at that moment, the
debouncer sees a disagreement, counts out its 20 ms, adopts 1, and the edge
detector reports a rising edge -- a press that never happened. The fix is one
line: load the synchronized pin at reset instead of a constant.

The testbench fails if v1 *stops* showing the bug, so the demonstration cannot
quietly rot into a test of nothing.

## What changed from v1

Every drawback named in the previous version of this README, and what happened to
it.

| v1 drawback | fix | verified by |
|---|---|---|
| `clk_10hz` was a fabric-generated clock | `tick_gen` emits a clock-enable strobe; single clock domain | `tb_stopwatch_top` |
| Lap capture crossed a clock domain unsynchronized | crossing no longer exists -- counter and lap stack share `clk` | structural |
| Nothing worked in simulation until `reset` was pulsed | declaration initializers on every register | `tb_no_reset` |
| No reset synchronizer | `reset_sync`: async assert, sync deassert, minimum width guarantee | structural |
| Async inputs went straight into logic | `sync2` on every pin, including all five view switches | `tb_debounce` |
| Held `sw_capture` across reset fired a spurious lap | debouncer loads the synchronized pin out of reset | `tb_debounce`, `make bug` |
| Start/stop was a level, needed a slide switch | debounce + edge + toggle flip-flop; works with a push button | `tb_stopwatch_top` |
| `reset` was the only way to clear laps | `clr` zeroes time and laps without stopping the count | `tb_stopwatch_top` |
| `/ 10` and `% 10` in the display path | counter holds BCD digits directly | `tb_time_counter` |
| 5 switch ports + 20 lap ports | `sw_view[4:0]` bus, flat lap vector, indexed array | -- |
| `display_stored` had an unused `clk` port | gone; `display_mux` is purely combinational | lint |
| Multiple switches on gave no indication of which lap | `viewing_lap` and `view_index[2:0]` outputs | `tb_stopwatch_top` |
| An empty lap slot displayed as `0:00:00.0` | `valid` bitmap blanks unwritten slots | `tb_stopwatch_top` |
| Hard-coded `2_499_999` and `999_999` | everything derived from `CLK_HZ` | testbenches override it |
| A 10-hour wrap was indistinguishable from a fresh start | sticky `overflow` output | `tb_time_counter` |
| `ms` port name meant tenths, not milliseconds | renamed `tenths_display` | -- |
| No decimal point control | three DPs lit as field separators in the board wrapper | -- |
| No leading-zero blanking | `LZ_BLANK` parameter, **default off** -- see below | -- |
| Five modules in one file | nine modules, one per file, plus `tb/` and `sim/` | -- |
| No testbench | five testbenches, 803 lines | -- |

One of those is a deliberate non-fix. **Leading-zero blanking is implemented but
off by default**, because a stopwatch is easier to read in a fixed `H:MM:SS.T`
field than with digits appearing and disappearing as it counts. It is offered as
a parameter rather than imposed.

## Known limitations

What is still true, named rather than hidden.

- **Simulation only.** No FPGA bring-up, no timing closure, no scope traces. The
  board wrapper elaborates and lints; it has never been on a board. The
  flip-flop count is a hand count, not a synthesis report.
- **Stop is still quantized to 100 ms.** The displayed value is the number of
  *completed* tenths, so the true elapsed time is somewhere in a 100 ms band
  above it. Start no longer has this error, since the start press re-phases the
  divider; stop inherently does.
- **Both buttons carry a 20 ms debounce latency.** This mostly cancels for
  interval measurement -- start and stop are delayed equally, so the *duration*
  is unaffected -- but the stopwatch does lag the physical press.
- **Hours is still one digit**, wrapping at 10 hours. `overflow` makes the wrap
  visible, but a second hours digit needs a seventh display and the target boards
  have six.
- **`LAP_DEPTH` is capped at 8** by the 3-bit `view_index` port, and in practice
  by needing one switch per slot. A deeper stack would want a browse button and
  an index display instead of one switch each.
- **Laps are absolute times, not splits.** No subtraction, so lap-to-lap deltas
  are left to the reader.
- **Oldest laps still fall off the end silently.** That is the intended behavior
  of a fixed-depth stack, not an oversight, but nothing signals the loss.
- **Synchronizers reduce metastability, they do not eliminate it.** Two stages at
  50 MHz is the ordinary engineering answer, not a proof.
- **`clr` while running zeroes and keeps counting.** That is a choice -- it makes
  `clr` a restart rather than a stop. For stop-and-zero, press start/stop first.

