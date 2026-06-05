from backtesting import Strategy
from backtesting.lib import crossover
import pandas as pd


class SmaCross(Strategy):
    fast = 50
    slow = 200

    def init(self):
        close = pd.Series(self.data.Close)
        self.ma_fast = self.I(lambda: close.rolling(self.fast).mean(), name=f"MA{self.fast}")
        self.ma_slow = self.I(lambda: close.rolling(self.slow).mean(), name=f"MA{self.slow}")

    def next(self):
        if crossover(self.ma_fast, self.ma_slow):
            self.buy(size=0.95)
        elif crossover(self.ma_slow, self.ma_fast):
            self.position.close()
