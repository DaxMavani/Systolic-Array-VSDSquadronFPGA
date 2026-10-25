"""
systolic_golden_model.py
 
Cycle-accurate Python golden reference model for a 4x4 weight-stationary
INT8 systolic array. Intended to be the self-checking golden reference
against which a SystemVerilog RTL implementation is verified.
 
Design conventions modeled
---------------------------
- Weights W (K x N, K = N = ARRAY_SIZE) are loaded stationary into the PE
  grid: PE(r, c).weight = W[r][c].
- Activations A (M x K) enter from the LEFT of each row and shift one PE
  to the right per cycle.
- Partial sums accumulate top-to-bottom: PE(r, c) adds its own
  act * weight product to the psum arriving from PE(r-1, c) (0 for r=0)
  and passes the result down to PE(r+1, c).
- Output C = A @ W (M x N) is read off the bottom row of the array.
- Activation rows are fed with a diagonal "skew" (row r delayed by r
  cycles relative to row 0) -- the standard systolic wavefront scheme
  that keeps every partial sum aligned with the correct activation as it
  moves through the grid.
- Weight preload is modeled cycle-accurately too: weights stream down
  from the top of each column, one array-row per cycle, mirroring a
  shift-register weight-load path in RTL.
 
Every PE carries a small integer "tag" alongside its activation/psum
registers, identifying which input row (m) produced that value. The
model asserts that a psum's tag always matches the act tag it is being
combined with -- this makes the model self-checking against its own
timing/skew logic, independent of the final numeric result check.
 
This file has no dependency beyond numpy and the standard library, and
is meant to be dropped straight into a verification flow: run(), then
compare_to_numpy() and/or compare_rtl_output() against RTL sim output.
"""
 
from __future__ import annotations
 
import csv
import random
from typing import List, Optional, Tuple
 
import numpy as np
 
# --------------------------------------------------------------------------
# Configuration
# --------------------------------------------------------------------------
 
ARRAY_SIZE = 4                    # 4x4 PE grid (K = N = 4)
ACT_MIN, ACT_MAX = -128, 127      # INT8 range for activations / weights
ACC_WIDTH = 32                    # accumulator bit width (INT32)
ACC_MIN = -(2 ** (ACC_WIDTH - 1))
ACC_MAX = 2 ** (ACC_WIDTH - 1) - 1
 
 
def check_int8(value: int, name: str = "value") -> int:
    if not (ACT_MIN <= value <= ACT_MAX):
        raise ValueError(f"{name}={value} outside INT8 range [{ACT_MIN},{ACT_MAX}]")
    return value
 
 
def check_acc(value: int, name: str = "accumulator") -> int:
    if not (ACC_MIN <= value <= ACC_MAX):
        raise ValueError(f"{name}={value} outside INT{ACC_WIDTH} range "
                          f"[{ACC_MIN},{ACC_MAX}] -- accumulator overflow")
    return value
 
 
# --------------------------------------------------------------------------
# Processing element
# --------------------------------------------------------------------------
 
class ProcessingElement:
    """
    One weight-stationary PE.
 
    Registers (all synchronous; updated in latch()/latch_preload() after
    the combinational compute() pass over the whole grid -- this two-phase
    split mirrors an RTL always_comb / always_ff pair and avoids
    order-of-evaluation bugs when sweeping the grid row by row):
 
      weight     stationary INT8 weight, set once during preload
      act        INT8 activation currently resident (shifts rightward)
      act_tag    input-row index (m) this activation belongs to, or None
                  for a bubble. Golden-model bookkeeping only -- has no
                  RTL equivalent, used purely for self-checking timing.
      psum       INT32 partial sum currently resident (shifts downward)
      psum_tag   tag of the psum's contributing activation; must equal
                  act_tag at the same PE/cycle whenever both are valid.
    """
 
    def __init__(self, row: int, col: int):
        self.row = row
        self.col = col
        self.weight = 0
        self.act: Optional[int] = None
        self.act_tag: Optional[int] = None
        self.psum = 0
        self.psum_tag: Optional[int] = None
 
        self._next_act: Optional[int] = None
        self._next_act_tag: Optional[int] = None
        self._next_psum = 0
        self._next_psum_tag: Optional[int] = None
        self._next_weight: Optional[int] = None
 
    # ---- weight preload path (streams down 1 row/cycle) ----
    def compute_preload(self, weight_in_from_above: Optional[int]):
        self._next_weight = weight_in_from_above
 
    def latch_preload(self):
        if self._next_weight is not None:
            self.weight = check_int8(self._next_weight, "weight (preload)")
 
    def load_weight(self, w: int):
        """Non-cycle-accurate direct weight set (used by instant loader)."""
        self.weight = check_int8(w, f"weight[{self.row}][{self.col}]")
 
    # ---- matmul path ----
    def compute(self,
                act_in: Optional[Tuple[int, int]],
                psum_in: Optional[Tuple[int, int]]):
        """
        act_in:  (value, tag) arriving from the left (or external input
                 for column 0), or None if no data is arriving this cycle.
        psum_in: (value, tag) arriving from the PE above (or None for
                 row 0, treated as psum=0).
        """
        if self.act is not None:
            product = self.act * self.weight
            base = 0 if psum_in is None else psum_in[0]
            psum_val = check_acc(base + product, f"psum[{self.row}][{self.col}]")
            psum_tag = self.act_tag
            if psum_in is not None and psum_in[1] is not None:
                assert psum_in[1] == self.act_tag, (
                    f"golden-model timing/skew bug at PE({self.row},{self.col}): "
                    f"incoming psum tag {psum_in[1]} != resident act tag {self.act_tag} "
                    f"(this indicates a bug in the skew schedule, not the RTL)")
        else:
            psum_val, psum_tag = 0, None
 
        self._next_psum = psum_val
        self._next_psum_tag = psum_tag
 
        if act_in is None:
            self._next_act, self._next_act_tag = None, None
        else:
            self._next_act, self._next_act_tag = act_in
 
    def latch(self):
        self.act, self.act_tag = self._next_act, self._next_act_tag
        self.psum, self.psum_tag = self._next_psum, self._next_psum_tag
 
 
# --------------------------------------------------------------------------
# 4x4 systolic array
# --------------------------------------------------------------------------
 
class SystolicArray4x4:
    """Cycle-accurate weight-stationary systolic array golden model."""
 
    def __init__(self, size: int = ARRAY_SIZE):
        self.size = size
        self.pes = [[ProcessingElement(r, c) for c in range(size)] for r in range(size)]
        self.cycle = 0
        self.trace: List[dict] = []
 
        # ---- corner-case bookkeeping (mirrors RTL controller hazards) ----
        # weights_loaded: guards corner case #12/"start at wrong time" analog
        #   -- run_matmul() must not be reachable before a preload completes,
        #   the same way S_RUN must not be reachable before preload_done.
        # _computing: guards corner case #13 "weight loading while computing"
        #   -- preload_weights()/load_weights_instant() must not be callable
        #   while a matmul is in flight, the same way weight_load_en and
        #   activation_enable must never overlap in the controller FSM.
        self.weights_loaded = False
        self._computing = False
 
    def reset(self):
        self.__init__(self.size)
 
    # ------------------------------------------------------------------
    # Weight preload
    # ------------------------------------------------------------------
    def preload_weights(self, W: np.ndarray, log_phase: str = "PRELOAD"):
        """
        Stream weight matrix W (size x size) into the grid from the top,
        one array-row per cycle. After `size` cycles, PE(r, c).weight ==
        W[r][c] for every PE, and weights stay stationary from then on.
        """
        if self._computing:
            raise RuntimeError(
                "preload_weights() called while a matmul is in flight -- "
                "models the RTL hazard of weight_load_en and "
                "activation_enable asserting in the same cycle (corner "
                "case: weight loading during compute)")
        assert W.shape == (self.size, self.size), "weight matrix must be size x size"
        for r in range(self.size):
            for c in range(self.size):
                check_int8(int(W[r, c]), f"W[{r}][{c}]")
 
        # injected[t][c] is pushed into the top of column c at cycle t,
        # chosen so PE(r,c) == W[r][c] after `size` cycles of shifting.
        injected = [[int(W[self.size - 1 - t, c]) for c in range(self.size)]
                    for t in range(self.size)]
 
        for t in range(self.size):
            for c in range(self.size):
                for r in range(self.size):
                    above = injected[t][c] if r == 0 else self.pes[r - 1][c].weight
                    self.pes[r][c].compute_preload(above)
            for row in self.pes:
                for pe in row:
                    pe.latch_preload()
            self._log_cycle(log_phase)
            self.cycle += 1
        self.weights_loaded = True
 
    def load_weights_instant(self, W: np.ndarray):
        """Convenience loader that skips preload timing (weights appear
        immediately). Useful for quick numeric checks when the RTL
        preload latency isn't being verified."""
        if self._computing:
            raise RuntimeError(
                "load_weights_instant() called while a matmul is in "
                "flight -- same hazard as preload_weights() (corner case: "
                "weight loading during compute)")
        assert W.shape == (self.size, self.size)
        for r in range(self.size):
            for c in range(self.size):
                self.pes[r][c].load_weight(int(W[r, c]))
        self.weights_loaded = True
 
    # ------------------------------------------------------------------
    # Matmul: fill / compute / drain
    # ------------------------------------------------------------------
    def run_matmul(self, A: np.ndarray, verbose: bool = False) -> np.ndarray:
        """
        Stream activation matrix A (M x size) through the array and
        reconstruct C = A @ W (M x size) strictly from cycle-by-cycle PE
        state -- not via a numpy shortcut -- so this exercises the same
        timing the RTL testbench will exercise.
        """
        if not self.weights_loaded:
            raise RuntimeError(
                "run_matmul() called before weights were loaded -- models "
                "the RTL hazard of activation_enable asserting before "
                "preload_done (corner case: start/compute at wrong time)")
 
        M, K = A.shape
        assert K == self.size, f"activation matrix must have {self.size} columns"
        for m in range(M):
            for r in range(K):
                check_int8(int(A[m, r]), f"A[{m}][{r}]")
 
        size = self.size
        total_cycles = M + 2 * (size - 1) + 1
        output = np.zeros((M, size), dtype=np.int64)
        filled = np.zeros((M, size), dtype=bool)
 
        self._computing = True
        for t in range(total_cycles):
            phase = "FILL" if t < size - 1 else ("DRAIN" if t >= M else "COMPUTE")
 
            for r in range(size):
                m = t - r  # row r is skewed by r cycles relative to row 0
                external_act = (int(A[m, r]), m) if 0 <= m < M else None
                for c in range(size):
                    if c == 0:
                        act_src = external_act
                    else:
                        left = self.pes[r][c - 1]
                        act_src = None if left.act is None else (left.act, left.act_tag)
                    psum_src = (None if r == 0 else
                                (self.pes[r - 1][c].psum, self.pes[r - 1][c].psum_tag))
                    self.pes[r][c].compute(act_src, psum_src)
 
            for row in self.pes:
                for pe in row:
                    pe.latch()
 
            # bottom row draining -> finished output values
            for c in range(size):
                bottom = self.pes[size - 1][c]
                if bottom.psum_tag is not None:
                    output[bottom.psum_tag, c] = bottom.psum
                    filled[bottom.psum_tag, c] = True
 
            self._log_cycle(phase)
            self.cycle += 1
            if verbose:
                self._print_cycle(t, phase)
 
        self._computing = False
        assert filled.all(), "golden model failed to drain all outputs -- check total_cycles"
        return output
 
    # ------------------------------------------------------------------
    # Debug / trace utilities
    # ------------------------------------------------------------------
    def _log_cycle(self, phase: str):
        row = {"cycle": self.cycle, "phase": phase}
        for r in range(self.size):
            for c in range(self.size):
                pe = self.pes[r][c]
                row[f"pe{r}{c}_w"] = pe.weight
                row[f"pe{r}{c}_act"] = pe.act
                row[f"pe{r}{c}_tag"] = pe.act_tag
                row[f"pe{r}{c}_psum"] = pe.psum
        self.trace.append(row)
 
    def _print_cycle(self, t: int, phase: str):
        print(f"--- cycle {t} [{phase}] ---")
        for r in range(self.size):
            cells = []
            for c in range(self.size):
                pe = self.pes[r][c]
                a = "." if pe.act is None else pe.act
                cells.append(f"a={a!s:>4} p={pe.psum:>6}")
            print("  " + " | ".join(cells))
 
    def save_trace_csv(self, path: str):
        if not self.trace:
            return
        fieldnames = list(self.trace[0].keys())
        with open(path, "w", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=fieldnames)
            writer.writeheader()
            writer.writerows(self.trace)
 
 
# --------------------------------------------------------------------------
# Top-level golden model
# --------------------------------------------------------------------------
 
class GoldenModel:
    """
    Top-level golden reference used for RTL verification.
 
        gm = GoldenModel()
        C  = gm.run(A, W)                 # cycle-accurate result
        gm.compare_to_numpy(A, W, C)      # independent numeric check
        gm.save_trace("trace.csv")        # cycle-by-cycle dump for debug
        gm.compare_rtl_output(C, "rtl_out.csv")   # vs RTL sim output
    """
 
    def __init__(self, size: int = ARRAY_SIZE):
        self.size = size
        self.array = SystolicArray4x4(size)
 
    def run(self, A: np.ndarray, W: np.ndarray,
            cycle_accurate_preload: bool = True, verbose: bool = False) -> np.ndarray:
        self.array.reset()
        if cycle_accurate_preload:
            self.array.preload_weights(W)
        else:
            self.array.load_weights_instant(W)
        return self.array.run_matmul(A, verbose=verbose)
 
    @staticmethod
    def reference(A: np.ndarray, W: np.ndarray) -> np.ndarray:
        """Independent numpy INT64-accumulated reference (not derived
        from the systolic simulation at all)."""
        return A.astype(np.int64) @ W.astype(np.int64)
 
    def compare_to_numpy(self, A: np.ndarray, W: np.ndarray, C: np.ndarray) -> bool:
        ref = self.reference(A, W)
        ok = bool(np.array_equal(C, ref))
        if not ok:
            diff = np.where(C != ref)
            print("MISMATCH between systolic golden model and numpy reference:")
            for m, n in zip(*diff):
                print(f"  C[{m}][{n}]: model={C[m, n]} ref={ref[m, n]}")
        return ok
 
    def save_trace(self, path: str):
        self.array.save_trace_csv(path)
 
    @staticmethod
    def compare_rtl_output(golden: np.ndarray, rtl_csv_path: str) -> bool:
        """
        Compare golden model output against RTL simulation output dumped
        to CSV (rows = output rows, cols = output columns, plain ints).
        Meant as the final self-checking step of a testbench flow.
        """
        rtl = np.loadtxt(rtl_csv_path, delimiter=",", dtype=np.int64)
        if rtl.shape != golden.shape:
            print(f"shape mismatch: golden {golden.shape} vs rtl {rtl.shape}")
            return False
        ok = bool(np.array_equal(golden, rtl))
        if not ok:
            diff = np.where(golden != rtl)
            print("MISMATCH between golden model and RTL output:")
            for m, n in zip(*diff):
                print(f"  C[{m}][{n}]: golden={golden[m, n]} rtl={rtl[m, n]}")
        return ok
 
 
# --------------------------------------------------------------------------
# Test-matrix generation
# --------------------------------------------------------------------------
 
def random_int8_matrix(rows: int, cols: int, seed: Optional[int] = None) -> np.ndarray:
    rng = random.Random(seed)
    return np.array([[rng.randint(ACT_MIN, ACT_MAX) for _ in range(cols)]
                      for _ in range(rows)], dtype=np.int64)
 
 
# --------------------------------------------------------------------------
# Self-test / regression suite
# --------------------------------------------------------------------------
 
def run_self_tests(trials: int = 20) -> bool:
    """Golden model vs. independent numpy reference across edge cases and
    random matrices of varying M. Also implicitly exercises the psum/act
    tag assertion in ProcessingElement.compute() on every cycle."""
    gm = GoldenModel()
    all_ok = True
 
    cases = [
        ("identity_weights", np.eye(ARRAY_SIZE, dtype=np.int64),
         random_int8_matrix(5, ARRAY_SIZE, seed=10)),
        ("zero_weights", np.zeros((ARRAY_SIZE, ARRAY_SIZE), dtype=np.int64),
         random_int8_matrix(3, ARRAY_SIZE, seed=11)),
        ("max_saturation", np.full((ARRAY_SIZE, ARRAY_SIZE), ACT_MAX, dtype=np.int64),
         np.full((2, ARRAY_SIZE), ACT_MAX, dtype=np.int64)),
        ("min_saturation", np.full((ARRAY_SIZE, ARRAY_SIZE), ACT_MIN, dtype=np.int64),
         np.full((2, ARRAY_SIZE), ACT_MIN, dtype=np.int64)),
        ("single_row_input", random_int8_matrix(ARRAY_SIZE, ARRAY_SIZE, seed=3),
         random_int8_matrix(1, ARRAY_SIZE, seed=4)),
 
        # --- corner case #2: zero activations against arbitrary (nonzero)
        # weights -- distinct from "zero_weights" above; exercises the
        # act==0/valid path rather than weight==0.
        ("zero_activations", random_int8_matrix(ARRAY_SIZE, ARRAY_SIZE, seed=12),
         np.zeros((4, ARRAY_SIZE), dtype=np.int64)),
 
        # --- corner case #3: explicit, non-random mixed-sign operands so
        # neg*pos and neg*neg products are guaranteed to occur (random
        # matrices only cover this probabilistically).
        ("mixed_sign_pattern",
         np.array([[5, -5, 5, -5],
                   [-5, 5, -5, 5],
                   [5, -5, 5, -5],
                   [-5, 5, -5, 5]], dtype=np.int64),
         np.array([[-3, 3, -3, 3],
                   [3, -3, 3, -3],
                   [-3, 3, -3, 3],
                   [3, -3, 3, -3]], dtype=np.int64)),
 
        # --- corner case #16: single non-zero (one-hot) weight -- only one
        # PE in the whole grid contributes to the output.
        ("single_nonzero_weight",
         np.array([[0, 0, 0, 0],
                   [0, 7, 0, 0],
                   [0, 0, 0, 0],
                   [0, 0, 0, 0]], dtype=np.int64),
         random_int8_matrix(3, ARRAY_SIZE, seed=13)),
 
        # --- corner case #16: single non-zero activation row entry -- only
        # one input element is ever multiplied.
        ("single_nonzero_activation",
         random_int8_matrix(ARRAY_SIZE, ARRAY_SIZE, seed=14),
         np.array([[0, 9, 0, 0]], dtype=np.int64)),
    ]
    for i in range(trials):
        m_rows = random.Random(200 + i).randint(1, 10)
        cases.append((f"random_{i}",
                       random_int8_matrix(ARRAY_SIZE, ARRAY_SIZE, seed=100 + i),
                       random_int8_matrix(m_rows, ARRAY_SIZE, seed=200 + i)))
 
    for name, W, A in cases:
        C = gm.run(A, W)
        ok = gm.compare_to_numpy(A, W, C)
        print(f"[{'PASS' if ok else 'FAIL'}] {name:<20} M={A.shape[0]}")
        all_ok &= ok
 
    return all_ok
 
 
# --------------------------------------------------------------------------
# Structural / control-flow corner cases (not pure numeric equality checks)
# --------------------------------------------------------------------------
 
def test_back_to_back_no_reset() -> bool:
    """Corner case #11: two matmul runs on the SAME array instance with no
    reset() between them (mirrors an RTL `start` pulse arriving again
    without rst_n toggling). Uses two different W/A pairs so any residual
    PE state leaking from run 1 -- weights, act, or psum registers --
    would corrupt run 2's numeric result and get caught here."""
    array = SystolicArray4x4()
 
    W1 = random_int8_matrix(ARRAY_SIZE, ARRAY_SIZE, seed=501)
    A1 = random_int8_matrix(4, ARRAY_SIZE, seed=502)
    array.preload_weights(W1)
    C1 = array.run_matmul(A1)
    ok1 = bool(np.array_equal(C1, GoldenModel.reference(A1, W1)))
 
    W2 = random_int8_matrix(ARRAY_SIZE, ARRAY_SIZE, seed=503)
    A2 = random_int8_matrix(4, ARRAY_SIZE, seed=504)
    array.preload_weights(W2)          # no reset() call in between
    C2 = array.run_matmul(A2)
    ok2 = bool(np.array_equal(C2, GoldenModel.reference(A2, W2)))
 
    print(f"[{'PASS' if ok1 and ok2 else 'FAIL'}] back_to_back_no_reset "
          f"(run1={ok1}, run2={ok2})")
    return ok1 and ok2
 
 
def test_weight_load_during_compute_guard() -> bool:
    """Corner case #13: reloading weights while a matmul is in flight must
    be rejected, mirroring the RTL hazard of weight_load_en and
    activation_enable overlapping. run_matmul() is atomic in this model,
    so the in-flight state is set directly to exercise the guard."""
    array = SystolicArray4x4()
    array.preload_weights(random_int8_matrix(ARRAY_SIZE, ARRAY_SIZE, seed=601))
 
    array._computing = True
    try:
        array.preload_weights(random_int8_matrix(ARRAY_SIZE, ARRAY_SIZE, seed=602))
        raised = False
    except RuntimeError:
        raised = True
    finally:
        array._computing = False
 
    print(f"[{'PASS' if raised else 'FAIL'}] weight_load_during_compute_guard")
    return raised
 
 
def test_matmul_without_preload_guard() -> bool:
    """Corner case #12: run_matmul() must not be reachable before weights
    are loaded, mirroring S_RUN being unreachable before preload_done."""
    array = SystolicArray4x4()
    try:
        array.run_matmul(np.zeros((1, ARRAY_SIZE), dtype=np.int64))
        raised = False
    except RuntimeError:
        raised = True
 
    print(f"[{'PASS' if raised else 'FAIL'}] matmul_without_preload_guard")
    return raised
 
 
def test_accumulator_boundary_guard() -> bool:
    """Corner case #5: with INT8 operands and K=4, the accumulator can
    never actually reach INT32 limits (max magnitude 4*127*127=64516), so
    the regression above can't naturally exercise check_acc()'s overflow
    path. This test drives check_acc() directly to confirm the guard
    itself works, so it's ready to catch a real overflow if ACC_WIDTH or
    the array size ever changes."""
    ok = True
    try:
        check_acc(ACC_MAX + 1)
        ok = False
    except ValueError:
        pass
    try:
        check_acc(ACC_MIN - 1)
        ok = False
    except ValueError:
        pass
 
    print(f"[{'PASS' if ok else 'FAIL'}] accumulator_boundary_guard")
    return ok
 
 
def run_structural_tests() -> bool:
    """Runs every non-numeric-equality corner case together."""
    results = [
        test_back_to_back_no_reset(),
        test_weight_load_during_compute_guard(),
        test_matmul_without_preload_guard(),
        test_accumulator_boundary_guard(),
    ]
    return all(results)
 
 
# NOTE on corner case #12 "start asserted at wrong time": the golden model
# has no clock or control-signal interface (no start/busy/done), so the RTL
# controller FSM's illegal state transitions (e.g. start pulsing again while
# busy) have no direct analog here beyond the weights_loaded ordering guard
# above. That transition table must be verified against the RTL testbench
# directly, not against this model.
 
 
if __name__ == "__main__":
    print("=== Running self-test regression suite ===")
    passed = run_self_tests()
    print(f"\nNumeric regression suite passed: {passed}\n")
 
    print("=== Running structural / hazard corner-case tests ===")
    structural_passed = run_structural_tests()
    print(f"\nStructural corner-case tests passed: {structural_passed}\n")
 
    passed = passed and structural_passed
 
    print("=== Demo run with trace export ===")
    gm = GoldenModel()
    W = random_int8_matrix(ARRAY_SIZE, ARRAY_SIZE, seed=1)
    A = random_int8_matrix(6, ARRAY_SIZE, seed=2)
 
    print("Weights (K x N):\n", W)
    print("Activations (M x K):\n", A)
 
    C = gm.run(A, W)
    print("\nSystolic golden-model output (M x N):\n", C)
    print("Matches numpy reference:", gm.compare_to_numpy(A, W, C))
 
    gm.save_trace("systolic_trace.csv")
    print("\nCycle-by-cycle trace written to systolic_trace.csv")
 
