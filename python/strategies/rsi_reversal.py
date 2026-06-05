from backtesting import Strategy
import pandas as pd


class RsiReversal(Strategy):
    rsi_period = 14
    oversold = 30
    overbought = 70

    def init(self):
        close = pd.Series(self.data.Close)
        delta = close.diff()
        gain = delta.clip(lower=0)
        loss = -delta.clip(upper=0)
        avg_gain = gain.rolling(self.rsi_period).mean()
        avg_loss = loss.rolling(self.rsi_period).mean()
        rs = avg_gain / avg_loss.replace(0, 1e-9)
        rsi = 100 - (100 / (1 + rs))
        self.rsi = self.I(lambda: rsi, name=f"RSI{self.rsi_period}")

    def next(self):
        if pd.isna(self.rsi[-1]):
            return
        if self.rsi[-1] < self.oversold and not self.position:
            self.buy(size=0.95)
        elif self.rsi[-1] > self.overbought and self.position:
            self.position.close()
