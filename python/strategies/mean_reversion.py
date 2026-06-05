from backtesting import Strategy
import pandas as pd


class MeanReversion(Strategy):
    lookback = 20
    entry_pct = 0.98
    exit_pct = 1.02

    def init(self):
        close = pd.Series(self.data.Close)
        self.sma = self.I(lambda: close.rolling(self.lookback).mean(), name=f"SMA{self.lookback}")

    def next(self):
        price = self.data.Close[-1]
        mean = self.sma[-1]
        if pd.isna(mean):
            return
        lower = mean * self.entry_pct
        upper = mean * self.exit_pct
        if price < lower and not self.position:
            self.buy(size=0.95)
        elif price > upper and self.position:
            self.position.close()
