import json
import random
import sys
import time


def run_mock_engine():
    pnl = 0.0
    peak = 0.0

    for i in range(1, 101):
        change = random.gauss(12.5, 40)
        pnl += change
        peak = max(peak, pnl)
        drawdown = ((pnl - peak) / peak * 100) if peak != 0 else 0.0
        status = "running" if i < 100 else "done"

        data = {
            "progress": i,
            "pnl": round(pnl, 2),
            "drawdown": round(drawdown, 2),
            "status": status,
        }
        print(json.dumps(data))
        sys.stdout.flush()
        time.sleep(0.05)


if __name__ == "__main__":
    run_mock_engine()
