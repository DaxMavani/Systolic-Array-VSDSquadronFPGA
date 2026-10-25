#!/usr/bin/env python3
"""
Host-side test for the 4x4 systolic array on the VSDSquadron FM.

Protocol (115200 8N1):
  PC -> FPGA : 32 bytes  = A (16 x int8, row-major) + W (16 x int8, row-major)
  FPGA -> PC : 65 bytes  = C (16 x int32 little-endian, row-major) + 1 byte cycle count

Usage:
  python3 host_test.py                      # default port /dev/ttyUSB0, 20 random tests
  python3 host_test.py -p /dev/ttyUSB0 -n 100
  python3 host_test.py --seed 42

NOTE: close picocom (Ctrl-A Ctrl-X) first, only one program can own the port.
"""
import argparse
import sys
import numpy as np
import serial

N = 4
CLK_HZ = 12_000_000


def run_on_fpga(ser, A, W):
    ser.reset_input_buffer()
    ser.write(A.astype(np.int8).tobytes() + W.astype(np.int8).tobytes())
    ser.flush()
    resp = ser.read(N * N * 4 + 1)
    if len(resp) != N * N * 4 + 1:
        raise TimeoutError(f"expected 65 bytes, got {len(resp)}")
    C = np.frombuffer(resp[:64], dtype="<i4").reshape(N, N)
    cycles = resp[64]
    return C, cycles


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-p", "--port", default="/dev/ttyUSB0")
    ap.add_argument("-b", "--baud", type=int, default=115200)
    ap.add_argument("-n", "--num", type=int, default=20, help="number of random tests")
    ap.add_argument("--seed", type=int, default=1)
    args = ap.parse_args()

    rng = np.random.default_rng(args.seed)

    tests = []
    # Directed tests
    tests.append(("signed mix",
                  np.array([[-3, 7, -128, 127], [5, -6, 1, -1],
                            [-128, 127, 0, 100], [9, -10, 11, -12]]),
                  np.array([[1, -2, 3, -4], [-5, 6, -7, 8],
                            [127, -128, 9, -10], [-1, 0, -128, 127]])))
    tests.append(("identity",
                  np.arange(1, 17).reshape(N, N), np.eye(N, dtype=int)))
    tests.append(("all -128 x -128", np.full((N, N), -128), np.full((N, N), -128)))
    tests.append(("all 127 x -128", np.full((N, N), 127), np.full((N, N), -128)))
    tests.append(("zeros", np.zeros((N, N), dtype=int), rng.integers(-128, 128, (N, N))))
    # Random tests
    for i in range(args.num):
        tests.append((f"random #{i+1}",
                      rng.integers(-128, 128, (N, N)),
                      rng.integers(-128, 128, (N, N))))

    passed = 0
    with serial.Serial(args.port, args.baud, timeout=1.0) as ser:
        for name, A, W in tests:
            expected = A.astype(np.int64) @ W.astype(np.int64)
            try:
                C, cycles = run_on_fpga(ser, A, W)
            except TimeoutError as e:
                print(f"[FAIL] {name}: {e}")
                continue
            ok = np.array_equal(C, expected)
            passed += ok
            print(f"[{'PASS' if ok else 'FAIL'}] {name:18s} cycles={cycles} "
                  f"({cycles / CLK_HZ * 1e6:.2f} us @ 12 MHz)")
            if not ok or name == "signed mix":
                print("  A =\n", A, "\n  W =\n", W)
                print("  FPGA C =\n", C, "\n  expected =\n", expected)

    print(f"\n{passed}/{len(tests)} tests passed")
    sys.exit(0 if passed == len(tests) else 1)


if __name__ == "__main__":
    main()
